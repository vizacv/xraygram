// XraygramCore — ядро xray внутри процесса iOS-приложения (и будущего Swift-клиента macOS).
//
// iOS не даёт приложению запускать дочерние процессы, поэтому вместо отдельного
// бинарника (как macos/core) собираем c-archive и линкуем в приложение.
// Логика та же, что в macos/core/main.go: share-ссылка → первый outbound (libXray share)
// → конфиг xray с одним inbound SOCKS5 на 127.0.0.1 с логином/паролем.
//
// C API (все строки — UTF-8; возвращённые char* освобождать через XGFree):
//
//	char *XGVersion(void);                       → "26.11.9"
//	char *XGCheck(char *link);                   → JSON {"ok":true,"protocol","address","port","name"} | {"ok":false,"code","error"}
//	                                               code (PAR-03, тексты переводит UI): empty, web_link, unsupported,
//	                                               incomplete, start_failed, no_port, other
//	char *XGStart(char *id, char *link, char *host, int port, char *user, char *pass);
//	                                             → JSON {"ok":true,"port":N,...описание} | {"ok":false,"error"}
//	                                               port 0 = выбрать свободный. Экземпляр с тем же id
//	                                               перезапускается; с другими id — живут параллельно
//	                                               (у каждой XRAY-записи свой порт, как процессы на macOS).
//	void  XGStop(char *id);
//	void  XGStopAll(void);
//	int   XGIsRunning(char *id);
//	void  XGSetMemoryLimit(long long bytes, int gcPercent);  // 0/-1 = не трогать
//	void  XGFreeOSMemory(void);
//	void  XGFree(char *p);
//
// Не используем пакет libXray/xray: под GOOS=ios он включает режим Network Extension
// (лимит 30 МБ, GC 10 %, FreeOSMemory каждую секунду). Главному приложению это не нужно,
// лимит задаётся явно через XGSetMemoryLimit.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"runtime/debug"
	"strconv"
	"strings"
	"sync"
	"unsafe"

	"github.com/xtls/libxray/share"
	"github.com/xtls/xray-core/core"
	_ "github.com/xtls/xray-core/main/distro/all"
)

func main() {}

const maxLinkSize = 64 * 1024

var (
	mu        sync.Mutex
	instances = map[string]*core.Instance{}
)

type summary struct {
	Protocol string `json:"protocol"`
	Address  string `json:"address"`
	Port     int    `json:"port"`
	Name     string `json:"name"`
}

func cString(value any) *C.char {
	data, err := json.Marshal(value)
	if err != nil {
		data = []byte(`{"ok":false,"error":"internal json error"}`)
	}
	return C.CString(string(data))
}

// linkError — ошибка с кодом для UI (таблица «Понятные ошибки» FEAT-01).
type linkError struct {
	code string
	err  error
}

func (e *linkError) Error() string {
	return e.err.Error()
}

var supportedSchemes = map[string]bool{"vless": true, "vmess": true, "trojan": true, "ss": true, "hysteria2": true, "hy2": true}

func failure(err error) *C.char {
	code := "other"
	var coded *linkError
	if errors.As(err, &coded) {
		code = coded.code
	}
	return cString(map[string]any{"ok": false, "code": code, "error": err.Error()})
}

// firstOutbound превращает ссылку в первый пригодный outbound xray.
func firstOutbound(link string) (map[string]any, error) {
	link = strings.TrimSpace(link)
	if link == "" {
		return nil, &linkError{"empty", errors.New("empty link")}
	}
	if len(link) > maxLinkSize {
		return nil, &linkError{"other", errors.New("link is too long")}
	}
	lower := strings.ToLower(link)
	if strings.HasPrefix(lower, "http://") || strings.HasPrefix(lower, "https://") {
		return nil, &linkError{"web_link", errors.New("web or subscription link")}
	}
	scheme, _, found := strings.Cut(lower, "://")
	if !found || !supportedSchemes[scheme] {
		// Текст ядра здесь содержит саму ссылку — не отдаём его наружу.
		return nil, &linkError{"unsupported", errors.New("unsupported share format")}
	}
	raw, err := share.ConvertShareLinksToXrayJson(link, "")
	if err != nil {
		message := err.Error()
		switch {
		case strings.Contains(message, "unsupported"):
			return nil, &linkError{"unsupported", errors.New("unsupported share format")}
		case strings.Contains(message, "no valid outbound"):
			return nil, &linkError{"incomplete", err}
		}
		return nil, &linkError{"other", err}
	}
	var parsed struct {
		Outbounds []map[string]any `json:"outbounds"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return nil, err
	}
	if len(parsed.Outbounds) == 0 {
		return nil, &linkError{"incomplete", errors.New("no valid outbound found")}
	}
	return parsed.Outbounds[0], nil
}

func toInt(value any) int {
	switch v := value.(type) {
	case float64:
		return int(v)
	case int:
		return v
	case string:
		n, _ := strconv.Atoi(v)
		return n
	}
	return 0
}

func describe(outbound map[string]any) summary {
	result := summary{}
	result.Protocol, _ = outbound["protocol"].(string)
	result.Name, _ = outbound["tag"].(string)
	if settings, ok := outbound["settings"].(map[string]any); ok {
		// vless/vmess: settings.vnext[0], остальные: settings.servers[0]
		// или плоский формат settings.address/port.
		pick := func(list any) {
			if items, ok := list.([]any); ok && len(items) > 0 {
				if item, ok := items[0].(map[string]any); ok {
					result.Address = fmt.Sprint(item["address"])
					result.Port = toInt(item["port"])
				}
			}
		}
		if value, ok := settings["address"]; ok {
			result.Address = fmt.Sprint(value)
			result.Port = toInt(settings["port"])
		} else if value, ok := settings["vnext"]; ok {
			pick(value)
		} else if value, ok := settings["servers"]; ok {
			pick(value)
		}
	}
	return result
}

func buildConfig(outbound map[string]any, host string, port int, user, pass string) (string, error) {
	outbound["tag"] = "proxy"
	socks := map[string]any{
		"auth": "noauth",
		"udp":  false,
	}
	if user != "" {
		socks["auth"] = "password"
		socks["accounts"] = []map[string]any{{"user": user, "pass": pass}}
	}
	config := map[string]any{
		"log": map[string]any{"loglevel": "warning", "access": "none"},
		"inbounds": []map[string]any{{
			"tag":      "socks-in",
			"listen":   host,
			"port":     port,
			"protocol": "socks",
			"settings": socks,
		}},
		// Первый outbound — маршрут по умолчанию. Без routing/geo-файлов:
		// весь трафик Телеги идёт через сервер.
		"outbounds": []map[string]any{
			outbound,
			{"tag": "direct", "protocol": "freedom"},
		},
	}
	data, err := json.Marshal(config)
	return string(data), err
}

func freePort(host string) (int, error) {
	listener, err := net.Listen("tcp", net.JoinHostPort(host, "0"))
	if err != nil {
		return 0, err
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port, nil
}

func stopLocked(id string) {
	if instance := instances[id]; instance != nil {
		_ = instance.Close()
		delete(instances, id)
	}
}

//export XGVersion
func XGVersion() *C.char {
	return C.CString(core.Version())
}

//export XGCheck
func XGCheck(link *C.char) *C.char {
	outbound, err := firstOutbound(C.GoString(link))
	if err != nil {
		return failure(err)
	}
	info := describe(outbound)
	return cString(map[string]any{
		"ok": true, "protocol": info.Protocol, "address": info.Address, "port": info.Port, "name": info.Name,
	})
}

//export XGStart
func XGStart(id *C.char, link *C.char, host *C.char, port C.int, user *C.char, pass *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()
	key := C.GoString(id)
	stopLocked(key)

	outbound, err := firstOutbound(C.GoString(link))
	if err != nil {
		return failure(err)
	}
	info := describe(outbound) // до buildConfig: он перезаписывает tag
	listenHost := C.GoString(host)
	if listenHost == "" {
		listenHost = "127.0.0.1"
	}
	listenPort := int(port)
	if listenPort == 0 {
		if listenPort, err = freePort(listenHost); err != nil {
			return failure(&linkError{"no_port", err})
		}
	}
	config, err := buildConfig(outbound, listenHost, listenPort, C.GoString(user), C.GoString(pass))
	if err != nil {
		return failure(err)
	}
	parsed, err := core.LoadConfig("json", strings.NewReader(config))
	if err != nil {
		return failure(&linkError{"incomplete", err})
	}
	server, err := core.New(parsed)
	if err != nil {
		return failure(&linkError{"start_failed", err})
	}
	if err := server.Start(); err != nil {
		_ = server.Close()
		return failure(&linkError{"start_failed", err})
	}
	instances[key] = server
	debug.FreeOSMemory()
	return cString(map[string]any{
		"ok": true, "port": listenPort,
		"protocol": info.Protocol, "address": info.Address, "serverPort": info.Port, "name": info.Name,
	})
}

//export XGStop
func XGStop(id *C.char) {
	mu.Lock()
	defer mu.Unlock()
	stopLocked(C.GoString(id))
	debug.FreeOSMemory()
}

//export XGStopAll
func XGStopAll() {
	mu.Lock()
	defer mu.Unlock()
	for id := range instances {
		stopLocked(id)
	}
	debug.FreeOSMemory()
}

//export XGIsRunning
func XGIsRunning(id *C.char) C.int {
	mu.Lock()
	defer mu.Unlock()
	if instance := instances[C.GoString(id)]; instance != nil && instance.IsRunning() {
		return 1
	}
	return 0
}

//export XGSetMemoryLimit
func XGSetMemoryLimit(bytes C.longlong, gcPercent C.int) {
	if bytes > 0 {
		debug.SetMemoryLimit(int64(bytes))
	}
	if gcPercent > 0 {
		debug.SetGCPercent(int(gcPercent))
	}
}

//export XGFreeOSMemory
func XGFreeOSMemory() {
	debug.FreeOSMemory()
}

//export XGFree
func XGFree(p *C.char) {
	C.free(unsafe.Pointer(p))
}
