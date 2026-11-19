#!/usr/bin/env bash
# Локальная сборка Xraygram (tdesktop + патч + xraygram-core) на Apple Silicon.
# Повторяет шаги .github/workflows/build-macos.yml, но с инкрементальной пересборкой.
#
#   macos/scripts/build-local.sh [команда] [--debug]
#
# Команды:
#   all        (по умолчанию) deps → src → core → configure (если ещё нет) → build → app
#   deps       brew-пакеты + Rust-либы, rnnoise, tg_owt, tde2e (готовое пропускается)
#   src        клон tdesktop $TDESKTOP_REF с сабмодулями + патч (если исходников ещё нет)
#   core       собрать xraygram-core (Go)
#   configure  cmake configure (заново)
#   build      инкрементальная сборка tdesktop
#   app        собрать Xraygram.app (macdeployqt, xraygram-core, ad-hoc подпись) в staging/
#              и подменить dist/Xraygram.app, если тот не запущен
#   swap       подменить dist/Xraygram.app собранным в staging/ (когда приложение закрыто)
#   quick      build + подменить в dist/Xraygram.app только исполняемый файл (секунды вместо
#              ~5 мин macdeployqt); если поменялись библиотеки/ресурсы — сам делает полный app
#   snapshot   сохранить копию dist/Xraygram.app с ID сборки: dist/Xraygram-macos-ГГГГММДД-N.app
#              (N — следующий свободный; свой ID: SNAPSHOT_ID=macos-... build-local.sh snapshot)
#   dmg        упаковать dist/Xraygram.app в DMG
#   run        запустить dist/Xraygram.app с логом в терминал
#   run-dev    запустить приложение прямо из build-каталога (без macdeployqt), быстрее всего
#              (оба — с -workdir upstream/xraygram-local/appdata, данные не идут в ~/Library)
#   status     показать, что готово
#
# Ключи API: из env TDESKTOP_API_ID/TDESKTOP_API_HASH или из файла
# ~/xraygram/.secrets/api.env (права 0600, в .gitignore), формат:
#   TDESKTOP_API_ID=12345
#   TDESKTOP_API_HASH=0123456789abcdef0123456789abcdef
# Если ключей нет — собирается с тестовыми ключами upstream (TDESKTOP_API_TEST).

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BUILD_TYPE="Release"
COMMAND="all"
for arg in "$@"; do
	case "$arg" in
		--debug) BUILD_TYPE="Debug" ;;
		--release) BUILD_TYPE="Release" ;;
		-h|--help) sed -n '2,31p' "$0"; exit 0 ;;
		*) COMMAND="$arg" ;;
	esac
done

XG_BUILD="$XG_WORK/build-$(echo "$BUILD_TYPE" | tr '[:upper:]' '[:lower:]')"
XG_CORE_BIN="$XG_WORK/bin/xraygram-core"
JOBS="$(sysctl -n hw.logicalcpu)"

mkdir -p "$XG_LIBS/local" "$XG_LOGS" "$XG_DIST" "$XG_WORK/bin"

export CMAKE_GENERATOR="Ninja"
export CMAKE_BUILD_PARALLEL_LEVEL="$JOBS"
export PATH="/opt/homebrew/bin:$PATH"

check_toolchain() {
	local dev
	dev="$(xcode-select -p 2>/dev/null || true)"
	if [[ "$dev" != *Xcode*.app* ]]; then
		xg_warn "Активен $dev, а не Xcode.app. Если сборка упадёт на SDK/Swift/Metal, нужен Xcode:"
		xg_warn "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
		xg_warn "  sudo xcodebuild -license accept"
	fi
}

deployment_target() {
	local cfg
	cfg="$(ls /opt/homebrew/Cellar/qtbase/*/lib/cmake/Qt6/Qt6ConfigExtras.cmake 2>/dev/null | tail -1)"
	[[ -n "$cfg" ]] || xg_die "qtbase из Homebrew не найден, запустите: $0 deps"
	grep 'set(QT_SUPPORTED_MIN_MACOS_VERSION' "$cfg" | sed -E 's/^.*"(.*)"\)$/\1/'
}

stamp_ok() { # $1 = каталог установки, $2 = ключ
	[[ -f "$1/.xg-stamp" ]] && [[ "$(cat "$1/.xg-stamp")" == "$2" ]]
}
stamp_write() { echo "$2" > "$1/.xg-stamp"; }

timed() { # $1 = имя лога, дальше команда
	local name="$1"; shift
	local start=$SECONDS rc
	xg_log "$name (лог: $XG_LOGS/$name.log)"
	set +e
	( set -e; "$@" ) > "$XG_LOGS/$name.log" 2>&1
	rc=$?
	set -e
	if (( rc != 0 )); then
		tail -40 "$XG_LOGS/$name.log" >&2
		xg_die "$name: ошибка (код $rc), полный лог $XG_LOGS/$name.log"
	fi
	xg_log "$name: готово за $(( (SECONDS - start) / 60 )) мин $(( (SECONDS - start) % 60 )) с"
}

deps_brew() {
	local missing=()
	for pkg in "${BREW_TOOLS[@]}" "${BREW_LIBS[@]}"; do
		brew list --versions "$pkg" > /dev/null 2>&1 || missing+=("$pkg")
	done
	if (( ${#missing[@]} )); then
		timed brew-install brew install "${missing[@]}"
	else
		xg_log "brew: всё установлено"
	fi
}

build_rust() {
	cd "$XG_LIBS"
	export RUSTUP_HOME="$XG_LIBS/rustup" CARGO_HOME="$XG_LIBS/cargo"
	if [[ ! -x "$CARGO_HOME/bin/cargo" ]]; then
		curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o rustup-init.sh
		sh rustup-init.sh -y --no-modify-path --profile minimal --default-toolchain "$RUST_TOOLCHAIN"
	fi
	export RUSTUP_TOOLCHAIN="$RUST_TOOLCHAIN" PATH="$CARGO_HOME/bin:$PATH"
	rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal

	fetch_sha() { # dir repo sha
		rm -rf "$1"; git init -q "$1"
		git -C "$1" remote add origin "$GIT_BASE/$2.git"
		git -C "$1" fetch -q --depth=1 origin "$3"
		git -C "$1" reset -q --hard FETCH_HEAD
	}
	fetch_sha rust-patches desktop-app/patches "$RUST_PATCHES"
	fetch_sha tlottie dkaraush/tlottie "$TLOTTIE"
	GIT_LFS_SKIP_SMUDGE=1 fetch_sha wallet-engine i582/wallet-engine "$WALLET_ENGINE"
	git -C wallet-engine apply ../rust-patches/wallet-engine.patch

	rm -rf tdesktop_rust
	cargo new --lib --vcs none tdesktop_rust
	cd tdesktop_rust
	printf 'pub use ::tlottie;\npub use ::wallet_engine;\n' > src/lib.rs
	cargo add --path ../tlottie --features c-api
	cargo add --path ../wallet-engine
	cargo rustc --lib --release \
		--crate-type staticlib --crate-type cdylib \
		--config "profile.release.opt-level='z'" \
		--config "profile.release.lto='thin'" \
		--config "profile.release.codegen-units=1" \
		--config "profile.release.panic='unwind'" \
		--config "profile.release.package.tlottie.opt-level=3" \
		-- --print native-static-libs
	local out="$XG_LIBS/local/tdesktop_rust"
	rm -rf "$out"
	install -d "$out/lib" "$out/include/tlottie" "$out/include/wallet_engine"
	install -m 644 target/release/libtdesktop_rust.a "$out/lib/libtdesktop_rust.a"
	install -m 644 ../tlottie/include/tlottie.h "$out/include/tlottie/tlottie.h"
	cargo run --manifest-path ../wallet-engine/bindgen/cpp/bindgen/Cargo.toml --locked -- \
		--library --out-dir "$out/include/wallet_engine" \
		target/release/libtdesktop_rust.dylib
}

build_rnnoise() {
	cd "$XG_LIBS"
	rm -rf rnnoise "$XG_LIBS/local/rnnoise"
	git clone -q --depth=1 "$GIT_BASE/xiph/rnnoise.git"
	git -C rnnoise rev-parse HEAD > rnnoise.sha
	cd rnnoise
	./autogen.sh
	./configure --prefix="$XG_LIBS/local/rnnoise" --disable-examples --disable-doc
	make -j"$JOBS"
	make install
}

build_tg_owt() {
	cd "$XG_LIBS"
	rm -rf tg_owt "$XG_LIBS/local/tg_owt"
	git clone -q --depth=1 --recursive --shallow-submodules "$GIT_BASE/desktop-app/tg_owt.git"
	git -C tg_owt rev-parse HEAD > tg_owt.sha
	cd tg_owt
	cmake -Bbuild . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$XG_LIBS/local/tg_owt"
	cmake --build build
	cmake --install build
}

build_tde2e() {
	cd "$XG_LIBS"
	rm -rf tde2e "$XG_LIBS/local/tde2e"
	git init -q tde2e
	git -C tde2e remote add origin "$GIT_BASE/tdlib/td.git"
	git -C tde2e fetch -q --depth=1 origin "$TDE2E"
	git -C tde2e reset -q --hard FETCH_HEAD
	cd tde2e
	cmake -Bbuild . -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$XG_LIBS/local/tde2e" -DTD_E2E_ONLY=ON
	cmake --build build
	cmake --install build
}

cmd_deps() {
	check_toolchain
	deps_brew
	export MACOSX_DEPLOYMENT_TARGET="$(deployment_target)"
	export CMAKE_BUILD_TYPE="Release"

	local key="$TLOTTIE-$WALLET_ENGINE-$RUST_PATCHES-$RUST_TOOLCHAIN"
	if stamp_ok "$XG_LIBS/local/tdesktop_rust" "$key"; then
		xg_log "Rust-либы: готовы"
	else
		timed deps-rust build_rust
		stamp_write "$XG_LIBS/local/tdesktop_rust" "$key"
	fi
	if stamp_ok "$XG_LIBS/local/rnnoise" "built"; then
		xg_log "rnnoise: готов ($(cat "$XG_LIBS/rnnoise.sha" 2>/dev/null))"
	else
		timed deps-rnnoise build_rnnoise
		stamp_write "$XG_LIBS/local/rnnoise" "built"
	fi
	if stamp_ok "$XG_LIBS/local/tde2e" "$TDE2E"; then
		xg_log "tde2e: готов"
	else
		timed deps-tde2e build_tde2e
		stamp_write "$XG_LIBS/local/tde2e" "$TDE2E"
	fi
	if stamp_ok "$XG_LIBS/local/tg_owt" "built"; then
		xg_log "tg_owt: готов ($(cat "$XG_LIBS/tg_owt.sha" 2>/dev/null))"
	else
		timed deps-tg_owt build_tg_owt
		stamp_write "$XG_LIBS/local/tg_owt" "built"
	fi
}

cmd_src() {
	if [[ -d "$XG_SRC/.git" ]]; then
		xg_log "исходники: $XG_SRC ($(git -C "$XG_SRC" branch --show-current))"
		if [[ ! -f "$XG_SRC/cmake/CMakeLists.txt" && ! -f "$XG_SRC/cmake/variables.cmake" ]]; then
			timed submodules git -C "$XG_SRC" submodule update --init --recursive --depth 1 --jobs 8
		fi
		return
	fi
	timed clone git clone --depth 1 --branch "$TDESKTOP_REF" \
		--recurse-submodules --shallow-submodules --jobs 8 \
		"$GIT_BASE/telegramdesktop/tdesktop.git" "$XG_SRC"
	git -C "$XG_SRC" switch -q -c xraygram
	for patch in "$XG_PATCHES"/*.patch; do
		xg_log "патч $(basename "$patch")"
		git -C "$XG_SRC" apply --whitespace=nowarn "$patch"
	done
	git -C "$XG_SRC" add -A
	local entry
	for entry in "${XG_SUBMODULE_PATCHES[@]}"; do
		xg_log "патч ${entry#*|} → ${entry%%|*}"
		git -C "$XG_SRC/${entry%%|*}" apply --whitespace=nowarn "$XG_PATCHES/${entry#*|}"
	done
}

cmd_core() {
	cd "$XG_CORE_SRC"
	[[ -f go.sum ]] || timed go-mod-tidy go mod tidy
	timed core-build env CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 \
		go build -trimpath -ldflags="-checklinkname=0 -s -w -buildid=" -o "$XG_CORE_BIN" .
	"$XG_CORE_BIN" version
}

load_api_args() {
	API_ARGS=()
	local id="${TDESKTOP_API_ID:-}" hash="${TDESKTOP_API_HASH:-}" source="env"
	if [[ -z "$id" || -z "$hash" ]] && [[ -f "$XG_API_ENV" ]]; then
		source="$XG_API_ENV"
		local mode
		mode="$(stat -f '%Lp' "$XG_API_ENV")"
		[[ "$mode" == "600" ]] || xg_warn "$XG_API_ENV: права $mode, лучше chmod 600"
		id="$(sed -n 's/^[[:space:]]*TDESKTOP_API_ID[[:space:]]*=[[:space:]]*//p' "$XG_API_ENV" | tr -d '"'"'"' \r' | tail -1)"
		hash="$(sed -n 's/^[[:space:]]*TDESKTOP_API_HASH[[:space:]]*=[[:space:]]*//p' "$XG_API_ENV" | tr -d '"'"'"' \r' | tail -1)"
	fi
	if [[ -n "$id" && -n "$hash" ]]; then
		[[ "$id" =~ ^[0-9]+$ ]] || xg_die "TDESKTOP_API_ID должен быть числом"
		[[ "$hash" =~ ^[0-9a-fA-F]{32}$ ]] || xg_die "TDESKTOP_API_HASH должен быть 32 hex-символа"
		xg_log "API: свои ключи (из $source)"
		API_ARGS=(-DTDESKTOP_API_TEST=OFF "-DTDESKTOP_API_ID=$id" "-DTDESKTOP_API_HASH=$hash")
	else
		xg_warn "Ключей API нет ($XG_API_ENV): собираю с TDESKTOP_API_TEST, вход, скорее всего, не пройдёт."
		API_ARGS=(-DTDESKTOP_API_TEST=ON)
	fi
}

prefix_path() {
	local result="/opt/homebrew/opt/ffmpeg@6:/opt/homebrew/opt/openal-soft"
	local dir
	for dir in "$XG_LIBS"/local/*/; do
		result="$result:${dir%/}"
	done
	echo "$result"
}

cmd_configure() {
	check_toolchain
	[[ -f "$XG_SRC/CMakeLists.txt" ]] || xg_die "нет исходников, запустите: $0 src"
	load_api_args
	export MACOSX_DEPLOYMENT_TARGET="$(deployment_target)"
	export CMAKE_PREFIX_PATH="$(prefix_path)"
	timed "configure-$BUILD_TYPE" cmake -S "$XG_SRC" -B "$XG_BUILD" -G Ninja \
		-DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
		"${API_ARGS[@]}" \
		-DDESKTOP_APP_USE_PACKAGED=ON \
		-DXRAYGRAM_ICNS="$XG_REPO/branding/macos/Xraygram.icns" \
		-DXRAYGRAM_BRANDING_DIR="$XG_REPO/branding" \
		-DXRAYGRAM_THEME_FILE="$XG_REPO/macos/theme/rentgen.tdesktop-theme" \
		-DDESKTOP_APP_DISABLE_AUTOUPDATE=ON \
		-DDESKTOP_APP_DISABLE_CRASH_REPORTS=ON
}

cmd_build() {
	[[ -f "$XG_BUILD/build.ninja" ]] || cmd_configure
	export MACOSX_DEPLOYMENT_TARGET="$(deployment_target)"
	export CMAKE_PREFIX_PATH="$(prefix_path)"
	timed "build-$BUILD_TYPE" cmake --build "$XG_BUILD" --parallel "$JOBS"
}

app_running() {
	pgrep -f "$XG_DIST/Xraygram.app/Contents/MacOS/" > /dev/null 2>&1
}

cmd_swap() {
	local staged="$XG_WORK/staging/Xraygram.app" app="$XG_DIST/Xraygram.app"
	[[ -d "$staged" ]] || xg_die "нет собранного бандла в $XG_WORK/staging, сначала: $0 app"
	if app_running; then
		xg_warn "Xraygram из $XG_DIST сейчас запущен. Закройте его (Cmd+Q) и выполните: $0 swap"
		return 1
	fi
	rm -rf "$app"
	mv "$staged" "$app"
	xg_log "готово: $app"
}

cmd_app() { # APP_OUT=<путь.app> — положить туда вместо подмены dist/Xraygram.app
	local src; src="$(xg_build_app)"; local staged="$XG_WORK/staging/Xraygram.app"
	[[ -d "$src" ]] || xg_die "нет $src, сначала: $0 build"
	[[ -x "$XG_CORE_BIN" ]] || cmd_core
	rm -rf "$staged"
	mkdir -p "$(dirname "$staged")"
	ditto "$src" "$staged"
	timed macdeployqt macdeployqt "$staged"
	install -m 755 "$XG_CORE_BIN" "$staged/Contents/MacOS/xraygram-core"
	codesign --force --sign - "$staged/Contents/MacOS/xraygram-core"
	timed codesign codesign --force --deep --sign - "$staged"
	codesign --verify --deep --strict "$staged"
	if find "$staged" -type f -perm +111 -print0 | xargs -0 otool -L 2>/dev/null | grep -q '/opt/homebrew'; then
		xg_warn "в бандле остались ссылки на /opt/homebrew (на этом Маке работает, на чужом — нет)"
	fi
	if [[ -n "${APP_OUT:-}" ]]; then # APP_OUT=dist/Xraygram-<ID>.app — собрать рядом, dist/Xraygram.app не трогать
		[[ -e "$APP_OUT" ]] && xg_die "уже есть $APP_OUT"
		mv "$staged" "$APP_OUT"
		xg_log "готово: $APP_OUT"
		return
	fi
	cmd_swap || true
}

bundle_target() { # путь зависимости → путь внутри Contents/Frameworks (как у macdeployqt)
	local dep="$1"
	if [[ "$dep" == *.framework/* ]]; then
		echo "$dep" | sed -E 's|^.*/([^/]+\.framework/.*)$|\1|'
	else
		basename "$dep"
	fi
}

cmd_quick() { # QUICK_TARGET=<другой .app> — обновить его вместо dist/Xraygram.app
	local app="${QUICK_TARGET:-$XG_DIST/Xraygram.app}" src
	cmd_build
	src="$(xg_build_app)"
	if [[ ! -d "$app" ]]; then
		[[ -n "${QUICK_TARGET:-}" ]] && xg_die "нет $app"
		xg_warn "нет $app, делаю полный app"
		cmd_app
		return
	fi
	if [[ -z "${QUICK_TARGET:-}" ]] && app_running; then
		xg_die "Xraygram из $XG_DIST запущен. Закройте его (Cmd+Q) и повторите: $0 quick"
	fi
	if ! cmp -s "$src/Contents/Info.plist" "$app/Contents/Info.plist" \
		|| ! diff -rq -x qt.conf "$src/Contents/Resources" "$app/Contents/Resources" > /dev/null; then
		xg_warn "изменились Info.plist или ресурсы, делаю полный app"
		cmd_app
		return
	fi
	local start=$SECONDS
	local name; name="$(xg_bundle_exe "$src")"
	local exe="$app/Contents/MacOS/$name" tmp="$app/Contents/MacOS/$name.new"
	cp "$src/Contents/MacOS/$name" "$tmp"

	local args=() dep rel missing=()
	while read -r dep; do
		case "$dep" in
			/System/*|/usr/lib/*|@*|"") continue ;;
		esac
		rel="$(bundle_target "$dep")"
		if [[ -e "$app/Contents/Frameworks/$rel" ]]; then
			args+=(-change "$dep" "@executable_path/../Frameworks/$rel")
		else
			missing+=("$dep")
		fi
	done < <(otool -L "$tmp" | tail -n +2 | awk '{print $1}')
	if (( ${#missing[@]} )); then
		rm -f "$tmp"
		xg_warn "новые библиотеки, которых нет в бандле: ${missing[*]}; делаю полный app"
		cmd_app
		return
	fi
	while read -r rpath; do
		case "$rpath" in
			/opt/homebrew/*|"$XG_WORK"/*) args+=(-delete_rpath "$rpath") ;;
		esac
	done < <(otool -l "$tmp" | awk '/LC_RPATH/{getline; getline; print $2}')
	(( ${#args[@]} )) && install_name_tool "${args[@]}" "$tmp" 2> /dev/null
	if otool -L "$tmp" | tail -n +2 | grep -qE '/opt/homebrew|'"$XG_WORK"; then
		rm -f "$tmp"
		xg_die "после подмены путей остались внешние ссылки, запустите полный: $0 app"
	fi
	mv "$tmp" "$exe"

	[[ -x "$XG_CORE_BIN" ]] || cmd_core
	cmp -s "$XG_CORE_BIN" "$app/Contents/MacOS/xraygram-core" \
		|| install -m 755 "$XG_CORE_BIN" "$app/Contents/MacOS/xraygram-core"
	codesign --force --sign - "$app/Contents/MacOS/xraygram-core"
	codesign --force --deep --sign - "$app"
	codesign --verify --deep --strict "$app"
	xg_log "быстро обновлён $app за $((SECONDS - start)) с"
}

next_build_id() {
	local day n=1
	day="$(date +%Y%m%d)"
	while [[ -e "$XG_DIST/Xraygram-macos-$day-$n.app" ]]; do
		n=$((n + 1))
	done
	echo "macos-$day-$n"
}

cmd_snapshot() { # [ID] — копия dist/Xraygram.app с ID сборки (регламент docs/process.md)
	local app="$XG_DIST/Xraygram.app" id="${SNAPSHOT_ID:-}"
	[[ -d "$app" ]] || xg_die "нет $app"
	[[ -n "$id" ]] || id="$(next_build_id)"
	local target="$XG_DIST/Xraygram-$id.app"
	[[ -e "$target" ]] && xg_die "$target уже есть, сборку с этим ID не перезаписываю"
	ditto "$app" "$target"
	codesign --verify --deep --strict "$target"
	xg_log "сборка $id: $target ($(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$app/Contents/MacOS/$(xg_bundle_exe "$app")"))"
}

cmd_dmg() {
	local app="$XG_DIST/Xraygram.app" stage="$XG_WORK/dmg"
	[[ -d "$app" ]] || cmd_app
	rm -rf "$stage"; mkdir -p "$stage"
	ditto "$app" "$stage/Xraygram.app"
	ln -s /Applications "$stage/Applications"
	local dmg="$XG_DIST/Xraygram-$TDESKTOP_REF-local-$(git -C "$XG_REPO" rev-parse --short HEAD)-macos-arm64.dmg"
	hdiutil create -volname Xraygram -srcfolder "$stage" -ov -format UDZO "$dmg"
	xg_log "готово: $dmg"
}

cmd_run() {
	mkdir -p "$XG_APPDATA"
	exec "$XG_DIST/Xraygram.app/Contents/MacOS/$(xg_bundle_exe "$XG_DIST/Xraygram.app")" -workdir "$XG_APPDATA/"
}

cmd_run_dev() {
	[[ -x "$XG_CORE_BIN" ]] || cmd_core
	mkdir -p "$XG_APPDATA"
	local app; app="$(xg_build_app)"
	XRAYGRAM_CORE="$XG_CORE_BIN" exec "$app/Contents/MacOS/$(xg_bundle_exe "$app")" -workdir "$XG_APPDATA/"
}

cmd_status() {
	echo "Toolchain:  $(xcode-select -p 2>/dev/null)"
	echo "Sources:    $XG_SRC ($(git -C "$XG_SRC" describe --tags 2>/dev/null || echo '?'), ветка $(git -C "$XG_SRC" branch --show-current 2>/dev/null))"
	for lib in tdesktop_rust rnnoise tde2e tg_owt; do
		printf '  %-14s %s\n' "$lib" "$([[ -f "$XG_LIBS/local/$lib/.xg-stamp" ]] && echo готов || echo нет)"
	done
	echo "Core:       $([[ -x "$XG_CORE_BIN" ]] && "$XG_CORE_BIN" version || echo нет)"
	echo "Build:      $XG_BUILD $([[ -f "$XG_BUILD/build.ninja" ]] && echo '(configured)' || echo '(нет)')"
	echo "App:        $([[ -d "$XG_DIST/Xraygram.app" ]] && echo "$XG_DIST/Xraygram.app" || echo нет)"
	echo "API env:    $([[ -f "$XG_API_ENV" ]] && echo "$XG_API_ENV (права $(stat -f '%Lp' "$XG_API_ENV"))" || echo "нет $XG_API_ENV")"
}

case "$COMMAND" in
	all)
		cmd_deps
		cmd_src
		cmd_core
		cmd_build
		cmd_app
		;;
	deps) cmd_deps ;;
	src) cmd_src ;;
	core) cmd_core ;;
	configure) cmd_configure ;;
	build) cmd_build ;;
	app) cmd_app ;;
	dmg) cmd_dmg ;;
	swap) cmd_swap ;;
	quick) cmd_quick ;;
	snapshot) cmd_snapshot ;;
	run) cmd_run ;;
	run-dev) cmd_run_dev ;;
	status) cmd_status ;;
	*) xg_die "неизвестная команда: $COMMAND (см. --help)" ;;
esac
