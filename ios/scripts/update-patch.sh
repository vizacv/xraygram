#!/usr/bin/env bash
# Выгружает правки из рабочей ветки Telegram-iOS в ios/patches/0001-xraygram-ios.patch
# и проверяет, что патч чисто применяется к $TGIOS_REF.
#
#   ios/scripts/update-patch.sh [--check-only]
#
# Правки делаем прямо в $XG_SRC (upstream/telegram-ios, ветка xraygram).
# В патч НЕ попадают (их кладёт `build.sh prepare` из репозитория Xraygram):
#   third-party/XraygramCore/XraygramCore.xcframework  — собирается build-core.sh
#   submodules/XraygramKit/Sources                     — канон в ios/xraykit/swift/XraygramKit
#   Telegram/Telegram-iOS/XraygramAppIcon.xcassets/…/AppIcon-1024.png — канон в branding/ios
#   Telegram/Telegram-iOS/Resources/XraygramLaunchIcon@*.png — канон в branding/launch
#   submodules/TelegramUI/Images.xcassets/Call/CallKitLogo.imageset/*.png — канон в branding/glyph/ios
# и служебное: build-input/, bazel-*.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PATCH="$XG_PATCHES/0001-xraygram-ios.patch"
TGCALLS_DIR="submodules/TgVoipWebrtc/tgcalls"
TGCALLS_PATCH="$XG_PATCHES/tgcalls/0001-socks5-tcp-relay.patch"
CHECK_ONLY=0
[[ "${1:-}" == "--check-only" ]] && CHECK_ONLY=1
EXCLUDES=(
	':(exclude)third-party/XraygramCore/XraygramCore.xcframework'
	':(exclude)submodules/XraygramKit/Sources'
	':(exclude)Telegram/Telegram-iOS/XraygramAppIcon.xcassets/AppIcon.appiconset/AppIcon-1024.png'
	':(exclude)Telegram/Telegram-iOS/Resources/XraygramLaunchIcon@2x.png'
	':(exclude)Telegram/Telegram-iOS/Resources/XraygramLaunchIcon@3x.png'
	':(exclude)submodules/TelegramUI/Images.xcassets/Call/CallKitLogo.imageset/CallKitLogo@2x.png'
	':(exclude)submodules/TelegramUI/Images.xcassets/Call/CallKitLogo.imageset/CallKitLogo@3x.png'
	':(exclude)build-input'
	':(exclude)bazel-*'
)

cd "$XG_SRC"
git cat-file -e "$TGIOS_REF^{commit}" 2>/dev/null || git fetch -q --depth 1 origin "$TGIOS_REF"

dirty_submodules="$(git submodule foreach --quiet --recursive \
	'if [ -n "$(git status --porcelain --untracked-files=no)" ]; then echo "$displaypath"; fi' | grep -vx "$TGCALLS_DIR" || true)"
if [[ -n "$dirty_submodules" ]]; then
	xg_warn "изменения в сабмодулях не попадут в патч:"
	echo "$dirty_submodules" >&2
fi

if (( ! CHECK_ONLY )); then
	git add -A -- . "${EXCLUDES[@]}"
	tmp="$(mktemp)"
	git diff --cached --binary --ignore-submodules=all "$TGIOS_REF" -- . "${EXCLUDES[@]}" > "$tmp"
	mkdir -p "$XG_PATCHES"
	if [[ -f "$PATCH" ]] && cmp -s "$tmp" "$PATCH"; then
		xg_log "патч не изменился"
		rm -f "$tmp"
	else
		mv "$tmp" "$PATCH"
		chmod 644 "$PATCH"
		xg_log "обновлён $PATCH"
	fi
	git diff --cached --stat --ignore-submodules=all "$TGIOS_REF" -- . "${EXCLUDES[@]}" | tail -1

	# Патч звонков (перенос macos/patches/tgcalls) — в сабмодуле tgcalls, пути от его корня.
	mkdir -p "$(dirname "$TGCALLS_PATCH")"
	tmp="$(mktemp)"
	git -C "$TGCALLS_DIR" diff > "$tmp"
	if [[ -f "$TGCALLS_PATCH" ]] && cmp -s "$tmp" "$TGCALLS_PATCH"; then
		rm -f "$tmp"
	else
		mv "$tmp" "$TGCALLS_PATCH"
		chmod 644 "$TGCALLS_PATCH"
		xg_log "обновлён $TGCALLS_PATCH"
	fi
fi

check_dir="$(mktemp -d)"
trap 'git -C "$XG_SRC" worktree remove --force "$check_dir" > /dev/null 2>&1 || true; rm -rf "$check_dir"' EXIT
git worktree add -q --detach "$check_dir" "$TGIOS_REF"
for patch in "$XG_PATCHES"/*.patch; do
	git -C "$check_dir" apply --check "$patch" || xg_die "$(basename "$patch") не применяется к $TGIOS_REF"
done
tgcalls_base="$(git -C "$XG_SRC/$TGCALLS_DIR" rev-parse HEAD)"
tgcalls_check="$(mktemp -d)"
git -C "$XG_SRC/$TGCALLS_DIR" worktree add -q --detach "$tgcalls_check" "$tgcalls_base"
if ! git -C "$tgcalls_check" apply --check "$TGCALLS_PATCH"; then
	git -C "$XG_SRC/$TGCALLS_DIR" worktree remove --force "$tgcalls_check"
	xg_die "$(basename "$TGCALLS_PATCH") не применяется к tgcalls $tgcalls_base"
fi
git -C "$XG_SRC/$TGCALLS_DIR" worktree remove --force "$tgcalls_check"
xg_log "патчи чисто применяются к $TGIOS_REF (tgcalls ${tgcalls_base:0:8})"
