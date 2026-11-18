#!/usr/bin/env bash
# smoke-macos.sh — автоматический смоук сборки Xraygram macOS (без рук владельца).
#
#   testing/scripts/smoke-macos.sh -a <путь к .app> [-b <ID сборки>] [-k] [-q]
#
#   -a  бандл (по умолчанию upstream/xraygram-local/dist/Xraygram.app)
#   -b  ID сборки для отчёта (по умолчанию имя бандла)
#   -k  не удалять тестовые папки данных после прогона
#   -q  без шагов, где запускается окно приложения (только бандл и core)
#
# Шаги (каждый PASS / FAIL / SKIP с доказательством):
#   B  бандл: подпись, bundle id, внешние библиотеки, entitlements, автозапуск, маркеры фич в бинарнике
#   C  xraygram-core отдельно: check, SOCKS-пароль, UDP, только 127.0.0.1, SIGTERM, смерть родителя, занятый порт
#   G  FEAT-03: чистый профиль → экран XRAY, ни одного внешнего соединения, core не стартует
#   S  FEAT-03: сохранённая неактивная ссылка → экран (saved: 1), core не стартует
#   X  подключение через XRAY к локальному тестовому серверу (upstream/android-work/testserver):
#      Telegram только на 127.0.0.1, падение core → перезапуск, Cmd+Q / kill -9 → ничего не остаётся
#   Y  система до и после: прокси, туннели, автозапуск, процессы, порты
#
# Безопасность: приложение запускается через `open -g -n` (без фокуса) с отдельным -workdir в
# upstream/xraygram-local/qa/, завершаются только процессы с этим -workdir. Чужой Xraygram не трогаем.
# Для шага X копируется только список прокси владельца (tdata/settingss, без аккаунта), а ссылка
# в xraygram.json подменяется на тестовый сервер: VPS владельца не используется. Пароли и ссылки не печатаются.
# Итог: testing/results/<ID>/smoke-macos.txt. Код выхода: 0 — все PASS/SKIP, 1 — есть FAIL.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/upstream/xraygram-local/dist/Xraygram.app"
BUILD=""
KEEP=0
QUICK=0
while getopts "a:b:kqh" opt; do
	case "$opt" in
		a) APP="$OPTARG" ;;
		b) BUILD="$OPTARG" ;;
		k) KEEP=1 ;;
		q) QUICK=1 ;;
		*) sed -n '2,25p' "$0"; exit 0 ;;
	esac
done
APP="$(cd "$APP" && pwd)" || { echo "нет бандла $APP"; exit 2; }
[[ -n "$BUILD" ]] || BUILD="$(basename "$APP" .app)"
EXE="$APP/Contents/MacOS/Telegram"
CORE="$APP/Contents/MacOS/xraygram-core"
QA="$ROOT/upstream/xraygram-local/qa/$BUILD"
OUT="$ROOT/testing/results/$BUILD"
TS="$ROOT/upstream/android-work/testserver"
OWNER_TDATA="$HOME/Library/Application Support/Xraygram/tdata"
mkdir -p "$OUT" "$QA"
chmod 700 "$QA"
REPORT="$OUT/smoke-macos.txt"
: > "$REPORT"
TMP="$(mktemp -d "$QA/tmp.XXXX")"

FAILS=0
log() { echo "$*" | sed -E 's/(192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+/<LAN>/g' | tee -a "$REPORT"; }  # локальные IP не пишем
pass() { log "PASS  $1  $2"; }
fail() { log "FAIL  $1  $2"; FAILS=$((FAILS + 1)); }
skip() { log "SKIP  $1  $2"; }
check() { # id описание условие...
	local id="$1" what="$2"; shift 2
	if "$@"; then pass "$id" "$what"; else fail "$id" "$what"; fi
}
now() { python3 -c 'import time;print(time.time())'; }
since() { python3 -c "print(round($(now)-$1,1))"; }
mask() { sed -E 's/(vless:\/\/)[^@]+@/\1<uuid>@/g; s/(pbk|sid)=[^&#]+/\1=<…>/g'; }

log "# Смоук Xraygram macOS: $BUILD"
log "# $(date '+%F %T'), $(sw_vers -productVersion), бандл: ${APP/#$ROOT\//}"
log "# бинарник: $(stat -f '%Sm, %z байт' "$EXE"), core: $("$CORE" version 2>&1)"

# ---------------------------------------------------------------- B: бандл
log ""
log "## B — бандл"
check B1 "подпись бандла валидна" codesign --verify --deep --strict "$APP"
id="$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist" 2>/dev/null)"
name="$(plutil -extract CFBundleName raw "$APP/Contents/Info.plist" 2>/dev/null)"
check B2 "bundle id/имя: $id / $name" test "$id" = "io.github.xraygram.desktop" -a "$name" = "Xraygram"
check B3 "нет URL-схем tg:// в Info.plist" bash -c "! plutil -extract CFBundleURLTypes raw '$APP/Contents/Info.plist' >/dev/null 2>&1"
ext="$(otool -L "$EXE" | tail -n +2 | awk '{print $1}' | grep -E '^/opt/homebrew|^/usr/local|/upstream/' | head -3)"
check B4 "нет ссылок на /opt/homebrew и build-каталоги${ext:+: $ext}" test -z "$ext"
check B5 "нет Contents/Library (LoginItems/LaunchAgents) в бандле" test ! -e "$APP/Contents/Library"
ent="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | tr -d '\0' | grep -c '<key>')"
check B6 "entitlements пустые (нет Network Extension), ключей: ${ent:-0}" test "${ent:-0}" -eq 0
for marker in \
	"FEAT-03|network blocked, showing the XRAY gate" \
	"FEAT-04|TCP relays, xray proxy" \
	"FEAT-04|REFLECTOR TCP via SOCKS5"; do
	feat="${marker%%|*}"; text="${marker#*|}"
	if grep -q -a -F "$text" "$EXE"; then pass "B7" "$feat: маркер «$text» в бинарнике"; else skip "B7" "$feat: маркера «$text» нет (сборка без фичи?)"; fi
done
for text in "Подключение через XRAY" "Подключиться без XRAY" "Без xray" "Удалить XRAY?"; do
	n="$(python3 -I -c "import sys;print(open(sys.argv[1],'rb').read().count(sys.argv[2].encode('utf-16-le')))" "$EXE" "$text")"
	if (( n > 0 )); then pass "B8" "строка UI «$text» есть"; else skip "B8" "строки UI «$text» нет"; fi
done

# ---------------------------------------------------------------- C: core отдельно
log ""
log "## C — xraygram-core отдельно (фиктивный сервер 192.0.2.1)"
FAKE='vless://00000000-0000-0000-0000-000000000000@192.0.2.1:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=SbVKOEMjK0sIlbwg4akyBg5mL5KZwwB-ed4eEE7YnRc&sid=ab&type=tcp#fake'
c_check() { printf '%s' "$1" | "$CORE" check 2>&1; }
out="$(c_check '')"; check C1 "пустая ссылка → ошибка ($out)" grep -q '^ERROR' <<< "$out"
out="$(c_check 'garbage')"; check C2 "мусор → ошибка ($out)" grep -q '^ERROR' <<< "$out"
out="$(c_check 'vless://abc')"; check C3 "обрезанная vless → ошибка ($out)" grep -q '^ERROR' <<< "$out"
out="$(c_check "$FAKE")"; check C4 "Reality-ссылка → $out" grep -q '^OK vless 192.0.2.1 fake' <<< "$out"

PROBE="$TMP/socks_probe.py"
cat > "$PROBE" <<'EOF'
import socket, struct, sys
h, p, u, pw = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
def greet(methods):
    s = socket.create_connection((h, p), timeout=5); s.sendall(bytes([5, len(methods)] + methods)); return s, s.recv(2)
def auth(s, user, pwd):
    s.sendall(bytes([1, len(user)]) + user.encode() + bytes([len(pwd)]) + pwd.encode()); return s.recv(2)
s, r = greet([0]); print("noauth", r.hex()); s.close()
s, r = greet([2]); print("badpass", auth(s, u, "wrong").hex()); s.close()
s, r = greet([2]); print("goodpass", auth(s, u, pw).hex())
s.sendall(b"\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00"); rep = s.recv(10); print("udp", rep[1] if len(rep) > 1 else -1)
EOF
PORT=39101
printf '%s' "$FAKE" | XRAYGRAM_SOCKS_USER=xraygram XRAYGRAM_SOCKS_PASS=qa-pass "$CORE" run -listen 127.0.0.1:$PORT > "$TMP/core.out" 2>&1 &
CP=$!
for i in $(seq 1 30); do grep -q READY "$TMP/core.out" && break; sleep 0.1; done
check C5 "run → READY ($(grep -o 'READY.*' "$TMP/core.out"))" grep -q READY "$TMP/core.out"
listen="$(lsof -nP -a -p $CP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $9}' | tr '\n' ' ')"
check C6 "слушает только 127.0.0.1 ($listen)" test "$listen" = "127.0.0.1:$PORT "
args="$(ps -o command= -p $CP)"
check C7 "ссылки нет в аргументах процесса" bash -c "! grep -q 'vless://' <<< '$args'"
probe="$(python3 -I "$PROBE" 127.0.0.1 $PORT xraygram qa-pass 2>&1 | tr '\n' ' ')"
check C8 "SOCKS: без пароля 05ff, неверный 01ff, верный 0100 ($probe)" \
	bash -c "grep -q 'noauth 05ff' <<< '$probe' && grep -q 'badpass 01ff' <<< '$probe' && grep -q 'goodpass 0100' <<< '$probe'"
check C9 "UDP ASSOCIATE отклонён (REP 7, udp:false)" grep -q 'udp 7' <<< "$probe"
printf '%s' "$FAKE" | XRAYGRAM_SOCKS_USER=xraygram XRAYGRAM_SOCKS_PASS=x "$CORE" run -listen 127.0.0.1:$PORT > "$TMP/busy.out" 2>&1 &
BP=$!; sleep 1.5
if kill -0 $BP 2>/dev/null; then kill $BP; fail C10 "второй core сел на занятый порт (SO_REUSEPORT, BUG-11): новый процесс забирает соединения"; else
	check C10 "занятый порт → ошибка bind" grep -q 'address already in use' "$TMP/busy.out"; fi
t0=$(now); kill -TERM $CP; for i in $(seq 1 30); do kill -0 $CP 2>/dev/null || break; sleep 0.1; done
check C11 "SIGTERM → выход за $(since $t0) с" bash -c "! kill -0 $CP 2>/dev/null"
sh -c "printf '%s' '$FAKE' | XRAYGRAM_SOCKS_USER=xraygram XRAYGRAM_SOCKS_PASS=x '$CORE' run -listen 127.0.0.1:39102 & echo \$! > '$TMP/child.pid'; wait" > /dev/null 2>&1 &
PARENT=$!; sleep 1.5; CH="$(cat "$TMP/child.pid")"
t0=$(now); kill -9 $PARENT; for i in $(seq 1 40); do kill -0 "$CH" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$CH" 2>/dev/null; then kill "$CH"; fail C12 "core пережил смерть родителя (4 с)"; else pass C12 "смерть родителя → core вышел за $(since $t0) с"; fi

# ---------------------------------------------------------------- запуск приложения
app_pid() { pgrep -f "MacOS/Telegram -workdir $1/" | head -1; }
launch() { # workdir
	open -g -n -a "$APP" --args -workdir "$1/"
	local i p
	for i in $(seq 1 100); do p="$(app_pid "$1")"; [[ -n "$p" ]] && { echo "$p"; return 0; }; sleep 0.1; done
	return 1
}
quit_pid() { # pid → graceful quit (тот же Apple Event, что Cmd+Q), адресно по PID
	osascript -l JavaScript -e "ObjC.import('AppKit'); var a=\$.NSRunningApplication.runningApplicationWithProcessIdentifier($1); a ? a.terminate : false" > /dev/null 2>&1
}
wait_gone() { local i; for i in $(seq 1 ${2:-50}); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.1; done; return 1; }
wait_log() { # файл шаблон секунд
	local i; for i in $(seq 1 $(( ${3:-20} * 10 ))); do grep -q -F "$2" "$1" 2>/dev/null && return 0; sleep 0.1; done; return 1
}
ext_conns() { # pid → внешние соединения (не 127.0.0.1/::1)
	lsof -nP -a -p "$1" -i 2>/dev/null | awk 'NR>1{print $8, $9, $10}' | awk '$2 ~ /->/' | grep -v -E -- '->(127\.0\.0\.1|\[::1\]):' || true
}
sample_ext() { # pid секунд → уникальные внешние соединения за время
	local i end=$(( SECONDS + $2 ))
	: > "$TMP/ext.txt"
	local t0=$SECONDS
	while (( SECONDS < end )); do
		ext_conns "$1" | sed "s/^/+$((SECONDS - t0))s /" >> "$TMP/ext.txt"
		lsof -nP -a -p "$1" -iUDP 2>/dev/null | awk -v t="+$((SECONDS - t0))s" 'NR>1{print t, "UDP", $9}' >> "$TMP/ext.txt"
		sleep 0.5
	done
	sort -t' ' -k2 -u "$TMP/ext.txt" | sort -n -t+ -k2 > "$TMP/ext2.txt"; mv "$TMP/ext2.txt" "$TMP/ext.txt"
	cat "$TMP/ext.txt"
}
cleanup_wd() { local p; p="$(app_pid "$1")"; [[ -n "$p" ]] && { quit_pid "$p"; wait_gone "$p" 50 || kill -9 "$p"; }; }

if (( QUICK )); then
	skip "G,S,X" "запуск приложения выключен (-q)"
else
	sys_before="$TMP/sys-before.txt"
	bash "$ROOT/testing/scripts/sys-check.sh" > "$sys_before" 2>&1

	# ------------------------------------------------------------ G: экран XRAY без записей
	log ""
	log "## G — FEAT-03: чистый профиль"
	WD="$QA/gate"; rm -rf "$WD"; mkdir -p "$WD"
	if P="$(launch "$WD")"; then
		pass G1 "приложение запущено (pid $P, open -g, workdir qa/gate)"
		if wait_log "$WD/log.txt" "network blocked" 25; then
			pass G2 "в логе: $(grep -o 'Xraygram: network blocked.*' "$WD/log.txt" | head -1)"
		else
			fail G2 "нет строки «network blocked» в log.txt за 25 с"
		fi
		ext="$(sample_ext "$P" "${GATE_SECS:-120}")"
		check G3 "${GATE_SECS:-120} с (F03-01): ни одного внешнего соединения/UDP${ext:+: $(echo $ext)}" test -z "$ext"
		# если блокировку снял человек («Подключиться без XRAY» → подтверждение), это видно по флагу
		da="$(jq -r '.directAllowed // false' "$WD/tdata/xraygram.json" 2>/dev/null || echo false)"
		[[ "$da" == true ]] && log "      ВНИМАНИЕ: в профиле directAllowed=true — кто-то нажал «Подключиться без XRAY», G3 не показателен"
		check G4 "core не запущен" test -z "$(pgrep -P "$P" xraygram-core)"
		lst="$(lsof -nP -a -p "$P" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $9}' | tr '\n' ' ')"
		check G5 "приложение ничего не слушает${lst:+: $lst}" test -z "$lst"
		refused="$(grep -c -i 'refused' "$WD/log.txt")"
		log "      инфо: строк «refused» в log.txt: $refused (попытки MTP в 127.0.0.1:1)"
		doh="$(grep -c -i -E 'dns\.google|cloudflare-dns|firebase' "$WD/log.txt")"
		check G6 "нет попыток DoH/Firebase в логе ($doh)" test "$doh" -eq 0
		t0=$(now); quit_pid "$P"
		if wait_gone "$P" 80; then pass G7 "Cmd+Q (terminate по PID) → выход за $(since $t0) с"; else fail G7 "не вышло за 8 с"; kill -9 "$P"; fi
	else
		fail G1 "приложение не запустилось"
	fi

	# ------------------------------------------------------------ S: сохранённая неактивная ссылка
	log ""
	log "## S — FEAT-03: сохранённая ссылка без записи в списке прокси"
	WD="$QA/saved"; rm -rf "$WD"; mkdir -p "$WD/tdata"
	jq -n --arg link "$FAKE" '{version:2, entries:[{link:$link, port:39111, password:"qa-saved", summary:"vless 192.0.2.1 fake"}]}' > "$WD/tdata/xraygram.json"
	chmod 600 "$WD/tdata/xraygram.json"
	if P="$(launch "$WD")"; then
		if wait_log "$WD/log.txt" "network blocked" 25; then
			line="$(grep -o 'Xraygram: network blocked.*' "$WD/log.txt" | head -1)"
			check S1 "экран с сохранённой ссылкой: $line" grep -q 'saved: 1' <<< "$line"
		else
			fail S1 "нет строки «network blocked» за 25 с"
		fi
		sleep 3
		check S2 "core для неактивной ссылки не запущен" test -z "$(pgrep -P "$P" xraygram-core)"
		ext="$(sample_ext "$P" 8)"
		check S3 "8 с: ни одного внешнего соединения${ext:+: $(echo $ext)}" test -z "$ext"
		check S4 "ссылка не выброшена из xraygram.json" test "$(jq '.entries|length' "$WD/tdata/xraygram.json")" -ge 1
		quit_pid "$P"; wait_gone "$P" 80 || kill -9 "$P"
	else
		fail S1 "приложение не запустилось"
	fi

	# ------------------------------------------------------------ X: подключение через тестовый сервер
	log ""
	log "## X — подключение через XRAY (тестовый сервер 127.0.0.1:10443, Reality)"
	STARTED_TS=""
	if [[ ! -r "$OWNER_TDATA/settingss" || ! -r "$OWNER_TDATA/xraygram.json" || ! -r "$TS/link-reality.txt" ]]; then
		skip X "нет списка прокси владельца или testserver — шаг пропущен"
	else
		if ! lsof -nP -iTCP:10443 -sTCP:LISTEN > /dev/null 2>&1; then
			nohup "$TS/xray" run -c "$TS/config.json" > "$TMP/testserver.log" 2>&1 &
			STARTED_TS=$!; sleep 1.5
			log "      инфо: тестовый сервер запущен смоуком (pid $STARTED_TS), будет остановлен"
		fi
		WD="$QA/xray"; rm -rf "$WD"; mkdir -p "$WD/tdata"
		cp -p "$OWNER_TDATA/settingss" "$WD/tdata/"
		link="$(sed 's/@10\.0\.2\.2:/@127.0.0.1:/' "$TS/link-reality.txt" | tr -d '\n')"
		# порт и пароль берём у записи владельца: по ним Телега узнаёт XRAY-запись в своём списке прокси
		jq --arg link "$link" '.entries |= [.[0] | .link = $link | .summary = "vless 127.0.0.1 qa"] | del(.directAllowed)' \
			"$OWNER_TDATA/xraygram.json" > "$WD/tdata/xraygram.json"
		chmod 600 "$WD/tdata/xraygram.json"
		if P="$(launch "$WD")"; then
			if wait_log "$WD/log.txt" "xray started on" 25; then
				pass X1 "$(grep -o 'Xraygram: xray started on.*' "$WD/log.txt" | head -1 | mask)"
			else
				fail X1 "core не стартовал за 25 с: $(grep 'Xraygram' "$WD/log.txt" | tail -2 | mask | tr '\n' ' ')"
			fi
			grep -q 'network blocked' "$WD/log.txt" && fail X2 "экран XRAY показан при наличии записи" || pass X2 "экран XRAY не показан (запись есть)"
			C="$(pgrep -P "$P" xraygram-core | head -1)"
			cport="$(ps -o command= -p "${C:-0}" | awk '{print $NF}' | sed 's/.*://')"
			ok=0
			for i in $(seq 1 40); do
				lsof -nP -a -p "$P" -iTCP -sTCP:ESTABLISHED 2>/dev/null | grep -q -- "->127.0.0.1:$cport" && { ok=1; break; }; sleep 0.5
			done
			check X3 "Telegram подключился к core 127.0.0.1:$cport за ≤ 20 с" test $ok -eq 1
			ext="$(sample_ext "$P" 15)"
			check X4 "15 с: Telegram только на 127.0.0.1${ext:+; внешние: $(echo $ext)}" test -z "$ext"
			cext="$(lsof -nP -a -p "${C:-0}" -i 2>/dev/null | awk 'NR>1 && $9 ~ /->/{print $9}' | grep -v -E -- '->127\.0\.0\.1:' | sort -u | tr '\n' ' ')"
			check X5 "core ходит только на тестовый сервер 127.0.0.1:10443${cext:+; ещё: $cext}" test -z "$cext"
			ts_hits="$(grep -c 'accepted' "$TS/access.log" 2>/dev/null)"
			log "      инфо: строк accepted в access.log тестового сервера: $ts_hits"
			# падение core
			t0=$(now); kill -9 "$C"; N=""
			for i in $(seq 1 100); do N="$(pgrep -P "$P" xraygram-core | head -1)"; [[ -n "$N" && "$N" != "$C" ]] && break; N=""; sleep 0.1; done
			nport="$(ps -o command= -p "${N:-0}" | awk '{print $NF}' | sed 's/.*://')"
			check X6 "kill -9 core → новый core за $(since $t0) с, порт ${nport:-?} (был $cport)" test -n "$N" -a "$nport" = "$cport"
			ext="$(sample_ext "$P" 6)"
			check X7 "после перезапуска core: Telegram только на 127.0.0.1${ext:+; внешние: $(echo $ext)}" test -z "$ext"
			# штатный выход
			C="$(pgrep -P "$P" xraygram-core | head -1)"
			t0=$(now); quit_pid "$P"
			if wait_gone "$P" 80; then pass X8 "Cmd+Q → приложение вышло за $(since $t0) с"; else fail X8 "не вышло за 8 с"; kill -9 "$P"; fi
			sleep 0.5
			check X9 "core $C завершился вместе с приложением" bash -c "! kill -0 ${C:-0} 2>/dev/null"
			check X10 "порт $cport свободен" bash -c "! lsof -nP -iTCP:$cport -sTCP:LISTEN >/dev/null 2>&1"
			# аварийное завершение приложения
			if P="$(launch "$WD")" && wait_log "$WD/log.txt" "xray started on" 25; then
				sleep 2; C="$(pgrep -P "$P" xraygram-core | head -1)"
				t0=$(now); kill -9 "$P"
				if wait_gone "${C:-0}" 30; then pass X11 "kill -9 приложения → core вышел за $(since $t0) с"; else fail X11 "core пережил приложение"; kill "$C"; fi
			else
				fail X11 "повторный запуск не удался"
			fi
		else
			fail X1 "приложение не запустилось"
		fi
		[[ -n "$STARTED_TS" ]] && kill "$STARTED_TS" 2>/dev/null
	fi

	# ------------------------------------------------------------ Y: система
	log ""
	log "## Y — система"
	sleep 1
	sys_after="$TMP/sys-after.txt"
	bash "$ROOT/testing/scripts/sys-check.sh" > "$sys_after" 2>&1
	d="$(diff <(sed '/^## процессы/,$d' "$sys_before") <(sed '/^## процессы/,$d' "$sys_after"))"
	check Y1 "прокси/туннели/VPN/автозапуск не изменились${d:+: $d}" test -z "$d"
	check Y2 "системный прокси выключен на всех службах" bash -c "! grep -E '(socks|web|secure|pac)=Yes' '$sys_after' >/dev/null"
	left="$(pgrep -f "workdir $QA/" | tr '\n' ' ')"
	check Y3 "не осталось наших процессов${left:+: $left}" test -z "$left"
fi

for wd in gate saved xray; do cleanup_wd "$QA/$wd"; done
if (( KEEP || FAILS )); then
	# при FAIL сохраняем логи для разбора; копии списка прокси и ссылок владельца удаляем всегда
	rm -f "$QA/xray/tdata/settingss" "$QA/xray/tdata/xraygram.json"
	for wd in gate saved xray; do [[ -f "$QA/$wd/log.txt" ]] && cp "$QA/$wd/log.txt" "$OUT/app-log-$wd.txt"; done
	log "# данные оставлены в ${QA/#$ROOT\//}, логи приложения — ${OUT/#$ROOT\//}/app-log-*.txt"
else
	rm -rf "$QA"
fi
log ""
log "# Итог: $(grep -c '^PASS' "$REPORT") PASS, $(grep -c '^FAIL' "$REPORT") FAIL, $(grep -c '^SKIP' "$REPORT") SKIP"
(( FAILS == 0 ))
