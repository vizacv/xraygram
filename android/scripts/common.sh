# Общие переменные локальной сборки Xraygram Android. Подключается через `source`.
# Всё рабочее — в upstream/ (в .gitignore): исходники, SDK/NDK, Gradle, Go, сборки, логи.

XG_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Версии
TG_REMOTE="https://github.com/DrKLO/Telegram.git"
TG_REF="21f7d109da6ab3506c9e9577f98c6a38771ab335"   # 13.2.2 (7303), 2026-11-12
LIBXRAY_REMOTE="https://github.com/XTLS/libXray.git"
LIBXRAY_REF="v26.11.9"
GOMOBILE_REF="latest"
NDK_VERSION="27.2.12479018"          # = ndkVersion в TMessagesProj/build.gradle
BUILD_TOOLS="36.0.0"
PLATFORM="android-36"
CMAKE_VERSION="3.22.1"
EMU_IMAGE="system-images;android-36;google_apis;arm64-v8a"
AVD_NAME="xraygram"

# Приложение
XG_APP_ID="${XRAYGRAM_APP_ID:-io.github.xraygram}"    # итоговый applicationId (без суффикса .web)
XG_ABIS="${XRAYGRAM_ABIS:-arm64-v8a}"                  # через запятую; arm64-v8a — телефоны и эмулятор на M-маке

# Пути
XG_WORK="${XRAYGRAM_ANDROID_WORK:-$XG_REPO/upstream/android-work}"
XG_SRC="${XRAYGRAM_TG_SRC:-$XG_REPO/upstream/tg-android}"
XG_LIBXRAY_SRC="$XG_REPO/upstream/libxray"
XG_LOGS="$XG_WORK/logs"
XG_DIST="$XG_WORK/dist"
XG_PATCHES="$XG_REPO/android/patches"
XG_SECRETS="$XG_REPO/.secrets"
XG_API_ENV="${XRAYGRAM_API_ENV:-$XG_SECRETS/api.env}"
XG_KEYSTORE="${XRAYGRAM_KEYSTORE:-$XG_SECRETS/android-release.jks}"
XG_KEYSTORE_ENV="$XG_SECRETS/android-keystore.env"

export ANDROID_HOME="$XG_WORK/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME="$XG_WORK/android-user"   # вместо ~/.android
export ANDROID_AVD_HOME="$XG_WORK/avd"
export ANDROID_EMULATOR_HOME="$ANDROID_USER_HOME"
export GRADLE_USER_HOME="$XG_WORK/gradle"          # вместо ~/.gradle
export JAVA_HOME="${XRAYGRAM_JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$XG_WORK/go/bin:$PATH"

# Go — кэши внутри проекта
export GOPATH="$XG_WORK/go"
export GOMODCACHE="$XG_WORK/go/pkg/mod"
export GOCACHE="$XG_WORK/go/cache"
export GOTELEMETRY="off"
export GOTELEMETRYDIR="$XG_WORK/go/telemetry"

xg_log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
xg_warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
xg_die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
xg_sdkmanager() {
	local sm="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
	[[ -x "$sm" ]] || sm="$(command -v sdkmanager)" || xg_die "нет sdkmanager (brew install --cask android-commandlinetools)"
	"$sm" --sdk_root="$ANDROID_HOME" "$@"
}
