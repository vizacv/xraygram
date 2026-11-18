#!/usr/bin/env bash
# Выгружает правки из рабочей ветки tdesktop в macos/patches/0001-xraygram-xray-socks.patch
# и проверяет, что патч чисто применяется к чистому тегу.
#
#   macos/scripts/update-patch.sh [--check-only]
#
# Правки делаем прямо в $XG_SRC (по умолчанию upstream/tdesktop, ветка xraygram).
# Новые файлы подхватываются автоматически (git add -A). Правки внутри сабмодулей
# в патч НЕ попадают — скрипт об этом предупредит.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PATCH="$XG_PATCHES/0001-xraygram-xray-socks.patch"
CHECK_ONLY=0
[[ "${1:-}" == "--check-only" ]] && CHECK_ONLY=1

cd "$XG_SRC"
git rev-parse -q --verify "refs/tags/$TDESKTOP_REF" > /dev/null \
	|| git fetch -q --depth 1 origin tag "$TDESKTOP_REF"

dirty_submodules="$(git submodule foreach --quiet --recursive \
	'if [ -n "$(git status --porcelain --untracked-files=no)" ]; then echo "$displaypath"; fi')"
if [[ -n "$dirty_submodules" ]]; then
	xg_warn "изменения в сабмодулях не попадут в патч:"
	echo "$dirty_submodules" >&2
fi

if (( ! CHECK_ONLY )); then
	git add -A
	tmp="$(mktemp)"
	git diff --cached --binary --ignore-submodules=all "$TDESKTOP_REF" > "$tmp"
	if [[ -f "$PATCH" ]] && cmp -s "$tmp" "$PATCH"; then
		xg_log "патч не изменился"
		rm -f "$tmp"
	else
		mv "$tmp" "$PATCH"
		xg_log "обновлён $PATCH"
	fi
	git diff --cached --stat --ignore-submodules=all "$TDESKTOP_REF" | tail -1
fi

check_dir="$(mktemp -d)"
trap 'git -C "$XG_SRC" worktree remove --force "$check_dir" > /dev/null 2>&1 || true; rm -rf "$check_dir"' EXIT
git worktree add -q --detach "$check_dir" "$TDESKTOP_REF"
for patch in "$XG_PATCHES"/*.patch; do
	git -C "$check_dir" apply --check "$patch" || xg_die "$(basename "$patch") не применяется к $TDESKTOP_REF"
	git -C "$check_dir" apply "$patch"
done
xg_log "патчи чисто применяются к $TDESKTOP_REF"
