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
# Xraygram с FEAT-19 (macos-2026112x), Telegram в сборках до него.
EXE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
# BUG-09: Qt сам активирует приложение, запущенное не через LaunchServices.
# С -startintray сборки с macos-20261119-3 отключают это сами; переменная — для старых.
export QT_MAC_DISABLE_FOREGROUND_APPLICATION_TRANSFORM=1
nohup "$APP/Contents/MacOS/$EXE" -workdir "$DATA/" -startintray "$@" \
	> "$DATA/stdout.log" 2>&1 &
echo $!
