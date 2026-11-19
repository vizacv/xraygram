#!/usr/bin/env bash
# Локальная сборка Xraygram Android на Маке (Apple Silicon).
#
#   android/scripts/build-local.sh [шаг...]
#
# Шаги (по умолчанию: all = deps src libxray keystore apk):
#   deps      JDK 17 (Homebrew), Android SDK/NDK/CMake в upstream/android-work/sdk, gomobile
#   src       клон DrKLO/Telegram (+ сабмодули --depth 1) в upstream/tg-android, ветка xraygram + наш патч
#   libxray   gomobile bind → libXray.aar (только ABI из XRAYGRAM_ABIS) → TMessagesProj/libs/
#   keystore  свой ключ подписи в .secrets/android-release.jks (создаётся один раз)
#   apk       Gradle assembleAfatStandalone → upstream/android-work/dist/Xraygram-<версия>-<abi>.apk
#   quick     то же, что apk, но без очереди heavy-build (инкрементальная пересборка после правки Java)
#   install   adb install -r последнего APK (телефон по USB или запущенный эмулятор)
#   emulator  создать (один раз) и запустить AVD «xraygram» (системный образ — в upstream/)
#   run       запустить приложение на подключённом устройстве
#   status    что уже есть
#
# Тяжёлые шаги (libxray, apk) идут через очередь tools/heavy-build.sh android ...,
# потому что на этом Маке параллельно собирают другие темы.
#
# Переменные: XRAYGRAM_ABIS (по умолчанию arm64-v8a), XRAYGRAM_APP_ID (io.github.xraygram).

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
HEAVY="$XG_REPO/tools/heavy-build.sh"
SELF="$XG_REPO/android/scripts/build-local.sh"
mkdir -p "$XG_WORK" "$XG_LOGS" "$XG_DIST"

heavy() { "$HEAVY" android "$@"; }

timed() { # timed <имя> <команда...>: лог в logs/<имя>.log, время в консоль
	local name="$1"; shift
	local start=$SECONDS
	xg_log "$name: $* (лог: $XG_LOGS/$name.log)"
	if ! "$@" > "$XG_LOGS/$name.log" 2>&1; then
		tail -40 "$XG_LOGS/$name.log" >&2
		xg_die "$name: ошибка, см. $XG_LOGS/$name.log"
	fi
	xg_log "$name: готово за $(( (SECONDS - start) / 60 )) мин $(( (SECONDS - start) % 60 )) с"
}

# ---------------------------------------------------------------- deps
step_deps() {
	if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
		xg_log "ставлю openjdk@17 (Homebrew)"
		brew install openjdk@17
	fi
	"$JAVA_HOME/bin/java" -version 2>&1 | head -1
	command -v go >/dev/null || brew install go
	mkdir -p "$ANDROID_HOME" "$ANDROID_USER_HOME"
	local pkgs=("cmdline-tools;latest" "platform-tools" "platforms;$PLATFORM" "build-tools;$BUILD_TOOLS"
		"ndk;$NDK_VERSION" "cmake;$CMAKE_VERSION")
	local missing=()
	[[ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]] || missing+=("cmdline-tools;latest")
	[[ -d "$ANDROID_HOME/platform-tools" ]] || missing+=("platform-tools")
	[[ -d "$ANDROID_HOME/platforms/$PLATFORM" ]] || missing+=("platforms;$PLATFORM")
	[[ -d "$ANDROID_HOME/build-tools/$BUILD_TOOLS" ]] || missing+=("build-tools;$BUILD_TOOLS")
	[[ -d "$ANDROID_HOME/ndk/$NDK_VERSION" ]] || missing+=("ndk;$NDK_VERSION")
	[[ -d "$ANDROID_HOME/cmake/$CMAKE_VERSION" ]] || missing+=("cmake;$CMAKE_VERSION")
	if (( ${#missing[@]} )); then
		xg_log "Android SDK: ставлю ${missing[*]} (лицензии SDK принимаются автоматически)"
		yes | xg_sdkmanager --licenses >/dev/null 2>&1 || true
		timed sdk xg_sdkmanager "${missing[@]}"
	fi
	if [[ ! -x "$GOPATH/bin/gomobile" ]]; then
		local ver
		ver="$(cd "$XG_LIBXRAY_SRC" && go list -m -f '{{.Version}}' golang.org/x/mobile)"
		xg_log "gomobile $ver"
		go install "golang.org/x/mobile/cmd/gomobile@$ver" "golang.org/x/mobile/cmd/gobind@$ver"
	fi
	xg_log "deps: ок"
}

# ---------------------------------------------------------------- src
step_src() {
	if [[ ! -d "$XG_SRC/.git" ]]; then
		timed clone git clone --recurse-submodules --shallow-submodules -j8 "$TG_REMOTE" "$XG_SRC"
	fi
	if [[ ! -d "$XG_LIBXRAY_SRC/.git" ]]; then
		timed clone-libxray git clone --depth 1 --branch "$LIBXRAY_REF" "$LIBXRAY_REMOTE" "$XG_LIBXRAY_SRC"
	fi
	cd "$XG_SRC"
	local head; head="$(git rev-parse HEAD)"
	if [[ "$(git rev-parse --abbrev-ref HEAD)" != "xraygram" ]]; then
		if [[ "$head" != "$TG_REF" ]]; then
			git fetch --depth 1 origin "$TG_REF"
			git checkout -q "$TG_REF"
			git submodule update --init --recursive --depth 1 -j8
		fi
		git checkout -q -b xraygram
	fi
	local patch
	for patch in "$XG_PATCHES"/*.patch; do
		[[ -e "$patch" ]] || continue
		if git apply --check "$patch" 2>/dev/null; then
			xg_log "применяю $(basename "$patch")"
			git apply --index "$patch"
		elif git apply --check -R "$patch" 2>/dev/null; then
			xg_log "$(basename "$patch") уже применён"
		else
			xg_die "$(basename "$patch") не применяется к $XG_SRC (правки в рабочем дереве? см. update-patch.sh)"
		fi
	done
	# Патчи сабмодуля tgcalls (звонки через SOCKS5 xray), пути от корня tgcalls — общие с macOS.
	local tgcalls="$XG_SRC/TMessagesProj/jni/tgcalls"
	for patch in "$XG_PATCHES"/tgcalls/*.patch; do
		[[ -e "$patch" ]] || continue
		if git -C "$tgcalls" apply --check "$patch" 2>/dev/null; then
			xg_log "tgcalls: применяю $(basename "$patch")"
			git -C "$tgcalls" apply "$patch"
		elif git -C "$tgcalls" apply --check -R "$patch" 2>/dev/null; then
			xg_log "tgcalls: $(basename "$patch") уже применён"
		else
			xg_die "tgcalls: $(basename "$patch") не применяется к $tgcalls"
		fi
	done
}

# ---------------------------------------------------------------- libxray
abi_targets() {
	local out=() abi
	IFS=',' read -ra abis <<< "$XG_ABIS"
	for abi in "${abis[@]}"; do
		case "$abi" in
			arm64-v8a) out+=(android/arm64) ;;
			armeabi-v7a) out+=(android/arm) ;;
			x86_64) out+=(android/amd64) ;;
			x86) out+=(android/386) ;;
			*) xg_die "неизвестный ABI: $abi" ;;
		esac
	done
	local IFS=,; echo "${out[*]}"
}

libxray_bind() {
	local out="$XG_WORK/libxray/libXray.aar"
	mkdir -p "$XG_WORK/libxray"
	cd "$XG_LIBXRAY_SRC"
	# Те же флаги, что в build/app/android.py libXray (API 23 = minSdk Telegram).
	ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$NDK_VERSION" \
	"$GOPATH/bin/gomobile" bind -v -target "$(abi_targets)" -androidapi 23 -trimpath \
		-ldflags="-checklinkname=0 -s -w -buildid= -extldflags=-Wl,-z,max-page-size=16384,--pack-dyn-relocs=android" \
		-o "$out" .
	rm -f "$XG_WORK/libxray/libXray-sources.jar"
}

step_libxray() {
	[[ -x "$GOPATH/bin/gomobile" ]] || step_deps
	local out="$XG_WORK/libxray/libXray.aar" stamp="$XG_WORK/libxray/stamp"
	local want; want="$(git -C "$XG_LIBXRAY_SRC" rev-parse HEAD) $(abi_targets)"
	if [[ -f "$out" && "$(cat "$stamp" 2>/dev/null)" == "$want" ]]; then
		xg_log "libXray.aar уже собран ($want)"
	else
		timed libxray heavy "$SELF" __libxray_bind
		echo "$want" > "$stamp"
	fi
	mkdir -p "$XG_SRC/TMessagesProj/libs"
	cp "$out" "$XG_SRC/TMessagesProj/libs/libXray.aar"
	ls -lh "$out"
}

# ---------------------------------------------------------------- keystore
step_keystore() {
	if [[ -f "$XG_KEYSTORE" && -f "$XG_KEYSTORE_ENV" ]]; then
		xg_log "ключ подписи: $XG_KEYSTORE"
		return
	fi
	[[ ! -f "$XG_KEYSTORE" ]] || xg_die "есть $XG_KEYSTORE, но нет $XG_KEYSTORE_ENV с паролем"
	xg_log "создаю ключ подписи $XG_KEYSTORE (RSA 4096, 100 лет)"
	mkdir -p "$XG_SECRETS"; chmod 700 "$XG_SECRETS"
	local pass; pass="$(openssl rand -hex 24)"
	(umask 077; printf 'XRAYGRAM_KEYSTORE_PASSWORD=%s\nXRAYGRAM_KEY_ALIAS=xraygram\n' "$pass" > "$XG_KEYSTORE_ENV")
	"$JAVA_HOME/bin/keytool" -genkeypair -keystore "$XG_KEYSTORE" -storetype PKCS12 -alias xraygram \
		-keyalg RSA -keysize 4096 -validity 36500 -dname "CN=Xraygram" \
		-storepass "$pass" -keypass "$pass" >/dev/null 2>&1
	chmod 600 "$XG_KEYSTORE"
	xg_warn "ключ подписи создан: сохраните $XG_KEYSTORE и $XG_KEYSTORE_ENV — без них обновления не поставятся поверх"
}

# ---------------------------------------------------------------- apk
gradle_env() {
	[[ -f "$XG_API_ENV" ]] || xg_die "нет $XG_API_ENV (TDESKTOP_API_ID/TDESKTOP_API_HASH с my.telegram.org), см. android/README.md"
	# shellcheck disable=SC1090
	set -a; source "$XG_API_ENV"; source "$XG_KEYSTORE_ENV"; set +a
	[[ -n "${TDESKTOP_API_ID:-}" && -n "${TDESKTOP_API_HASH:-}" ]] || xg_die "в $XG_API_ENV нет TDESKTOP_API_ID/TDESKTOP_API_HASH"
	# Значения уходят в Gradle через окружение (не в аргументы, не в файлы репозитория).
	export ORG_GRADLE_PROJECT_XRAYGRAM_API_ID="$TDESKTOP_API_ID"
	export ORG_GRADLE_PROJECT_XRAYGRAM_API_HASH="$TDESKTOP_API_HASH"
	local build_id; build_id="$(next_build_id)"
	echo "$build_id" > "$XG_WORK/build-id"
	export ORG_GRADLE_PROJECT_XRAYGRAM_BUILD="$build_id"
	# versionCode растёт с каждой сборкой: android-20261119-4 → 26111904 (×10 + ABI в gradle → 261119049)
	local ymd="${build_id#android-20}" ; ymd="${ymd%-*}"
	export ORG_GRADLE_PROJECT_XRAYGRAM_VERSION_CODE="$(( 10#$ymd * 100 + ${build_id##*-} ))"
	export ORG_GRADLE_PROJECT_XRAYGRAM_KEYSTORE="$XG_KEYSTORE"
	export ORG_GRADLE_PROJECT_XRAYGRAM_KEYSTORE_PASSWORD="$XRAYGRAM_KEYSTORE_PASSWORD"
	export ORG_GRADLE_PROJECT_XRAYGRAM_KEY_ALIAS="$XRAYGRAM_KEY_ALIAS"
	unset TDESKTOP_API_ID TDESKTOP_API_HASH XRAYGRAM_KEYSTORE_PASSWORD
	gradle_fcm
	brand_icons
	printf 'sdk.dir=%s\n' "$ANDROID_HOME" > "$XG_SRC/local.properties"
}

# FEAT-09: свой проект Firebase. .secrets/google-services.json (package io.github.xraygram) кладётся в
# TMessagesProj_AppStandalone/src/afatStandalone/ — google-services берёт файл варианта раньше корневого (телеграмовского).
# Этот путь исключён из git и патча. Нет файла — сборка без FCM (XRAYGRAM_FCM=false).
gradle_fcm() {
	local src="$XG_SECRETS/google-services.json"
	local dst="$XG_SRC/TMessagesProj_AppStandalone/src/afatStandalone/google-services.json"
	grep -qx 'TMessagesProj_AppStandalone/src/afatStandalone/google-services.json' "$XG_SRC/.git/info/exclude" 2>/dev/null \
		|| echo 'TMessagesProj_AppStandalone/src/afatStandalone/google-services.json' >> "$XG_SRC/.git/info/exclude"
	if [[ -f "$src" ]]; then
		python3 -I - "$src" "$XG_APP_ID" <<'PY' || xg_die "$src не подходит (нужен свой проект Firebase с Android-приложением $XG_APP_ID)"
import json, sys
d = json.load(open(sys.argv[1]))
pkgs = [c["client_info"]["android_client_info"]["package_name"] for c in d.get("client", [])]
assert d["project_info"]["project_id"] != "tmessages2", "это телеграмовский google-services.json"
assert sys.argv[2] in pkgs, "нет клиента " + sys.argv[2]
PY
		mkdir -p "$(dirname "$dst")"
		(umask 077; cp "$src" "$dst")
		export ORG_GRADLE_PROJECT_XRAYGRAM_FCM=true
		xg_log "FCM: свой google-services.json — пуши Firebase включены"
	else
		rm -f "$dst"
		export ORG_GRADLE_PROJECT_XRAYGRAM_FCM=false
		xg_log "FCM: нет $src — сборка без пушей Firebase (Keep-Alive по умолчанию)"
	fi
}

# FEAT-07: иконка из branding/android (единый источник для всех платформ). Копируется поверх ic_launcher_sa
# модуля Standalone при каждой сборке; эти файлы update-patch.sh в патч не выгружает.
brand_icons() {
	local b="$XG_REPO/branding/android" g="$XG_REPO/branding/glyph/android" res="$XG_SRC/TMessagesProj_AppStandalone/src/main/res"
	[[ -f "$b/ic_launcher_foreground.png" ]] || { xg_warn "нет $b — иконка телеграмовская"; return; }
	local d
	for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
		cp "$b/mipmap-$d/ic_launcher.png" "$res/mipmap-$d/ic_launcher_sa.png"
	done
	cp "$b/ic_launcher_foreground.png" "$res/mipmap-xxxhdpi/xraygram_icon_foreground.png"
	cp "$b/ic_launcher_background.png" "$res/mipmap-xxxhdpi/xraygram_icon_background.png"
	cat > "$res/mipmap-anydpi-v26/ic_launcher_sa.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<!-- Xraygram (FEAT-07): generated by android/scripts/build-local.sh from branding/android -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/xraygram_icon_background" />
    <foreground android:drawable="@mipmap/xraygram_icon_foreground" />
</adaptive-icon>
XML
	# Тематические иконки Android 13+ (FEAT-19 §3): monochrome-слой из branding/glyph.
	if [[ -f "$g/ic_launcher_monochrome.png" ]]; then
		cp "$g/ic_launcher_monochrome.png" "$res/mipmap-xxxhdpi/xraygram_icon_monochrome.png"
		mkdir -p "$res/mipmap-anydpi-v33"
		cat > "$res/mipmap-anydpi-v33/ic_launcher_sa.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<!-- Xraygram (FEAT-07/19): generated by android/scripts/build-local.sh from branding/android and branding/glyph -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/xraygram_icon_background" />
    <foreground android:drawable="@mipmap/xraygram_icon_foreground" />
    <monochrome android:drawable="@mipmap/xraygram_icon_monochrome" />
</adaptive-icon>
XML
	fi
	# FEAT-19 (PAR-19): та же иконка в модуле TMessagesProj под своими именами — для окна «Поделиться»
	# (intent-filter), системных контактов, звонка в системе, окна условий. Патч ссылается на
	# @mipmap/xraygram_launcher{,_round}, @drawable/ic_stat_xraygram, @drawable/xraygram_splash; в патч файлы не идут.
	local lib="$XG_SRC/TMessagesProj/src/main/res"
	for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
		mkdir -p "$lib/mipmap-$d" "$lib/drawable-$d"
		cp "$b/mipmap-$d/ic_launcher.png" "$lib/mipmap-$d/xraygram_launcher.png"
		cp "$b/mipmap-$d/ic_launcher_round.png" "$lib/mipmap-$d/xraygram_launcher_round.png"
		# шторка уведомлений: монохромный знак 24 dp
		cp "$g/drawable-$d/ic_stat_xraygram.png" "$lib/drawable-$d/ic_stat_xraygram.png"
	done
	mkdir -p "$lib/drawable-nodpi"
	# Заставка (FEAT-19 §1): иконка 176 dp со скруглением и свечением на холсте 240 dp (branding/launch).
	cp "$XG_REPO/branding/launch/android-splash-xxxhdpi.png" "$lib/drawable-nodpi/xraygram_splash.png"
	rm -f "$lib/drawable-nodpi/xraygram_splash_foreground.png" "$lib/drawable-nodpi/xraygram_splash_background.png" \
		"$lib/drawable-nodpi/xraygram_icon_large.png"
	xg_log "иконка: branding/android, знак: branding/glyph, заставка: branding/launch"
}

gradle_build() {
	cd "$XG_SRC"
	./gradlew --console=plain -Dorg.gradle.jvmargs="-Xmx6g -XX:MaxMetaspaceSize=1g" \
		-PAPP_PACKAGE="$XG_APP_ID" -PXRAYGRAM_ABIS="$XG_ABIS" \
		:TMessagesProj_AppStandalone:assembleAfatStandalone
}

# ID сборки по docs/process.md: android-<ГГГГММДД>-<N>, N — следующий после записанных в docs/builds.md и лежащих в dist/.
next_build_id() {
	local day; day="$(date +%Y%m%d)"
	local n; n="$( { grep -oE "android-$day-[0-9]+" "$XG_REPO/docs/builds.md" 2>/dev/null; ls "$XG_DIST" 2>/dev/null | grep -oE "android-$day-[0-9]+"; } \
		| sed -E 's/.*-//' | sort -n | tail -1 || true)"
	echo "android-$day-$(( ${n:-0} + 1 ))"
}

copy_apk() {
	local apk="$XG_SRC/TMessagesProj_AppStandalone/build/outputs/apk/afat/standalone/app.apk"
	[[ -f "$apk" ]] || xg_die "нет $apk"
	local ver; ver="$(grep '^APP_VERSION_NAME=' "$XG_SRC/gradle.properties" | cut -d= -f2)"
	local abi="${XG_ABIS//,/-}"
	# ID сборки по docs/process.md: android-<ГГГГММДД>-<N>, N — следующий после записанных в docs/builds.md и лежащих
	# в dist/. Выданные APK никогда не перезаписываются. Регистрация в docs/builds.md и сообщение QA — вручную.
	# ID вшит в APK при сборке (gradle_env → BuildConfig.XRAYGRAM_BUILD, «О приложении»), берём его же.
	local id; id="$(cat "$XG_WORK/build-id" 2>/dev/null || true)"
	[[ -n "$id" && ! -e "$XG_DIST/Xraygram-$id.apk" ]] || id="$(next_build_id)"
	rm -f "$XG_WORK/build-id"
	local dst="$XG_DIST/Xraygram-$id.apk"
	[[ ! -e "$dst" ]] || xg_die "$dst уже есть"
	echo "$id ($ver, $abi)" > "$dst.id"
	cp "$apk" "$dst"
	(cd "$XG_DIST" && shasum -a 256 "$(basename "$dst")" > "$(basename "$dst").sha256")
	ln -sf "$(basename "$dst")" "$XG_DIST/Xraygram-latest.apk"
	ls -lh "$dst"
	"$ANDROID_HOME/build-tools/$BUILD_TOOLS/aapt2" dump badging "$dst" 2>/dev/null | grep -E "^package:|^application-label:|native-code" || true
}

step_apk() {
	[[ -f "$XG_SRC/TMessagesProj/libs/libXray.aar" ]] || step_libxray
	step_keystore
	gradle_env
	timed apk heavy "$SELF" __gradle_build
	copy_apk
}

step_quick() {
	gradle_env
	timed apk-quick gradle_build
	copy_apk
}

# ---------------------------------------------------------------- device
step_install() {
	local apk="$XG_DIST/Xraygram-latest.apk"
	[[ -e "$apk" ]] || xg_die "нет APK, сначала: build-local.sh apk"
	adb install -r "$apk"
}

step_run() {
	local act
	act="$(adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$XG_APP_ID" | tail -1 | tr -d '\r')"
	adb shell am start -n "$act"
}

step_emulator() {
	if [[ ! -x "$ANDROID_HOME/emulator/emulator" || ! -d "$ANDROID_HOME/${EMU_IMAGE//;//}" ]]; then
		timed emulator-sdk xg_sdkmanager "emulator" "$EMU_IMAGE"
	fi
	if [[ ! -d "$ANDROID_AVD_HOME/$AVD_NAME.avd" ]]; then
		mkdir -p "$ANDROID_AVD_HOME"
		echo no | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd -n "$AVD_NAME" -k "$EMU_IMAGE" -d pixel_7 --force
	fi
	if adb devices | grep -q '^emulator-'; then
		xg_log "эмулятор уже запущен"
		return
	fi
	xg_log "запускаю эмулятор $AVD_NAME (лог: $XG_LOGS/emulator.log)"
	nohup "$ANDROID_HOME/emulator/emulator" -avd "$AVD_NAME" -no-snapshot-save -no-boot-anim -gpu auto \
		> "$XG_LOGS/emulator.log" 2>&1 &
	adb wait-for-device
	until [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == "1" ]]; do sleep 2; done
	xg_log "эмулятор загрузился"
}

step_status() {
	echo "SDK:       $( [[ -d $ANDROID_HOME/ndk/$NDK_VERSION ]] && echo ok || echo нет)"
	echo "gomobile:  $( [[ -x $GOPATH/bin/gomobile ]] && echo ok || echo нет)"
	echo "исходники: $(git -C "$XG_SRC" log --oneline -1 2>/dev/null || echo нет) [$(git -C "$XG_SRC" rev-parse --abbrev-ref HEAD 2>/dev/null)]"
	echo "libXray:   $(ls -lh "$XG_WORK/libxray/libXray.aar" 2>/dev/null | awk '{print $5}' || echo нет)"
	echo "ключ:      $( [[ -f $XG_KEYSTORE ]] && echo "$XG_KEYSTORE" || echo нет)"
	echo "APK:       $(ls -1 "$XG_DIST"/*.apk 2>/dev/null | tr '\n' ' ')"
	echo "очередь:   $("$HEAVY" status)"
}

steps=("$@")
(( ${#steps[@]} )) || steps=(all)
for s in "${steps[@]}"; do
	case "$s" in
		all) step_deps; step_src; step_libxray; step_keystore; step_apk ;;
		deps|src|libxray|keystore|apk|quick|install|run|emulator|status) "step_$s" ;;
		__libxray_bind) libxray_bind ;;   # внутренние: вызываются через очередь heavy-build
		__gradle_build) gradle_build ;;
		*) xg_die "неизвестный шаг: $s" ;;
	esac
done
