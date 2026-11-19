# Решения Android (DrKLO/Telegram)

## 2026-11-18 — База: DrKLO/Telegram `21f7d109` (13.2.2, 7303), модуль `TMessagesProj_AppStandalone`

Свежее ничего нет: `master` = `21f7d109` от 2026-11-12. Тегов в репо нет, поэтому закрепляем SHA (`TG_REF` в
`scripts/common.sh`). Модуль Standalone — сборка «с сайта»: без Play-обновлений, свой `ApplicationLoaderImpl`.
Вариант сборки `afatStandalone` (R8, `minify` + `shrinkResources`), как у upstream для APK с telegram.org.

## 2026-11-18 — xray внутри процесса (libXray `.aar`, gomobile), а не отдельным исполняемым файлом

Варианты:
- **(а) libXray.aar в процессе** — `gomobile bind`, Java-класс `libXray.LibXray.invoke(json)`;
- **(б) исполняемый файл в `nativeLibraryDir`** (`libxraygram-core.so`, запускаемый через `ProcessBuilder`), как
  `xraygram-core` на macOS.

Выбрали **(а)**. Почему на Android иначе, чем на macOS:
- **Фон и Doze.** Дочерний процесс не получает никаких льгот: в Doze сеть режется всему UID одинаково, а при
  заморозке кэшированных приложений (Android 11+, «cached apps freezer») cgroup замораживается целиком — вместе с
  дочерним процессом. Выигрыша в живучести нет.
- **Phantom process killer** (Android 12+): система убивает «фантомные» дочерние процессы приложений, когда их больше
  32 на устройство или когда они жгут CPU в фоне. Ровно наш случай (долгоживущий сетевой процесс) — риск, что xray
  тихо умрёт, а Телега останется без сети. Внутри процесса этого нет.
- **Перезапуск.** Процесс Телеги убит → xray умер вместе с ним, при следующем старте `ConnectionsManager.init`
  поднимает его снова. Сирот (висящих xray) не бывает. Падение Go внутри процесса роняет приложение — но libXray
  в процессе используют v2rayNG/Hiddify годами, это проверенный путь.
- **Память.** Один Go-рантайм ~20–40 МБ. Отдельный процесс — то же плюс свой ART-зигот не нужен, но выигрыша нет;
  а на каждую запись отдельный процесс (как на macOS) — это ×N.
- **Упаковка проще:** `.aar` подключается Gradle'ом, а исполняемый файл пришлось бы маскировать под `lib*.so`
  и полагаться на `extractNativeLibs` (у Standalone `useLegacyPackaging = true`, так что сработало бы, но это хак).
- Черновик `XrayTransport.java` уже был под этот вариант, API libXray сверен.

Минус: libXray держит **один** экземпляр xray на процесс (`xray.RunXray` → `ErrAlreadyRunning`). Решено следующим пунктом.

## 2026-11-18 — Один экземпляр xray на все XRAY-записи, у каждой свой SOCKS-порт

Конфиг собирается из всех XRAY-записей списка прокси: на каждую ссылку — свой inbound `socks` на
`127.0.0.1:<порт>` и свой outbound, правило маршрутизации `inboundTag → outboundTag`. Так у невыбранных записей
работает пинг в списке и работает ротация прокси Телеги, как на macOS (там — отдельный процесс на запись).
- Порт закрепляется за ссылкой на всё время жизни процесса: перезапуск xray (появилась новая ссылка) не меняет адрес,
  к которому подключён tgnet.
- `ConnectionsManager` получает порт сразу (`XrayTransport.startAsync`), а xray стартует в своём потоке
  `xraygram-core`; tgnet сам переподключается, пока inbound не поднялся. UI-поток не ждёт Go.
- SOCKS закрыт логином `xraygram` и случайным паролем (новым на каждый запуск процесса): на телефоне localhost
  виден всем приложениям.
- Ссылка не уходит в нативный код Телеги: в `native_setProxySettings` для XRAY передаётся `secret = ""`
  (иначе tgnet посчитал бы прокси MTProto).
- Если прокси выключен или выбран не-XRAY, xray останавливается (`stopAsync`). Проверка пинга в списке может
  поднять его снова — он поживёт до следующего переключения прокси.

## 2026-11-18 — Новый тип `ProxySettings.Type.XRAY` (код 3)

В отличие от tdesktop, в Android-клиенте уже есть ровно такой шаблон — тип `WEB` (`WebProxyTransport` поднимает
локальный порт и отдаёт его tgnet). Модель прокси одна (`ProxySettings`), сериализация списка (`SharedConfig`,
схема V3) пишет тип числом, так что новый тип добавляется маленьким патчем: ссылка хранится в поле `secret`,
`address`/`port` вычисляются из ссылки (для подписи, сравнения, хранения). Старые версии Telegram (если данные
когда-нибудь попадут к ним) прочитают код 3 как SOCKS5 — не падают.

## 2026-11-18 — UX как на macOS

- Экран «Прокси» → «Добавить прокси»: тип **XRAY (VLESS)** первым и выбран по умолчанию. Одно поле «Ссылка»
  (`vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`), если ссылка в буфере — подставляется сама.
  Под полем — «Сервер: vless · host:port · имя» (разбор в Java сразу, через 300 мс — проверка парсером xray,
  «✓» или текст ошибки). «Сохранить» — добавить и подключиться (как у обычного прокси).
- В списке: `XRAY · <имя из #fragment или адрес>`, пинг/статус — штатные (MTProto-пинг через xray).
- «Поделиться» для XRAY показывает QR самой ссылки.
- Ссылки `vless://` и т.п. открываются в Xraygram (intent-filter): штатное окно «Подключить прокси?» с
  «XRAY · vless · host:port · имя» вместо секрета.
- Строки XRAY — по-русски для русской локали, иначе по-английски, без правок `strings.xml` (кроме `AppName`).

## 2026-11-18 — Звонки через прокси: исследование (заменено переносом патча tgcalls ниже)

Проверено по коду 13.2.2: `VoIPService` передаёт в `Instance.makeInstance(... proxy = null ...)` — Telegram Android
вообще не пускает звонки через прокси (пункт «Use proxy for calls» убран). В tgcalls v2 (`NativeNetworkingImpl`)
наличие прокси только выключает UDP/STUN, а SOCKS5 к портам не подключается; в встроенном webrtc больше нет
`AsyncSocksProxySocket`. Только устаревший v1 (`NetworkManager.cpp`) умеет SOCKS5.
Чтобы звонки шли через xray, нужно править нативный tgcalls (SOCKS5-обёртка для TCP-сокетов TURN в
`NativeNetworkingImpl`, плюс передать `Instance.Proxy` из `VoIPService`) и пересобирать `libtmessages`. Это отдельная
задача; сейчас звонки идут напрямую, как у официального клиента.

Оркестратор (2026-11-18): патч tgcalls v2 (SOCKS5 в port allocator, только TCP-relay) делает macOS-тема отдельным
переиспользуемым патчем в `macos/patches/`; когда он заработает на Маке, его перенесём в
`TMessagesProj/jni/voip/tgcalls` (сабмодуль — значит, отдельным патчем, `update-patch.sh` правки сабмодулей не
выгружает) и передадим `Instance.Proxy` из `VoIPService` для XRAY-записей. Свою правку tgcalls на Android не делаем.

## 2026-11-18 — Звонки через xray: перенесён патч tgcalls из macOS

Оркестратор передал `macos/patches/tgcalls/0001-socks5-tcp-relay.patch` (SOCKS5 в port allocator tgcalls v2, только
TCP-ретрансляторы). На Android-версии tgcalls (`545f5ae`) он лёг целиком, кроме одного куска с логом в
`InstanceV2ReferenceImpl.cpp` (другой контекст) — вставлен руками. Android-вариант — `patches/tgcalls/0001-socks5-tcp-relay.patch`
(пути от корня tgcalls, против `545f5ae`); `build-local.sh src` применяет, `update-patch.sh` выгружает и проверяет.
Java: `VoIPService` для личного звонка при включённой XRAY-записи передаёт `Instance.Proxy(127.0.0.1, <порт xray>,
xraygram, <пароль>)` и `enableP2p = false`; иначе — как upstream (`proxy = null`). Галку «прокси для звонков» не
возвращаем. Групповые звонки/видеочаты идут без прокси (как на macOS до оценки); предупреждения в UI на Android пока нет.
Живой звонок не проверен (нужны два аккаунта; в эмуляторе только сборка/запуск).

## 2026-11-18 — Экран «Подключение через XRAY» (правила MAC-05, как на macOS)

- **Заблокировано** = в списке прокси нет XRAY-записей и нет явного выбора «напрямую»
  (`mainconfig`: `xraygram_direct_allowed`). Логика — `utils/proxy/XrayGate.java`.
- Пока заблокировано, все аккаунты получают «чёрную дыру» — SOCKS5 `127.0.0.1:1` (`ConnectionsManager.init` и
  `setProxySettings`), сохранённые настройки прокси не меняются. DoH/backup-фолбэк (`onRequestNewServerIpAndPort`:
  Google/Mozilla DNS) не запускается; нативный tgnet при заданном прокси его и так не просит (`ConnectionsManager.cpp:701`).
- Экран — фрагмент `ui/XrayGateActivity` поверх всего в `LaunchActivity` (показ из `onResume` и сразу после удаления
  последней XRAY-записи); Назад сворачивает приложение, свайп-назад выключен. Поле ссылки с подстановкой из буфера,
  превью «Сервер: … ✓» (парсер xray), «Подключить»; «Сохранённые серверы» (ссылки удалённых XRAY-записей,
  `xraygram_saved_links`, до 20) + «Новая ссылка»; внизу «Подключиться без XRAY (напрямую)» с подтверждением и красной
  кнопкой. Экран сам закрывается, если XRAY-запись появилась другим путём (например, `vless://`-ссылкой).
- Удаление: если удаляется активная XRAY-запись и есть другая — переключение на неё (MAC-04, никогда не напрямую).
  Если удаляется последняя XRAY-запись — в подтверждении текст «Это последняя XRAY-запись…», после удаления — экран.
  Блокировка применяется после удаления из списка, чтобы не было окна «напрямую».
- Любое сохранение списка с XRAY-записью сбрасывает `xraygram_direct_allowed`.
- Выключатель «Использовать прокси» в списке при наличии XRAY-записей работает как upstream (явное действие).

## 2026-11-18 — FCM (Firebase push) выключен

Смоук `android-20261118-2` показал соединение процесса приложения с Google `172.217.x:443` — и до XRAY, и после:
это получение FCM-токена (`PushListenerController.onRequestPushToken` → Firebase Installations), трафик мимо xray.
В форке FCM всё равно не работает (ключи Firebase привязаны к официальному пакету и подписи), поэтому в Xraygram
он выключен: `initPushServices` идёт по ветке «нет Google Play Services» (сервер получает пустой токен через
MTProto), в манифесте Standalone `firebase_messaging_auto_init_enabled=false`. Уведомления — только через
Keep-Alive Service / Background Connection (FEAT-09). Сборка `android-20261118-1` (у владельца) этот трафик ещё делает.

## 2026-11-18 — FEAT-09 ред. 2: свой проект Firebase (PAR-12)

- `.secrets/google-services.json` (проект владельца, клиент `io.github.xraygram`) скрипт кладёт в
  `TMessagesProj_AppStandalone/src/afatStandalone/google-services.json`: плагин google-services берёт файл варианта
  раньше корневого (телеграмовского). Путь в `.git/info/exclude`, в патч не идёт. Скрипт проверяет, что это не
  `tmessages2` и что есть клиент `io.github.xraygram`. Есть файл → `XRAYGRAM_FCM=true` (BuildConfig), нет → `false`.
- Логика — `utils/proxy/XrayPush.java`. FCM-токен запрашивается штатным путём Telegram
  (`PushListenerController.onRequestPushToken` → `account.registerDevice` по MTProto, то есть через xray), но только
  при `XRAYGRAM_FCM` и только после снятия блокировки FEAT-03 (`initPushServices` при блокировке выходит;
  `XrayGate.connect/allowDirect` → `XrayPush.onGateOpened`). Автоинициализация FCM в манифесте выключена — токен
  берём явным вызовом. С телеграмовским json FCM не стартует никогда.
- Запасной путь (`xraygram_push_fallback`): нет своего json, нет Google Play services, нет токена за 60 с после
  снятия блокировки или ошибка FCM. Тогда Keep-Alive Service и Background Connection по умолчанию включены (значение
  пользователя уважается), служба `NotificationsService` становится foreground с уведомлением «Xraygram на связи»
  (тип `specialUse`, на API < 34 — `dataSync`; если система не даёт стартовать foreground из фона — остаётся обычной
  службой, как upstream), один раз объяснение «Уведомления в фоне» с запросом
  `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. Флаг сам не снимается (FEAT-09 п. 9).
- Android 13+: запрос разрешения на уведомления — сразу после снятия блокировки, не раньше.
- В «Уведомления и звуки» строка состояния доставки; в запасном режиме с ограничением батареи нажатие открывает запрос.
- Не трогали: Play Integrity (`LoginActivity`, `ConnectionsManager.onIntegrityCheckClassic` — только по запросу сервера
  при входе, работает через процесс Google Play) и App Indexing (`FirebaseUserActions` — только для голосовых действий
  ассистента). Отключение могло бы сломать вход; продукту на решение.

## 2026-11-18 — Версии звонка при XRAY (PAR-08)

`NativeInstance.getAllVersions()` на Android: v1 `InstanceImpl` 2.7.7/5.0.0, `InstanceV2Impl` 7/8/9/12/13,
`InstanceV2ReferenceImpl` 10/11, на arm64 ещё `InstanceV2PumpImpl` 18/19. При активной XRAY-записи
(`utils/proxy/XrayCalls`) в `requestCall`/`acceptCall`/`confirmCall` уходят только 7–13. v1 исключён: его TURN по TCP
идёт через стандартный `TurnPort`, а в libwebrtc больше нет SOCKS-адаптера, то есть `set_proxy` он проигнорирует.
Pump прокси не принимает вовсе. Если всё же выбрана неразрешённая версия или нет локального порта xray — звонок
завершается ошибкой («лучше не соединится, чем утечка»).

## 2026-11-18 — «Без XRAY» перед групповыми звонками (PAR-09)

`VoIPHelper.startCall(Chat …)` (групповой звонок, видеочат, трансляция, запланированный звонок) и
`VoIPHelper.joinConference` при активной XRAY-записи сначала показывают диалог FEAT-04 «Без XRAY»; «Продолжить» —
вход как upstream. Повторный вход тем же путём в течение 10 с (сброс звонка → повторный вызов) не спрашивает снова.
Просмотр live-историй (`Stories/LivePlayer`) не перехватываем.

## 2026-11-18 — Статус «XRAY: причина», удаление из ядра (PAR-06a), тексты (PAR-01/03/07), прочее

- `XrayTransport` помнит причину по ссылке («не удалось запустить», «нет свободного локального порта»); список
  прокси показывает `XRAY: <причина>` красным вместо «Подключение…».
- После удаления XRAY-записи `XrayTransport.pruneAsync()` перезапускает xray без её ссылки (порты остальных не
  меняются) или останавливает, если XRAY-записей не осталось.
- Превью и ошибки ссылки — `utils/proxy/XrayLinkPreview`: таблица «Понятные ошибки» FEAT-01, без «✓»; заголовок
  поля «Ссылка», подсказка FEAT-01. Тексты экрана XRAY, «напрямую» и удаления последней записи — по FEAT-02/03.
- Кнопка «Прокси» на экране ввода номера видна всегда (PAR-10).
- «Telegram» → «Xraygram» в подсказках о разрешениях, где речь о самом приложении (PAR-13): точечно по списку
  ключей в `LocaleController`; фразы про сервис Telegram не меняем.
- Иконка (FEAT-07, PAR-14) — из `branding/android` скриптом сборки поверх `ic_launcher_sa` модуля Standalone
  (адаптивная без monochrome-слоя: там был бы самолётик Telegram). В патч не выгружается.

## 2026-11-18 — Поделиться сервером (PAR-04, FEAT-15 этап 1) и подтверждение «напрямую» (PAR-05)

- В окне XRAY-записи пункт «Поделиться» стал «Поделиться сервером»: каждый раз предупреждение «Поделиться сервером?»
  (Показать / Отмена), затем своё окно `ui/XrayShareSheet`: заголовок `XRAY · <имя>`, QR сохранённой ссылки (с `#имя`)
  без текста ссылки, «Копировать ссылку» (на Android 13+ `ClipDescription.EXTRA_IS_SENSITIVE`, тост «Ссылка
  скопирована»), «Отправить…» (системное меню), «Закрыть». Ссылка не пишется в лог. Штатный QR `QRCodeBottomSheet`
  не взяли: он показывает подпись и делится картинкой.
- «Поделиться списком прокси» (выбор нескольких → поделиться) XRAY-записи пропускает; если остались только XRAY —
  ничего не отправляет.
- Выключатель «Использовать прокси» при наличии XRAY-записей → диалог FEAT-03 «Подключиться напрямую?» (красная
  кнопка), «Отмена» ничего не меняет. Тот же диалог — у выхода «напрямую» на экране XRAY (`XrayGate.confirmDirect`).
  Переключение на не-XRAY прокси — без диалога.

## 2026-11-18 — Ребрендинг минимальный

- `applicationId` **`io.github.xraygram`** (суффикс `.web` у Standalone убран) — ставится рядом с официальным
  Telegram и Telegram Web-сборкой; authorities провайдеров и разрешения в манифесте берутся из `${applicationId}`.
- Имя **Xraygram**: `AppName`/`Page1Title` в `values/strings.xml` (Standalone оставляет только базовые ресурсы,
  `localeFilters "zz"`), подмена этих ключей в `LocaleController` (облачные языковые пакеты говорят «Telegram»), на
  экране приветствия вместо картинки-логотипа «Telegram» — текст. Остальные строки с «Telegram» (например, «Please allow
  Telegram to receive calls…» на экране входа) — из облачных пакетов, не трогали.
- Иконка пока телеграмовская (для личного теста; для раздачи нужна своя — правила Telegram для форков).
- `CHECK_UPDATES = false` и `checkAppUpdate` выключен: Standalone-сборка иначе предложит поставить официальный APK.
- `SAFETYNET_KEY = ""`, `SUPPORTS_PASSKEYS/FPNV = false`, `IS_BILLING_UNAVAILABLE = true` — эти функции работают
  только с официальными app id.
- `google-services.json`: клиент `org.telegram.messenger.web` переименован в `io.github.xraygram`, чтобы плагин
  собрал APK. FCM-пуши при этом **не работают** (ключи Firebase привязаны к официальному пакету и подписи) —
  уведомления только через фоновое соединение, см. README.
- `tg://` и `t.me`-ссылки upstream-манифест регистрирует — оставили (Android спросит, чем открыть).

## 2026-11-18 — Ключи API и подпись

- `api_id`/`api_hash` — те же, что для macOS, из `.secrets/api.env`. В `BuildVars` они берутся из
  `BuildConfig.XRAYGRAM_API_ID/HASH`, которые Gradle получает из переменных окружения
  (`ORG_GRADLE_PROJECT_XRAYGRAM_API_*`). В git, в патч и в аргументы командной строки не попадают.
  Без `api.env` сборка останавливается (официальные ключи Telegram Android в форке не используем).
- Подпись — **свой keystore** `.secrets/android-release.jks` (PKCS12, RSA 4096), пароль в
  `.secrets/android-keystore.env`; создаётся скриптом один раз. Debug-ключ не берём: release-вариант (R8) быстрее на
  телефоне, а один и тот же ключ нужен, чтобы новые сборки ставились поверх. Потеря ключа = удалить приложение
  (с данными) и поставить заново.

## 2026-11-18 — Локальная сборка: только arm64-v8a

Upstream собирает 4 ABI (`afat`). Для теста хватает `arm64-v8a`: это все современные телефоны и эмулятор на M-маке.
Нативная часть (tgnet, webrtc, ffmpeg, …) и libXray собираются только под выбранные ABI — вдвое-вчетверо быстрее и
APK меньше. Другие ABI: `XRAYGRAM_ABIS=arm64-v8a,armeabi-v7a`.

## 2026-11-19 — Ребрендинг без Telegram (FEAT-19, PAR-17…21) и F07-04

Инвентаризация — `rebrand-inventory.md`. Сделано в сборке после `android-20261119-1`:

- **Имя (§0.1 инвентаризации).** `AppName` = Xraygram во всех `values-*`. До этого на телефоне с русским языком под
  иконкой, в «Недавних» и в «Аккаунтах» было «Telegram».
- **Заставка (PAR-17).** `Theme.TMessages.Start` (values, -v21, -v31, -night): фон `#0B1220`, иконка из
  `branding/launch/android-splash-xxxhdpi.png` (176 dp, скругление 40, свечение, холст 240 dp). Своей заставки у
  upstream нет: окно запуска — `drawable/xraygram_launch_background.xml`. Системная заставка Android 12+ — та же
  картинка с отступом 13 %, чтобы скруглённая иконка целиком влезла в круглую маску системы (круг — допустимое
  отличие).
- **Вступление (PAR-18).** Новый `XrayIntroActivity` вместо `IntroActivity`, который больше не открывается (файл и
  GL-рендер upstream остались). Один экран в цветах «Рентген», луч кодом 1,2 с; без луча при «Удалить анимацию»
  (масштаб анимации 0). Язык: «Русский · English», `applyLanguage` встроенного/облачного пакета. Порядок: вступление →
  «Начать» → экран XRAY (`XrayGate.present`) → номер. `XrayGate.showIfNeeded` не перекрывает вступление.
- **Иконки (PAR-19).**
  - Шторка: `ic_stat_xraygram` из `branding/glyph/android` (копируется при сборке). Цвет уведомлений и звонков —
    акцент `#3EF2C8`. Monochrome-слой адаптивной иконки (тематические иконки Android 13+) —
    `branding/glyph/android/ic_launcher_monochrome.png`, `mipmap-anydpi-v33/ic_launcher_sa.xml`.
  - Заголовок списка чатов и шапка историй: надпись «Xraygram» текстом (`XraygramWordmarkDrawable`) вместо картинки
    «Telegram».
  - Иконка в системных контактах, звонке, окне «Поделиться», окне условий: `@mipmap/xraygram_launcher`, копируется из
    `branding/android` при сборке.
  - QR (решение продукта: всё, что уходит другим, — без знака Telegram и без нашего): `TelegramQRCodeWriter.PLAIN` —
    без дырки и логотипа в центре; `QRCodeBottomSheet` (группы, папки, звонки, прокси) и `QrShareView`/`QrCodeLayer`
    (профиль) — без логотипа.
  - Водяной знак (самолётик) в видео-кружочках убран: `InstantCameraVideoEncoderOverlayHelper`,
    `RoundVideoOverlayRenderer` (F19-18).
  - Выбор альтернативных иконок (все в стиле Telegram) скрыт; если такая уже выбрана — при запуске возвращается
    основная (`LauncherIconController.tryFixLauncherIconIfNeeded`).
  - В значках пунктов настроек логотипа Telegram нет (лампочка, облачко, вопрос, щит) — менять нечего (F19-13 n/a).
- **«О приложении» (PAR-21).** Внизу настроек строка «Xraygram для Android <версия> · неофициальный клиент Telegram»;
  по нажатию — диалог: иконка, «Xraygram <версия>», «Неофициальный клиент…», «На основе Telegram Android <версия>.
  Исходный код: github.com/vizacv/xraygram» (ссылка открывается).
  Долгое нажатие — меню отладки upstream. Версия Xraygram = ID сборки без префикса (`20261119-2`):
  `BuildConfig.XRAYGRAM_BUILD`, его ставит `build-local.sh`, тот же ID получает файл APK.
- **Строки (PAR-20).** `XrayBranding.apply` из `LocaleController.getStringV2`: работает для встроенных ресурсов,
  облачных пакетов и фолбэка. Подмена только в ключах списка. Внутри них защищённые словосочетания не трогаются:
  «Telegram's», «Telegram Premium/Stars/… servers/cloud/account/users», «серверы/облако/аккаунт/пользователи Telegram».
  `TelegramVersion` → «Xraygram <версия> · Telegram Android <версия>».
  Не подменяются (сервис, правило п. 2): вход и коды (`SentAppCode*`, `CallText`, `OtherLoginCode`), «на Telegram»,
  приглашения (`InviteText2`, `InviteTextNum_*`, `ShareTelegram2`), Premium/звёзды/бусты, Passport,
  FAQ/Features/Ask a Question, `SessionsListInfo`, хранение в облаке (`StorageCleared2`, `StorageUsageInfo`,
  `DownloadedFilesMessage`), модераторы, `NotificationsServiceConnectionInfo` (соединение с сервисом),
  `RoundVideoCompositionInfo` (ждёт решения про водяной знак).
  Ключи подмены (95), для F19-09…12:
  `AppNameBeta NoChats AppUpdate AppUpdateBeta UpdateTelegram UpdateAppAlert UnsupportedMedia2 UnsupportedBlockMessage
  UnsupportedMessageMessage StoryUnsupported Gift2ExportTONUpdateRequiredText NotificationsPermissionAlertSubtitle
  ContactsPermissionAlert QRCodePermissionNoCameraWithHint AllowReadCall AllowReadCallAndLog AllowReadCallLog
  AllowFillNumber PermissionStorageWithHint PermissionNoAudioWithHint PermissionNoBluetoothWithHint
  PermissionNoAudioVideoWithHint PermissionNoCameraWithHint PermissionNoCameraMicVideo PermissionNoLocation
  PermissionNoLocationStory PermissionNoLocationFriends PermissionNoLocationNavigation PermissionNoContactsSharing
  PermissionNoContactsSaving PermissionNoStorageAvatar PermissionNoAudioStorageStory PermissionDrawAboveOtherApps
  PermissionDrawAboveOtherAppsGroupCall PermissionXiaomiLockscreen PermissionFSILockscreen PermissionBackgroundLocation
  VoipNeedMicPermissionWithHint VoipNeedMicCameraPermissionWithHint VoipNeedCameraPermission
  AgeVerificationNeedCameraPermission VoipInCallBranding VoipInVideoCallBranding VoipInConferenceCallBranding
  VoipOutgoingCall CallViaTelegram VideoCallViaTelegram VoiceCallViaTelegram VoipInCallBrandingWithName
  VoipInVideoCallBrandingWithName VoipRateCallAlert VoipErrorUnknown AllowBackgroundActivityInfo
  AllowBackgroundActivityInfoOneUIBelowS AllowBackgroundActivityInfoOneUIAboveS IncomingCallsSystemSettingDescription
  NotificationHiddenName NotificationHiddenChatName SecretChatName ProfilePopupNotificationInfo LiveLocationPausedText
  ClearTelegramCache TelegramCacheSize LocalDatabaseSize LocalDatabaseInfo StorageUsageTelegram StorageUsageTelegramLess
  LowDiskSpaceMessage ClearingCacheDescription SdCardAlert SdCardErrorDescription OptimizingTelegram
  MigrateOldFolderDescription ImportImportingInfo ChangePasscodeInfo EnterYourPasscodeInfo EnterYourTelegramPasscode
  CreatePasscodeInfoPIN CreatePasscodeInfoPassword UnlockToUse AppLocked ScreenCaptureAlert
  WalletAuthorizeTransactionPasscode OpenInTelegramBrowser BrowserSettingsCustomTabs BrowserSettingsNoCustomTabsInfo
  BrowserSettingsEnableInfo BrowserSettingsCookiesInfo BrowserExternalRestricted CreateNewThemeAlert Page2Message
  Page3Message Page4Message Page5Message Page6Message` + `TelegramVersion` (свой текст), `AppName`/`Page1Title`
  (всегда «Xraygram»).
- **F07-04.** `crunchPngs false` у `standalone`: PNG иконок в APK байт-в-байт как в `branding/`.
- **BUG-20.** Свой тип системного аккаунта `io.github.xraygram.account` (`auth.xml`, `sync_contacts.xml`,
  `ContactsController.XRAYGRAM_ACCOUNT_TYPE`). Mime-типы данных контакта (`vnd.org.telegram.messenger.android.*`) не
  трогаем: от них зависит сопоставление контактов и открытие чата из системной книги. При установленном официальном
  Telegram «Написать» из книги может предложить выбор приложения.
- **Не трогаем (решения продукта):** папка `Pictures/Telegram` и сохранение в галерею; пограничные строки (см. выше);
  утёнок на пустых экранах; метка «Telegram» у контакта в системной книге.
