# Исследование: Telegram Desktop (tdesktop) + xray на macOS

Дата: 2026-11-18. Ведёт тема «Xraygram macOS».

## Исходники

| Репозиторий | Версия | Где лежит |
|---|---|---|
| `telegramdesktop/tdesktop` | тег **`v7.4.4`** = `bf4f714036f21c750d535dab199c811b3f9bfdd4` (2026-11-13). master на момент клона: `9918118a` | `upstream/tdesktop` (shallow, без сабмодулей; рабочая ветка `xraygram` с нашими правками) |
| сабмодули на `v7.4.4` | `cmake` = `7ceca301`, `lib_ui` = `caaa3f1e`, `lib_base` = `42a0e5dd` | не клонировали; нужные заголовки смотрели через raw.githubusercontent.com |
| `XTLS/libXray` | `v26.11.9` = `5a0f7d8`, Go-тег `v1.261109.0` | `upstream/libxray` |
| `XTLS/Xray-core` | `v26.11.9` (тянется libXray через go.mod) | — |

Между `v7.4.4` и master в нужных нам местах (`.github`, `mtproto`, `connection_box.cpp`, `CMakeLists.txt`) отличается только `win.yml`.

## Прокси в tdesktop

Пути от `Telegram/SourceFiles/`.

- **`mtproto/mtproto_proxy_data.h`** — `MTP::ProxyData`: `enum class Type { None, Socks5, Http, Mtproto, Web }`,
  поля `host, port, user, password`, `Settings { System, Enabled, Disabled }`. `operator==` сравнивает тип, хост, порт,
  логин и пароль (`mtproto_proxy_data.cpp`, `ProxyData::operator==`). `ToNetworkProxy()` даёт `QNetworkProxy` для Qt.
  - Тип `Web` — свежий «веб-прокси» Телеги (`mtproto/web_proxy/*`, `MTP::WebProxy::Transport::Activate/Deactivate`).
    Он сделан как раз по схеме «локальный мост»: хороший образец, как вешать свой транспорт.
- **`core/core_settings_proxy.{h,cpp}`** — `Core::SettingsProxy`: список прокси, выбранный, режим, ротация, IPv6.
  Сериализация: `SerializeProxyData/DeserializeProxyData` пишут тип числом 0..4. Новый тип в `ProxyData::Type`
  потребовал бы менять формат хранения и все `switch` по типу (их ~20 мест) — поэтому новый тип **не вводим**.
- **`core/application.cpp`**:
  - `Application::run()` — после `startLocalStorage()` и `ValidateScale()` вызывается `refreshGlobalProxy()`
    («Depends on app settings being read»). Сюда вставлен `Xraygram::Start()`.
  - `Application::refreshGlobalProxy()` — по выбранному прокси включает/выключает WebProxy и вызывает
    `Sandbox::Instance().refreshGlobalProxy()` (ставит `QNetworkProxy::setApplicationProxy` для всего прочего HTTP-трафика).
  - `Application::setCurrentProxy(proxy, settings)` — единая точка смены прокси (вызывает `refreshGlobalProxy`, шлёт `proxyChanges`).
  - `Application::~Application()` — после `_domain->finish()` гасим xray (`Xraygram::Shutdown()`).
- **Соединения**: `mtproto/connection_tcp.cpp`, `connection_http.cpp`, `session_private.cpp`, `session.cpp`
  смотрят на `ProxyData::Type` (особые ветки только для `Web` и `Mtproto`). SOCKS5 для TCP идёт через
  `QNetworkProxy` (Qt реализует RFC 1928/1929, логин/пароль поддерживаются). Мы этот код не трогаем.
- **Проверка прокси**: `mtproto/proxy_check.cpp` (`MTP::StartProxyCheck`) — пинг через прокси до DC; для нашей
  SOCKS5-записи работает как обычно, пока xray запущен.
- **Экран настроек прокси**: `boxes/connection_box.{h,cpp}` (~3000 строк):
  - `ProxiesBox` — список; `setupTopButton()` — меню «⋮» (там «Add from clipboard»), `addNewProxy()` — кнопка «Add proxy».
  - `ProxyBox` — форма одного прокси (тип, адрес, логин/пароль, MTProto-секрет).
  - `ProxiesBoxController` — модель: `addNewItem`, `applyItem`, `deleteItem`, `updateView` (подпись типа `SOCKS5`/`MTPROTO`/...),
    `ProxyDataIsShareable` (что можно шарить ссылкой), `AddProxyFromClipboard` (разбор `tg://proxy` / `tg://socks` из буфера).
  - Тот же `ProxiesBox` открывается и с экрана входа (до логина), это важно: без прокси войти нельзя.
- **Ссылки `tg://socks` / `tg://proxy` / `tg://webproxy`**: `core/local_url_handlers.cpp` (`ApplySocksProxy`/`ApplyMtprotoProxy`,
  список типов около `MTP::ProxyData::Type::Web`), подтверждение — `ProxiesBoxController::ShowApplyConfirmation`.
  `vless://` Телега как ссылку не распознаёт, поэтому ловим её из буфера обмена.
- **Ротация прокси**: `core/proxy_rotation_manager.cpp` — переключает между записями списка при обрывах; нашу запись
  рассматривает как обычный SOCKS5.

## Имя приложения, папка данных, bundle id

- `core/version.h`: `AppName = "Telegram Desktop"`. На macOS папка данных — `~/Library/Application Support/<AppName>/`
  (`platform/mac/specific_mac_p.mm`, `objc_appDataPath()`). Имя одиночного экземпляра (`core/sandbox.cpp`) — md5 от
  рабочей папки, так что другая папка = нет конфликта с официальным клиентом.
- `core/launcher.cpp`: `QApplication::setApplicationName(u"TelegramDesktop"_q)` — влияет на `QStandardPaths`.
- `Telegram/CMakeLists.txt` (блок `if (build_macstore) ... else()`): `bundle_identifier "com.tdesktop.Telegram"`, `output_name "Telegram"`.
- `Telegram/Telegram.plist`: `CFBundleName=@output_name@`, `CFBundleURLTypes` со схемами `tg`, `tonsite`, `ton`.
  Если их оставить, LaunchServices может отдать `tg://` ссылки нашему приложению вместо официального.

## api_id / api_hash

- `Telegram/cmake/telegram_options.cmake`: `TDESKTOP_API_ID`/`TDESKTOP_API_HASH` (CMake cache), без них configure падает.
- `-DTDESKTOP_API_TEST=ON` подставляет тестовые `17349` / `344583e4...`. Сам CMake предупреждает: ключи «very limited»,
  у пользователей при входе будут internal server errors. Upstream CI использует их только для проверки сборки.
  **Для личной тестовой сборки не годятся** (вход, скорее всего, не пройдёт: `API_ID_PUBLISHED_FLOOD` и т.п.).
  Нужны свои ключи с https://my.telegram.org → API development tools.
- Флаги попадают в бинарник как `target_compile_definitions(Telegram PRIVATE TDESKTOP_API_ID=...)`; в лог CI не печатаем.

## Сборка macOS в upstream

Два workflow на `v7.4.4`:

1. **`.github/workflows/mac.yml`** — «официальный» путь: `Telegram/build/prepare/mac.sh` → `prepare.py` (2182 строки)
   собирает из исходников **всё**: Qt 6 (`qt_<ver>`), ffmpeg, openssl3, dav1d, libvpx, openh264, libavif, libjxl, libheif,
   openal-soft, tg_owt (WebRTC), crashpad/breakpad, tde2e, Rust (tlottie, wallet-engine) и т.д. Кэш — `Libraries` + `ThirdParty`
   по ключу `hashFiles(prepare.py)`. Дальше `configure.sh` → Xcode-проект, `-D TDESKTOP_API_TEST=ON`, Debug. Холодный прогон —
   часы (порядка 3–5 ч на 3-ядерном `macos-latest`, близко к лимиту 6 ч), кэш весит много (документация: ~35 ГБ библиотек для двух архитектур).
2. **`.github/workflows/mac_packaged.yml`** — Qt, ffmpeg@6, openssl, opus, libavif, libheif, jpeg-xl и пр. из **Homebrew**;
   из исходников только Rust-библиотеки, rnnoise, tg_owt, tde2e (каждое в своём `actions/cache`). Генератор Ninja, Debug,
   `cmake -Bbuild . -DTDESKTOP_API_TEST=ON`, затем `macdeployqt build/Telegram.app` (копирует Qt и brew-dylib в бандл).
   Запускается на каждый push в upstream, значит на `v7.4.4` рабочий. Оценка: холодный ~1,5–2,5 ч, с кэшем ~1 ч.

Мы берём **вариант 2** (см. `decisions.md`). Риск: brew со временем обновит Qt/ffmpeg, а мы закреплены на `v7.4.4`;
если сборка сломается из-за новой версии brew-пакета — обновить тег tdesktop или вернуться к варианту 1.

Ещё по CMake (`cmake_helpers` `variables.cmake`, коммит `7ceca301`): без `DESKTOP_APP_SPECIAL_TARGET`
`DESKTOP_APP_DISABLE_AUTOUPDATE` и `DESKTOP_APP_DISABLE_CRASH_REPORTS` и так `ON`; мы всё равно задаём их явно — форк
не должен обновляться официальным апдейтером и слать крэш-репорты Телеге.

## xray: что даёт libXray для macOS

- `build/main.py apple go|gomobile` — c-archive/xcframework для iOS/macOS (cgo). `linux`/`windows` дополнительно
  собирают CLI `bin/xray` из `desktop_bin/` — но там `//go:build windows || (linux && !android)`, для darwin его нет.
- Go-пакеты без cgo и без build-тегов для darwin: `share` (`ConvertShareLinksToXrayJson(links, secretKey)` → `{"outbounds":[...]}`,
  имя из `#fragment` кладётся в `tag`), `xray` (`RunXray(json)`, `StopXray()`, `XrayVersion()`; один экземпляр на процесс),
  `memory` (`memory_other.go` для не-iOS).
- Поддерживаемые схемы share-ссылок: vless, vmess, trojan, ss, socks, hysteria2 (+ base64-подписки).

## Что сделано в патче

`macos/patches/0001-xraygram-xray-socks.patch` (против `v7.4.4`, проверен `git apply --check` на чистом теге):

- `Telegram/SourceFiles/xraygram/xraygram_core.{h,cpp}` — менеджер XRAY-записей: `Instance` на каждую запись
  (процесс `xraygram-core`, порт, пароль, перезапуск с backoff), `Manager` (хранение `tdata/xraygram.json` v2,
  `SaveLink`, асинхронный `CheckLink`, `TitleFor`/`LinkFor` для UI).
- `boxes/connection_box.{cpp,style}` — тип «XRAY (VLESS)» в `ProxyBox` (поле «Ссылка» + строка статуса), перехват
  `vless://` из буфера в «Add proxy»/«Add from clipboard», подпись `XRAY · имя` в списке, запрет шаринга XRAY-записей.
- `window/main_window.cpp`, `window_saved_windows.cpp`, `window_restore_shell.cpp`, `platform/mac/window_title_mac.mm`,
  `boxes/about_box.cpp` — «Telegram» → «Xraygram» в заголовках.
- `core/application.cpp` — `Xraygram::Start()` в `run()`, `EnsureRunning(proxy)` в `refreshGlobalProxy()`, `Shutdown()` в деструкторе.
- Ребрендинг: `AppName = "Xraygram"`, `setApplicationName("Xraygram")`, bundle id `io.github.xraygram.desktop`,
  `CFBundleName/DisplayName = Xraygram`, убраны URL-схемы `tg/ton/tonsite`. Исполняемый файл внутри остаётся `Telegram`
  (меньше правок в CMake), бандл переименовывается в `Xraygram.app` в CI.

Помощник `macos/core/` (Go, `xraygram-core`): `version`, `check` (ссылка из stdin → `OK <протокол> <адрес> <имя>`),
`run -listen 127.0.0.1:PORT` (ссылка из stdin, логин/пароль SOCKS из env → `READY ...`, выход по SIGTERM или смерти родителя).
Конфиг xray: inbound `socks` на 127.0.0.1 с паролем, `udp:false`; outbound — первый из ссылки (tag `proxy`, он же маршрут
по умолчанию) + `freedom`. Без routing и geo-файлов.

Как работает в приложении:
1. Ссылка, порт и случайный пароль SOCKS лежат в `~/Library/Application Support/Xraygram/tdata/xraygram.json` (права 0600).
2. При старте, если ссылка есть, запускается `Contents/MacOS/xraygram-core run ...`; ждём `READY` до 5 с.
   Если порт занят — берём свободный и переписываем запись в настройках прокси.
3. В списке прокси — обычная SOCKS5-запись `127.0.0.1:<порт>`, логин `xraygram` (по нему и узнаём «свою»), подпись `XRAY`.
   Выбор/отключение/ротация — штатными средствами Телеги.
4. Если xray упал — перезапуск с экспоненциальной задержкой 3 с → 6 → 12 … до 2 мин (сброс, если проработал ≥ 60 с);
   неудачный запуск тоже не повторяется чаще этой задержки, чтобы не подвешивать UI синхронным ожиданием `READY`.
   Если при перезапуске порт занят — новый порт, запись в настройках заменяется, прокси переприменяется.
   Если умерла Телега — помощник сам выходит (опрос `getppid` раз в секунду).
5. При смене ссылки, если пришлось сменить порт, старая XRAY-запись удаляется из списка (`removeStaleXrayItems`).

Ограничения теста: ссылка лежит в `xraygram.json` открытым текстом (0600, но локальный код-пароль Телеги её не шифрует);
`udp:false` — звонки через xray не пойдут (MTProto работает по TCP, этого хватает); окно ввода и `check`/`READY` синхронные
(до ~10 с в худшем случае при сохранении ссылки).

## Что НЕ проверено (локально собрать нельзя)

- Компиляция C++ патча и Go-помощника — только вычитка (своя + независимый агент сверил все API с заголовками
  lib_ui/lib_base на закреплённых коммитах сабмодулей и с исходниками libXray; ошибок компиляции не нашёл,
  найденные runtime-проблемы исправлены). Первая настоящая проверка — CI.
- Поведение `macdeployqt` с brew-библиотеками на текущем `macos-latest`, запуск DMG на macOS 26.7.
- Реальное подключение через VLESS+Reality (нужна ссылка владельца).

## Локальная сборка на MacBook Air M5 (2026-11-18)

Скрипты: `macos/scripts/build-local.sh`, `update-patch.sh`, `common.sh`. Повторяют CI-вариант `mac_packaged`.

- **Компиляция патча**: с первого раза без ошибок и без предупреждений в наших файлах (57 предупреждений — все
  upstream: `Q_OS_MAC deprecated`, `ld: ... built for newer macOS (26.0) than being linked (14.4)` от brew-библиотек и
  Swift-модуля `lib_translate`). `MACOSX_DEPLOYMENT_TARGET` = 14.4 (из `Qt6ConfigExtras.cmake` brew qtbase 6.12.0).
- **CommandLineTools достаточно**: Swift 6.4 (`lib_translate`, `enable_language(Swift)`), SDK 27.0, `actool`/`metal`
  сборка не вызывает. Полный Xcode не понадобился.
- **packaged-режим**: `cmake_helpers/validate_special_target.cmake` включает `DESKTOP_APP_USE_PACKAGED`, если рядом с
  исходниками нет `../Libraries`. Наши либы лежат в `upstream/xraygram-local/libs`, скрипт ещё и задаёт флаг явно.
- **Подводные камни**: rnnoise `autogen.sh` качает модель через `wget` (добавлен в brew-пакеты); `go mod tidy` один раз
  упал на `proxy.golang.org` (`stream error ... INTERNAL_ERROR`), со второй попытки прошёл — при постоянных сбоях
  `GOPROXY=direct`.
- **Ключи API** — compile definition всей цели `Telegram`, поэтому смена ключей = пересборка почти всего (~15 мин).
- **Время**: tdesktop с нуля 18 мин, инкрементально ~5 с, macdeployqt 5 мин (бинарник ~800 МБ, бандл 421 МБ).
- **Дымовой тест** (`-workdir upstream/xraygram-local/appdata`): приложение стартует (Qt 6.12.0); с фиктивной ссылкой в
  `tdata/xraygram.json` в логе `Xraygram: xray started on 127.0.0.1:20877 (vless example.com smoke)`, порт слушает
  `xraygram-core`; после `kill -9` Телеги помощник сам вышел. `xraygram-core run` без логина/пароля SOCKS отказывает
  (`No authentication method was acceptable`).
- **Следы вне проекта**: tdesktop при старте создаёт пустой `~/Library/Application Support/Xraygram` даже с `-workdir`;
  Go писал телеметрию в `~/Library/Application Support/go` — теперь `GOTELEMETRY=off`, `GOTELEMETRYDIR` внутри проекта.
