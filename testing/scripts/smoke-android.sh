#!/usr/bin/env bash
# smoke-android.sh — автоматический смоук APK Xraygram Android: статика + эмулятор (без рук владельца).
#
#   tools/heavy-build.sh qa testing/scripts/smoke-android.sh -a <путь к APK> [-b <ID>] [-s]
#
#   -a  APK (по умолчанию upstream/android-work/dist/Xraygram-latest.apk)
#   -b  ID сборки (по умолчанию из <apk>.id или имя файла)
#   -s  только статика, без эмулятора
#
# Статика (A): applicationId/имя, подпись, контрольная сумма, разрешения (нет VPN/BIND_VPN_SERVICE, нет
#   автозапуска сверх нужного), схема vless:// (FEAT-08), libXray в APK.
# Эмулятор (E): общий набор Android-темы `android/scripts/smoke-emulator.sh` (GATE → XRAY по vless-интенту →
#   COLD, всё против тестового сервера upstream/android-work/testserver). Его вывод и скриншоты кладём в отчёт.
#   APK копируется во временный файл — исходник (возможно, «у владельца») не трогаем.
# Итог: testing/results/<ID>/smoke-android.txt. Код выхода 1, если есть FAIL.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/android/scripts/common.sh"
APK="$XG_DIST/Xraygram-latest.apk"
BUILD=""
STATIC=0
while getopts "a:b:sh" opt; do
	case "$opt" in
		a) APK="$OPTARG" ;;
		b) BUILD="$OPTARG" ;;
		s) STATIC=1 ;;
		*) sed -n '2,18p' "$0"; exit 0 ;;
	esac
done
[[ -f "$APK" ]] || { echo "нет APK $APK"; exit 2; }
APK="$(cd "$(dirname "$APK")" && pwd)/$(basename "$APK")"
if [[ -z "$BUILD" ]]; then
	BUILD="$(awk '{print $1}' "$APK.id" 2>/dev/null)"
	[[ -n "$BUILD" ]] || BUILD="$(basename "$APK" .apk)"
fi
OUT="$ROOT/testing/results/$BUILD"
mkdir -p "$OUT"
REPORT="$OUT/smoke-android.txt"
: > "$REPORT"
FAILS=0
log() { echo "$*" | sed -E 's/(192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+/<LAN>/g' | tee -a "$REPORT"; }  # локальные IP не пишем
pass() { log "PASS  $1  $2"; }
fail() { log "FAIL  $1  $2"; FAILS=$((FAILS + 1)); }
warn() { log "WARN  $1  $2"; }
check() { local id="$1" what="$2"; shift 2; if "$@"; then pass "$id" "$what"; else fail "$id" "$what"; fi; }
BT="$ANDROID_HOME/build-tools/$BUILD_TOOLS"

log "# Смоук Xraygram Android: $BUILD"
log "# $(date '+%F %T'), APK ${APK/#$ROOT\//} ($(stat -f '%z байт, %Sm' "$APK"))"

log ""
log "## A — статика"
if [[ -f "$APK.sha256" ]]; then
	want="$(awk '{print $1}' "$APK.sha256")"; got="$(shasum -a 256 "$APK" | awk '{print $1}')"
	check A1 "sha256 совпадает с $(basename "$APK").sha256" test "$want" = "$got"
fi
badging="$("$BT/aapt2" dump badging "$APK" 2>/dev/null)"
pkg="$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<< "$badging")"
ver="$(sed -n "s/.*versionName='\([^']*\)'.*/\1/p" <<< "$badging")"
label="$(sed -n "s/^application-label:'\(.*\)'/\1/p" <<< "$badging")"
check A2 "applicationId: $pkg (не org.telegram.messenger)" bash -c "[[ '$pkg' == io.github.xraygram* ]]"
check A3 "имя: $label, версия $ver" test "$label" = "Xraygram"
sig="$("$BT/apksigner" verify --print-certs "$APK" 2>&1)"
check A4 "подпись валидна ($(grep -m1 'Signer #1 certificate DN' <<< "$sig" | sed 's/.*DN: //'))" grep -q 'certificate DN' <<< "$sig"
perms="$(grep "^uses-permission:" <<< "$badging" | sed "s/.*name='\([^']*\)'.*/\1/" | sed 's/android.permission.//' | tr '\n' ' ')"
log "      инфо: разрешения: $perms"
check A5 "нет VPN-сервиса (BIND_VPN_SERVICE)" bash -c "! '$BT/aapt2' dump xmltree --file AndroidManifest.xml '$APK' 2>/dev/null | grep -q BIND_VPN_SERVICE"
manifest="$("$BT/aapt2" dump xmltree --file AndroidManifest.xml "$APK" 2>/dev/null)"
if grep -q '"vless"' <<< "$manifest"; then pass A6 "intent-filter для vless:// есть (FEAT-08)"; else warn A6 "intent-filter для vless:// нет (FEAT-08)"; fi
libs="$(unzip -l "$APK" | awk '{print $4}' | grep -E '^lib/.*\.so$' | tr '\n' ' ')"
check A7 "нативные библиотеки arm64 есть" grep -q 'lib/arm64-v8a/' <<< "$libs"
if grep -qiE 'libgojni|libxray|libgomobile' <<< "$libs"; then pass A8 "libXray (gomobile) в APK"
else warn A8 "не нашёл libgojni/libxray .so в APK"; fi
for s in "Подключение через XRAY" "Подключиться без XRAY"; do
	n="$(unzip -p "$APK" 'resources.arsc' 'classes*.dex' 2>/dev/null | python3 -I -c 'import sys;d=sys.stdin.buffer.read();s=sys.argv[1];print(d.count(s.encode("utf-8"))+d.count(s.encode("utf-16-le")))' "$s")"
	if (( n > 0 )); then pass A9 "строка FEAT-03 «$s» есть"; else warn A9 "строки FEAT-03 «$s» нет (сборка без экрана XRAY?)"; fi
done

if (( STATIC )); then
	log ""; log "## E — эмулятор: пропущен (-s)"
else
	log ""
	log "## E — эмулятор (android/scripts/smoke-emulator.sh reality)"
	mkdir -p "$ROOT/upstream/qa-tmp"; TMPAPK="$(mktemp -d "$ROOT/upstream/qa-tmp/apk.XXXX")/$(basename "$APK")"
	cp "$APK" "$TMPAPK"
	SMOKE_OUT="$OUT/smoke-emulator.log"
	bash "$ROOT/android/scripts/smoke-emulator.sh" reality "$TMPAPK" > "$SMOKE_OUT" 2>&1
	rc=$?
	rm -rf "$(dirname "$TMPAPK")"
	# PASS/FAIL-строки набора + строки-подробности под FAIL (адреса прямых соединений)
	sed -E 's/\x1b\[[0-9;]*m//g' "$SMOKE_OUT" | awk '
		/^(PASS|FAIL) / { st=$1; sub(/^(PASS|FAIL) /, ""); print st "  E  " $0; infail=(st=="FAIL"); next }
		/^(==>|Success|Warning|Performing)/ { infail=0; next }
		infail && NF { print "            " $0 }' | while IFS= read -r line; do log "$line"; done
	(( rc == 0 )) || FAILS=$((FAILS + rc))
	for f in "$XG_LOGS"/smoke-*.png; do [[ -f "$f" ]] && cp "$f" "$OUT/android-$(basename "$f")"; done
	log "      инфо: полный вывод — ${SMOKE_OUT/#$ROOT\//}, скриншоты — ${OUT/#$ROOT\//}/android-smoke-*.png"
fi
log ""
log "# Итог: $(grep -c '^PASS' "$REPORT") PASS, $(grep -c '^FAIL' "$REPORT") FAIL, $(grep -c '^WARN' "$REPORT") WARN"
(( FAILS == 0 ))
