#!/usr/bin/env bash
# Выгружает правки из upstream/tg-android (ветка xraygram) в android/patches/0001-xraygram.patch
# и проверяет, что патч чисто применяется к чистому TG_REF.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
OUT="$XG_PATCHES/0001-xraygram.patch"
cd "$XG_SRC"
# Сборочные артефакты не в патч (на случай, если exclude потерялся).
grep -qx 'TMessagesProj/libs/libXray.aar' .git/info/exclude 2>/dev/null || printf 'TMessagesProj/libs/libXray.aar\nlocal.properties\n' >> .git/info/exclude
git add -A
if git diff --cached --submodule=short "$TG_REF" | grep -q '^Submodule'; then
	xg_warn "есть правки внутри сабмодулей — в патч они не попадут"
fi
mkdir -p "$XG_PATCHES"
# Иконка (FEAT-07) кладётся скриптом сборки из branding/android — в патч не идёт.
git diff --cached --binary "$TG_REF" -- . ':!TMessagesProj/libs/libXray.aar' \
	':!TMessagesProj_AppStandalone/src/main/res/mipmap-*/ic_launcher_sa.png' \
	':!TMessagesProj_AppStandalone/src/main/res/mipmap-xxxhdpi/xraygram_icon_*.png' \
	':!TMessagesProj_AppStandalone/src/main/res/mipmap-anydpi-v26/ic_launcher_sa.xml' \
	':!TMessagesProj_AppStandalone/src/main/res/mipmap-anydpi-v33/ic_launcher_sa.xml' \
	':!TMessagesProj/src/main/res/mipmap-*/xraygram_launcher*.png' \
	':!TMessagesProj/src/main/res/drawable-*/ic_stat_xraygram.png' \
	':!TMessagesProj/src/main/res/drawable-nodpi/xraygram_*.png' > "$OUT"
xg_log "$(basename "$OUT"): $(grep -c '^diff --git' "$OUT") файлов, $(wc -l < "$OUT" | tr -d ' ') строк"
# Проверка на чистом дереве TG_REF.
tmp="$(mktemp -d "$XG_WORK/patchcheck.XXXX")"
trap 'git worktree remove --force "$tmp" >/dev/null 2>&1 || rm -rf "$tmp"' EXIT
git worktree add --detach -q "$tmp" "$TG_REF"
git -C "$tmp" apply --check "$OUT" && xg_log "патч чисто применяется к $TG_REF"

# Сабмодуль tgcalls: свои правки — отдельным патчем с путями от корня tgcalls (как macos/patches/tgcalls).
TGC="$XG_SRC/TMessagesProj/jni/tgcalls"
if [[ -n "$(git -C "$TGC" status --porcelain)" ]]; then
	mkdir -p "$XG_PATCHES/tgcalls"
	OUT2="$XG_PATCHES/tgcalls/0001-socks5-tcp-relay.patch"
	git -C "$TGC" add -A
	git -C "$TGC" diff --cached HEAD > "$OUT2"
	git -C "$TGC" reset -q
	xg_log "tgcalls/$(basename "$OUT2"): $(grep -c '^diff --git' "$OUT2") файлов, против $(git -C "$TGC" rev-parse --short HEAD)"
	tmp2="$(mktemp -d "$XG_WORK/tgcallscheck.XXXX")"
	git -C "$TGC" worktree add --detach -q "$tmp2" HEAD
	git -C "$tmp2" apply --check "$OUT2" && xg_log "патч tgcalls чисто применяется к $(git -C "$TGC" rev-parse --short HEAD)"
	git -C "$TGC" worktree remove --force "$tmp2"
fi
