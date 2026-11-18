#!/usr/bin/env bash
# sys-check.sh — проверка, что Xraygram (macOS) не меняет систему.
#
#   testing/scripts/sys-check.sh            # снимок состояния
#   testing/scripts/sys-check.sh > a.txt    # до запуска; потом > b.txt после Cmd+Q; diff a.txt b.txt
#
# Печатает: системные прокси (scutil + networksetup по всем службам), utun-интерфейсы,
# VPN-конфигурации, LaunchAgents/Daemons и фоновые объекты (BTM) со словами xray/xraygram,
# процессы Xraygram/xraygram-core и их слушающие порты. Ничего не меняет.

set -uo pipefail
echo "## scutil --proxy"
scutil --proxy | grep -vE '^\s*$'

echo "## networksetup (socks/web/secure/pac по службам)"
networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | while read -r s; do
	s="${s#\*}"
	printf '%-28s socks=%s web=%s secure=%s pac=%s\n' "$s" \
		"$(networksetup -getsocksfirewallproxy "$s" 2>/dev/null | awk -F': ' '/^Enabled/{print $2}')" \
		"$(networksetup -getwebproxy "$s" 2>/dev/null | awk -F': ' '/^Enabled/{print $2}')" \
		"$(networksetup -getsecurewebproxy "$s" 2>/dev/null | awk -F': ' '/^Enabled/{print $2}')" \
		"$(networksetup -getautoproxyurl "$s" 2>/dev/null | awk -F': ' '/^Enabled/{print $2}')"
done

echo "## туннельные интерфейсы"
ifconfig -l | tr ' ' '\n' | grep -E '^(utun|tun|tap|ipsec|ppp)' | tr '\n' ' '; echo

echo "## VPN-конфигурации (scutil --nc list)"
scutil --nc list | tail -n +2 | sed -E 's/^\* ?//' | awk '{print $1, $NF}'

echo "## LaunchAgents/Daemons с xray/xraygram"
ls ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons 2>/dev/null | grep -i -E 'xray' || echo "нет"
echo "## launchctl (кроме обычной GUI-записи приложения application.io.github.xraygram...)"
launchctl list | grep -i xray | grep -v 'application\.io\.github\.xraygram' || echo "нет"
echo "## фоновые объекты/автозапуск (sfltool dumpbtm)"
n="$(sfltool dumpbtm 2>/dev/null | grep -ci xraygram)"; echo "упоминаний xraygram: ${n:-0}"

echo "## процессы"
ps -axo pid=,ppid=,command= | grep -E 'Xraygram\.app/|xraygram-core' | grep -v grep \
	| sed -E 's/(-listen [0-9.:]+).*/\1/' || true
[[ -n "$(pgrep -f 'Xraygram\.app/|xraygram-core')" ]] || echo "нет процессов Xraygram/xraygram-core"

echo "## слушающие порты Xraygram/xraygram-core"
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==1 || /xraygram|Telegram/' | awk '{print $1, $2, $9}' \
	| while read -r cmd pid name; do
		[[ "$cmd" == COMMAND ]] && continue
		path="$(ps -o command= -p "$pid" 2>/dev/null)"
		[[ "$path" == */Applications/Telegram.app/* ]] && continue
		echo "$cmd $pid $name"
	done
lsof -nP -iUDP 2>/dev/null | awk '/xraygram/{print $1, $2, $9}'
echo "## конец"
