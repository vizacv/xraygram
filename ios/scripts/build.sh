#!/usr/bin/env bash
# Сборка Xraygram iOS (Telegram-iOS + патч + XraygramCore/XraygramKit) на Apple Silicon.
#
#   ios/scripts/build.sh <команда> [--release]
#
# Команды:
#   src        клон Telegram-iOS $TGIOS_REF с сабмодулями + патчи (если исходников ещё нет)
#   core       собрать XraygramCore.xcframework (Go, ios/xraykit/go) — ios/scripts/build-core.sh
#   prepare    положить ядро и XraygramKit в дерево, сгенерировать configuration.json
#   sim        собрать для симулятора (arm64), без подписи и расширений → dist/Xraygram-sim.app
#   run-sim    поставить в симулятор «Xraygram iPhone» и запустить
#   signing    взять из Xcode профиль бесплатного Apple ID для bundle id → upstream/xraygram-ios/signing
#   device     собрать для iPhone с бесплатной подписью (без расширений) → dist/Xraygram.ipa
#   device-check  собрать фреймворки для iPhone без профиля (проверка компиляции/линковки arm64)
#   install    поставить dist/Xraygram.ipa на подключённый iPhone (devicectl)
#   snapshot   снять последнюю сборку под ID ios-ГГГГММДД-N (docs/process.md): dist/Xraygram-<ID>-sim.app
#              и/или dist/Xraygram-<ID>.ipa; дальше — строка в docs/builds.md и сообщение QA
#   status     что готово
#
# По умолчанию Debug (debug_sim_arm64 / debug_arm64); --release — release_*.
# Тяжёлые шаги (sim, device) запускайте через очередь: tools/heavy-build.sh ios ios/scripts/build.sh sim
#
# Ключи API: TDESKTOP_API_ID/TDESKTOP_API_HASH из .secrets/api.env (те же, что у macOS).
# Свои параметры iOS (необязательно) — .secrets/ios.env:
#   XRAYGRAM_IOS_BUNDLE_ID=io.github.vizacv.xraygram   # должен быть уникален в Apple
#   XRAYGRAM_IOS_TEAM_ID=ABCDE12345                   # Team ID «Personal Team» (signing заполнит сам)

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

RELEASE=0
COMMAND="status"
for arg in "$@"; do
	case "$arg" in
		--release) RELEASE=1 ;;
		--debug) RELEASE=0 ;;
		-h|--help) sed -n '2,25p' "$0"; exit 0 ;;
		*) COMMAND="$arg" ;;
	esac
done

DEFAULT_BUNDLE_ID="io.github.vizacv.xraygram"
SIM_NAME="Xraygram iPhone"
CONFIG_JSON="$XG_WORK/configuration.json"
BUILD_NUMBER="${XRAYGRAM_BUILD_NUMBER:-$(date +%y%m%d%H)}"

mkdir -p "$XG_WORK" "$XG_LOGS" "$XG_DIST"

bundle_id() {
	local value
	value="$(xg_env_get "$XG_IOS_ENV" XRAYGRAM_IOS_BUNDLE_ID)"
	echo "${value:-$DEFAULT_BUNDLE_ID}"
}

team_id() {
	local value
	value="$(xg_env_get "$XG_IOS_ENV" XRAYGRAM_IOS_TEAM_ID)"
	echo "${value:-0000000000}"
}

cmd_src() {
	if [[ -d "$XG_SRC/.git" ]]; then
		xg_log "исходники: $XG_SRC ($(git -C "$XG_SRC" branch --show-current))"
		return
	fi
	timed_clone() {
		git init -q "$XG_SRC"
		git -C "$XG_SRC" remote add origin "$TGIOS_URL"
		git -C "$XG_SRC" fetch -q --depth 1 origin "$TGIOS_REF"
		git -C "$XG_SRC" checkout -q FETCH_HEAD
		git -C "$XG_SRC" submodule update --init --recursive --depth 1 --jobs 8
	}
	xg_timed clone timed_clone
	git -C "$XG_SRC" switch -q -c xraygram
	for patch in "$XG_PATCHES"/*.patch; do
		xg_log "патч $(basename "$patch")"
		git -C "$XG_SRC" apply --whitespace=nowarn "$patch"
	done
	# Звонки через SOCKS5 xray: патч сабмодуля tgcalls (пути от его корня).
	for patch in "$XG_PATCHES"/tgcalls/*.patch; do
		xg_log "патч tgcalls $(basename "$patch")"
		git -C "$XG_SRC/submodules/TgVoipWebrtc/tgcalls" apply --whitespace=nowarn "$patch"
	done
	git -C "$XG_SRC" add -A
}

cmd_core() {
	"$XG_REPO/ios/scripts/build-core.sh"
}

write_configuration() {
	local id hash
	id="$(xg_env_get "$XG_API_ENV" TDESKTOP_API_ID)"
	hash="$(xg_env_get "$XG_API_ENV" TDESKTOP_API_HASH)"
	[[ -n "$id" && -n "$hash" ]] || xg_die "нет ключей API в $XG_API_ENV (TDESKTOP_API_ID/TDESKTOP_API_HASH)"
	[[ "$id" =~ ^[0-9]+$ ]] || xg_die "TDESKTOP_API_ID должен быть числом"
	[[ "$hash" =~ ^[0-9a-fA-F]{32}$ ]] || xg_die "TDESKTOP_API_HASH должен быть 32 hex-символа"
	local tmp
	tmp="$(mktemp "$XG_WORK/configuration.XXXXXX")"
	chmod 600 "$tmp"
	BUNDLE_ID="$(bundle_id)" TEAM_ID="$(team_id)" API_ID="$id" API_HASH="$hash" python3 -I - > "$tmp" <<'PY'
import json, os
print(json.dumps({
    "bundle_id": os.environ["BUNDLE_ID"],
    "api_id": os.environ["API_ID"],
    "api_hash": os.environ["API_HASH"],
    "team_id": os.environ["TEAM_ID"],
    "is_internal_build": "false",
    "is_appstore_build": "false",
    "appstore_id": "0",
    "app_specific_url_scheme": "xraygram",
    "premium_iap_product_id": "",
    "enable_siri": False,
    "enable_icloud": False,
}, indent=2))
PY
	mv "$tmp" "$CONFIG_JSON"
	xg_log "configuration.json: bundle $(bundle_id), team $(team_id), свои ключи API"
}

cmd_prepare() {
	[[ -d "$XG_SRC/.git" ]] || xg_die "нет исходников, запустите: $0 src"
	[[ -d "$XG_XCFRAMEWORK_CORE" ]] || cmd_core
	rsync -a --delete "$XG_XCFRAMEWORK_CORE/" "$XG_SRC/third-party/XraygramCore/XraygramCore.xcframework/"
	mkdir -p "$XG_SRC/submodules/XraygramKit/Sources"
	rsync -a --delete "$XG_REPO/ios/xraykit/swift/XraygramKit/Sources/" "$XG_SRC/submodules/XraygramKit/Sources/"
	# Иконка Xraygram (FEAT-07): канон — branding/ios/AppIcon-1024.png.
	install -m 644 "$XG_REPO/branding/ios/AppIcon-1024.png" \
		"$XG_SRC/Telegram/Telegram-iOS/XraygramAppIcon.xcassets/AppIcon.appiconset/AppIcon-1024.png"
	# FEAT-19: заставка и вступление (branding/launch: холст 240 pt, иконка 176 pt со свечением) и знак
	# CallKit (branding/glyph/ios, 40 pt, важна только альфа) вместо самолётика.
	local res="$XG_SRC/Telegram/Telegram-iOS/Resources" s
	for s in 2x 3x; do
		install -m 644 "$XG_REPO/branding/launch/LaunchIcon@$s.png" "$res/XraygramLaunchIcon@$s.png"
		install -m 644 "$XG_REPO/branding/glyph/ios/CallKitIcon@$s.png" \
			"$XG_SRC/submodules/TelegramUI/Images.xcassets/Call/CallKitLogo.imageset/CallKitLogo@$s.png"
	done
	write_configuration
}

# XRAYGRAM_KEEP_GOING=1 — bazel --keep_going: все ошибки компиляции за один проход.
keep_going() {
	[[ "${XRAYGRAM_KEEP_GOING:-0}" == "1" ]] && echo "--continueOnError"
	return 0
}

make_py() { # аргументы после общих
	cd "$XG_SRC"
	python3 build-system/Make/Make.py \
		--overrideXcodeVersion \
		--bazelUserRoot "$XG_BAZEL_ROOT" \
		--cacheDir "$XG_BAZEL_CACHE" \
		"$@"
}

extract_app() { # $1 = ipa, $2 = куда положить .app
	local stage
	stage="$(mktemp -d "$XG_WORK/stage.XXXXXX")"
	unzip -q -o "$1" -d "$stage"
	rm -rf "$2"
	mv "$stage/Payload/Telegram.app" "$2"
	rm -rf "$stage"
}

cmd_sim() {
	cmd_prepare
	local configuration="debug_sim_arm64"
	(( RELEASE )) && configuration="release_sim_arm64"
	xg_timed "sim-$configuration" make_py build $(keep_going) \
		--configurationPath "$CONFIG_JSON" \
		--xcodeManagedCodesigning \
		--disableProvisioningProfiles \
		--disableExtensions \
		--buildNumber "$BUILD_NUMBER" \
		--configuration "$configuration"
	extract_app "$XG_SRC/bazel-bin/Telegram/Telegram.ipa" "$XG_DIST/Xraygram-sim.app"
	xg_log "готово: $XG_DIST/Xraygram-sim.app"
}

sim_udid() {
	local udid runtime
	udid="$(xcrun simctl list devices -j | python3 -I -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if device["name"] == name and device.get("isAvailable"):
            print(device["udid"]); sys.exit(0)
' "$SIM_NAME")"
	if [[ -z "$udid" ]]; then
		runtime="$(xcrun simctl list runtimes -j | python3 -I -c '
import json, sys
import re
items = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
# Обычный рантайм (без суффикса устройства вроде -iPhone19-4).
plain = [r for r in items if re.search(r"iOS-\d+-\d+$", r["identifier"])]
print((plain or items)[-1]["identifier"])')"
		udid="$(xcrun simctl create "$SIM_NAME" "iPhone 17" "$runtime" 2>/dev/null \
			|| xcrun simctl create "$SIM_NAME" "$(xcrun simctl list devicetypes | awk -F' [(]' '/iPhone/{n=$1} END{print n}')" "$runtime")"
	fi
	echo "$udid"
}

cmd_run_sim() {
	local app="$XG_DIST/Xraygram-sim.app" udid
	[[ -d "$app" ]] || xg_die "нет $app, сначала: $0 sim"
	udid="$(sim_udid)"
	xcrun simctl boot "$udid" 2>/dev/null || true
	open -a Simulator --args -CurrentDeviceUDID "$udid" 2>/dev/null || true
	xcrun simctl terminate "$udid" "$(bundle_id)" 2>/dev/null || true
	# simctl install не заменяет приложение с тем же номером сборки (кэш installd), поэтому
	# поверх установленного копируем бандл целиком; контейнер данных (вход в аккаунт) не трогается.
	local dest
	dest="$(xcrun simctl get_app_container "$udid" "$(bundle_id)" app 2>/dev/null || true)"
	if [[ -n "$dest" && -d "$dest" && -x "$app/Telegram" ]]; then
		rm -rf "$dest" && cp -Rp "$app" "$dest"
	else
		xcrun simctl install "$udid" "$app"
	fi
	xcrun simctl launch "$udid" "$(bundle_id)"
	xg_log "запущено в симуляторе $SIM_NAME ($udid)"
}

# Профили, которые Xcode скачал/создал для бесплатного Apple ID (Personal Team).
profile_dirs=(
	"$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
	"$HOME/Library/MobileDevice/Provisioning Profiles"
)

cmd_signing() {
	local bid found="" dir file appid team
	bid="$(bundle_id)"
	for dir in "${profile_dirs[@]}"; do
		[[ -d "$dir" ]] || continue
		for file in "$dir"/*.mobileprovision; do
			[[ -f "$file" ]] || continue
			appid="$(security cms -D -i "$file" 2>/dev/null | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null || true)"
			if [[ "$appid" == *".$bid" ]]; then
				found="$file"
				team="${appid%%.*}"
			fi
		done
	done
	if [[ -z "$found" ]]; then
		xg_warn "профиля для $bid нет. Нужен шаг владельца (см. ios/README.md, «Подпись»):"
		xg_warn "  Xcode → Settings → Accounts → Apple ID; iPhone подключён, Developer Mode включён;"
		xg_warn "  затем: $0 signing-stub (создаст профиль через проект-заглушку)"
		return 1
	fi
	rm -rf "$XG_SIGNING"
	mkdir -p "$XG_SIGNING/profiles" "$XG_SIGNING/certs"
	cp "$found" "$XG_SIGNING/profiles/Telegram.mobileprovision"
	if [[ "$(team_id)" != "$team" ]]; then
		touch "$XG_IOS_ENV"; chmod 600 "$XG_IOS_ENV"
		grep -v '^XRAYGRAM_IOS_TEAM_ID=' "$XG_IOS_ENV" > "$XG_IOS_ENV.tmp" || true
		echo "XRAYGRAM_IOS_TEAM_ID=$team" >> "$XG_IOS_ENV.tmp"
		mv "$XG_IOS_ENV.tmp" "$XG_IOS_ENV"; chmod 600 "$XG_IOS_ENV"
	fi
	local expires groups
	expires="$(security cms -D -i "$found" | plutil -extract ExpirationDate raw -o - - 2>/dev/null || echo '?')"
	groups="$(security cms -D -i "$found" | plutil -extract Entitlements.com\\.apple\\.security\\.application-groups json -o - - 2>/dev/null || echo 'нет')"
	xg_log "профиль: $(basename "$found"), team $team, истекает $expires, app groups: $groups"
}

cmd_signing_stub() {
	"$XG_REPO/ios/scripts/signing-stub.sh" "$(bundle_id)"
}

cmd_device() {
	[[ -f "$XG_SIGNING/profiles/Telegram.mobileprovision" ]] || cmd_signing || xg_die "нет профиля подписи"
	cmd_prepare
	local configuration="debug_arm64"
	(( RELEASE )) && configuration="release_arm64"
	xg_timed "device-$configuration" make_py build $(keep_going) \
		--configurationPath "$CONFIG_JSON" \
		--codesigningInformationPath "$XG_SIGNING" \
		--disableExtensions \
		--buildNumber "$BUILD_NUMBER" \
		--configuration "$configuration"
	cp "$XG_SRC/bazel-bin/Telegram/Telegram.ipa" "$XG_DIST/Xraygram.ipa"
	codesign -dv --verbose=2 "$XG_DIST/Xraygram.ipa" > /dev/null 2>&1 || true
	xg_log "готово: $XG_DIST/Xraygram.ipa"
}

cmd_device_check() {
	cmd_prepare
	local configuration="debug_arm64"
	(( RELEASE )) && configuration="release_arm64"
	# Само приложение для устройства без профиля не анализируется (rules_apple требует
	# provisioning_profile), поэтому собираем TelegramUIFramework: он тянет TelegramCore с ядром и
	# почти весь код.
	xg_timed "device-check-$configuration" make_py build $(keep_going) \
		--target //Telegram:TelegramUIFramework \
		--configurationPath "$CONFIG_JSON" \
		--xcodeManagedCodesigning \
		--disableProvisioningProfiles \
		--disableExtensions \
		--buildNumber "$BUILD_NUMBER" \
		--configuration "$configuration"
	xg_log "компиляция для iPhone (arm64) прошла: TelegramUIFramework + TelegramCore с XraygramCore"
}

cmd_install() {
	local ipa="$XG_DIST/Xraygram.ipa" app="$XG_DIST/Xraygram.app" device
	[[ -f "$ipa" ]] || xg_die "нет $ipa, сначала: $0 device"
	extract_app "$ipa" "$app"
	device="$(xcrun devicectl list devices --hide-default-columns --columns Identifier --columns State 2>/dev/null \
		| awk '/connected/{print $1; exit}')"
	[[ -n "$device" ]] || xg_die "iPhone не найден: подключите кабелем, разблокируйте, нажмите «Доверять»"
	xcrun devicectl device install app --device "$device" "$app"
	xg_log "установлено на $device. Первый запуск: Настройки → Основные → VPN и управление устройством → доверять разработчику"
}

next_build_id() {
	local today n=1 file
	today="$(date +%Y%m%d)"
	for file in "$XG_DIST"/Xraygram-ios-"$today"-*; do
		[[ -e "$file" ]] || continue
		file="$(basename "$file")"
		file="${file#Xraygram-ios-$today-}"
		file="${file%%[!0-9]*}"
		(( file >= n )) && n=$((file + 1))
	done
	if [[ -f "$XG_REPO/docs/builds.md" ]]; then
		while read -r used; do
			(( used >= n )) && n=$((used + 1))
		done < <(grep -oE "ios-$today-[0-9]+" "$XG_REPO/docs/builds.md" | sed -E 's/.*-//')
	fi
	echo "ios-$today-$n"
}

cmd_snapshot() {
	local id="${XRAYGRAM_BUILD_ID:-$(next_build_id)}" made=0
	if [[ -d "$XG_DIST/Xraygram-sim.app" ]]; then
		ditto "$XG_DIST/Xraygram-sim.app" "$XG_DIST/Xraygram-$id-sim.app"
		xg_log "$id: $XG_DIST/Xraygram-$id-sim.app"
		made=1
	fi
	if [[ -f "$XG_DIST/Xraygram.ipa" ]]; then
		cp "$XG_DIST/Xraygram.ipa" "$XG_DIST/Xraygram-$id.ipa"
		xg_log "$id: $XG_DIST/Xraygram-$id.ipa"
		made=1
	fi
	(( made )) || xg_die "нечего снимать: нет dist/Xraygram-sim.app и dist/Xraygram.ipa"
	xg_log "дальше: строка $id в docs/builds.md и сообщение QA (xraygram-tester)"
}

cmd_status() {
	echo "Xcode:      $DEVELOPER_DIR ($(xcodebuild -version 2>/dev/null | head -1)), xcode-select: $(xcode-select -p)"
	echo "Sources:    $XG_SRC ($(git -C "$XG_SRC" rev-parse --short HEAD 2>/dev/null || echo нет), ветка $(git -C "$XG_SRC" branch --show-current 2>/dev/null))"
	echo "Core:       $([[ -d "$XG_XCFRAMEWORK_CORE" ]] && echo "$XG_XCFRAMEWORK_CORE" || echo нет)"
	echo "Bundle id:  $(bundle_id), team $(team_id)"
	echo "Signing:    $([[ -f "$XG_SIGNING/profiles/Telegram.mobileprovision" ]] && echo готов || echo нет)"
	echo "Sim app:    $([[ -d "$XG_DIST/Xraygram-sim.app" ]] && echo "$XG_DIST/Xraygram-sim.app" || echo нет)"
	echo "IPA:        $([[ -f "$XG_DIST/Xraygram.ipa" ]] && echo "$XG_DIST/Xraygram.ipa" || echo нет)"
	echo "API env:    $([[ -f "$XG_API_ENV" ]] && echo "$XG_API_ENV" || echo "нет $XG_API_ENV")"
}

case "$COMMAND" in
	src) cmd_src ;;
	core) cmd_core ;;
	prepare) cmd_prepare ;;
	sim) cmd_sim ;;
	run-sim) cmd_run_sim ;;
	signing) cmd_signing ;;
	signing-stub) cmd_signing_stub ;;
	device) cmd_device ;;
	device-check) cmd_device_check ;;
	install) cmd_install ;;
	snapshot) cmd_snapshot ;;
	status) cmd_status ;;
	*) xg_die "неизвестная команда: $COMMAND (см. --help)" ;;
esac
