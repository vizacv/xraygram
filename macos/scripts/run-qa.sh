#!/usr/bin/env bash
# Запуск QA-копии Xraygram в фоне, без окна на переднем плане (BUG-09).
#
#   macos/scripts/run-qa.sh <Xraygram-...-QA.app> <папка_данных> [-- доп. аргументы]
#
# Бинарник запускается напрямую (не через open/LaunchServices) с -workdir и -startintray.
# Печатает PID. Остановить: kill <PID> (только этот процесс; проверяйте -workdir в `ps`).
set -euo pipefail
APP="${1:?укажите QA-копию .app}"
DATA="${2:?укажите папку данных}"
shift 2
[[ "${1:-}" == "--" ]] && shift
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == *.qa ]] \
	|| { echo "это не QA-копия (make-qa-app.sh)" >&2; exit 1; }
mkdir -p "$DATA"
DATA="$(cd "$DATA" && pwd)"
nohup "$APP/Contents/MacOS/Telegram" -workdir "$DATA/" -startintray "$@" \
	> "$DATA/stdout.log" 2>&1 &
echo $!
