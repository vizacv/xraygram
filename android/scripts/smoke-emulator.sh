#!/usr/bin/env bash
# Смоук-тест Xraygram Android в эмуляторе против локального тестового VLESS-сервера на Маке.
#
#   tools/heavy-build.sh <кто> android/scripts/smoke-emulator.sh [reality|plain] [путь к APK]
#
# По умолчанию APK — upstream/android-work/dist/Xraygram-latest.apk. Через heavy-build обязательно:
# на перегруженном Маке эмулятор зависает (ANR system_server).
#
# Шаги и проверки (печатает PASS/FAIL по каждой):
#   GATE   чистая установка → экран «Подключение через XRAY», за 20 с у приложения нет сокетов наружу
#          (допустим только отказ на 127.0.0.1:1 — «чёрная дыра»);
#   XRAY   открыть vless://-ссылку (intent) → «Connect Proxy» → соединения к DC Telegram идут через тестовый сервер
#          (access.log), у приложения нет соединений, кроме 127.0.0.1 и 10.0.2.2:<порт сервера>;
#   COLD   force-stop + запуск → снова через xray, без прямых соединений.
# Скриншоты — logs/smoke-*.png (уменьшенные до 1000 px). Эмулятор гасится в конце (SMOKE_HOLD=<с> — подержать).
#
# Тестовый сервер: upstream/android-work/testserver (xray-core, 127.0.0.1:10086 plain, :10443 Reality; эмулятор видит
# Мак как 10.0.2.2). Если не слушает — скрипт поднимет его и потушит после себя.
# Координаты кнопок — для AVD «xraygram» (pixel_7, 1080×2400); uiautomator dump на Android 16 зависает, им не пользуемся.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
MODE="${1:-reality}"
APK="${2:-$XG_DIST/Xraygram-latest.apk}"
TS="$XG_WORK/testserver"
SELF_DIR="$(dirname "${BASH_SOURCE[0]}")"
[[ -x "$TS/xray" && -f "$TS/config.json" && -f "$TS/link-$MODE.txt" ]] || xg_die "нет тестового сервера в $TS"
[[ -e "$APK" ]] || xg_die "нет APK $APK"
LINK="$(cat "$TS/link-$MODE.txt")"
SERVER_PORT=$([[ "$MODE" == plain ]] && echo 10086 || echo 10443)
fails=0
pass() { printf '\033[1;32mPASS\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*"; fails=$((fails + 1)); }
shot() { adb exec-out screencap -p > "$XG_LOGS/smoke-$1.png" && sips -Z 1000 "$XG_LOGS/smoke-$1.png" >/dev/null; }
app_peers() { # уникальные удалённые адреса TCP-сокетов приложения за N секунд
	local secs="$1" out=""
	for _ in $(seq 1 "$secs"); do
		out+="$(adb shell "ss -tanp 2>/dev/null" | grep "\"github.xraygram\"" | awk '{print $1" "$5}')"$'\n'
		sleep 1
	done
	printf '%s' "$out" | grep -v '^$' | sort -u
}
outside() { grep -vE "^LISTEN | (127\.0\.0\.1|10\.0\.2\.2:$SERVER_PORT|\[::ffff:127\.0\.0\.1\])" || true; }
# FEAT-09 / BUG-15: после снятия блокировки допустимы соединения с Google (FCM-токен, Firebase Installations).
# Отличаем по обратному DNS (*.1e100.net / *.google.com). Печатаем их отдельно, провалом не считаем.
GOOGLE_ALLOWED_IPS="$(for h in firebaseinstallations.googleapis.com fcmregistrations.googleapis.com fcmtoken.googleapis.com android.clients.google.com mtalk.google.com; do dig +short "$h" A "$h" AAAA 2>/dev/null; done | grep -E '^[0-9a-f.:]+$' | sort -u)"
is_google_ip() { # разрешённые хосты FEAT-09 (резолв на Маке) или сети Google
	printf '%s\n' "$GOOGLE_ALLOWED_IPS" | grep -qx "$1" && return 0
	case "$1" in
		172.217.*|142.250.*|142.251.*|216.58.*|74.125.*|173.194.*|108.177.*|64.233.*|209.85.*|2607:f8b0:*|2a00:1450:*) return 0 ;;
	esac
	return 1
}
not_google() {
	local line ip host
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		ip="$(printf '%s' "$line" | awk '{print $2}' | sed -E 's/^\[(::ffff:)?//; s/\]?:[0-9]+$//')"
		host="$(dig +short -x "$ip" 2>/dev/null | head -1)"
		if [[ "$host" == *1e100.net. || "$host" == *google.com. ]] || is_google_ip "$ip"; then
			printf 'INFO  Google (допустимо после снятия блокировки, BUG-15): %s %s\n' "$line" "$host" >&2
		else
			printf '%s\n' "$line"
		fi
	done
}

own_server=""
if ! lsof -nP -iTCP:"$SERVER_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
	xg_log "поднимаю тестовый сервер"
	"$TS/xray" run -c "$TS/config.json" > "$XG_LOGS/testserver.log" 2>&1 &
	own_server=$!
	sleep 1
fi
cleanup() {
	[[ -n "$own_server" ]] && kill "$own_server" 2>/dev/null
	if [[ -n "${SMOKE_HOLD:-}" ]]; then xg_log "держу эмулятор ${SMOKE_HOLD} с"; sleep "$SMOKE_HOLD"; fi
	adb emu kill >/dev/null 2>&1 || true
}
trap cleanup EXIT

"$SELF_DIR/build-local.sh" emulator
adb root >/dev/null 2>&1; sleep 2; adb wait-for-device
xg_log "ставлю $(basename "$(readlink "$APK" 2>/dev/null || echo "$APK")")"
adb install -r "$APK" | tail -1
adb shell pm clear "$XG_APP_ID" >/dev/null

# GATE
"$SELF_DIR/build-local.sh" run >/dev/null; sleep 8; shot 1-gate
peers="$(app_peers 20)"
if [[ -z "$(printf '%s\n' "$peers" | outside)" ]]; then pass "GATE: за 20 с наружу ничего (${peers:-сокетов нет})"
else fail "GATE: соединения наружу без XRAY:"$'\n'"$(printf '%s\n' "$peers" | outside)"; fi

# XRAY
: > "$TS/access.log"
adb shell "am start -a android.intent.action.VIEW -d '$LINK' $XG_APP_ID" >/dev/null
sleep 5; shot 2-alert
adb shell input tap 540 2234   # «Connect Proxy» в окне «Прокси-сервер»
start=$SECONDS
until grep -qE "accepted tcp:(91\.108|149\.154|95\.161|\[2001:(67c|b28))" "$TS/access.log" 2>/dev/null || (( SECONDS - start > 60 )); do sleep 1; done
if grep -qE "accepted tcp:(91\.108|149\.154|95\.161|\[2001:(67c|b28))" "$TS/access.log"; then
	pass "XRAY ($MODE): DC Telegram через тестовый сервер за $(( SECONDS - start )) с"
else
	fail "XRAY ($MODE): за 60 с нет соединений к DC через тестовый сервер"
fi
peers="$(app_peers 10)"; shot 3-connected
bad="$(printf '%s\n' "$peers" | outside | not_google)"
if [[ -z "$bad" ]]; then pass "XRAY: прямых соединений нет (Google для FCM — см. INFO)"
else fail "XRAY: прямые соединения:"$'\n'"$bad"; fi

# COLD
adb shell am force-stop "$XG_APP_ID"; : > "$TS/access.log"
"$SELF_DIR/build-local.sh" run >/dev/null; start=$SECONDS
until grep -q "accepted tcp:" "$TS/access.log" 2>/dev/null || (( SECONDS - start > 30 )); do sleep 1; done
if grep -q "accepted tcp:" "$TS/access.log"; then pass "COLD: через xray за $(( SECONDS - start )) с"; else fail "COLD: нет соединений через xray за 30 с"; fi
peers="$(app_peers 8)"; shot 4-cold
bad="$(printf '%s\n' "$peers" | outside | not_google)"
if [[ -z "$bad" ]]; then pass "COLD: прямых соединений нет (Google для FCM — см. INFO)"
else fail "COLD: прямые соединения:"$'\n'"$bad"; fi

crash="$(adb logcat -d -b crash | grep -c "$XG_APP_ID" || true)"
(( crash == 0 )) && pass "крэшей нет" || fail "крэши в logcat -b crash: $crash"
xg_log "итог: $([[ $fails -eq 0 ]] && echo 'всё PASS' || echo "FAIL: $fails")"
exit "$fails"
