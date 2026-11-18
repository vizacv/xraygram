# Xraygram macOS

Основа: Telegram Desktop (`telegramdesktop/tdesktop`, тег **v7.4.4**). Цель первого этапа: тестовая сборка
под Apple Silicon (arm64), в которой можно вставить `vless://` ссылку и Телега ходит через встроенный xray.

База знаний этой системы ведётся здесь (ведёт тема «Xraygram macOS»).

- [research.md](research.md) — что нашли в tdesktop и libXray: прокси-код, сборка, api_id, как устроен патч.
- [decisions.md](decisions.md) — принятые решения и почему.
- [patches/](patches/) — патч против tdesktop `v7.4.4`.
- [core/](core/) — Go-помощник `xraygram-core` (libXray `share` + `xray`), кладётся в `Xraygram.app/Contents/MacOS/`.
- [build-macos.yml](../.github/workflows/build-macos.yml) — GitHub Actions workflow (лежит в `.github/workflows/`).

## Статус

- [x] Исследование tdesktop: прокси-код, сборка macOS, upstream CI, api_id
- [x] Способ встраивания xray: дочерний процесс `xraygram-core` (Go, libXray), SOCKS5 на 127.0.0.1
- [x] Патчи (`patches/0001-xraygram-xray-socks.patch`, чисто применяется к `v7.4.4`)
- [x] GitHub Actions workflow (`.github/workflows/build-macos.yml`)
- [x] Секреты api_id/api_hash в GitHub Secrets; локально — `.secrets/api.env`
- [x] Локальная сборка на MacBook Air M5: патч компилируется без ошибок и предупреждений в наших файлах,
      `Xraygram.app` запускается, `xraygram-core` стартует с приложением и умирает вместе с ним (2026-11-18)
- [ ] Первый зелёный прогон CI
- [ ] Тест с реальной `vless://` ссылкой и входом в аккаунт

## Как собрать (CI)

1. Workflow: `.github/workflows/build-macos.yml` (каноничная копия, правится там).
2. Секреты репозитория: `TDESKTOP_API_ID`, `TDESKTOP_API_HASH` (свои, с https://my.telegram.org).
   Без них сборка пройдёт на тестовых ключах upstream, но войти в аккаунт, скорее всего, не получится.
3. Actions → «Xraygram macOS» → Run workflow (Release по умолчанию).
4. Артефакт `Xraygram-macos-arm64` → `Xraygram-v7.4.4-<sha>-macos-arm64.dmg` (+ `.sha256`).

Задания: `core` (ubuntu, ~3 мин: собирает `xraygram-core` для darwin/arm64 и гоняет smoke-тест на Linux),
`macos` (macos-latest: brew-зависимости, tg_owt/tde2e/rnnoise/Rust с кэшем, tdesktop + патч, `macdeployqt`,
сборка бандла, ad-hoc подпись, DMG). Первый прогон — ориентировочно 1,5–2,5 ч, повторные ~1 ч.

## Как запускать на Mac

```bash
xattr -dr com.apple.quarantine /Applications/Xraygram.app
```

Дальше: Настройки → Продвинутые → Тип соединения (или значок прокси на экране входа) → **Add proxy**.
В окне «Edit proxy» первым стоит тип **XRAY (VLESS)** (выбран по умолчанию): одно поле «Ссылка»
(`vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`; если ссылка уже в буфере — подставится сама),
под ним строка «Сервер: vless · host · имя» или понятная ошибка. **Save** — сохранить и подключиться.
В списке запись выглядит как `XRAY · <имя из #fragment или адрес>`, с пингом как у остальных.
Записей может быть несколько: у каждой свой процесс `xraygram-core` и свой локальный порт, переключение — как между
обычными прокси. Редактирование записи открывает то же окно с выбранным XRAY и подставленной ссылкой.

Данные: `~/Library/Application Support/Xraygram/` (официальный Telegram не затрагивается).
Ссылки хранятся в `tdata/xraygram.json` (права 0600, формат v2: список `entries`; старый формат с одной ссылкой
переносится автоматически). Логи xray — в `DebugLogs` при включённом debug-логе Телеги.

## Локальная сборка (быстрые итерации)

Скрипты: [scripts/build-local.sh](scripts/build-local.sh), [scripts/update-patch.sh](scripts/update-patch.sh),
общие версии/пути — [scripts/common.sh](scripts/common.sh) (держать в синхроне с `.github/workflows/build-macos.yml`).
Повторяют шаги CI (вариант `mac_packaged`: Qt и пр. из Homebrew), всё рабочее лежит в `upstream/` (не в git):

| Что | Где |
|---|---|
| исходники tdesktop `v7.4.4` + сабмодули, наши правки (ветка `xraygram`, staged) | `upstream/tdesktop` |
| Rust-либы, rnnoise, tg_owt, tde2e (`local/<lib>`), rustup/cargo | `upstream/xraygram-local/libs` |
| сборка tdesktop (Ninja) | `upstream/xraygram-local/build-release` (или `build-debug`) |
| `xraygram-core` | `upstream/xraygram-local/bin` |
| готовый `Xraygram.app`, DMG | `upstream/xraygram-local/dist` |
| логи каждого шага | `upstream/xraygram-local/logs` |
| кэши Go (`GOPATH`, `GOCACHE`, телеметрия выключена) | `upstream/xraygram-local/go` |
| данные приложения при `run`/`run-dev` (`-workdir`) | `upstream/xraygram-local/appdata` |

Ключи API — в `~/xraygram/.secrets/api.env` (папка в `.gitignore`, права 0600, в git не попадает).
Создать с запросом значений (ввод хэша скрыт):

```bash
read "i?api_id: " && read -s "h?api_hash: " && mkdir -p ~/xraygram/.secrets && (umask 077; printf 'TDESKTOP_API_ID=%s
TDESKTOP_API_HASH=%s
' "$i" "$h" > ~/xraygram/.secrets/api.env) && echo OK
```

Содержимое (свои значения с my.telegram.org):

```
TDESKTOP_API_ID=12345
TDESKTOP_API_HASH=0123456789abcdef0123456789abcdef
```

Без файла сборка идёт на тестовых ключах upstream. Значения попадают только в `CMakeCache.txt` в `upstream/` и в бинарник.
После создания/смены файла нужен `build-local.sh configure`.

Команды (из корня репозитория):

```bash
macos/scripts/build-local.sh            # всё: deps → src → core → build → app
```

```bash
macos/scripts/build-local.sh quick      # правка C++ → сборка + обновление dist/Xraygram.app за ~5–30 с
```

```bash
macos/scripts/build-local.sh build && macos/scripts/build-local.sh run-dev   # или запуск прямо из build-каталога
```

`quick` подменяет в готовом `dist/Xraygram.app` только исполняемый файл (и `xraygram-core`, если он менялся):
переписывает пути к библиотекам на `@executable_path/../Frameworks/...` так же, как `macdeployqt`, убирает rpath
на `/opt/homebrew` и заново подписывает бандл. Если поменялись `Info.plist`/ресурсы или появилась новая
библиотека, которой нет в бандле, сам переключается на полный `app` (~4–5 мин). Приложение должно быть закрыто.

```bash
macos/scripts/build-local.sh app        # собрать dist/Xraygram.app (macdeployqt + xraygram-core + подпись)
```

```bash
macos/scripts/build-local.sh status
```

Ещё: `deps`, `src`, `core`, `configure`, `dmg`, `run`, `swap`; `--debug` — Debug-сборка в отдельный каталог.
`app` собирает бандл в `upstream/xraygram-local/staging/` и подменяет `dist/Xraygram.app`, только если тот не запущен;
иначе подмену делает `build-local.sh swap` после закрытия приложения.
`run-dev` запускает приложение прямо из build-каталога (библиотеки берутся из `/opt/homebrew`), `xraygram-core`
подставляется через переменную `XRAYGRAM_CORE`; это быстрее, чем пересобирать бандл.

Правки патча: меняем файлы в `upstream/tdesktop`, потом

```bash
macos/scripts/update-patch.sh
```

Он делает `git add -A`, выгружает `git diff --cached v7.4.4` в `patches/0001-xraygram-xray-socks.patch`
и проверяет, что патч чисто применяется к чистому тегу. Правки внутри сабмодулей в патч не попадают (скрипт предупредит).

Время на MacBook Air M5 (10 ядер), 2026-11-18:

| Шаг | Время |
|---|---|
| brew-пакеты (с нуля) | ~2–3 мин |
| сабмодули tdesktop (`--depth 1`) | 1,5 мин |
| Rust-либы / rnnoise / tde2e / tg_owt | 1 мин 50 с / 1 мин / 15 с / 2 мин |
| `xraygram-core` (первый раз, с загрузкой модулей) | ~1 мин |
| tdesktop с нуля (configure 20 с + build) | **18 мин** |
| пересборка после смены ключей API (почти всё) | 15 мин |
| `app`: macdeployqt + подпись | 4,5–5 мин |
| `quick`: правка одного `.cpp` → готовый `dist/Xraygram.app` | **~5 с** (сборка 3 с + подмена 3 с) |
| **инкрементально** (правка одного `.cpp` + линковка) | **~5 с** |

Хватает CommandLineTools (Swift 6.4, SDK 26/27), полный Xcode для этой сборки не понадобился.
tdesktop при старте всё равно создаёт пустой `~/Library/Application Support/Xraygram` (даже с `-workdir`).

Требования: Homebrew (скрипт ставит недостающие пакеты сам, `brew upgrade` не делает), CommandLineTools или Xcode.
Если сборке нужен полный Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

```bash
sudo xcodebuild -license accept
```
