#!/usr/bin/env bash
# Профиль подписи для бесплатного Apple ID (Personal Team) через проект-заглушку.
#
#   ios/scripts/signing-stub.sh <bundle-id> [device-udid]
#   ios/scripts/signing-stub.sh <bundle-id> --check   # только проверить проект (симулятор, без подписи)
#
# Создаёт в upstream/xraygram-ios/signing-stub крошечное приложение с тем же bundle id и
# App Group group.<bundle-id> и собирает его xcodebuild'ом с автоматической подписью:
# Xcode регистрирует App ID, группу и подключённый iPhone в Personal Team и кладёт профиль
# в свой каталог профилей. Потом `build.sh signing` забирает его в upstream/xraygram-ios/signing.
#
# Нужно от владельца заранее: Xcode → Settings → Accounts → войти Apple ID (бесплатный);
# iPhone подключён кабелем, разблокирован, «Доверять этому компьютеру», Developer Mode включён.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BUNDLE_ID="${1:?bundle id}"
DEVICE="${2:-}"
STUB="$XG_WORK/signing-stub"
CHECK=0
if [[ "$DEVICE" == "--check" ]]; then
	CHECK=1
	DEVICE=""
fi

team_from_xcode() {
	# Команды из аккаунтов Xcode; бесплатная — «Personal Team» (isFreeProvisioningTeam).
	{ defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null || true; } \
		| python3 -I -c '
import re, sys
text = sys.stdin.read()
free = re.findall(r"isFreeProvisioningTeam = 1;[^}]*?teamID = (\w+);", text, re.S)
free += re.findall(r"teamID = (\w+);[^}]*?isFreeProvisioningTeam = 1;", text, re.S)
anyteam = re.findall(r"teamID = (\w+);", text)
print((free or anyteam or [""])[0])'
}

TEAM="$(xg_env_get "$XG_IOS_ENV" XRAYGRAM_IOS_TEAM_ID)"
[[ -n "$TEAM" && "$TEAM" != "0000000000" ]] || TEAM="$(team_from_xcode)"
if (( CHECK )); then
	TEAM="${TEAM:-0000000000}"
	DEVICE="check"
fi
[[ -n "$TEAM" ]] || xg_die "в Xcode нет аккаунта. Владелец: Xcode → Settings → Accounts → «+» → Apple ID, потом повторить"

if [[ -z "$DEVICE" ]]; then
	DEVICE="$(xcrun devicectl list devices --hide-default-columns --columns Identifier --columns State 2>/dev/null \
		| awk '/connected/{print $1; exit}')"
fi
[[ -n "$DEVICE" ]] || xg_die "iPhone не найден: подключите кабелем, разблокируйте, «Доверять», включите Developer Mode"
UDID="$DEVICE"
if (( ! CHECK )); then
	UDID="$(xcrun devicectl device info details --device "$DEVICE" 2>/dev/null | awk -F': ' '/udid/{print $2; exit}')"
	UDID="${UDID:-$DEVICE}"
fi

rm -rf "$STUB"
mkdir -p "$STUB/Stub" "$STUB/Stub.xcodeproj"
cat > "$STUB/Stub/main.swift" <<'SWIFT'
import UIKit
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, nil)
SWIFT
cat > "$STUB/Stub/Stub.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.$BUNDLE_ID</string>
	</array>
</dict>
</plist>
PLIST
cat > "$STUB/Stub.xcodeproj/project.pbxproj" <<PBX
// !\$*UTF8*\$!
{
	archiveVersion = 1;
	classes = {};
	objectVersion = 56;
	objects = {
		A0000000000000000000001 /* main.swift in Sources */ = {isa = PBXBuildFile; fileRef = A0000000000000000000002; };
		A0000000000000000000002 /* main.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = main.swift; sourceTree = "<group>"; };
		A0000000000000000000003 /* Stub.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Stub.entitlements; sourceTree = "<group>"; };
		A0000000000000000000004 /* Xraygram.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Xraygram.app; sourceTree = BUILT_PRODUCTS_DIR; };
		A0000000000000000000010 = {isa = PBXGroup; children = (A0000000000000000000011, A0000000000000000000012); sourceTree = "<group>"; };
		A0000000000000000000011 /* Stub */ = {isa = PBXGroup; children = (A0000000000000000000002, A0000000000000000000003); path = Stub; sourceTree = "<group>"; };
		A0000000000000000000012 /* Products */ = {isa = PBXGroup; children = (A0000000000000000000004); name = Products; sourceTree = "<group>"; };
		A0000000000000000000020 /* Sources */ = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A0000000000000000000001); runOnlyForDeploymentPostprocessing = 0; };
		A0000000000000000000030 /* Xraygram */ = {isa = PBXNativeTarget; buildConfigurationList = A0000000000000000000050; buildPhases = (A0000000000000000000020); buildRules = (); dependencies = (); name = Xraygram; productName = Xraygram; productReference = A0000000000000000000004; productType = "com.apple.product-type.application"; };
		A0000000000000000000040 /* Project object */ = {isa = PBXProject; attributes = {LastUpgradeCheck = 2700; TargetAttributes = {A0000000000000000000030 = {CreatedOnToolsVersion = 27.0; }; }; }; buildConfigurationList = A0000000000000000000060; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = A0000000000000000000010; productRefGroup = A0000000000000000000012; projectDirPath = ""; projectRoot = ""; targets = (A0000000000000000000030); };
		A0000000000000000000051 /* Debug */ = {isa = XCBuildConfiguration; buildSettings = {
			CODE_SIGN_ENTITLEMENTS = Stub/Stub.entitlements;
			CODE_SIGN_STYLE = Automatic;
			DEVELOPMENT_TEAM = $TEAM;
			GENERATE_INFOPLIST_FILE = YES;
			INFOPLIST_KEY_CFBundleDisplayName = Xraygram;
			INFOPLIST_KEY_UILaunchScreen_Generation = YES;
			IPHONEOS_DEPLOYMENT_TARGET = 15.0;
			PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID;
			PRODUCT_NAME = Xraygram;
			SDKROOT = iphoneos;
			SWIFT_VERSION = 5.0;
			TARGETED_DEVICE_FAMILY = "1,2";
		}; name = Debug; };
		A0000000000000000000061 /* Debug */ = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = iphoneos; }; name = Debug; };
		A0000000000000000000050 = {isa = XCConfigurationList; buildConfigurations = (A0000000000000000000051); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
		A0000000000000000000060 = {isa = XCConfigurationList; buildConfigurations = (A0000000000000000000061); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
	};
	rootObject = A0000000000000000000040;
}
PBX

if (( CHECK )); then
	xg_timed signing-stub-check xcodebuild -project "$STUB/Stub.xcodeproj" -scheme Xraygram \
		-sdk iphonesimulator -destination "generic/platform=iOS Simulator" \
		-derivedDataPath "$STUB/DerivedData" CODE_SIGNING_ALLOWED=NO build
	exit 0
fi

xg_log "заглушка: bundle $BUNDLE_ID, team $TEAM, устройство $UDID"
xg_timed signing-stub xcodebuild \
	-project "$STUB/Stub.xcodeproj" \
	-scheme Xraygram \
	-configuration Debug \
	-destination "id=$UDID" \
	-derivedDataPath "$STUB/DerivedData" \
	-allowProvisioningUpdates \
	-allowProvisioningDeviceRegistration \
	build
xg_log "профиль выпущен; дальше: ios/scripts/build.sh signing"
