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
//	    Печатает "READY" в stdout, когда inbound поднят. Завершается по SIGTERM/SIGINT
//	    или когда умирает родитель (Telegram), чтобы не оставлять висящий xray.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/xtls/libxray/share"
	"github.com/xtls/libxray/xray"
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
	if settings, ok := outbound["settings"].(map[string]any); ok {
		// vless/vmess: settings.vnext[0].address, остальные: settings.servers[0].address
		// или settings.address (новый плоский формат).
		pick := func(list any) {
			if items, ok := list.([]any); ok && len(items) > 0 {
				if item, ok := items[0].(map[string]any); ok {
					address = fmt.Sprint(item["address"])
				}
			}
		}
		if value, ok := settings["address"]; ok {
			address = fmt.Sprint(value)
		} else if value, ok := settings["vnext"]; ok {
			pick(value)
		} else if value, ok := settings["servers"]; ok {
			pick(value)
		}
	}
	return fmt.Sprintf("%s %s %s", protocol, address, name)
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
		"log": map[string]any{"loglevel": "warning"},
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
	host, portText, err := net.SplitHostPort(*listen)
	if err != nil {
		return fail(err)
	}
	port, err := strconv.Atoi(portText)
	if err != nil {
		return fail(err)
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
	config, err := buildConfig(
		outbound,
		host,
		port,
		os.Getenv("XRAYGRAM_SOCKS_USER"),
		os.Getenv("XRAYGRAM_SOCKS_PASS"))
	if err != nil {
		return fail(err)
	}
	if err := xray.RunXray(config); err != nil {
		return fail(err)
	}
	fmt.Println("READY " + summary)

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)
	parent := os.Getppid()
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-signals:
			_ = xray.StopXray()
			return 0
		case <-ticker.C:
			// Родитель умер (крэш Телеги) → нас усыновил launchd.
			if os.Getppid() != parent {
				_ = xray.StopXray()
				return 0
			}
		}
	}
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
