# iOS — инвентаризация ребрендинга (FEAT-19) и темы «Рентген» (FEAT-20)

2026-11-19. Только чтение: дерево `upstream/telegram-ios` (ветка `xraygram`, база 24638bc6 + наш патч).
Трудозатраты: **S** — замена ассета/строки (до пары часов), **M** — несколько файлов или новый ассет + код
(полдня–день), **L** — сквозное (дни). Пути — от корня Telegram-iOS.

Уже сделано раньше: `CFBundleDisplayName`/`CFBundleName` = Xraygram, иконка приложения, схема `xraygram`,
`Tour.Title1`/`Tour.Text1`.

## 1. Заставка при запуске (PAR-17, F19-01)

| Где | Что сейчас | Чем заменить | Труд |
|---|---|---|---|
| `Telegram/Telegram-iOS/Base.lproj/LaunchScreen.xib` (BUILD `:LaunchScreen`, `UILaunchStoryboardName`) | пустой view `systemBackgroundColor` (белый/чёрный), логотипа нет | фон `#0B1220`, по центру `UIImageView` 176×176 pt с картинкой `XraygramLaunchIcon` из asset catalog. Скругление 40 и свечение — уже в PNG (в xib слой не настроить без runtime-атрибутов) | S |

Ассет: **`LaunchIcon` 176 pt @2x (352 px) и @3x (528 px)**, скругление 40 pt, свечение `accent` 25 %, прозрачный фон
вокруг (или сразу на `#0B1220`). Тот же ассет — для вступления. Пока нет — делаю из `xraygram-icon-1024.png`
простым ресайзом (заглушка без свечения).

## 2. Вступление (PAR-18, F19-02…05)

| Где | Что сейчас | Чем заменить | Труд |
|---|---|---|---|
| `submodules/RMIntro` (ObjC + OpenGL ES): `RMIntroViewController.m:683` текстуры `telegram_sphere.png`/`telegram_plane1.png` (`Telegram/Telegram-iOS/Resources/intro/`), анимация `core/animations.c`; 6 слайдов `Tour.*` из en.lproj напрямую (мимо `PresentationStrings`, поэтому всегда английский) | синий шар + самолётик, слайды Fast/Free/Secure… | **не трогать RMIntro**, а заменить контроллер: в `AuthorizationUI/Sources/AuthorizationSequenceSplashController.swift` вместо `RMIntroViewController` — свой UIKit-экран `XraygramIntroView`: иконка + луч (`CAGradientLayer`, движение 1,2 с, один раз; при `UIAccessibility.isReduceMotionEnabled` — без луча), `XRAYGRAM` моноширинным 28 с разрядкой 6, подпись, «Начать» (`accent`), «Русский · English» | M |
| язык во вступлении | upstream: кнопка «Continue in <язык>» по `suggestedLocalization` (нужна сеть) | «Русский · English»: тексты экрана — из `XrayStrings` сразу; по «Начать» — `activateLocalization("ru"/"en")` как upstream (пакет придёт через XRAY после подключения) | S |
| порядок экранов | экран XRAY показывается поверх всего с запуска (`AppDelegate.updateXraygramGate`) | заставка → вступление → «Начать» → экран XRAY → номер: экран XRAY ждёт, пока пользователь не нажмёт «Начать» (флаг «вступление пройдено» в `UserDefaults`; для вошедшего профиля — сразу). Сеть заблокирована с запуска как и раньше | S–M |
| `Tour.Text2…6` | «**Telegram** delivers…» | не показываются после замены — не трогаем | — |
| Lottie на экранах входа (`IntroPhone`, `IntroMessage`, `IntroLetter`, `IntroMail`, `IntroPassword` — `Telegram/Telegram-iOS/Resources/*.tgs`) | телефон, пузырь, письмо — слоёв с логотипом нет | оставить (проверить `IntroMessage` глазами) | — |

## 3. Иконки (PAR-19, F19-08, 13, 20)

| Где | Что сейчас | Чем заменить | Труд |
|---|---|---|---|
| CallKit: `submodules/TelegramCallsUI/Sources/CallKitIntegration.swift:174` → `Images.xcassets/Call/CallKitLogo.imageset` (@2x, @3x) | шаблон-самолётик | `branding/glyph/ios/CallKitIcon{@2x,@3x}.png` (40 pt, альфа) — уже готово. Имя в CallKit берётся из `CFBundleDisplayName` (= Xraygram) | S |
| Ярлык на домашнем экране «Edit App Icon»: `Telegram/Telegram-iOS/Icons.xcassets/Shortcuts/AppIcon.imageset/tlogo_24.pdf` (`ApplicationShortcutItem.swift:37`) | логотип Telegram | ярлык убрать вместе с альтернативными иконками | S |
| Контекстное меню телефона «Invite to Telegram»: `Images.xcassets/Chat/Context Menu/Telegram` (`ChatControllerOpenPhoneContextMenu.swift:118`) | логотип Telegram 24 pt | обычный значок «пригласить» (`Chat/Context Menu/AddUser` или SF Symbol); текст не трогаем (сеть Telegram) | S |
| Альтернативные иконки (`Telegram/BUILD` `alternate_icon_folders` / `alternate_icons`, `*.alticon`, `AppDelegate.swift:1002` `getAvailableAlternateIcons`, Оформление → иконка) | 11 иконок Telegram (в т.ч. Premium) | `getAvailableAlternateIcons` → `[]` (выбор в настройках скрывается сам); если выбрана — `setAlternateIconName(nil)`; убрать `alternate_icons` из BUILD; во `WebBrowserItem.swift:159` значок «Xraygram» вместо `BlueIcon` | S |
| Настройки: «Ask a Question», «Telegram FAQ», «Telegram Features» (`PeerInfoSettingsItems.swift:352-358`) | значки — обычные глифы на цветных квадратах, **логотипа Telegram нет** | значки не менять; тексты — защищённые (п. 2 спеки) | — |
| Premium/Stars/Business/Passport в настройках | свои значки функций | не трогаем | — |
| Уведомления | iOS рисует иконку приложения (уже Xraygram); расширения уведомлений в нашей сборке выключены | — | — |
| Устаревший экран звонка `Call/CallTitleLogo` | скрыт (`isHidden = true`) | — | — |

Размеры ассетов, которые нужны: **CallKit 40 pt @2x/@3x (есть)**; **LaunchIcon 176 pt @2x/@3x** (п. 1). Остальное —
переиспользуем существующие глифы, новые не нужны.

## 4. QR и то, что уходит другим (F19-18, 19)

| Где | Что сейчас | Чем заменить | Труд |
|---|---|---|---|
| `submodules/QrCodeUI/Sources/QrCodeScreen.swift`: на экране вырез `.cutout` + Lottie `PlaneLogo` (l.729), в картинке для отправки `.custom(Chat/Links/QrLogo)` (l.579-586) — QR приглашений, папок, групп | самолётик в центре | `.none` и без Lottie (как QR «Поделиться сервером»). Прокси/XRAY уже со щитом/без логотипа | S |
| QR профиля — `QrStudioScreen` (`QrStudioCachedAnimationLayer.swift:16` самолётик из `PlaneLogoPlain.tgs`, экспорт `Share/QrPlaneIcon`, круглое окно `QrStudioCodePaths.logoRadius`) | самолётик в центре и на экспорте | убрать слой логотипа и окно (QR без выреза) или откатить на `QrCodeScreen` с `.none` | M |
| Водяной знак в кружочках: `CameraNeo/Sources/RoundVideoDecoration.swift` (`isEnabled = false`), `CameraRoundVideoFilter.swift` не используется | выключен в upstream | проверить, что выключен; ничего не делаем | — |

## 5. «О приложении» (PAR-21, F19-14, 21)

| Где | Что сейчас | Чем заменить | Труд |
|---|---|---|---|
| низ настроек (`PeerInfoSettingsItems.swift`) | строки версии **нет** (только в скрытом Debug-меню `DebugController.swift:1967`) | добавить последнюю секцию — строку «Xraygram для iOS <версия> · неофициальный клиент Telegram»; тап → `textAlertController` с полным текстом §4 и ссылкой github.com/vizacv/xraygram (открывает браузер) | S–M |

Версия Xraygram — `CFBundleShortVersionString` + buildNumber; версия upstream — константа из `versions.json` (13.2).

## 6. Строки (PAR-20, F19-09…12, 16)

**Как устроено.** `build-system/GenerateStrings/GenerateStrings.py` генерирует ObjC `_PresentationStrings` из
en.lproj. Каждый язык — `_PresentationStringsComponent(languageCode, …, dict)`; облачные пакеты
(`langpack.getLangPack`/`getDifference`) хранятся в `LocalizationSettings` и превращаются в тот же `dict`
(`dictFromLocalization`, `PresentationData.swift:139`). Все аксессоры идут через C-функцию `getSingle`
(primary → secondary → en из бандла).

**Где подменять (одна точка):** инициализатор `_PresentationStringsComponent` (шаблон в GenerateStrings.py) —
прогнать `dict` через `XraygramStringsPatch.apply(dict)` один раз на загрузку языка, и тот же вызов для
fallback-словаря в `getSingle`. Это покрывает бандл, все облачные пакеты (уже скачанные тоже), экран входа и места,
которые читают `primaryComponent.dict[...]` напрямую. Подмена — только по списку ключей, внутри значения
`Telegram`/`Телеграм`/`Телеграмм` → `Xraygram`; остальное слово «Telegram» в том же значении не трогаем, если оно
внутри защищённого словосочетания. Стоимость — один проход по ~13 тыс. строк при смене языка. **M.**

Цифры по en.lproj: 13 478 ключей, «Telegram» в значении — 576; после отсева защищённого (Premium, Stars, аккаунт,
серверы, «on Telegram», URL…) — ~170 кандидатов, из них по моей оценке ~90–110 — «о приложении»:
`AccessDenied.*` (22, должны совпадать с пунктом iOS «Настройки → Xraygram»), `EnterPasscode.*`,
`PasscodeSettings.LockTelegram`, `Passcode.AppLockedAlert`, `DialogList.PasscodeLockHelp`, `ClearCache.StorageCache`,
`StorageManagement.DescriptionAppUsage`, `Update.*`, `Conversation.UpdateTelegram`, `Login.ErrorAppOutdated`,
`Call.StatusIncoming`/`StatusOngoing`, `Calls.RatingTitle`, `Notifications.TelegramTones`,
`WebBrowser.Telegram`, `Attachment.CameraAccessText`, `Story.Camera.AccessPlaceholderTitle`, `Map.HomeAndWorkInfo`,
`ChatImportActivity.OpenApp`… Пограничные (`SentAppCode*`-аналоги `Login.CodeSentInternal`,
`Login.EnterCodeTelegramText`, приглашения, `Contacts.InviteToTelegram`, Premium-only) — не трогаем по таблице
FEAT-19 п. 3. Итоговый список ключей — `ios/rebrand-strings.md` (сделаю при реализации, отдам QA).

**Мимо `PresentationStrings` (отдельно):**

| Где | Что | Чем | Труд |
|---|---|---|---|
| `Telegram/Telegram-iOS/*.lproj/InfoPlist.strings` (17 из 80 языков с «Telegram») и usage descriptions в `Telegram/BUILD` (`NSContacts/NSLocation*/NSMotionUsageDescription`) | системные запросы доступа | «Telegram» → «Xraygram» в en/ru (и остальных, где слово латиницей); защищённое («облако Telegram») оставить | S |
| **`ar.lproj`, `ko.lproj` InfoPlist.strings — `CFBundleDisplayName` = «تيليجرام» / «텔레그램»** | на арабском/корейском iPhone имя под иконкой — «Telegram» (баг) | удалить эти строки | S |
| `*.lproj/AppIntentVocabulary.plist` (20 файлов, Siri-фразы «Send a Telegram message») | Siri | убрать filegroup (Siri у нас выключен) | S |
| `submodules/LegacyComponents/Sources/TGLocalization.m:48-72` | уже глобально меняет «Telegram» → `CFBundleDisplayName` в строках камеры/редактора — заодно портит «Telegram Premium» | заменить на тот же список ключей | S |
| `StoreDownloadedMedia.swift:12` | альбом «Telegram» в Фото | «Xraygram» | S |
| `DeviceContactData.swift:211` (+ `DeviceContactDataManager.swift:147,160,214`) | метка «Telegram» в Контактах iOS | оставить (это ссылка на аккаунт Telegram; смена ломает сопоставление) | — |
| `AuthorizationSequenceController.swift:1469` | «Telegram: <версия>» в письме поддержки | «Xraygram: <версия>» | S |
| Тексты с сервера (служебный чат, ToS, имя сеанса «Telegram iOS» в «Устройствах» по api_id) | | не трогаем (сервис) | — |

## 7. Заголовок списка чатов (F19-17)

На iOS заголовок — текст `DialogList.Title` («Чаты»/«Chats»), **логотипа-надписи «Telegram» нет** (это Android).
Вопрос продукту: оставить «Чаты» (F19-17 выполнен — «Telegram» нет) или ставить «Xraygram». Предлагаю оставить
«Чаты» — так в upstream iOS, и вкладка внизу называется так же.

## 8. Тема «Рентген» по умолчанию (FEAT-20, PAR-22 — пока не делаю)

- Встроенные темы: `PresentationBuiltinThemeReference` (`TelegramUIPreferences/Sources/PresentationThemeSettings.swift:12`),
  в форке уже есть `.neutral = 4`, `.neutralNight = 5` — образец. Генераторы — `TelegramPresentationData/Sources/
  MakePresentationTheme.swift`, тёмные — `DefaultDarkPresentationTheme.swift` (фоны зашиты: #000/#1c1c1d) и
  `DefaultDarkTintedPresentationTheme.swift` (всё выводится из акцента — с бирюзой фон станет бирюзовым).
- Акцент + цвет пузыря (`PresentationThemeAccentColor`) палитру **не выражают**: нет фонов, текста, обводки пузыря,
  warn/error.
- **Рекомендация:** новый случай `.rentgen = 6` со своим генератором `RentgenPresentationTheme.swift` (копия tinted с
  константами палитры), прописать во все `switch` (компилятор покажет ~8 мест), карточки в трёх выборах темы
  (`ThemeSettingsController.swift:1185`, `ThemePickerController.swift:1009`, `ThemeAutoNightSettingsController.swift:589`,
  исключение в `ThemeCarouselItem.swift:434`), не маппить в legacy-ключи (`BubblelessThemeSettings.swift:67`).
- По умолчанию: `PresentationThemeSettings.defaultSettings` (:717) — **и** `theme`, **и**
  `automaticThemeSwitchSetting.theme` = `.builtin(.rentgen)`, иначе в системной тёмной теме будет обычная Night.
  Обои — `.color(0x0B1220)` (узор с сервера до подключения не скачать). Обновить тест
  `PresentationThemeSettingsStorageTests` (сравнение байтов дефолта).
- Цвета заглушек аватаров: `AvatarNode.swift:600` (7 пар, индекс по `nameColor % 7`) — 6 цветов палитры + повтор,
  буквы `#0B1220`.
- Экраны до входа (вступление, экран XRAY, номер) берут `currentPresentationData` → станут тёмными сами.
- Оценка: **M–L** (1,5–3 дня с проверкой по кадрам).

## 9. Значок статуса XRAY над чатами (FEAT-20, PAR-23 — пока не делаю)

- Шапка: `ChatListUI/Sources/ChatListController.swift` (`ChatListLocationContext` :6855, сигналы заголовка :6994,
  щит прокси :7454 `ChatListProxyButtonComponent`), разметка — `TelegramUI/Components/ChatListHeaderComponent/
  Sources/ChatListNavigationBar.swift` (`update` :952: строка заголовка 44 pt → поиск 60 pt → панели).
- **Рекомендация:** слот-пилюля между строкой заголовка и поиском: новое поле `xrayStatus` в
  `ChatListHeaderComponent.Content` (другие экраны не задеты), высота ~28 pt, едет вместе с поиском при прокрутке и
  прячется при поиске; учесть раскрытые истории. **M** (1–2 дня с проверкой по кадрам). Дешевле (**S–M**) — панель
  в `HeaderPanelContainerComponent` под поиском (`ChatListControllerNode.swift:1469`), но это не «под заголовком».
- Данные: `account.networkState` (уже подписан, :6963), полный `ProxySettings` из `accountManager.sharedData`
  (`xraygramNetworkBlocked`, `xraygramDirectAllowed`, `activeServer.xrayDisplayTitle`), пинг —
  `ProxyServersStatuses` (пингует один раз → пересоздавать раз в 30 с). Тап — как у щита:
  `makeProxySettingsController` (:7474).

## Порядок работ по FEAT-19 (беру сейчас)

1. S: ar/ko `CFBundleDisplayName`, CallKit-знак, альтернативные иконки + ярлык, значок «Invite» в меню,
   InfoPlist.strings/usage descriptions, AppIntentVocabulary, альбом в Фото, письмо поддержки.
2. S: LaunchScreen (заглушка иконки до готового ассета).
3. M: своё вступление + порядок «вступление → экран XRAY → номер».
4. M: подмена строк по списку ключей в `_PresentationStringsComponent` + `TGLocalization`; список в
   `ios/rebrand-strings.md`.
5. S–M: QR без логотипа (QrCodeScreen, QrStudio).
6. S–M: строка версии внизу настроек + диалог.
