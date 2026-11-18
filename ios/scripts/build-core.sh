#!/usr/bin/env bash
# Собирает XraygramCore.xcframework (ios/xraykit/go, Go c-archive на libXray + Xray-core)
# для iPhone (arm64), симулятора на Apple Silicon (arm64) и macOS arm64 (для будущего Swift-клиента).
#
#   ios/scripts/build-core.sh            # → upstream/xraygram-ios/XraygramCore.xcframework
#
# Кэши Go — в upstream/xraygram-ios/go. Xcode берётся через DEVELOPER_DIR (sudo не нужен).

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

SRC="$XG_REPO/ios/xraykit/go"
OUT="$XG_WORK/core"
XCF="$XG_XCFRAMEWORK_CORE"
MIN_IOS="15.0"
MIN_MACOS="12.0"

build_one() { # $1 = sdk, $2 = GOOS, $3 = clang target
	local sdk="$1" goos="$2" target="$3"
	local dir="$OUT/$sdk-arm64" sysroot
	sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"
	mkdir -p "$dir"
	local flags="-isysroot $sysroot -target $target -arch arm64"
	(
		cd "$SRC"
		env GOOS="$goos" GOARCH=arm64 CGO_ENABLED=1 \
			CC="$(xcrun --sdk "$sdk" -f clang)" CXX="$(xcrun --sdk "$sdk" -f clang++)" \
			CGO_CFLAGS="$flags" CGO_CXXFLAGS="$flags" CGO_LDFLAGS="$flags" \
			go build -trimpath -buildmode=c-archive \
				-ldflags="-s -w -buildid=" \
				-o "$dir/libxraygramcore.a" .
	)
}

[[ -f "$SRC/go.sum" ]] || xg_timed core-go-mod-tidy bash -c "cd '$SRC' && go mod tidy"
rm -rf "$OUT" "$XCF"
xg_timed core-iphoneos build_one iphoneos ios "arm64-apple-ios$MIN_IOS"
xg_timed core-iphonesimulator build_one iphonesimulator ios "arm64-apple-ios$MIN_IOS-simulator"
xg_timed core-macosx build_one macosx darwin "arm64-apple-macos$MIN_MACOS"

include="$OUT/include"
mkdir -p "$include"
cp "$OUT/iphoneos-arm64/libxraygramcore.h" "$include/XraygramCore.h"
cat > "$include/module.modulemap" <<'MAP'
module XraygramCore {
  header "XraygramCore.h"
  export *
}
MAP
xcodebuild -create-xcframework \
	-library "$OUT/iphoneos-arm64/libxraygramcore.a" -headers "$include" \
	-library "$OUT/iphonesimulator-arm64/libxraygramcore.a" -headers "$include" \
	-library "$OUT/macosx-arm64/libxraygramcore.a" -headers "$include" \
	-output "$XCF" > "$XG_LOGS/core-xcframework.log" 2>&1 || { cat "$XG_LOGS/core-xcframework.log"; exit 1; }
du -sh "$OUT"/*-arm64/libxraygramcore.a
xg_log "готово: $XCF"
