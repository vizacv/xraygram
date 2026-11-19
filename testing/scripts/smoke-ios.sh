#!/usr/bin/env bash
# smoke-ios.sh — автоматический смоук сборки Xraygram iOS в симуляторе (без рук владельца).
#
#   tools/heavy-build.sh qa testing/scripts/smoke-ios.sh -a <путь к .app> [-b <ID>] [-k]
#
#   -a  .app для симулятора (по умолчанию upstream/xraygram-ios/dist/Xraygram-sim.app)
#   -b  ID сборки (по умолчанию имя .app)
#   -k  не выключать симулятор QA после прогона (для ручных шагов)
#
# Своё устройство «Xraygram QA» (создаётся при первом запуске), устройство iOS-темы не трогаем.
# Приложение ставится заново (чистые данные). Процесс приложения в симуляторе — обычный процесс Мака,
# поэтому его сокеты видны через lsof.
#   B  бандл: id, имя, URL-схемы
#   G  FEAT-03: первый запуск → экран XRAY, ни одного внешнего соединения 20 с, xray не слушает; скриншот
#   L  FEAT-08: `simctl openurl vless://…` (тестовый сервер 127.0.0.1:10443) — подхватывает ли приложение ссылку;
#      если подключилось — процесс ходит только на 127.0.0.1 (xray внутри процесса → тестовый сервер на Маке)
#   E  завершение: процесс исчез, портов нет
# Итог: testing/results/<ID>/smoke-ios.txt (+ скриншоты). Код выхода 1, если есть FAIL.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/upstream/xraygram-ios/dist/Xraygram-sim.app"
BUILD=""
KEEP=0
while getopts "a:b:kh" opt; do
	case "$opt" in
		a) APP="$OPTARG" ;;
		b) BUILD="$OPTARG" ;;
		k) KEEP=1 ;;
		*) sed -n '2,20p' "$0"; exit 0 ;;
	esac
done
APP="$(cd "$APP" && pwd)" || { echo "нет $APP"; exit 2; }
[[ -n "$BUILD" ]] || BUILD="$(basename "$APP" .app)"
OUT="$ROOT/testing/results/$BUILD"
TS="$ROOT/upstream/android-work/testserver"
mkdir -p "$OUT"
REPORT="$OUT/smoke-ios.txt"
: > "$REPORT"
FAILS=0
log() { echo "$*" | sed -E 's/(192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+/<LAN>/g' | tee -a "$REPORT"; }  # локальные IP не пишем
pass() { log "PASS  $1  $2"; }
fail() { log "FAIL  $1  $2"; FAILS=$((FAILS + 1)); }
skip() { log "SKIP  $1  $2"; }
warn() { log "WARN  $1  $2"; }
check() { local id="$1" what="$2"; shift 2; if "$@"; then pass "$id" "$what"; else fail "$id" "$what"; fi; }

BID="$(plutil -extract CFBundleIdentifier raw "$APP/Info.plist")"
log "# Смоук Xraygram iOS (симулятор): $BUILD"
log "# $(date '+%F %T'), бандл ${APP/#$ROOT\//}, $BID $(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")"

log ""
log "## B — бандл"
check B1 "bundle id не телеграмовский ($BID)" bash -c "[[ '$BID' != ph.telegra.Telegraph* ]]"
dn="$(plutil -extract CFBundleDisplayName raw "$APP/Info.plist" 2>/dev/null)"
bn="$(plutil -extract CFBundleName raw "$APP/Info.plist" 2>/dev/null)"
check B2 "имя: CFBundleDisplayName=$dn, CFBundleName=$bn" test "$dn" = "Xraygram" -a "$bn" = "Xraygram"
schemes="$(plutil -extract CFBundleURLTypes json -o - "$APP/Info.plist" 2>/dev/null | python3 -I -c 'import json,sys;print(" ".join(s for t in json.load(sys.stdin) for s in t.get("CFBundleURLSchemes",[])))' 2>/dev/null)"
if grep -qwE "tg|telegram|ton|tonsite|tc" <<< "$schemes"; then fail B3 "регистрирует схемы: $schemes (tg:// может уйти в Xraygram вместо Telegram)"; else pass B3 "схемы: ${schemes:-нет}"; fi
grep -qw vless <<< "$schemes" && pass B4 "схема vless:// зарегистрирована (FEAT-08)" || warn B4 "схема vless:// не зарегистрирована (FEAT-08)"

# ---- устройство QA
DEVTYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17"
RUNTIME="$(xcrun simctl list runtimes -j | python3 -I -c 'import json,sys
t=sys.argv[1]
r=[x for x in json.load(sys.stdin)["runtimes"] if x["isAvailable"] and x["platform"]=="iOS" and any(d["identifier"]==t for d in x.get("supportedDeviceTypes",[]))]
print(r[-1]["identifier"] if r else "")' "$DEVTYPE")"
UDID="$(xcrun simctl list devices -j | python3 -I -c 'import json,sys
for rt,devs in json.load(sys.stdin)["devices"].items():
    for d in devs:
        if d["name"]=="Xraygram QA" and d["isAvailable"]: print(d["udid"]); raise SystemExit')"
if [[ -z "$UDID" ]]; then
	[[ -n "$RUNTIME" ]] || { fail I0 "нет среды iOS для $DEVTYPE"; exit 1; }
	UDID="$(xcrun simctl create "Xraygram QA" "$DEVTYPE" "$RUNTIME" 2>&1)" || { fail I0 "не создать устройство: $UDID"; exit 1; }
	log "      инфо: создано устройство Xraygram QA ($UDID, $RUNTIME)"
fi
xcrun simctl boot "$UDID" 2>/dev/null
xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1
log "      инфо: устройство Xraygram QA $UDID загружено"
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null
xcrun simctl uninstall "$UDID" "$BID" 2>/dev/null
check I1 "установка .app" xcrun simctl install "$UDID" "$APP"

app_pid() { pgrep -f "$UDID/data/Containers/Bundle/Application/.*/$(basename "$APP")/" | head -1; }
app_pid2() { # имя исполняемого файла внутри .app
	local exe; exe="$(plutil -extract CFBundleExecutable raw "$APP/Info.plist")"
	pgrep -f "$UDID/.*/$exe$" | head -1
}
ext_sample() { # pid секунд
	local end=$(( SECONDS + $2 )) f; f="$(mktemp)"
	while (( SECONDS < end )); do
		lsof -nP -a -p "$1" -i 2>/dev/null | awk 'NR>1{print $8, $9}' | grep -- '->' | grep -v -E -- '->(127\.0\.0\.1|\[::1\]):' >> "$f"
		lsof -nP -a -p "$1" -iUDP 2>/dev/null | awk 'NR>1{print "UDP", $9}' | grep -v -E '127\.0\.0\.1|\[::1\]|\*:\*' >> "$f"
		sleep 0.5
	done
	sort -u "$f"; rm -f "$f"
}
listens() { lsof -nP -a -p "$1" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $9}' | tr '\n' ' '; }

log ""
log "## G — FEAT-03: первый запуск"
xcrun simctl launch "$UDID" "$BID" > /dev/null 2>&1
sleep 20   # первый запуск на чистом устройстве ~15 с белого экрана
P="$(app_pid2)"
check G1 "приложение запущено (pid ${P:-нет})" test -n "$P"
if [[ -n "$P" ]]; then
	xcrun simctl io "$UDID" screenshot "$OUT/ios-gate.png" > /dev/null 2>&1 && log "      скриншот: ${OUT/#$ROOT\//}/ios-gate.png"
	ext="$(ext_sample "$P" "${GATE_SECS:-120}")"
	check G2 "${GATE_SECS:-120} с (F03-01): ни одного внешнего соединения/UDP${ext:+: $(echo $ext)}" test -z "$ext"
	l="$(listens "$P")"
	check G3 "xray не слушает (записей нет)${l:+: $l}" test -z "$l"
	# логи приложения (подсказка iOS-темы): маркер экрана и куда шли MTTcpConnection
	GRP="$(xcrun simctl get_app_container "$UDID" "$BID" groups 2>/dev/null | awk '{print $2}' | head -1)"
	alog="$(ls -t "$GRP"/telegram-data/logs/app-logs/log-*.txt 2>/dev/null | head -1)"
	if [[ -n "$alog" ]]; then
		# с FEAT-19 (ios-20261119-2+) на чистой установке сначала вступление, экран XRAY — после «Начать»
		if grep -q "\[Xraygram\] .*network blocked" "$alog"; then
			pass G4 "в логе приложения «[Xraygram] network blocked»"
		else
			skip G4 "маркера экрана XRAY нет — сборка с вступлением FEAT-19 (экран XRAY после «Начать»); блокировку проверяют G2/G5"
		fi
		via="$(grep -h "MTTcpConnection" "$alog" | grep -oE "via [0-9.]+:[0-9]+" | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
		check G5 "все MTTcpConnection через «чёрную дыру» 127.0.0.1:1 (${via:-нет строк})" bash -c "[[ -n '$via' ]] && ! grep -q -v 'via 127.0.0.1:1$' <<< \"\$(grep -h MTTcpConnection '$alog' | grep -oE 'via [0-9.]+:[0-9]+')\""
	else
		skip G4 "лог приложения не найден"
	fi
fi

log ""
log "## X — подключение через XRAY (тестовый сервер 127.0.0.1:10443, Reality)"
# Запись без UI: сборки с поддержкой SIMCTL_CHILD_XRAYGRAM_ADD_LINK_FILE (только симулятор), иначе — openurl vless://.
STARTED_TS=""
if [[ -r "$TS/link-reality.txt" ]]; then
	if ! lsof -nP -iTCP:10443 -sTCP:LISTEN > /dev/null 2>&1; then
		nohup "$TS/xray" run -c "$TS/config.json" > /dev/null 2>&1 &
		STARTED_TS=$!; sleep 1.5
		log "      инфо: тестовый сервер запущен смоуком (pid $STARTED_TS)"
	fi
	LINKF="$(mktemp "$ROOT/upstream/qa-ios-link.XXXX")"; chmod 600 "$LINKF"
	sed 's/@10\.0\.2\.2:/@127.0.0.1:/; s/#.*$/#qa-ios/' "$TS/link-reality.txt" | tr -d '\n' > "$LINKF"
	ts_from=$(( $(stat -f %z "$TS/access.log" 2>/dev/null || echo 0) + 1 ))   # смещение в байтах
	xcrun simctl terminate "$UDID" "$BID" 2>/dev/null
	SIMCTL_CHILD_XRAYGRAM_ADD_LINK_FILE="$LINKF" xcrun simctl launch "$UDID" "$BID" > /dev/null 2>&1
	l=""; P=""
	for i in $(seq 1 60); do P="$(app_pid2)"; l="$(listens "${P:-0}")"; [[ -n "$l" ]] && break; sleep 0.5; done
	rm -f "$LINKF"
	if [[ -z "$l" ]]; then
		skip X "сборка не умеет XRAYGRAM_ADD_LINK_FILE (xray не поднялся за 30 с) — подключение руками (README)"
	else
		pass X1 "запись добавлена из окружения, xray слушает: $l"
		alog="$(ls -t "$GRP"/telegram-data/logs/app-logs/log-*.txt 2>/dev/null | head -1)"
		[[ -n "$alog" ]] && check X2 "маркер «adding XRAY entry from environment» в логе" grep -q "adding XRAY entry from environment" "$alog"
		sleep 5
		xcrun simctl io "$UDID" screenshot "$OUT/ios-connected.png" > /dev/null 2>&1
		ext="$(ext_sample "$P" 30)"
		check X3 "30 с после подключения: процесс только на 127.0.0.1${ext:+: $(echo $ext)}" test -z "$ext"
		acc=""
		for i in $(seq 1 15); do   # xray пишет access.log с задержкой
			acc="$(tail -c +"$ts_from" "$TS/access.log" 2>/dev/null | grep -oE 'accepted tcp:[^ ]+' | sed 's/accepted tcp://' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
			grep -qE '(149\.154|91\.108|95\.161|2001:b28|2001:67c)' <<< "$acc" && break; sleep 1
		done
		check X4 "тестовый сервер принял соединения к DC (${acc:-нет})" bash -c "grep -qE '(149\.154|91\.108|95\.161|2001:b28|2001:67c)' <<< '$acc'"
		if grep -qE '(^|[ ;])1\.0\.0\.0:|(^|[ ;])3\.0\.0\.0:' <<< "$acc"; then
			fail X5 "CONNECT к 1.0.0.0/3.0.0.0 (IPv6-адрес DC ушёл как мусорный IPv4)"
		else
			pass X5 "нет CONNECT к 1.0.0.0/3.0.0.0$(grep -q '\[2001' <<< "$acc" && echo '; IPv6 DC идут как [2001:…]')"
		fi
		via="$(grep -h MTTcpConnection "$alog" 2>/dev/null | grep -oE 'via [0-9.]+:[0-9]+( using [a-z]+)?' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
		log "      инфо: MTTcpConnection: ${via:-нет строк}"
		# холодный старт: запись сохранилась, xray поднимается сам
		xcrun simctl terminate "$UDID" "$BID" 2>/dev/null
		xcrun simctl launch "$UDID" "$BID" > /dev/null 2>&1
		l=""; for i in $(seq 1 60); do P="$(app_pid2)"; l="$(listens "${P:-0}")"; [[ -n "$l" ]] && break; sleep 0.5; done
		check X6 "холодный старт: xray поднялся сам (${l:-не слушает})" test -n "$l"
		ext="$(ext_sample "${P:-0}" 20)"
		check X7 "холодный старт, 20 с: только 127.0.0.1${ext:+: $(echo $ext)}" test -z "$ext"
	fi
	[[ -n "$STARTED_TS" ]] && kill "$STARTED_TS" 2>/dev/null
else
	skip X "нет тестового сервера upstream/android-work/testserver"
fi

log ""
log "## E — завершение"
P="$(app_pid2)"
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null
sleep 2
check E1 "процесс приложения завершён" bash -c "! kill -0 ${P:-0} 2>/dev/null"
if (( KEEP )); then log "# устройство Xraygram QA оставлено включённым ($UDID)"; else xcrun simctl shutdown "$UDID" 2>/dev/null; fi
log ""
log "# Итог: $(grep -c '^PASS' "$REPORT") PASS, $(grep -c '^FAIL' "$REPORT") FAIL, $(grep -c '^WARN' "$REPORT") WARN, $(grep -c '^SKIP' "$REPORT") SKIP"
(( FAILS == 0 ))
