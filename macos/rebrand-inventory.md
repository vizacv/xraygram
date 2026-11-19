# Инвентаризация ребрендинга macOS (FEAT-19) и темы «Рентген» (FEAT-20)

2026-11-19, тема macOS. Только разведка по коду tdesktop 7.4.4 + нашему патчу (`macos/patches/0001-…`), без сборок.
Пути — от `upstream/tdesktop/Telegram/`. Оценка: **S** ≤ 1 ч, **M** ½ дня, **L** 1–2 дня, **XL** больше.
Решение владельца (`docs/decisions.md`, 2026-11-19): убрать видимое «Telegram» о приложении; оставить служебный чат с
кодами, названия функций сервиса (Premium, звёзды), «неофициальный клиент Telegram» в «О приложении».

## Уже сделано в сборке macos-20261118-3

| Что | Где |
|---|---|
| Имя в Dock/Finder/меню, bundle id | `Telegram.plist` (`CFBundleName/DisplayName = Xraygram`), `CMakeLists.txt` |
| Меню «About/Hide/Quit Xraygram» | `platform/mac/global_menu_mac.mm` берёт имя из `CFBundleName` |
| Заголовок окна, восстановленные окна, рисованный заголовок | `window/main_window.cpp`, `window_saved_windows.cpp`, `window_restore_shell.cpp`, `platform/mac/window_title_mac.mm` |
| Заголовок «О приложении» | `boxes/about_box.cpp` (`setTitle("Xraygram")`) |
| Экран приветствия | `intro/intro_start.cpp` (заголовок + «Неофициальный клиент Telegram…») |
| Подсказка трея (`AppName`), папка данных | `core/version.h` (`AppName = "Xraygram"`) |
| Иконка приложения (Dock, Finder, системные уведомления) | `Icon.icns` из `branding/macos/Xraygram.icns` (CMake-опция `XRAYGRAM_ICNS`) |

## 1. Картинки и анимации

| # | Где видит пользователь | Код / ресурс | Чем заменить | Оценка |
|---|---|---|---|---|
| 1.1 | Вступление: самолётик и боковые узоры над «Xraygram» | `intro/intro_step.cpp` `Step::paintCover()`; стили `introCoverIcon` (`intro_plane_trace/inner/outer/top`), `introCoverLeft/Right` в `intro/intro.style`; иконки `Resources/icons/intro_*` | Рисовать персонажа (`branding/xraygram-icon-1024.png` → ресурс) + луч сканера кодом: градиентная полоса `accent` 55 % и линия `accent-hi`, 1,2 с, один раз (`Ui::Animations::Simple` в `Step`); надпись `XRAYGRAM` моноширинным — через `_title` или свой `FlatLabel` | **L** |
| 1.2 | Логотип окна, превью уведомлений в настройках, свои (не системные) уведомления, вложение-аватар уведомлений | `window/main_window.cpp` `Logo()` / `LogoNoMargin()` → `Resources/art/logo_256.png`, `logo_256_no_margin.png`; используются в `settings/sections/settings_notifications.cpp`, `window/notifications_manager_default.cpp`, `window/notifications_utilities.cpp`, `platform/mac/specific_mac.mm` (фолбэк иконки) | Подложить наши PNG теми же именами (ресурсы qrc). Лучше оверлеем файлов в `build-local.sh src`/CI из `branding/macos/tdesktop-art/` (бинарники не в патч) | **S** (+ генерация PNG продуктом/скриптом `tools/branding`) |
| 1.3 | Аватар служебного чата «Telegram» (777000) | `data/data_peer.cpp` (`isNotificationsUser()` → `LogoNoMargin`) | **Оставить** (решение: служебный чат остаётся). Если делать 1.2 оверлеем `logo_256_no_margin.png`, здесь тоже станет обезьянка — тогда вернуть Telegram-лого отдельным ресурсом для 777000 | S |
| 1.4 | Настройка «круглая иконка приложения» (Продвинутые) | `settings/sections/settings_advanced.cpp` `IconMacRound()` → `Resources/art/icon_round512@2x.png`, `Window::OverrideApplicationIcon` | Подложить нашу круглую версию или скрыть пункт | S |
| 1.5 | Иконки `Resources/art/icon16…512(@2x).png` | `Resources/qrc/telegram/telegram.qrc`; на macOS видны мало (окно/Dock — из `.icns`) | Оверлей теми же именами вместе с 1.2 | S |
| 1.6 | Иконка в меню-баре (трей) | `platform/mac/tray_mac.mm` `TrayIconBack()` → `st::macTrayIcon` → `Resources/icons/mac_tray_icon(@2x/@3x).png` (шаблон-маска, красится в цвет меню-бара) | Монохромный силуэт обезьянки 16/32/48 px той же маской (альфа) | **S** + рисунок |
| 1.7 | QR входа по QR (самолётик в центре) | `intro/intro_qr.cpp` `TelegramLogoImage()` (`st::introQrPlane` = `Resources/icons/intro_qr_plane*`) | Наша маленькая иконка в круге | S |
| 1.8 | QR прокси и наш «Поделиться сервером» (самолётик в центре) | `boxes/connection_box.cpp` `ProxyQrLogo()` → `st::introQrPlane` | Для XRAY-QR — наша иконка (или без центра: выше читаемость длинной ссылки) | S |
| 1.9 | Кольцевая надпись «TELEGRAM» при записи круглого видео | `ui/controls/round_video_recorder.cpp` `initCircularTextAdd()` (`u"Telegram"_q.toUpper()`) | `XRAYGRAM` | S |
| 1.10 | Пустые состояния (утка в «нет чатов», собака и т.п.) | `Resources/animations/no_chats.tgs`, `dog_empty.tgs`… (Lottie) | Это не логотип, а маскоты Telegram. По решению «полного редизайна нет» — **оставить**; при желании позже заменить 2–3 главные (no_chats) | (M, если делать) |
| 1.11 | Dock-бейдж | `platform/mac/main_window_mac.mm` (`setBadgeLabel`) | Только число, иконка из `.icns` — **ничего не нужно** | — |
| 1.12 | Системные уведомления macOS | `platform/mac/notifications_manager_mac*.mm` | Иконка = иконка бандла (уже наша) — **ничего не нужно** | — |
| 1.13 | Заставка при запуске | macOS — n/a (у tdesktop нет splash) | — | — |

## 2. Захардкоженные строки (не из lang.strings)

| # | Где | Код | Чем заменить | Оценка |
|---|---|---|---|---|
| 2.1 | Подвал главного меню: «Telegram Desktop» со ссылкой на desktop.telegram.org | `window/window_main_menu.cpp` (`_telegram->setMarkedText(tr::link("Telegram Desktop", …))`) | «Xraygram» → ссылка на репозиторий проекта (или без ссылки) | S |
| 2.2 | Заголовок уведомления при «скрывать имя и текст» | `window/notifications_manager_default.cpp` (`u"Telegram Desktop"_q`) | «Xraygram» | S |
| 2.3 | Превью уведомления в настройках | `settings/sections/settings_notifications.cpp` (`u"Telegram Desktop"_q`) | «Xraygram» | S |
| 2.4 | Окно отчёта о сбое | `core/crash_report_window.cpp` (`u"Telegram"_q`) — у нас крэш-репорты выключены | «Xraygram» (попутно) | S |
| 2.5 | Тексты «О приложении» | `boxes/about_box.cpp`: `lng_about_text1` («Official free messaging app based on Telegram API»), `lng_about_text2` (ссылки на `telegramdesktop/tdesktop`), `lng_about_text3` (FAQ telegram.org) | Свой текст: «Неофициальный клиент Telegram (Telegram API)…», GPL + ссылка на наш GitHub (GPL требует давать исходники), FAQ — убрать или на README. Строки — продукту | S |

## 3. Строки из языковых пакетов (встроенных и облачных)

**Где перехватывать.** Все строки `tr::lng_*` (встроенный английский `Resources/langs/lang.strings` → сгенерированный
`GetOriginalValue()`, и облачные пакеты `langpack.getDifference`) хранятся в `Lang::Instance::_values` и читаются через
`Lang::Instance::getValue(ushort key)` (`lang/lang_instance.h`). Варианты:

- **на чтении (рекомендую):** в `getValue()` — `return Xraygram::Brand(key, _values[key])`, где `Brand` для ключей из
  списка заменяет «Telegram Desktop» / «Telegram» → «Xraygram» (быстрая проверка по `std::bitset<kKeysCount>` или
  `base::flat_set<ushort>`). Одна точка, работает для любого языка (облачный RU приходит с «Telegram» — подмена и там).
  Требует, чтобы в переводе слово было «Telegram» латиницей — в официальных пакетах так и есть.
- на записи: `PrepareDefaultValues()`, колбэк `ParseKeyValue` в `Instance::applyValue()`, `Instance::resetValue()`,
  `Instance::reset()` — 4 места, тот же список ключей.

**Список ключей (черновик, утверждает продукт).** В `lang.strings` 358 упоминаний «Telegram», из них про само
приложение (заменять):
- с «Telegram Desktop» (19): `lng_error_start_minimized_passcoded`, `lng_proxy_unsupported`, `lng_intro_about`
  (уже не используется — у нас свой текст), `lng_theme_no_desktop`, `lng_passcode_about`, `lng_passcode_about2`,
  `lng_passcode_about3`, `lng_settings_passkeys_unsigned_error`, `lng_bot_share_location_unavailable`,
  `lng_new_version_wrap`, `lng_group_call_mac_access`, `lng_group_call_mac_screencast_access`, `lng_terms_delete_warning`,
  `lng_language_not_ready_about`, `lng_outdated_soon`, `lng_outdated_now`, `lng_wallet_protection_open_warning_lock`
  (+2 Windows/UWP — не видны на macOS);
- про приложение без «Desktop» (~20): `lng_open_from_tray`, `lng_quit_from_tray`, `lng_tray_icon_text`,
  `lng_update_telegram`, `lng_settings_add_sendto`, `lng_settings_passcode_lock_app`, `lng_settings_use_touchid_about`,
  `lng_settings_use_applewatch_about`, `lng_settings_use_systempwd_about`, `lng_passcode_unlock_about`,
  `lng_local_storage_device_telegram`, `lng_local_storage_device_usage`, `lng_message_unsupported`,
  `lng_unsupported_message_text`, `lng_unsupported_block_text`, `lng_bad_photo`, `lng_bad_video`.
- **оставить** (про сервис/аккаунт/серверы, ~300): «Telegram account», «Telegram servers», «Telegram cloud», коды
  «from Telegram», «joined Telegram», Premium/Stars/Gifts/Business/TON, «Telegram FAQ / Features / Support»,
  QR-вход «Telegram on your phone» (речь об официальном приложении на телефоне).
- спорные (решить продукту): `lng_settings_faq`, `lng_settings_features`, `lng_settings_ask_sure` (ведут на
  telegram.org — может, скрыть пункты), `lng_intro_qr_title`.

**Меню macOS:** `lng_mac_menu_*_telegram` уже получают `{telegram}` = `CFBundleName` → «Xraygram». Заголовок
app-меню (`global_menu_mac.mm`, `addMenu("Telegram")`) система заменяет именем бандла — не видно.

Оценка раздела 3: **M** (хук + список ключей + проверка на RU/EN облачных пакетах).

## 4. Тема «Рентген» по умолчанию

**Как устроено в 7.4.4.** Без сохранённой темы (`storage/localstorage.cpp` `InitialLoadTheme()`, ключ 0) действует
встроенная палитра `lib_ui/ui/colors.palette` (день). «Ночной режим» = файл `:/gui/night.tdesktop-theme`
(`window/themes/window_theme.cpp` `kNightThemeFile`, `NightThemePath()`). Встроенные схемы в настройках —
`window/themes/window_themes_embedded.cpp` `EmbeddedThemes()` (`EmbeddedType::Default/DayBlue/Night/NightGreen`).
По умолчанию включено следование за системой (`Core::Settings::_systemDarkModeEnabled = true`).

**Предлагаю:**
1. Ресурс `Resources/rentgen.tdesktop-theme` (палитра `name: #hex;` по токенам `branding/theme-rentgen.md`; основа —
   `night.tdesktop-theme`, перекрасить ~150–200 ключей: фоны `bg/surface`, текст, `accent` в `activeButtonBg`,
   `dialogsUnreadBg`, `historyOutBg` = `bubble-out`, `msgOutBg`, ссылки, `warn/error`; аватары — `historyPeer1…8UserpicBg`).
   Добавить в qrc (`Resources/qrc/telegram/telegram.qrc`).
2. `EmbeddedType::Rentgen` первым в `EmbeddedThemes()` (название «Рентген»/«X-ray» через `Xraygram::Tr`).
3. Сделать её «ночной» и включённой при первом запуске: `kNightThemeFile` → `:/gui/rentgen.tdesktop-theme`; в
   `InitialLoadTheme()` при ключе 0 (нет сохранённой темы) — `SetNightModeValue(true)` и применить; значение по
   умолчанию `_systemDarkModeEnabled = false`, чтобы светлая тема macOS не переключала обратно на дневную.
   «Ночной режим» в меню тогда переключает Рентген ↔ классическую дневную; выбор пользователя сохраняется как обычно.
4. Фон чатов: свой `background.tgv`/однотонный `bg` для Рентгена (`Data::ThemeWallPaper` при этой теме).
5. Моноширинный шрифт для пилюли/ссылок: системный через `style::font::monospace()` (`lib_ui/ui/style/style_core_font.h`,
   им tdesktop рисует код в сообщениях); JetBrains Mono встраивать не стоит (лишний ресурс ради пары строк).

Оценка раздела 4: палитра **L** (подбор + проверка экранов), встраивание и default **M**.

## 5. Значок статуса XRAY над списком чатов

**Место:** `dialogs/dialogs_widget.cpp` `Widget::updateControlsGeometry()` — под полем поиска (`_searchControls`) и над
историями (`_stories`), рядом с `_topBarSuggestion` (`dialogs/ui/dialogs_top_bar_suggestion_content.*`, слот для
промо-подсказок над чатами — готовый механизм SlideWrap со сдвигом списка). Пилюлю делаем отдельным виджетом
`Xraygram::StatusPill` (центр, высота ~24, моноширинный 12, фон `accent` 10 %, обводка 35 %), клик →
`ProxiesBoxController::Show(controller)`. В узком режиме (свёрнутая колонка) — только точка.

**Данные:**
- активная запись и имя — `Core::App().settings().proxy()` + `Xraygram::IsXrayProxy/TitleFor`;
- состояние — `account->mtp().dcstate()` (как в `window/window_connecting_widget.cpp` `refreshState()`),
  `Xraygram::StatusFor()` (ядро упало), `Xraygram::NetworkBlocked()`/выбор «напрямую»;
- пинг: штатный `MTP::StartProxyCheck()` (тот же, что в списке прокси) раз в 30–60 с для активной XRAY-записи, или
  взять время pong у MTP-сессии (нужно протащить из `SessionPrivate`) — первый вариант проще;
- обновление — `Xraygram::StateChanges()`, `Core::App().proxyChanges()`, `connectionTypeChanges()`.

**Состояния** — по `branding/theme-rentgen.md` (accent / warn «подключение…» / error «нет связи» / warn «Напрямую,
без XRAY»). Штатный `ConnectionState`-виджет (левый нижний угол) оставить или скрыть при пилюле — решить продукту.

Оценка раздела 5: **L** (виджет + данные + раскладка + узкий режим).

## 6. Сводка трудозатрат

| Раздел | Оценка |
|---|---|
| 1. Картинки (оверлей PNG, трей, QR, круговая надпись) | M (без вступления) |
| 1.1 Вступление с лучом | L |
| 2. Захардкоженные строки + «О приложении» | S–M |
| 3. Подмена строк языковых пакетов | M |
| 4. Тема «Рентген» по умолчанию | L + M |
| 5. Пилюля статуса XRAY | L |
| **Итого** | **≈ 5–7 рабочих дней** на macOS, из них ~2 — палитра и вступление |

Что нужно от продукта/владельца: список ключей раздела 3 (что менять, что оставить), тексты «О приложении», монохромная
иконка для меню-бара, PNG для оверлея (`logo_256*`, `icon_round512@2x`, маленькая иконка для QR), решение по пунктам
FAQ/Features/Support и по штатному индикатору соединения при наличии пилюли.
