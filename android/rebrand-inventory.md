# Android: инвентаризация ребрендинга (FEAT-19) и темы «Рентген» (FEAT-20)

Составлено 2026-11-19 по исходникам `upstream/tg-android` (DrKLO 13.2.2 `21f7d109` + наш патч `android/patches/0001-xraygram.patch`).
Сборок и правок кода не было. Пути ниже даны от `TMessagesProj/src/main/`, если не сказано иное.
Основание: `docs/decisions.md` (2026-11-19), `branding/theme-rentgen.md`, `branding/mockups/rentgen.dc.html`.

Оценка трудозатрат: **S** — до 1 ч, **M** — полдня, **L** — день и больше. Проверка на эмуляторе и сборка не включены
(Java-пересборка ≈ 4–6 мин, плюс смоук).

## 0. Что важно знать сразу

1. **Баг, виден уже сейчас: на телефоне с русским (и ещё 8 языками) системным языком подпись под иконкой — «Telegram».**
   Мы поменяли `AppName` только в `res/values/strings.xml`. В `res/values-{ru,uk,de,es,it,nl,pt-rBR,ar,ko}/strings.xml`
   осталось `Telegram` / `تيليجرام` / `텔레그램`. Отсюда же подпись в «Недавних», в «Настройки → Приложения», имя
   аккаунта в «Настройки → Аккаунты». Внутри приложения этого не видно: там `getStringV2` подменяет `AppName`. На
   эмуляторе (en-US) мы этого не замечали. Исправление — **S**: `AppName` = Xraygram во всех 9 файлах.
2. **Заголовок списка чатов — картинка со словом «Telegram».** `ui/DialogsActivity.java:3439` ставит векторную
   надпись `drawable/telegram_logo_2.xml` как `ImageSpan` поверх `AppName`. Поэтому текст «Xraygram» не виден, а виден
   логотип «Telegram». Та же надпись есть в шапке историй: `ui/Stories/DialogStoriesCell.java:339`. Без входа в аккаунт
   это не проверить, поэтому в смоуке и не всплыло. **S**.
3. **Иконка в шторке уведомлений — самолётик Telegram** (`drawable-*/notification.webp`). Нужна монохромная
   (белая на прозрачном) версия знака Xraygram. В `branding/` такой нет: **нужен ассет от владельца/брендинга**.
   Тот же силуэт пригодится как monochrome-слой адаптивной иконки (тематические иконки Android 13+).
4. **Функциональное, не брендинг.** Тип системного аккаунта `org.telegram.messenger` (`res/xml/auth.xml`,
   `sync_contacts.xml`, `ContactsController.java:394…534`) совпадает с официальным Telegram. Если на телефоне стоят
   оба приложения, Android оставляет аутентификатор того, кто установлен первым, и синхронизация контактов у второго
   ломается. Предлагаю отдельный BUG: тип `io.github.xraygram` плюс свои mime-типы в `contacts.xml`. **S–M**.

## 1. Логотипы и картинки

| Где видит пользователь | Файл / класс | Чем заменить | Оценка |
|---|---|---|---|
| Заставка при запуске, Android 12+ | `res/values-v31/styles.xml`, `res/values-night/styles.xml` (`Theme.TMessages.Start`): `windowSplashScreenAnimatedIcon=@drawable/tg_splash_320` (анимированный вектор: голубой круг с самолётиком), фон белый / `#1f2732` | Иконка-обезьянка (слой foreground из `branding/android`, вписанный в круг 160 dp из 240 dp), `windowSplashScreenBackground=#0B1220` в обоих файлах. Свечение `accent` 25 % проще запечь в PNG. Анимация не нужна | S |
| Заставка до Android 12 и белая вспышка | `res/values/styles.xml`, `res/values-v21/styles.xml`: `windowBackground` белый | `windowBackground` → layer-list (`#0B1220` + иконка по центру), `colorPrimary*` → `surface` | S |
| Вступление (первый экран) | `ui/IntroActivity.java`: карусель из 6 страниц, OpenGL-рендер `Intro.*` (`jni/intro`), текстуры `drawable-*/intro_*.webp` (самолётик `intro_tg_plane`, шар Telegram). Слоган «Telegram» уже убран (FEAT-06), но шар Telegram и страницы 2–6 («**Telegram** доставляет…») остались | По спеке — один экран без GL: иконка, сверху вниз проходит луч (свой View: `LinearGradient` + `ValueAnimator`, 1,2 с, один раз), `XRAYGRAM` моноширинным 28, подпись, «Начать», «Русский · English». Логику кнопок и выбора языка взять из текущего IntroActivity. Строки `Page2..6*` больше не нужны | M (4–6 ч) |
| Заголовок списка чатов | `ui/DialogsActivity.java:3439-3445`, `drawable/telegram_logo_2.xml`, цвет `key_telegram_color_dialogsLogo` | Убрать `ImageSpan` и оставить текст «Xraygram» (как в IntroActivity). Либо свой векторный wordmark. Под заголовком — значок статуса XRAY (§5) | S |
| Шапка историй (свёрнутая) | `ui/Stories/DialogStoriesCell.java:336-343` (`telegramLogoView`, тот же `telegram_logo_2`) | TextView «Xraygram» или тот же wordmark | S |
| Шторка уведомлений: маленькая иконка | `R.drawable.notification`: `NotificationsController.java:407, 4657, 5660`, `NotificationsService.java:45` (keep-alive), `FilesMigrationService.java:65,184` | Заменить `drawable-{m,h,xh,xxh,xxxh}dpi/notification.webp` монохромным силуэтом (**нужен ассет**, см. §0.3). Код не трогать | S (+ ассет) |
| Большая иконка: контакты, звонок в системе, OAuth | `drawable-*/ic_launcher_dr.webp`: `res/xml/contacts.xml` (строки «Написать / Позвонить через…» в системной книге), `VoIPService.java:5885` (PhoneAccount), `NotificationsController.java:5893` | Наша иконка в 5 плотностях (из `branding/android/mipmap-*`) | S |
| Иконка в системном окне «Поделиться» | `AndroidManifest.xml:272, 334, 345, 355`: `intent-filter android:icon="@mipmap/ic_launcher"` / `ic_launcher_round` (это иконки модуля `TMessagesProj`, а не наши `_sa`) | В `brand_icons` (`android/scripts/build-local.sh`) ещё перезаписывать `TMessagesProj/src/main/res/mipmap-*/ic_launcher{,_round}.png` и `mipmap-anydpi-v26/ic_launcher{,_round}.xml` | S |
| Альтернативные иконки (Premium: Vintage, Aqua, Premium, Turbo, Nox) | `AndroidManifest.xml:114-208` (activity-alias `*Icon`), `mipmap-*/icon_{2..6}_*`, выбор в `ui/ThemeActivity.java` (`AppIconsSelectorCell`), превью в `Premium/PremiumAppIconsPreviewView.java` | Скрыть строку выбора иконки в ThemeActivity и превью в Premium; алиасы оставить выключенными (или удалить). Выбрав такую иконку, пользователь получит иконку Telegram | S |
| QR своего профиля / канала | `ui/QrShare/QrShareView.java:454, 2077` — самолётик `raw/plane_logo_plain.json` в центре QR | Наша иконка (статичный bitmap) или QR без логотипа | M |
| QR ссылок (группы, папки, звонки, приглашения) | `TelegramQRCodeWriter.java:197` (`raw/qr_logo.svg`), центр-анимация `raw/qr_code_logo.json`: `LinkActionView:403`, `FilterCreateActivity:2113`, `FilterChatlistActivity:1327`, `CallLogActivity:1682`, `QrShare/QrCodeLayer:96` | Свой `qr_logo.svg` (силуэт) и `setCenterAnimation` → статичная иконка. Генератор из `XrayShareSheet` (QR без логотипа) уже есть | M |
| Окно обновления условий использования | `ui/Components/TermsOfServiceView.java:62` (`logo_middle`) | Наша иконка | S |
| Экран «Обновите приложение» | `ui/Components/BlockingUpdateView.java:69` (`qr_code_logo`) | У нас не показывается: `checkAppUpdate` выключен. Можно не трогать | — |
| Вход по QR (с компьютера) | `ui/ActionIntroActivity.java:597` (`raw/qr_login.json`) | Проверить на эмуляторе, есть ли в анимации знак Telegram. Если есть — заменить картинкой | S (проверка) |
| Водяной знак в кружочках (видео-сообщениях) | `InstantCameraVideoEncoderOverlayHelper.java:74`, `utils/recorder/round/RoundVideoOverlayRenderer.java:989`: самолётик `plane_logo_plain` вшивается в видео | **Вопрос продукту:** знак видят получатели. Заменить на наш, убрать или оставить | S после решения |
| Утята-заглушки на пустых экранах | `raw/utyan_*.json` (пустой список чатов, кэш, звонки, пароль…) | Это маскот, а не логотип Telegram, и в решении его нет. Предлагаю оставить | — |
| Иконки пунктов настроек | `ui/SettingsActivity.java:840-843` и др. (`settings_*`, цвета `IconBackgroundColors`) | Это общие значки, не логотип. Перекрашивать под «Рентген» только по отдельному решению | — |

## 2. Имя и иконки в системных местах

| Место | Откуда | Что делать | Оценка |
|---|---|---|---|
| Подпись под иконкой, «Недавние», «Приложения» | `config/release/AndroidManifest_standalone.xml:39` → `@string/AppName` | См. §0.1: `AppName` во всех `values-*` | S |
| Иконка лаунчера, круглая, адаптивная | `TMessagesProj_AppStandalone/src/main/res` (`ic_launcher_sa`, `xraygram_icon_*`) — уже наши | Добавить monochrome-слой, когда будет силуэт (§0.3) | S |
| «Настройки → Аккаунты» | `res/xml/auth.xml` (`label=@string/AppName`) | Имя исправится с §0.1, тип аккаунта — §0.4 | — |
| Системные контакты («Сообщение / Звонок …») | `res/xml/contacts.xml` (`ic_launcher_dr`), подписи из `ContactsController` | Иконка — §1, тексты — по списку строк (§3) | S |
| Каналы уведомлений | `NotificationsController.java:295, 391, 4137`, `VoIPService.java:5422` и др.: имена из строк, без «Telegram» | Ничего. Канал keep-alive уже называется «Xraygram» | — |
| Ярлыки (long-press по иконке), виджеты | `res/xml/shortcuts.xml`, `*_widget_info.xml` (`EditWidget*Info`, превью `chats_widget_preview`, `contacts_widget_preview`) | Строки без «Telegram»; превью-картинки проверить глазами (там может быть интерфейс Telegram) | S (проверка) |
| Экран звонка, системный звонок | строки `VoipInCallBranding*` («Звонок Telegram»), `CallViaTelegram`, `VoipOutgoingCall` | Через подмену строк (§3) | — |
| Строка версии внизу настроек (у Android-клиента «О приложении» — это она) | `ui/SettingsActivity.java:1059` и `AndroidUtilities.java:6733` → `TelegramVersion` («Telegram for Android %1$s») | Свой текст: «Xraygram для Android %1$s · неофициальный клиент Telegram», так выполняется требование правил API. Отдельного экрана «О приложении» нет; если продукт хочет экран с иконкой, это ещё M | S |

## 3. Строки

### 3.1 Откуда берутся

- **Встроенные ресурсы:** `res/values/strings.xml` — английский, 530 строк с «Telegram»; `res/values-{ru,uk,…}` —
  только около 265 строк экрана входа на каждый язык (в `values-ru` 20 строк с «Telegram», плюс `AppName`, `Page1..6`).
- **Облачные языковые пакеты.** Русский и остальные языки приходят с сервера (`langpack.getLangPack` /
  `langpack.getDifference`), путь — `LocaleController.java:3545-3590` → `saveRemoteLocaleStrings` (3099…), файл
  пакета на диске → `localizationExternal`.
- **Одна точка для всех строк:** `LocaleController.getStringV2(key, res, fallback)` (`LocaleController.java:4803`).
  Через неё идут `getString`, `formatString` (1655, 1687) и `formatPlural*` (они вызывают `formatString`). У нас там
  уже есть подмена `AppName`/`Page1*` и `xraygramAppName(stringRes, value)`: замена Telegram→Xraygram для
  нескольких строк разрешений.

### 3.2 Где перехватывать (рекомендация)

**Перехватывать в `getStringV2` по списку ключей, а не при сохранении пакета.** Причины:
- одинаково работает для встроенных ресурсов, облачного пакета и фолбэка;
- не трогает файлы пакетов на диске, поэтому обновления langpack не ломаются;
- ключ известен, значит подменяем только «приложенческие» строки, а сервисные («Telegram Premium», Passport, звёзды)
  не трогаем.

Как сделать: вынести `xraygramAppName` в класс `XrayBranding`:
- `HashSet<String>` ключей, где «Telegram» означает приложение;
- замена `Telegram`/`Телеграм`/`Telegram'а` → `Xraygram`;
- для 3–4 ключей — свой текст целиком (`TelegramVersion`, `Page1Message`).

Перехватывать по ключу (имени), а не по `res id`: облачные пакеты знают только имена. Ветку `fallback` (сейчас без
подмены) тоже пропустить через `XrayBranding`. Стоимость — одна проверка `HashSet` на вызов, это незаметно.

Не перехватываются (и не нужно): тексты, которые присылает сервер, — служебные сообщения, текст условий, описания
ботов, `help.getPremiumPromo`. Это содержимое сервиса.

### 3.3 Что подменять

Из 530 строк примерно 150 не про сервис. Полный список кандидатов будет в коде `XrayBranding` с комментариями. Группы:

| Группа | Ключи (примеры) | Действие |
|---|---|---|
| Системные разрешения | `PermissionNo*WithHint`, `PermissionStorageWithHint`, `PermissionDrawAboveOtherApps*`, `PermissionXiaomiLockscreen`, `PermissionFSILockscreen`, `PermissionBackgroundLocation`, `AllowReadCall*`, `AllowFillNumber`, `NotificationsPermissionAlertSubtitle`, `ContactsPermissionAlert`, `QRCodePermissionNoCameraWithHint`, `VoipNeed*Permission*` | → Xraygram (часть уже сделана) |
| Звонки | `VoipInCallBranding*`, `VoipInVideoCallBranding*`, `VoipInConferenceCallBranding`, `VoipOutgoingCall`, `CallViaTelegram`, `VideoCallViaTelegram`, `VoiceCallViaTelegram`, `VoipRingtoneInfo`, `VoipRateCallAlert`, `CallReportSent`, `VoipQuickRepliesExplain` | → Xraygram |
| Память и кэш | `ClearTelegramCache`, `TelegramCacheSize`, `StorageUsageTelegram*`, `LocalDatabaseInfo`, `LowDiskSpaceMessage`, `SdCard*`, `OptimizingTelegram*`, `MigrateOldFolderDescription`, `DownloadedFilesMessage` | → Xraygram |
| Код-пароль, блокировка, работа в фоне | `EnterYourTelegramPasscode`, `CreatePasscodeInfo*`, `ChangePasscodeInfo`, `AppLocked`, `ScreenCaptureAlert`, `AllowBackgroundActivityInfo*`, `NotificationsServiceConnectionInfo` | → Xraygram |
| Обновления | `UpdateTelegram`, `UpdateAppAlert`, `AppUpdate*` | Не показываются (обновления выключены). Подменить для порядка |
| Вступление | `Page2..6Title/Message` | Уходят вместе со старой каруселью (§1) |
| Встроенный браузер | `OpenInTelegramBrowser*`, `BrowserSettings*` | → Xraygram |
| Версия, «О приложении» | `TelegramVersion` | свой текст (§2) |
| **Оставить** (сервис, решение 2026-11-19) | Premium, звёзды, подарки, бусты, розыгрыши, Passport, Business, реклама и монетизация, «служебные уведомления» с кодами, вход (`SentAppCode*`: «код в приложении Telegram на другом устройстве» — там правда Telegram), `NumberNotOnTelegram`, `InviteToTelegram`, `ContactJoined` (речь о сети Telegram), `TelegramFAQ` / `TelegramFeatures` / `AskAQuestion` (справка и поддержка Telegram) | без изменений |
| На решение продукта | `InviteText2` / `ShareTelegram2` (приглашение со ссылкой на telegram.org), `ProfileUnofficialSecurityRisk`, `SubscribeToPremiumOfficialAppNeededDescription` | продукт |

Оценка: **M** (4–6 ч). Сюда входит ручная разметка ~150 ключей по EN и RU-пакету и проверка в эмуляторе на RU и EN.
Встроенные `values-ru` и прочие языки чинятся той же подменой (кроме `AppName`, который нужен системе, — §0.1).

## 4. Тема «Рентген» по умолчанию

Как устроено (`ui/ActionBar/Theme.java`, 10 400 строк):
- встроенные темы — `ThemeInfo` с `assetName` в `assets/*.attheme`: `Blue` (`bluebubbles.attheme`, = `defaultTheme`,
  `currentDayTheme`), `Dark Blue` (`darkblue.attheme`, = `currentNightTheme`), `Arctic Blue`, `Day`, `Night`
  (строки 3980–4100);
- при старте тема берётся из настроек `theme` / `nighttheme` и `themeConfig.lastDayTheme/lastDarkTheme` (4145–4185);
- по умолчанию на Android 10+ `selectedAutoNightType = AUTO_NIGHT_TYPE_SYSTEM` (4340): светлая система → `Blue`,
  тёмная → `Dark Blue`.

План:
1. **`assets/rentgen.attheme`** — копия `darkblue.attheme` (529 ключей), перекрашенная по токенам `theme-rentgen.md`:
   - `bg` → `windowBackgroundWhite`, `chats_*Background`, `actionBarDefault`;
   - `surface` → шапки, `chat_messagePanelBackground`, поля;
   - `surface-2` → `chat_inBubble`;
   - `bubble-out` → `chat_outBubble*`;
   - `accent` → `chats_unreadCounter`, `windowBackgroundWhiteBlue*`, `chats_actionBackground` (FAB), `featuredStickers_addButton`, ссылки, «в сети»;
   - `text` / `text-2` / `text-3`;
   - `warn` / `error`;
   - аватары → `avatar_background*`;
   - фон чата — сплошной `#0B1220` (`chat_wallpaper`) или тёмный узор.

   Скрипт-генератор положить в `android/scripts/`, чтобы тему можно было пересобрать после правки токенов. Тот же
   `.attheme` пригоден для iOS/macOS только частично: форматы тем там другие.
2. **Регистрация в `Theme.java`:**
   - новый `ThemeInfo` `name="Rentgen"` (`sortIndex 0`, preview-цвета из токенов, без набора акцентов или с одним);
   - в `isDark()` (1679) добавить `"Rentgen"` к тёмным;
   - `themesDict.put("Rentgen", …)`.
3. **По умолчанию:** если в настройках нет `theme`, `nighttheme`, `lastDayTheme` (чистая установка), то
   `applyingTheme = currentDayTheme = currentNightTheme = Rentgen`. Тогда авто-ночной режим «как в системе» не уводит
   в синюю тему на светлой системе. Если пользователь выберет другую тему, всё работает как в upstream. Места, где
   upstream сбрасывает тему на `defaultTheme` / `"Dark Blue"` (6775, 7159-7161), тоже направить на Rentgen.
   Стандартные темы остаются в «Настройки → Оформление».
4. **Цвета до загрузки темы:** `Theme.TMessages.Start` (§1, заставка) и цвета системных панелей — `bg`/`surface`,
   чтобы при запуске не было белой вспышки.
5. **Шрифт:** моноширинный Roboto Mono уже есть в APK (`assets/fonts/rmono.ttf`,
   `AndroidUtilities.TYPEFACE_ROBOTO_MONO`). JetBrains Mono — по желанию (+~250 КБ). Предлагаю Roboto Mono.

Оценка: генератор и `.attheme` — **M**, регистрация и умолчания — **S–M**, подгонка по скриншотам эмулятора — **M**.
Всего ~1–1,5 дня.

## 5. Значок статуса XRAY над списком чатов

Где: `ui/DialogsActivity.java`, контейнер `topPanelLayout` (`AnimatedLinearLayout` под шапкой; в него уже кладутся
`fragmentContextView` — плашка звонка/музыки — и `dialogsHintCell`, строки 4750–4770). Пилюля — новая view
`XrayStatusPill` первым ребёнком `topPanelLayout`, видимость через `setViewVisible`. Так она по центру под заголовком,
сдвигает список и не ломает свёртку шапки историй.

Данные:
- состояние — `currentConnectionState` (`NotificationCenter.didUpdateConnectionState`, 10613) плюс
  `proxySettingsChanged` (10520) и `proxyCheckDone`;
- сервер — `XrayTransport.parse(SharedConfig.currentProxy.getLink()).displayName()`;
- пинг — `ConnectionsManager.checkProxy` для текущей записи, раз в 60 с, пока экран виден (по образцу
  `ProxyListActivity`);
- статус ошибки ядра — `XrayTransport.statusError(link)` (PAR-06a).

Состояния — по таблице `theme-rentgen.md`: `accent` / `warn` / `error`, «Напрямую, без XRAY». Тап →
`ProxyListActivity`. Моноширинный 12, фон `accent` 10 %, обводка 35 %.

Существующий щит прокси в шапке (`proxyDrawable`, `updateProxyButton` 10158) можно оставить или спрятать при видимой
пилюле. **Вопрос продукту:** что показывать, когда активен обычный SOCKS5/MTProto, а не XRAY (в спеке состояния нет).

Оценка: **M** (4–6 ч).

## 6. F07-04: иконки в APK пережимаются

AGP в release по умолчанию пережимает PNG (`crunchPngs`), поэтому хэши `ic_launcher_sa.png` в APK отличаются от
`branding/android`. Исправление: в `TMessagesProj_AppStandalone/build.gradle` → `buildTypes.standalone { crunchPngs false }`
(через наш патч). Наши иконки лежат в модуле приложения, так что этого достаточно; иконки, которые копируем в
`TMessagesProj` (§1, «Поделиться»), проверить по хэшу после сборки. APK станет немного больше (Telegram-ресурсы в основном `.webp`, их это не касается). Делать вместе с первой сборкой
ребрендинга. **S**.

## 7. Порядок и общая оценка

| # | Блок | Оценка | Зависит от |
|---|---|---|---|
| 1 | §0.1 `AppName` во всех языках, §6 crunchPngs, иконки `ic_launcher`/`ic_launcher_dr`/`logo_middle`, wordmark в заголовке и историях, выбор альтернативных иконок | S×6 ≈ 3 ч | — |
| 2 | Подмена строк `XrayBranding` | M | — |
| 3 | Заставка + `Theme.TMessages.Start` | S–M | — |
| 4 | Тема «Рентген» по умолчанию | L (1–1,5 дня) | токены (есть) |
| 5 | Значок статуса XRAY | M | п. 4 (цвета) |
| 6 | Новое вступление с лучом | M | п. 4 |
| 7 | QR-логотипы | M | силуэт |
| 8 | Иконка в шторке, monochrome-слой | S | **силуэт от владельца** |
| 9 | Тип системного аккаунта (BUG) | S–M | решение оркестратора |

Итого ≈ 4–5 рабочих дней на Android, без QA. Предлагаю две сборки:
- (а) п. 1–3 + 8 — быстро убирает самое заметное;
- (б) тема, пилюля, вступление, QR.

### Силуэт: какие файлы нужны Android

Лучше один **SVG** (одноцветный, без градиентов, без текста, линии толщиной от 1,5 px при размере 24): из него я сделаю
VectorDrawable, растровые размеры тогда не нужны. Если PNG, то:

| Назначение | Холст | Знак внутри | Файлы |
|---|---|---|---|
| Строка состояния и шторка (`notification`) | 24 dp | 20 dp по центру (поля 2 dp) | белый на прозрачном: mdpi 24, hdpi 36, xhdpi 48, xxhdpi 72, xxxhdpi 96 px |
| Monochrome-слой адаптивной иконки (тематические иконки Android 13+) | 108 dp | 66 dp (безопасная зона) | белый на прозрачном, 432×432 px (xxxhdpi) |
| Центр QR | любой | — | тот же SVG |

Цвет не важен: Android берёт только альфа-канал и красит сам (акцент `#3EF2C8` задаём в коде). Пока силуэта нет,
в сборке стоит заглушка: монохромный круг с буквой X.

### Что нужно от владельца / продукта

1. **Монохромный силуэт знака** (SVG или PNG 96×96, белый на прозрачном) для шторки, monochrome-иконки и центра QR.
2. **Водяной знак в кружочках:** заменить на наш знак, убрать или оставить.
3. **Пилюля при обычном SOCKS5/MTProto:** что показывать.
4. **Пограничные строки** из §3.3 (приглашение друзей со ссылкой на telegram.org и др.).
5. **Отдельный экран «О приложении»** с иконкой нужен или достаточно строки версии внизу настроек.
6. **Тип аккаунта `org.telegram.messenger`** (§0.4): завести BUG.
