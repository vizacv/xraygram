// xraygram-core — маленький помощник для Xraygram (Telegram Desktop + xray).
//
// Живёт внутри .app (Contents/MacOS/xraygram-core) и запускается клиентом
// как дочерний процесс. Share-ссылку (vless://, vmess://, trojan://, ss://,
// hysteria2://) всегда читает из stdin, чтобы секрет не светился в `ps`.
//
//	xraygram-core version
//	xraygram-core check            < link   → "OK <protocol> <address> <name>" или ошибка, код 1
//	xraygram-core run -listen 127.0.0.1:PORT < link
//	    env XRAYGRAM_SOCKS_USER / XRAYGRAM_SOCKS_PASS — логин/пароль локального SOCKS5.
//	    Печатает "READY" в stdout, когда порт слушается. Завершается по SIGTERM/SIGINT
//	    или когда умирает родитель (Telegram), чтобы не оставлять висящий xray.
//
// SOCKS5 (CONNECT, логин/пароль) обслуживает сам помощник, а соединения отдаёт в ядро
// xray через core.Dial. Своих слушающих сокетов у xray нет: xray-core ставит
// SO_REUSEPORT на все свои listener'ы, и чужой процесс мог бы сесть на тот же
// 127.0.0.1:порт и получать логин/пароль (BUG-11). net.Listen в Go так не делает.
package main

import (
	"bufio"
	"context"
	"crypto/subtle"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/xtls/libxray/share"
	"github.com/xtls/libxray/xray"
	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/core"
)

const maxLinkSize = 64 * 1024

func readLink() (string, error) {
	data, err := io.ReadAll(io.LimitReader(os.Stdin, maxLinkSize))
	if err != nil {
		return "", err
	}
	if len(data) == 0 {
		return "", errors.New("empty link")
	}
	return string(data), nil
}

// firstOutbound превращает ссылку в первый пригодный outbound xray.
func firstOutbound(link string) (map[string]any, error) {
	raw, err := share.ConvertShareLinksToXrayJson(link, "")
	if err != nil {
		return nil, err
	}
	var parsed struct {
		Outbounds []map[string]any `json:"outbounds"`
	}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return nil, err
	}
	if len(parsed.Outbounds) == 0 {
		return nil, errors.New("no valid outbound found")
	}
	return parsed.Outbounds[0], nil
}

func describe(outbound map[string]any) string {
	protocol, _ := outbound["protocol"].(string)
	name, _ := outbound["tag"].(string)
	address := ""
	port := ""
	take := func(item map[string]any) {
		if value, ok := item["address"]; ok && value != nil {
			address = fmt.Sprint(value)
		}
		if value, ok := item["port"]; ok && value != nil {
			port = fmt.Sprint(value)
		}
	}
	if settings, ok := outbound["settings"].(map[string]any); ok {
		// vless/vmess: settings.vnext[0], остальные: settings.servers[0]
		// или плоский формат settings.address/port.
		pick := func(list any) {
			if items, ok := list.([]any); ok && len(items) > 0 {
				if item, ok := items[0].(map[string]any); ok {
					take(item)
				}
			}
		}
		if _, ok := settings["address"]; ok {
			take(settings)
		} else if value, ok := settings["vnext"]; ok {
			pick(value)
		} else if value, ok := settings["servers"]; ok {
			pick(value)
		}
	}
	// Формат: "<протокол> <хост:порт> <имя>", имя может содержать пробелы.
	endpoint := address
	if port != "" {
		endpoint = net.JoinHostPort(address, port)
	}
	return fmt.Sprintf("%s %s %s", protocol, endpoint, name)
}

// buildConfig: только outbound из ссылки (первый — маршрут по умолчанию) и freedom.
// Входов нет: соединения приходят через core.Dial из serveSocks.
func buildConfig(outbound map[string]any) (string, error) {
	outbound["tag"] = "proxy"
	config := map[string]any{
		"log": map[string]any{"loglevel": "warning"},
		"outbounds": []map[string]any{
			outbound,
			{"tag": "direct", "protocol": "freedom"},
		},
	}
	data, err := json.Marshal(config)
	return string(data), err
}

func cmdCheck() int {
	link, err := readLink()
	if err == nil {
		var outbound map[string]any
		if outbound, err = firstOutbound(link); err == nil {
			fmt.Println("OK " + describe(outbound))
			return 0
		}
	}
	fmt.Fprintln(os.Stderr, "ERROR "+err.Error())
	return 1
}

func cmdRun(args []string) int {
	flags := flag.NewFlagSet("run", flag.ContinueOnError)
	listen := flags.String("listen", "127.0.0.1:10808", "SOCKS5 listen address")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	fail := func(err error) int {
		fmt.Fprintln(os.Stderr, "ERROR "+err.Error())
		return 1
	}
	link, err := readLink()
	if err != nil {
		return fail(err)
	}
	outbound, err := firstOutbound(link)
	if err != nil {
		return fail(err)
	}
	summary := describe(outbound) // до buildConfig: он перезаписывает tag
	config, err := buildConfig(outbound)
	if err != nil {
		return fail(err)
	}

	// Сначала порт (без SO_REUSEPORT): занят — сразу ошибка, xray не стартуем.
	front, err := net.Listen("tcp", *listen)
	if err != nil {
		return fail(err)
	}
	defer front.Close()

	parsed, err := core.LoadConfig("json", strings.NewReader(config))
	if err != nil {
		return fail(err)
	}
	instance, err := core.New(parsed)
	if err != nil {
		return fail(err)
	}
	if err := instance.Start(); err != nil {
		_ = instance.Close()
		return fail(err)
	}
	defer instance.Close()

	user := os.Getenv("XRAYGRAM_SOCKS_USER")
	pass := os.Getenv("XRAYGRAM_SOCKS_PASS")
	go func() {
		for {
			client, err := front.Accept()
			if err != nil {
				return
			}
			go serveSocks(client, user, pass, instance)
		}
	}()
	fmt.Println("READY " + summary)

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)
	parent := os.Getppid()
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-signals:
			return 0
		case <-ticker.C:
			// Родитель умер (крэш Телеги) → нас усыновил launchd.
			if os.Getppid() != parent {
				return 0
			}
		}
	}
}

// serveSocks — SOCKS5 (RFC 1928) только CONNECT, авторизация логином/паролем (RFC 1929),
// если они заданы. UDP ASSOCIATE и BIND не поддерживаются (ответ 7), как раньше у xray.
func serveSocks(client net.Conn, user, pass string, instance *core.Instance) {
	defer client.Close()
	_ = client.SetDeadline(time.Now().Add(20 * time.Second))
	reader := bufio.NewReader(client)
	readN := func(n int) ([]byte, error) {
		buffer := make([]byte, n)
		_, err := io.ReadFull(reader, buffer)
		return buffer, err
	}

	head, err := readN(2)
	if err != nil || head[0] != 5 {
		return
	}
	methods, err := readN(int(head[1]))
	if err != nil {
		return
	}
	want := byte(0)
	if user != "" {
		want = 2
	}
	offered := false
	for _, method := range methods {
		if method == want {
			offered = true
		}
	}
	if !offered {
		_, _ = client.Write([]byte{5, 0xff})
		return
	}
	_, _ = client.Write([]byte{5, want})
	if want == 2 {
		version, err := readN(2)
		if err != nil || version[0] != 1 {
			return
		}
		gotUser, err := readN(int(version[1]))
		if err != nil {
			return
		}
		passLength, err := readN(1)
		if err != nil {
			return
		}
		gotPass, err := readN(int(passLength[0]))
		if err != nil {
			return
		}
		userOk := subtle.ConstantTimeCompare(gotUser, []byte(user)) == 1
		passOk := subtle.ConstantTimeCompare(gotPass, []byte(pass)) == 1
		if !userOk || !passOk {
			_, _ = client.Write([]byte{1, 1})
			return
		}
		_, _ = client.Write([]byte{1, 0})
	}

	request, err := readN(4)
	if err != nil || request[0] != 5 {
		return
	}
	reply := func(code byte) {
		_, _ = client.Write([]byte{5, code, 0, 1, 0, 0, 0, 0, 0, 0})
	}
	if request[1] != 1 {
		reply(7)
		return
	}
	var address xnet.Address
	switch request[3] {
	case 1:
		ip, err := readN(4)
		if err != nil {
			return
		}
		address = xnet.IPAddress(ip)
	case 4:
		ip, err := readN(16)
		if err != nil {
			return
		}
		address = xnet.IPAddress(ip)
	case 3:
		length, err := readN(1)
		if err != nil {
			return
		}
		domain, err := readN(int(length[0]))
		if err != nil {
			return
		}
		address = xnet.DomainAddress(string(domain))
	default:
		reply(8)
		return
	}
	portBytes, err := readN(2)
	if err != nil {
		return
	}
	port := xnet.Port(binary.BigEndian.Uint16(portBytes))

	upstream, err := core.Dial(context.Background(), instance, xnet.TCPDestination(address, port))
	if err != nil {
		reply(5)
		return
	}
	defer upstream.Close()
	reply(0)
	_ = client.SetDeadline(time.Time{})

	done := make(chan struct{}, 2)
	go func() {
		_, _ = io.Copy(upstream, reader)
		done <- struct{}{}
	}()
	go func() {
		_, _ = io.Copy(client, upstream)
		done <- struct{}{}
	}()
	<-done
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: xraygram-core version | check | run -listen host:port")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "version":
		fmt.Println("xray " + xray.XrayVersion())
	case "check":
		os.Exit(cmdCheck())
	case "run":
		os.Exit(cmdRun(os.Args[2:]))
	default:
		fmt.Fprintln(os.Stderr, "unknown command "+os.Args[1])
		os.Exit(2)
	}
}
