#!/usr/bin/env bash
# net-watch.sh — следит за сетью Xraygram (macOS) и печатает всё подозрительное.
#
#   testing/scripts/net-watch.sh [-t секунд] [-w рабочая_папка] [-i интервал]
#
#   -t  сколько секунд следить (по умолчанию 0 = пока не нажмёте Ctrl+C)
#   -w  папка данных экземпляра (по умолчанию ~/Library/Application Support/Xraygram;
#       для тестового: upstream/xraygram-local/appdata или appdata-qa)
#   -i  интервал опроса, с (по умолчанию 1)
#
# Что считается нормой:
#   Telegram (Xraygram)  → только TCP на 127.0.0.1:<порт xraygram-core>
#   xraygram-core        → слушает 127.0.0.1, наружу только на адрес VPS из xraygram.json
# Всё остальное печатается с пометкой:
#   УТЕЧКА   — Telegram ходит наружу мимо xray (TCP или UDP не на 127.0.0.1)
#   UDP      — у Telegram открыт UDP-сокет (звонки, WebRTC)
#   CORE?    — xraygram-core ходит не на VPS
#   WEBVIEW  — WebKit-процесс Xraygram (мини-приложения) ходит наружу (мимо xray)
# Адрес VPS в выводе заменяется на <VPS>, ссылка и пароль не читаются и не печатаются.
# Ничего не меняет и ничего не убивает: только lsof/ps.

set -uo pipefail
DURATION=0
WORKDIR="$HOME/Library/Application Support/Xraygram"
INTERVAL=1
while getopts "t:w:i:h" opt; do
	case "$opt" in
		t) DURATION="$OPTARG" ;;
		w) WORKDIR="$OPTARG" ;;
		i) INTERVAL="$OPTARG" ;;
		*) sed -n '2,20p' "$0"; exit 0 ;;
	esac
done
WORKDIR="${WORKDIR%/}"
CONF="$WORKDIR/tdata/xraygram.json"

# Адреса VPS: второе поле summary ("vless <host> <name>") всех записей + их IP.
VPS=()
if [[ -r "$CONF" ]] && command -v jq > /dev/null; then
	while read -r host; do
		[[ -z "$host" ]] && continue
		VPS+=("$host")
		while read -r ip; do [[ -n "$ip" ]] && VPS+=("$ip"); done \
			< <(dscacheutil -q host -a name "$host" 2>/dev/null | awk '/ip_address|ipv6_address/{print $2}')
	done < <(jq -r '.entries[]?.summary | split(" ")[1] // empty' "$CONF" 2>/dev/null)
fi
(( ${#VPS[@]} )) || echo "!! не нашёл адрес VPS в $CONF — все соединения core будут помечены CORE?"

mask() {
	local line="$1" v
	for v in "${VPS[@]}"; do line="${line//$v/<VPS>}"; done
	echo "$line"
}
is_vps() {
	local addr="$1" v
	for v in "${VPS[@]}"; do [[ "$addr" == "$v:"* || "$addr" == "[$v]:"* ]] && return 0; done
	return 1
}

# Экземпляр определяем по аргументу -workdir (у основного его нет).
app_pids() {
	local pid cmd
	while read -r pid cmd; do
		if [[ "$WORKDIR" == "$HOME/Library/Application Support/Xraygram" ]]; then
			[[ "$cmd" == *"-workdir"* ]] && continue
		else
			[[ "$cmd" == *"-workdir $WORKDIR"* ]] || continue
		fi
		echo "$pid"
	done < <(ps -axo pid=,command= | grep -E 'Xraygram[^/]*\.app/Contents/MacOS/(Xraygram|Telegram)( |$)|Telegram\.app/Contents/MacOS/Telegram -workdir' | grep -v grep | grep -iv '/Applications/Telegram.app')
}
core_pids() { local p; for p in "$@"; do pgrep -P "$p" xraygram-core; done; }
# WebKit-процессы (XPC) не дети приложения; узнаём их по открытым файлам с id бандла.
webkit_pids() {
	lsof -nP -c com.apple.WebKit 2>/dev/null | grep -i 'xraygram' | awk '{print $2}' | sort -u
}

SEEN="$(mktemp -t xg-netwatch)"
trap 'rm -f "$SEEN"' EXIT
report() { # ключ строка — печатает каждую находку один раз (bash 3.2 без ассоциативных массивов)
	grep -Fxq -- "$1" "$SEEN" && return
	echo "$1" >> "$SEEN"
	printf '%s %s\n' "$(date +%T)" "$(mask "$2")"
}

APPS=($(app_pids))
(( ${#APPS[@]} )) || { echo "Xraygram (workdir $WORKDIR) не запущен"; exit 1; }
echo "Слежу: Telegram ${APPS[*]}, core $(core_pids "${APPS[@]}" | tr '\n' ' '), VPS: ${#VPS[@]} адрес(ов). Ctrl+C — стоп."

start=$SECONDS
leaks=0
while :; do
	APPS=($(app_pids))
	(( ${#APPS[@]} )) || { echo "$(date +%T) приложение завершилось"; break; }
	for pid in "${APPS[@]}"; do
		while read -r proto name state; do
			remote="${name#*->}"
			if [[ "$proto" == UDP ]]; then
				report "udp $name" "UDP      Telegram[$pid] $name"
				[[ "$name" == *"->"* && "$remote" != 127.0.0.1:* ]] && { report "leak $remote" "УТЕЧКА   Telegram[$pid] UDP → $remote"; ((leaks++)); }
			elif [[ "$name" == *"->"* && "$remote" != 127.0.0.1:* && "$remote" != "[::1]:"* ]]; then
				report "leak $remote" "УТЕЧКА   Telegram[$pid] TCP → $remote $state"; ((leaks++))
			elif [[ "$state" == "(LISTEN)" ]]; then
				report "listen $name" "LISTEN   Telegram[$pid] $name"
			fi
		done < <(lsof -nP -a -p "$pid" -i 2>/dev/null | awk 'NR>1{print $8, $9, $10}')
	done
	for pid in $(core_pids "${APPS[@]}"); do
		while read -r proto name state; do
			remote="${name#*->}"
			if [[ "$state" == "(LISTEN)" ]]; then
				[[ "$name" == 127.0.0.1:* ]] || report "clisten $name" "CORE?    core[$pid] слушает не на 127.0.0.1: $name"
			elif [[ "$name" == *"->"* && "$remote" != 127.0.0.1:* ]] && ! is_vps "$remote"; then
				report "core $remote" "CORE?    core[$pid] $proto → $remote $state"
			fi
		done < <(lsof -nP -a -p "$pid" -i 2>/dev/null | awk 'NR>1{print $8, $9, $10}')
	done
	for pid in $(webkit_pids); do
		while read -r proto name state; do
			[[ "$name" == *"->"* ]] || continue
			remote="${name#*->}"
			report "wk $remote" "WEBVIEW  $(ps -o comm= -p "$pid" | xargs basename)[$pid] $proto → $remote (мимо xray)"
		done < <(lsof -nP -a -p "$pid" -i 2>/dev/null | awk 'NR>1{print $8, $9, $10}')
	done
	(( DURATION > 0 && SECONDS - start >= DURATION )) && break
	sleep "$INTERVAL"
done
echo "Итог: ${leaks} соединений Telegram мимо 127.0.0.1 за $((SECONDS - start)) с."
