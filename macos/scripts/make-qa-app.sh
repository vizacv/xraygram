#!/usr/bin/env bash
# QA-копия бандла Xraygram, которая не мешает владельцу (BUG-09):
#   - свой bundle id io.github.xraygram.desktop.qa и имя «Xraygram QA»
#     (не путается с основным, свои настройки macOS);
#   - LSUIElement + LSBackgroundOnly: без значка в Dock, приложение не становится активным.
#
#   macos/scripts/make-qa-app.sh <Xraygram-....app> [куда.app]
#   по умолчанию: рядом, с суффиксом -QA (Xraygram-macos-20261118-3-QA.app)
#
# Запуск — только через run-qa.sh (бинарник напрямую, -workdir, -startintray).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC="${1:?укажите исходный .app}"
SRC="${SRC%/}"
DST="${2:-${SRC%.app}-QA.app}"
[[ -d "$SRC" ]] || xg_die "нет $SRC"
[[ -e "$DST" ]] && xg_die "$DST уже есть"

ditto "$SRC" "$DST"
PL="$DST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.github.xraygram.desktop.qa" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Xraygram QA" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Xraygram QA" "$PL"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$PL" 2>/dev/null \
	|| /usr/libexec/PlistBuddy -c "Set :LSUIElement true" "$PL"
/usr/libexec/PlistBuddy -c "Add :LSBackgroundOnly bool true" "$PL" 2>/dev/null \
	|| /usr/libexec/PlistBuddy -c "Set :LSBackgroundOnly true" "$PL"
codesign --force --deep --sign - "$DST" 2>/dev/null
codesign --verify --deep --strict "$DST"
xg_log "QA-копия: $DST"
