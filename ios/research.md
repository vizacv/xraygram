# Исследование: Telegram-iOS + xray

Что нашли в `TelegramMessenger/Telegram-iOS` (master, коммит `24638bc6`, 2026-11-03, версия приложения 13.2)
и в libXray для встраивания xray в iPhone-клиент. Клон: `upstream/telegram-ios` (ветка `xraygram` — наши правки).

## Сборка Telegram-iOS

- Система сборки — **Bazel** (`MODULE.bazel`, правила `rules_apple`/`rules_swift` — сабмодули в `build-system/bazel-rules`).
  Вход — обёртка `build-system/Make/Make.py`: сама скачивает Bazel нужной версии в `build-input/`
  (`bazel-9.2.0-darwin-arm64`, sha256 из `versions.json`), пишет `build-input/configuration-repository`
  (переменные `variables.bzl` + профили) и зовёт `bazel build Telegram/Telegram`.
- `versions.json`: `app 13.2`, **`xcode 27.1`**, `bazel 9.2.0`, `macos 27`.
  У нас Xcode **27.2**. Make.py проверяет версию и падает, но есть штатный флаг **`--overrideXcodeVersion`**
  (им пользуются и сами разработчики, см. `CLAUDE.md` апстрима). Иначе пришлось бы ставить Xcode 27.1 рядом
  (`Xcode_27.1.app` из developer.apple.com, переключение через `DEVELOPER_DIR`, без sudo).
- `xcode-select` трогать не нужно: скрипты экспортируют `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
  лицензия Xcode уже принята (`xcodebuild -checkFirstLaunchStatus` → 0). Есть среда симулятора iOS 27.2.
- Кэши Bazel по умолчанию — `/private/var/tmp/_bazel_$USER` и `~/...`. Уводим внутрь проекта:
  `--bazelUserRoot upstream/xraygram-ios/bazel-root` (это `--output_user_root`) и `--cacheDir upstream/xraygram-ios/bazel-cache`
  (disk cache). Клон + сабмодули ≈ 1 ГБ.
- Конфигурации: `debug_sim_arm64`, `release_sim_arm64`, `debug_arm64`, `release_arm64` (32-бит и x86 нет).
- Конфигурация приложения — JSON (`build-system/template_minimal_development_configuration.json`):
  `bundle_id`, `api_id`, `api_hash`, `team_id`, `is_internal_build`, `is_appstore_build`, `appstore_id`,
  `app_specific_url_scheme`, `premium_iap_product_id`, `enable_siri`, `enable_icloud`.
  Наш генерирует `build.sh prepare` в `upstream/xraygram-ios/configuration.json` (0600): ключи — из
  `.secrets/api.env` (те же `TDESKTOP_API_ID/HASH`, что у macOS), `enable_siri/icloud = false`.
- Подпись — один из источников: `--gitCodesigningRepository` (fastlane match), `--codesigningInformationPath <dir>`
  (папка `profiles/*.mobileprovision` + `certs/`), `--xcodeManagedCodesigning`. Профили сопоставляются по
  `application-identifier` = `TEAM.bundle_id[.Share|.NotificationService|...]`.
- `aps-environment` Make.py берёт из профиля основного приложения и **падает**, если его нет → патчим
  (`BuildConfiguration.py`): без него собираем без push.
- Флаги `--//Telegram:disableExtensions` и `--//Telegram:disableProvisioningProfiles` есть в `Telegram/BUILD`, но в Make.py
  доступны только для `generateProject` → патчим: добавили `--disableExtensions/--disableProvisioningProfiles` и для `build`.

## Состав приложения и бесплатный Apple ID

`ios_application(name = "Telegram")` + фреймворки `MtProtoKit`, `SwiftSignalKit`, `Postbox`, `TelegramCore`, `TelegramUI`
и расширения: Share, NotificationContent, NotificationService, Intents (Siri), Widget, BroadcastUpload
(+ watch-приложение, по умолчанию выключено).

Таблица Apple «Supported capabilities (iOS)» (колонка «Apple Developer» = бесплатный аккаунт, проверено 2026-11-18):

| Capability | Бесплатно | Где в Telegram | Что делаем |
|---|---|---|---|
| App Groups | **да** | `group.<bundle_id>` — общий контейнер данных (AppDelegate берёт путь из него) | оставляем |
| Keychain sharing | да | `BuildConfig.keychainAccessGroup` | оставляем (профиль даёт `TEAM.*`) |
| Background modes | да | audio, fetch, voip, remote-notification… (Info.plist) | оставляем |
| Data protection | да | — | — |
| Push Notifications | **нет** | `aps-environment`, PushKit (VoIP) | убираем: `aps-environment` пустой |
| iCloud | нет | `enable_icloud` | `false` в конфигурации |
| Siri | нет | `enable_siri`, Intents-расширение | `false` + без расширений |
| Associated Domains | нет | только для официальных bundle id | само выключается |
| Communication Notifications, CarPlay, Sign in with Apple, Apple Pay, unrestricted VoIP | нет | только для официальных bundle id | само выключается |
| Network Extensions / Personal VPN | нет | не используются | — |

Ограничения бесплатного аккаунта (developer.apple.com, «Developer account overview»): **до 10 App ID, живут 7 дней;
до 3 устройств; до 3 приложений на устройство; профиль истекает через 7 дней** — потом пересобрать/переподписать и
поставить заново (данные приложения сохраняются, если bundle id тот же).

Каждое расширение — отдельный App ID (`<bundle>.Share` и т.д.), т.е. с 6 расширениями сразу 7 из 10 App ID.
Поэтому первая сборка **без расширений** (`--disableExtensions`). Что перестаёт работать:

- **Push-уведомления** (нет и Push, и NotificationService): сообщения приходят, только пока приложение открыто
  или недавно свёрнуто; входящие **звонки** не будят приложение (PushKit тоже требует push).
- «Поделиться» из других приложений (Share), виджеты, Siri/Shortcuts, превью уведомлений, трансляция экрана в
  звонке (BroadcastUpload), Apple Watch.
- Всё остальное (чаты, медиа, звонки при открытом приложении, прокси) — работает.

Share-расширение при желании можно вернуть позже (свой App ID + та же App Group; xray внутри расширения НЕ
поднимать — лимит памяти расширений ~120 МБ и второй Go-рантайм; расширение ходило бы мимо прокси).

## Прокси в TelegramCore / MtProtoKit

- Модель: `submodules/TelegramCore/Sources/SyncCore/SyncCore_ProxySettings.swift`
  - `ProxyServerConnection`: `.socks5(username, password)`, `.mtp(secret)`, `.web(secret, path)` (новый «WEB proxy»);
    сериализация Postbox-`Codable` по ключу `_t` (0/1/2/3). Мы добавили **`.xray(link:)` с `_t = 4`**.
  - `ProxyServerSettings(host, port, connection)`, `ProxySettings(enabled, servers, activeServer, useForCalls)`,
    `effectiveActiveServer`. Хранится в `accountManager` shared data (`SharedDataKeys.proxySettings`) — общее для
    всех аккаунтов.
- В сеть: `submodules/TelegramCore/Sources/Settings/ProxySettings.swift` → `ProxyServerSettings.mtProxySettings`
  → `MTSocksProxySettings(ip, port, username, password, secret)`. Используется в трёх местах:
  `initializedNetwork` (старт), `Network.updateProxySettings` (смена активного прокси, подписка в `Account.swift`),
  `ProxyServersStatuses` (пинг **каждой** записи списка через `MTProxyConnectivity.pingProxy`).
- MtProtoKit (`MTTcpConnection.m`) умеет SOCKS5 с логином/паролем (метод `0x02`, RFC 1929); адрес-IP идёт без DNS.
  Rust-движок (`submodules/MTProtoRustEngine`, на iOS по умолчанию выключен — `NetworkEngineSettings.defaultSettings`
  = `.mtProtoKit`) берёт тот же `MTSocksProxySettings` (`RustNetworkSession.makeProxy`). Т.е. xray подключается
  на уровне `mtProxySettings` для обоих движков.
- UI (`submodules/SettingsUI/Sources/Data and Storage/`):
  - `ProxyListSettingsController.swift` — список, пинг/статус, «Use for calls», шаринг списка;
  - `ProxyServerSettingsController.swift` — экран «Proxy» (добавить/изменить): тип SOCKS5/MTProto/WEB, поля,
    «Paste from clipboard» (если в буфере `tg://socks|proxy` или `t.me/...`);
  - `ProxySettingsServerItem.swift` — строка списка (`host:port`);
  - ещё упоминания: `DataAndStorageSettingsController` (подпись типа), `PeerInfoSettingsItems` (пункт «Прокси» в
    настройках), `SettingsSearchableItems`, `QrCodeScreen` (QR со ссылкой), `ProxyServerPreviewScreen` (лист при
    открытии ссылки прокси).
- Разбор ссылок `tg://socks?server=&port=&user=&pass=`, `tg://proxy?...&secret=`, `https://t.me/socks|proxy?...`:
  `submodules/UrlHandling/Sources/UrlHandling.swift` (`parseInternalUrl` → `.proxy(...)`, `parseProxyUrl`),
  открытие — `TelegramUI/Sources/OpenResolvedUrl.swift` (`ProxyServerPreviewScreen`). `vless://` Телега как ссылку
  не понимает — подставляем из буфера на экране добавления (как на macOS).

## Звонки (tgcalls / WebRTC)

- `PresentationCallManager` берёт `activeServer`, если `enabled && useForCalls`; `OngoingCallContext` превращает
  `.socks5` в `VoipProxyServerWebrtc(host, port, user, pass)` (MTProto/WEB — без прокси).
- tgcalls (`NetworkManager.cpp`, `v2/*`) отдаёт его WebRTC как `rtc::ProxyInfo` `PROXY_SOCKS5` → порт-аллокатор
  ходит к relay/TURN **по TCP через SOCKS5** (UDP через SOCKS5 WebRTC не умеет). Нашему inbound UDP не нужен.
- Для `.xray` отдаём тот же локальный SOCKS5 (`ProxyServerSettings.xrayLocalSocks`), переключатель «Use for calls»
  показывается и для XRAY-записей.

## xray внутри процесса iOS

iOS-приложение не может запускать дочерние процессы (как `xraygram-core` на macOS) → ядро линкуется в приложение.

- libXray (`upstream/libxray`, тег `v26.11.9` = Xray-core v26.11.9) даёт для Apple:
  `gomobile bind` (ObjC-фреймворк) или `go build -buildmode=c-archive` + `CGoInvoke` (`build/app/apple_go.py`).
- **Не берём пакет `libXray/xray` как есть**: под `GOOS=ios` его `RunXray` включает `memory.InitForceFree()` —
  режим для Network Extension (лимит 30 МБ, `SetGCPercent(10)`, `FreeOSMemory` **каждую секунду** навсегда). Для
  главного приложения это лишняя нагрузка на CPU/батарею. Ещё он допускает **один** экземпляр на процесс.
- Своё ядро **`ios/xraykit/go`** (Go c-archive, ~250 строк): libXray `share` (разбор ссылок) + Xray-core `core`
  напрямую; логика конфига — как в `macos/core` (SOCKS5 inbound 127.0.0.1 с логином/паролем, первый outbound,
  `freedom` запасной). Несколько экземпляров по ключу — у каждой XRAY-записи свой порт (как процессы на macOS),
  чтобы список прокси мог пинговать все записи. Проверено на macOS-срезе: два экземпляра параллельно, остановка
  одного не трогает другой, SOCKS5 без пароля отклоняется («No authentication method was acceptable»).
- `XraygramCore.xcframework` (`ios/scripts/build-core.sh`): ios-arm64, ios-arm64-simulator, macos-arm64 —
  по ~38 МБ статики (до линковки и strip), сборка ~30 с. Нужны `-lresolv`, CoreFoundation, Security.
- **Один Go-рантайм на процесс**: ядро должно линковаться ровно в один бинарник. Подключаем как зависимость
  `TelegramCore` → оно попадает в `TelegramCoreFramework`; `rules_apple` исключает библиотеки уже слинкованных
  фреймворков из зависящих (`frameworks = [...]`), так что в `TelegramUIFramework` и в сам `Telegram` не дублируется
  (проверить после сборки: `nm` на `_XGStart` только в TelegramCore).
- Swift-обёртка **`XraygramKit`** (`ios/xraykit/swift`, только Foundation — годится для будущего macOS Swift-клиента
  на том же TelegramCore): `XrayLink.check/extract/displayTitle`, `XrayProxyManager` (endpoint/retain/release,
  перезапуск после фона).

### Фон и возврат из фона

- Пока приложение активно или выполняет фоновую задачу, горутины xray работают как обычно.
- В приостановленном состоянии всё стоит (и MTProto тоже). iOS может **отобрать слушающий сокет**
  у приостановленного приложения (Apple TN2277, «Networking and Multitasking»): после возврата `accept()` получает
  ошибку. Поэтому на `sceneWillEnterForeground` (`AppDelegate.handleWillEnterForeground`) зовём
  `XrayProxyManager.handleWillEnterForeground()`: неблокирующий `connect()` на каждый порт; мёртвые экземпляры
  перезапускаются **на том же порту** (MTSocksProxySettings не меняются). Если порт занят — новый порт и уведомление
  `endpointsChangedNotification` → `Network` переприменяет активный прокси.

### Память

- Лимиты jetsam у главного приложения на современных iPhone — сотни МБ / гигабайты, xray с одним VLESS+Reality
  outbound занимает единицы–десятки МБ. Ставим мягкий лимит Go `SetMemoryLimit(64 МБ)` и `GOGC=50`
  (`XrayProxyManager.memoryLimitBytes`), после старта/остановки — `FreeOSMemory`.
- В расширениях (если вернём) ядро не запускать: лимиты 24–120 МБ.

## Что выяснилось на сборке и в симуляторе (2026-11-18)

- Xcode 27.2 + `--overrideXcodeVersion` собирает без правок. Нужен компонент **Metal Toolchain**
  (`xcodebuild -downloadComponent MetalToolchain`, без sudo, ставится в `/System/Library/AssetsV2`).
- Первая сборка `debug_sim_arm64` (без расширений) — 15,5 мин на M5 (6362 действия), инкрементальная — ~40 с.
  `.app` для симулятора ~660 МБ (Debug, без strip), TelegramCoreFramework 107 МБ (с ядром xray).
- `simctl install` не заменяет приложение с тем же номером сборки — `build.sh run-sim` копирует бандл поверх
  установленного (`simctl get_app_container`), данные/вход сохраняются (так советует CLAUDE.md апстрима).
- **Буфер обмена на iOS 27**: `UIPasteboard.general.string` без действия пользователя → `PBErrorDomain 13
  "Operation not authorized"` без диалога; даже по нажатию кнопки в симуляторе системный запрос не показался
  («Paste requires user authorization. Prompting…» → отказ). Штатная вставка из меню поля (долгое нажатие →
  Paste) работает всегда. Поэтому: строка «Вставить ссылку из буфера» (на устройстве должна показать запрос) +
  вставка в поле. Штатная автоподстановка `tg://proxy` из буфера в Telegram на iOS 27 тоже не срабатывает.
- **Экран входа**: в Telegram-iOS прокси до входа открывается только из алерта таймаута отправки кода
  («Use Proxy»). Для заблокированного Telegram это тупик → добавили кнопку «Прокси» в навигацию экрана
  «Your Phone» (`AuthorizationSequencePhoneEntryController`), открывает тот же список прокси.
- Эмуляция ввода в симуляторе (`simctl`/HID) теряет символы в длинной строке — для проверок вставлять через буфер
  (`xcrun simctl pbcopy <udid>`).

## Экран XRAY и блокировка сети (2026-11-18)

- Все MTProto-сети берут прокси из `ProxySettings.effectiveActiveServer` (`initializedNetwork` в `Network.swift`,
  подписки в `Account.swift`: неавторизованный и авторизованный аккаунт). Если записи настроек ещё нет (первый
  запуск), раньше было `nil` = напрямую; теперь подставляется `ProxySettings.defaultSettings` (= блокировка).
- `MTBackupAddressSignals.fetchBackupIps` создаёт свой `MTContext` с `withUpdatedSocksProxySettings:nil` — то есть
  поиск запасных адресов всегда шёл мимо прокси (DoH к Google/Cloudflare, затем прямое MTProto к найденным IP).
  Запускается из `MTContext` после неудачных подключений (через 5–20 с). Выключен при заданном прокси.
- Проверено по логам симулятора: при блокировке все `MTTcpConnection` идут «via 127.0.0.1:1» и получают
  `Connection refused` локально; после «Подключить» — «via 127.0.0.1:<порт xray> using xg…»; после «напрямую» —
  без «via». (Прямое соединение к 149.154.167.50, замеченное `lsof`, оказалось Telegram Desktop на самом Маке.)
- Экран входа Telegram-iOS показывается `mainWindow.present(authRoot, on: .root)`, а `Window1.present` для уровней ≤3
  кладёт `ViewController` оверлеем в верхний `NavigationController`. Если показать свой экран раньше экрана входа,
  тот его перекроет — поэтому показ ждёт хозяина.
- Версии звонков: `InstanceImpl` (v1), `InstanceV2Impl` 7/8/9/12/13, `InstanceV2ReferenceImpl` 10/11,
  `InstanceV2CompatImpl` 14, `InstanceV2PumpImpl` 18/19 (`OngoingCallThreadLocalContext.mm`,
  `ensureRegisteredImplementations`). Выбор версии — `CallSessionManager` (`filteredVersions`, `selectVersionOnAccept`).

## BUG-18: падение в GCDAsyncSocket (симулятор, 2026-11-18 18:28)

`Telegram-2026-11-18-182835.ips`: `EXC_BREAKPOINT`, «Abort Cause» в `_os_unfair_lock_recursive_abort`, поток очереди
`GCDAsyncSocket`: `-[GCDAsyncSocket doReadEOF]` → `closeWithError:` → `CFReadStreamClose` → `SocketStream::close` →
`CFSocketInvalidate` → `~SocketStream` → `CFSocketInvalidate` (повторно) → рекурсивная блокировка. Кода Xraygram в
стеке нет: это апстримный путь MtProtoKit (GCDAsyncSocket на iOS всегда держит CFStream на сокет) и, по виду,
ошибка CFNetwork iOS 27 (повторный вход в `CFSocketInvalidate` при уничтожении потока). Связь с нами косвенная:
`doReadEOF` — удалённая сторона закрыла соединение. С выдуманным сервером xray принимает SOCKS-соединение и сразу
закрывает его (outbound не подключается) — EOF идут сериями, вероятность гонки выше. С рабочим сервером EOF редки.
Чинить в MtProtoKit вслепую не стали; если повторится с рабочим сервером или на устройстве — смотреть отказ от
CFStream (`createReadAndWriteStream`) для соединений к 127.0.0.1.
