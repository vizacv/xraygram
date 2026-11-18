# Общие переменные для сборки Xraygram iOS. Подключается через `source`.

XG_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Telegram-iOS: коммит, против которого написан патч (ветка master upstream на 2026-11-03).
TGIOS_REF="24638bc69bd083981b178dd1e7f921eebbf7fc46"
TGIOS_URL="https://github.com/TelegramMessenger/Telegram-iOS.git"
# libXray: тот же тег, что и у macOS (macos/core/go.mod): v26.11.9 = Xray-core v26.11.9.
LIBXRAY_REF="v26.11.9"
LIBXRAY_URL="https://github.com/XTLS/libXray.git"

# Xcode из /Applications без переключения xcode-select (sudo не нужен).
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Всё рабочее — в upstream/ (он в .gitignore).
XG_SRC="${XRAYGRAM_TGIOS:-$XG_REPO/upstream/telegram-ios}"
XG_LIBXRAY_SRC="${XRAYGRAM_LIBXRAY:-$XG_REPO/upstream/libxray}"
XG_WORK="${XRAYGRAM_IOS_WORK:-$XG_REPO/upstream/xraygram-ios}"
XG_LOGS="$XG_WORK/logs"
XG_DIST="$XG_WORK/dist"
XG_PATCHES="$XG_REPO/ios/patches"
XG_XCFRAMEWORK_CORE="$XG_WORK/XraygramCore.xcframework"
XG_BAZEL_CACHE="$XG_WORK/bazel-cache"        # --cacheDir (disk cache)
XG_BAZEL_ROOT="$XG_WORK/bazel-root"          # --output_user_root (вместо /private/var/tmp/_bazel_$USER)
XG_SIGNING="$XG_WORK/signing"                # профили/сертификат для бесплатной подписи

# Ключи Telegram API — те же, что у macOS (TDESKTOP_API_ID/HASH), в .secrets/ (0600, не в git).
XG_API_ENV="${XRAYGRAM_API_ENV:-$XG_REPO/.secrets/api.env}"
# Bundle id и Team ID для бесплатной подписи — тоже в .secrets/ (не секрет, но личное).
XG_IOS_ENV="${XRAYGRAM_IOS_ENV:-$XG_REPO/.secrets/ios.env}"

# Кэши Go — внутри проекта.
export GOPATH="$XG_WORK/go"
export GOMODCACHE="$XG_WORK/go/pkg/mod"
export GOCACHE="$XG_WORK/go/cache"
export GOTELEMETRY="off"
export GOTELEMETRYDIR="$XG_WORK/go/telemetry"
export GOFLAGS="-modcacherw"

export PATH="/opt/homebrew/bin:$PATH"

xg_log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
xg_warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
xg_die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

xg_timed() { # $1 = имя лога, дальше команда
	local name="$1"; shift
	local start=$SECONDS rc
	mkdir -p "$XG_LOGS"
	xg_log "$name (лог: $XG_LOGS/$name.log)"
	set +e
	( set -e; "$@" ) > "$XG_LOGS/$name.log" 2>&1
	rc=$?
	set -e
	if (( rc != 0 )); then
		tail -40 "$XG_LOGS/$name.log" >&2
		xg_die "$name: ошибка (код $rc), полный лог $XG_LOGS/$name.log"
	fi
	xg_log "$name: готово за $(( (SECONDS - start) / 60 )) мин $(( (SECONDS - start) % 60 )) с"
}

# Читает KEY=value из env-файла (без source, чтобы не исполнять содержимое).
xg_env_get() { # $1 = файл, $2 = ключ
	[[ -f "$1" ]] || return 0
	sed -n "s/^[[:space:]]*$2[[:space:]]*=[[:space:]]*//p" "$1" | tr -d '"'"'"' \r' | tail -1
}
