#!/usr/bin/env bash
# Выгружает правки из рабочей ветки tdesktop в патчи и проверяет, что они чисто
# применяются к чистому тегу:
#   - корень tdesktop → macos/patches/0001-xraygram-xray-socks.patch;
#   - сабмодули из XG_SUBMODULE_PATCHES (common.sh) → macos/patches/<имя>/*.patch,
#     против коммита сабмодуля, закреплённого в теге tdesktop.
#
#   macos/scripts/update-patch.sh [--check-only]
#
# Правки делаем прямо в $XG_SRC (по умолчанию upstream/tdesktop, ветка xraygram) и в его
# сабмодулях. Новые файлы подхватываются автоматически (git add -A). Правки в сабмодулях,
# которых нет в XG_SUBMODULE_PATCHES, в патчи НЕ попадают — скрипт предупредит.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

PATCH="$XG_PATCHES/0001-xraygram-xray-socks.patch"
CHECK_ONLY=0
[[ "${1:-}" == "--check-only" ]] && CHECK_ONLY=1
TMP_ROOT="$XG_WORK/tmp"
mkdir -p "$TMP_ROOT"

write_if_changed() { # $1 = новый файл, $2 = патч
	mkdir -p "$(dirname "$2")"
	if [[ -f "$2" ]] && cmp -s "$1" "$2"; then
		xg_log "без изменений: ${2#$XG_REPO/}"
		rm -f "$1"
	else
		mv "$1" "$2"
		chmod 644 "$2"
		xg_log "обновлён: ${2#$XG_REPO/}"
	fi
}

cd "$XG_SRC"
git rev-parse -q --verify "refs/tags/$TDESKTOP_REF" > /dev/null \
	|| git fetch -q --depth 1 origin tag "$TDESKTOP_REF"

known=()
for entry in "${XG_SUBMODULE_PATCHES[@]}"; do
	known+=("${entry%%|*}")
done
while IFS= read -r path; do
	[[ -z "$path" ]] && continue
	if [[ ! " ${known[*]} " == *" $path "* ]]; then
		xg_warn "изменения в сабмодуле $path не попадут в патчи (его нет в XG_SUBMODULE_PATCHES)"
	fi
done < <(git submodule foreach --quiet --recursive \
	'if [ -n "$(git status --porcelain --untracked-files=no)" ]; then echo "$displaypath"; fi')

if (( ! CHECK_ONLY )); then
	git add -A
	tmp="$(mktemp "$TMP_ROOT/patch.XXXXXX")"
	git diff --cached --binary --ignore-submodules=all "$TDESKTOP_REF" > "$tmp"
	write_if_changed "$tmp" "$PATCH"
	git diff --cached --stat --ignore-submodules=all "$TDESKTOP_REF" | tail -1

	for entry in "${XG_SUBMODULE_PATCHES[@]}"; do
		path="${entry%%|*}"
		target="$XG_PATCHES/${entry#*|}"
		base="$(git ls-tree "$TDESKTOP_REF" "$path" | awk '{print $3}')"
		[[ -n "$base" ]] || xg_die "в $TDESKTOP_REF нет сабмодуля $path"
		git -C "$path" add -A
		tmp="$(mktemp "$TMP_ROOT/patch.XXXXXX")"
		git -C "$path" diff --cached --binary "$base" > "$tmp"
		if [[ ! -s "$tmp" ]]; then
			rm -f "$tmp"
			xg_log "$path: правок нет"
			continue
		fi
		write_if_changed "$tmp" "$target"
		git -C "$path" diff --cached --stat "$base" | tail -1
	done
fi

check_dir="$(mktemp -d "$TMP_ROOT/check.XXXXXX")"
sub_checks=()
cleanup() {
	git -C "$XG_SRC" worktree remove --force "$check_dir" > /dev/null 2>&1 || true
	for item in "${sub_checks[@]}"; do
		git -C "$XG_SRC/${item%%|*}" worktree remove --force "${item#*|}" > /dev/null 2>&1 || true
	done
	rm -rf "$check_dir" "$TMP_ROOT"/sub.*
}
trap cleanup EXIT

git worktree add -q --detach "$check_dir" "$TDESKTOP_REF"
for patch in "$XG_PATCHES"/*.patch; do
	git -C "$check_dir" apply --check "$patch" || xg_die "$(basename "$patch") не применяется к $TDESKTOP_REF"
	git -C "$check_dir" apply "$patch"
done
xg_log "патчи tdesktop чисто применяются к $TDESKTOP_REF"

for entry in "${XG_SUBMODULE_PATCHES[@]}"; do
	path="${entry%%|*}"
	patch="$XG_PATCHES/${entry#*|}"
	[[ -f "$patch" ]] || continue
	base="$(git ls-tree "$TDESKTOP_REF" "$path" | awk '{print $3}')"
	sub_dir="$(mktemp -d "$TMP_ROOT/sub.XXXXXX")"
	rmdir "$sub_dir"
	sub_checks+=("$path|$sub_dir")
	git -C "$path" worktree add -q --detach "$sub_dir" "$base"
	git -C "$sub_dir" apply --check "$patch" || xg_die "${entry#*|} не применяется к $path@${base:0:8}"
	xg_log "${entry#*|} чисто применяется к $path@${base:0:8}"
done
