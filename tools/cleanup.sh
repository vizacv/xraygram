#!/bin/bash
# Чистка upstream/ после выдачи сборок (правило: docs/orchestration.md «Место на диске»).
#
#   tools/cleanup.sh --dry-run   показать, что будет удалено и сколько
#   tools/cleanup.sh             удалить
#   tools/cleanup.sh size        только размер upstream/ и бюджет
#
# Удаляет: кэши Bazel/Gradle/Go, промежуточные файлы сборок, старые сборки (в dist/ остаётся по одной
# последней на платформу + её QA-копия), временные файлы. НЕ трогает: исходники, инструменты (Android SDK,
# эмулятор, Gradle wrapper, gomobile, собранные библиотеки macOS), .secrets/, логи.
# Запускать, когда ничего не собирается: берёт замок очереди tools/heavy-build.sh.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
U="$ROOT/upstream"
BUDGET_GB=${XRAYGRAM_DISK_BUDGET_GB:-30}
DRY=0

size_gb() { du -sk "$U" 2>/dev/null | awk '{printf "%.1f", $1/1048576}'; }

case "${1:-}" in
	--dry-run) DRY=1 ;;
	size) s=$(size_gb); echo "upstream/: ${s} ГБ, бюджет ${BUDGET_GB} ГБ"
	      awk -v s="$s" -v b="$BUDGET_GB" 'BEGIN{exit !(s>b)}' && echo "ПРЕВЫШЕН — запусти tools/cleanup.sh"; exit 0 ;;
	"") ;;
	*) sed -n '2,13p' "$0"; exit 2 ;;
esac

if (( ! DRY )) && [[ "${XRAYGRAM_IN_QUEUE:-}" != 1 ]]; then
	exec env XRAYGRAM_IN_QUEUE=1 "$ROOT/tools/heavy-build.sh" cleanup "$0"
fi

rmrf() {
	local p
	for p in "$@"; do
		[[ -e "$p" || -L "$p" ]] || continue
		case "$p" in "$U"/*) ;; *) echo "пропуск (вне upstream/): $p"; continue ;; esac
		case "$p" in *"/.secrets"*) echo "пропуск (секреты): $p"; continue ;; esac
		printf '%8s  %s\n' "$(du -sh "$p" 2>/dev/null | cut -f1)" "${p#"$ROOT"/}"
		if (( ! DRY )); then chmod -R u+w "$p" 2>/dev/null; rm -rf "$p"; fi
	done
}

# Оставить в каталоге только последнюю сборку с ID (по имени) и указанные «рабочие» копии.
keep_latest() {
	local dir=$1 pattern=$2 latest f
	[[ -d "$dir" ]] || return 0
	latest=$(cd "$dir" && ls -1d $pattern 2>/dev/null | sort -V | tail -1)
	[[ -n "$latest" ]] || return 0
	echo "оставляю: ${dir#"$ROOT"/}/$latest"
	for f in "$dir"/$pattern; do
		[[ "$(basename "$f")" == "$latest" ]] && continue
		rmrf "$f"
	done
}

before=$(size_gb)
echo "== до: upstream/ ${before} ГБ"

echo "== iOS: кэши Bazel и Go"
rmrf "$U/xraygram-ios/bazel-cache" "$U/xraygram-ios/bazel-root" \
     "$U/xraygram-ios/go/cache" "$U/xraygram-ios/go/pkg" \
     "$U/xraygram-ios/signing-stub/DerivedData"

echo "== Android: промежуточные файлы, кэши Gradle и Go"
rmrf "$U/tg-android/TMessagesProj/build" "$U/tg-android/TMessagesProj/.cxx" \
     "$U/tg-android/TMessagesProj_AppStandalone/build" "$U/tg-android/.gradle" "$U/tg-android/build" \
     "$U/android-work/gradle/caches" "$U/android-work/gradle/daemon" \
     "$U/android-work/go/cache" "$U/android-work/go/pkg"

echo "== macOS: каталог сборки, кэши Go, временные"
rmrf "$U/xraygram-local/build-release" "$U/xraygram-local/go/cache" "$U/xraygram-local/go/pkg" \
     "$U/xraygram-local/tmp" "$U/xraygram-local/staging"

echo "== дубли и мусор"
rmrf "$U/tg" "$U/qa-tmp"

echo "== старые сборки"
# Android: последняя APK (+ .sha256/.id), ссылка Xraygram-latest.apk на неё
keep_latest "$U/android-work/dist" 'Xraygram-android-*.apk'
for f in "$U/android-work/dist"/*.apk.sha256 "$U/android-work/dist"/*.apk.id; do
	[[ -e "${f%.sha256}" && "$f" == *.sha256 ]] && continue
	[[ -e "${f%.id}" && "$f" == *.id ]] && continue
	rmrf "$f"
done
rmrf "$U/android-work/dist/Xraygram-13.2.2-arm64-v8a.apk"
# macOS: последняя сборка + её QA-копия; dist/Xraygram.app (рабочая копия владельца) не трогаем
keep_latest "$U/xraygram-local/dist" 'Xraygram-macos-*-[0-9].app'
keep_latest "$U/xraygram-local/dist" 'Xraygram-macos-*-QA.app'
# iOS: последняя сборка; Xraygram-sim.app (её использует смоук) — клоном последней, без лишнего места (APFS)
keep_latest "$U/xraygram-ios/dist" 'Xraygram-ios-*-sim.app'
last_ios=$(cd "$U/xraygram-ios/dist" 2>/dev/null && ls -1d Xraygram-ios-*-sim.app 2>/dev/null | sort -V | tail -1)
if [[ -n "$last_ios" ]] && (( ! DRY )); then
	rm -rf "$U/xraygram-ios/dist/Xraygram-sim.app"
	cp -cR "$U/xraygram-ios/dist/$last_ios" "$U/xraygram-ios/dist/Xraygram-sim.app"
	echo "Xraygram-sim.app = клон $last_ios"
fi

after=$(size_gb)
echo "== после: upstream/ ${after} ГБ (было ${before} ГБ)"
