# Общие переменные для локальной сборки Xraygram macOS. Подключается через `source`.
# Версии держим в синхроне с .github/workflows/build-macos.yml.

XG_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TDESKTOP_REF="v7.4.4"
TDE2E="51743dfd01dff6179e2d8f7095729caa4e2222e9"
TLOTTIE="92df98dc209bc39b1e567ec74a8c86a0af5239de"
WALLET_ENGINE="e59e0d89d7ee90c388bf36e3334c5b276f396697"
RUST_PATCHES="23d349a3ff09dbc1fa8127ce39ba9223de0edf21"
RUST_TOOLCHAIN="1.96.1"
GIT_BASE="https://github.com"

# Патчи сабмодулей tdesktop: "путь сабмодуля|патч относительно macos/patches".
# Пути внутри патча — от корня репозитория сабмодуля (так его могут взять Android/iOS).
XG_SUBMODULE_PATCHES=(
	"Telegram/ThirdParty/tgcalls|tgcalls/0001-socks5-tcp-relay.patch"
)

BREW_LIBS=(ada-url ffmpeg@6 jpeg-xl libavif libheif minizip openal-soft openh264 openssl opus qtbase qtimageformats qtshadertools qtsvg xz)
BREW_TOOLS=(autoconf automake boost cmake libtool ninja pkg-config python go jq wget)

# Всё рабочее — в upstream/ (он в .gitignore).
XG_SRC="${XRAYGRAM_TDESKTOP:-$XG_REPO/upstream/tdesktop}"
XG_WORK="${XRAYGRAM_WORK:-$XG_REPO/upstream/xraygram-local}"
XG_LIBS="$XG_WORK/libs"
XG_LOGS="$XG_WORK/logs"
XG_DIST="$XG_WORK/dist"
XG_PATCHES="$XG_REPO/macos/patches"
XG_CORE_SRC="$XG_REPO/macos/core"

# Ключи Telegram API — в .secrets/ проекта (в .gitignore, права 0600), не в git.
XG_API_ENV="${XRAYGRAM_API_ENV:-$XG_REPO/.secrets/api.env}"

# Кэши Go держим внутри проекта, а не в ~/go и ~/Library/Caches.
export GOPATH="$XG_WORK/go"
export GOMODCACHE="$XG_WORK/go/pkg/mod"
export GOCACHE="$XG_WORK/go/cache"
export GOTELEMETRY="off"
export GOTELEMETRYDIR="$XG_WORK/go/telemetry"
# Данные запущенного из скриптов приложения (run/run-dev) — тоже внутри проекта.
XG_APPDATA="${XRAYGRAM_APPDATA:-$XG_WORK/appdata}"

xg_log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
xg_warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
xg_die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
