# Решения macOS (tdesktop)

## 2026-11-18 — База: tdesktop `v7.4.4`, а не master

Патчи пишем против релизного тега `v7.4.4` (`bf4f7140`). Тег стабильнее master, а upstream CI на нём зелёный.
Обновление на новый тег: `git apply --3way` патча на новом теге, правка конфликтов, новый `.patch`.

## 2026-11-18 — xray как дочерний процесс `xraygram-core` (вариант «а», но на Go-пакетах libXray)

Варианты:
- **(а) отдельный бинарник внутри `.app`**, запускается `QProcess`, поднимает SOCKS5 на 127.0.0.1;
- **(б) libXray как c-shared/c-archive** внутри процесса Телеги, вызовы `CGoInvoke`.

Выбрали (а), но бинарник — не голый `xray` из Xray-core, а свой маленький `xraygram-core` (`macos/core/main.go`,
~200 строк), собранный на Go-пакетах libXray `share` и `xray`. Причины:
- голый Xray-core не понимает `vless://` ссылки; переписывать парсер на C++ (Reality, xhttp, flow, fp...) долго и хрупко,
  а у libXray он уже есть (`ConvertShareLinksToXrayJson`);
- отдельный процесс изолирует Go-рантайм от Qt (сигналы, потоки, два рантайма в одном процессе), падение xray не роняет
  Телегу, перезапуск тривиален;
- сборка проще: `CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build` можно делать даже на Linux-раннере, никакой связки
  cgo + CMake + Xcode;
- на стороне C++ — только `QProcess`, без новых библиотек в CMake.

Минусы: +1 процесс (~20–40 МБ RAM), локальный порт виден другим программам — закрыт паролем SOCKS5 (случайный, 0600-файл).
Ссылка передаётся через stdin, не в аргументах (не видна в `ps`).

## 2026-11-18 — Не вводим новый `ProxyData::Type::Xray`

Новый тип меняет формат сериализации настроек (`core_settings_proxy.cpp`) и требует правок во всех `switch` по типу
(mtproto-соединения, проверки, ротация, UI). Вместо этого xray выглядит для Телеги как обычный SOCKS5 `127.0.0.1:<порт>`
с логином `xraygram`; ссылка хранится отдельно в `tdata/xraygram.json`. Патч получается маленьким (~800 строк, из них
~600 новых файлов) и легко переносится на новые версии tdesktop.

## 2026-11-18 — UX первого теста (заменено «UX v2» ниже)

- Настройки → Продвинутые → Тип соединения (или кнопка прокси на экране входа) → меню «⋮» → **«Xray: ссылка vless://»**.
  Если в буфере обмена лежит `vless://...`, то и «Add proxy», и «Add from clipboard» сразу открывают это окно.
- Окно: поле для ссылки, статус («Xray работает: 127.0.0.1:PORT → vless host name»), кнопки «Сохранить и подключить»,
  «Отмена», «Удалить».
- «Сохранить»: `xraygram-core check` → сохранить → перезапустить xray → добавить/выбрать запись и включить прокси.
- xray стартует при запуске приложения, если ссылка сохранена, и живёт, пока приложение открыто.
- Строки окна — только по-русски, без `lang.strings` (не трогаем локализацию ради теста).

## 2026-11-18 — Сборка: вариант upstream `mac_packaged.yml` (Homebrew Qt)

Полная сборка `prepare.py` из исходников (`mac.yml`) идёт часами и упирается в лимит 6 ч и в размер кэша.
`mac_packaged.yml` берёт Qt/ffmpeg и пр. из Homebrew, собирает только tg_owt/tde2e/rnnoise/Rust, бандлит библиотеки
`macdeployqt`. Для тестовой сборки этого достаточно. Минус — зависимость от текущих версий brew.
Если упрёмся — переключаемся на `mac.yml`-путь (prepare.py + Xcode).

Build type по умолчанию `Release` (upstream CI собирает Debug: быстрее компилируется, но UI заметно медленнее).

## 2026-11-18 — Ребрендинг минимальный

`AppName = "Xraygram"` (папка данных `~/Library/Application Support/Xraygram`, не пересекается с официальным клиентом),
bundle id `io.github.xraygram.desktop`, имя в Dock/Finder «Xraygram», URL-схемы `tg://` не регистрируем.
Иконка пока телеграмовская — для личного теста нормально, для публичной раздачи нужна своя (правила Telegram для форков).
Автообновление и крэш-репорты выключены явно.

## 2026-11-18 — Подпись: ad-hoc

Нет Apple Developer ID → `codesign --sign -` (ad-hoc) всего бандла. После скачивания DMG macOS ставит карантин;
запуск: `xattr -dr com.apple.quarantine /Applications/Xraygram.app` (или «Всё равно открыть» в
Системные настройки → Конфиденциальность и безопасность).

## 2026-11-18 — Локальная сборка: те же шаги, что в CI, всё внутри `~/xraygram`

`macos/scripts/build-local.sh` повторяет `mac_packaged`-вариант (brew Qt, свои tg_owt/tde2e/rnnoise/Rust). Рабочие
исходники — `upstream/tdesktop` (ветка `xraygram`, правки staged, сабмодули `--depth 1`), всё собранное — в
`upstream/xraygram-local/` (libs, build-release/debug, bin, dist, logs, go, appdata). rustup/cargo и кэши Go — там же,
`~/.cargo`, `~/go` не создаются. Ключи API — `.secrets/api.env` (0600, в .gitignore). `run`/`run-dev` запускают
приложение с `-workdir upstream/xraygram-local/appdata`, чтобы тестовые аккаунты не смешивались с будущей «боевой»
установкой. Патч выгружается `update-patch.sh` и сразу проверяется на чистом теге.

Зависимости из master (rnnoise, tg_owt) не закреплены, как и в upstream CI; их SHA пишутся в `libs/*.sha`.

## 2026-11-18 — UX v2: тип XRAY в штатном окне прокси, несколько записей

Владелец: пункт в меню «⋮» никто не найдёт. Теперь:
- В `ProxyBox` («Edit proxy») пятый тип **XRAY (VLESS)**, первый в списке и выбран по умолчанию для новой записи.
  Это UI-значение радиокнопки (`ProxyData::Type(0x58)`), в `ProxyData` и настройки оно не попадает — формат
  хранения Телеги по-прежнему не меняем. При выборе XRAY вместо адреса/логина одно поле «Ссылка» и строка статуса
  (асинхронный `xraygram-core check` с задержкой 300 мс после ввода). Save → `Xraygram::SaveLink` → обычный путь
  добавления/замены записи контроллера.
- «Add proxy» и «Add from clipboard» при `vless://...` в буфере открывают это же окно со ссылкой. Отдельное окно и
  пункт «⋮» убраны (`xraygram_box.*` удалены).
- В списке: `XRAY · <имя из #fragment или адрес сервера>` без порта (флаг `web` у строки только скрывает порт).
- **Несколько записей**: каждая XRAY-запись — свой SOCKS5 `127.0.0.1:<порт>` со своим случайным паролем и свой
  процесс `xraygram-core`. Вариант «один порт, перезапуск core при переключении» отвергнут: тогда пинг у
  невыбранных записей всегда «недоступен», а ротация прокси не работает. Цена — ~20–40 МБ RAM на запись.
  Записи, которых нет в списке прокси Телеги, удаляются из `xraygram.json` при следующем запуске.
- Видимое «Telegram» → «Xraygram»: заголовок окна (`MainWindow::updateTitle`), рисованный заголовок macOS
  (`window_title_mac.mm`), восстановленные окна, About. Меню приложения уже брало имя из `CFBundleName`.

## 2026-11-18 — Звонки 1:1 через xray: TCP-ретрансляторы Telegram через SOCKS5

- Звонок с активной XRAY-записью идёт **только** через relay-кандидаты на TCP-ретрансляторах Telegram, каждое
  соединение — через локальный SOCKS5 xray. UDP, STUN, прямой P2P и прямой TCP выключены. Если TCP-ретрансляторов
  нет, звонок не соединяется, но и напрямую не идёт: для нашей аудитории это лучше тихой утечки.
- Правки tgcalls — отдельный патч `patches/tgcalls/0001-socks5-tcp-relay.patch` с путями от корня tgcalls, чтобы его
  взяли Android и iOS. SOCKS5-адаптер написан внутри `ReflectorPort.cpp` (в libwebrtc его больше нет), новых файлов нет —
  не нужно править списки сборки на других платформах. `update-patch.sh` выгружает и проверяет его против коммита
  сабмодуля из тега tdesktop.
- Галку «использовать прокси для звонков» не возвращаем: для XRAY прокси в звонке включён всегда.
- Групповые звонки/видеочаты/конференции — предупреждение «Без xray» (варианты и оценки — `research.md`).
- MAC-04: удаление активной XRAY-записи → другая XRAY-запись или подтверждение. MAC-05 — решено ниже («Экран XRAY»).

## 2026-11-18 — Экран «Подключение через XRAY» (MAC-05). Поведение для всех платформ

Решение владельца: пока нет ни одной XRAY-записи, клиент **никуда не подключается** и показывает экран для ссылки.

### Правила (копировать на Android/iOS как есть)

1. **Состояние «заблокировано»** = нет ни одной XRAY-записи в списке прокси **и** пользователь не выбирал явно
   «без XRAY». Проверяется на лету, ничего отдельно не хранится, кроме флага `directAllowed`.
2. **Пока заблокировано — ни байта в сторону Telegram:**
   - MTProto-сессии получают вместо настроек «чёрную дыру»: SOCKS5 `127.0.0.1:1` (там никто не слушает, соединение
     отклоняется локально);
   - загрузчик конфига считает, что прокси включён, и **не** делает обходных запросов (DoH к Google/Cloudflare,
     Firebase и т.п.);
   - прочий HTTP клиента (Qt application proxy) — туда же.
   Сохранённые настройки прокси при этом не меняются: блокировка накладывается сверху.
3. **Экран** (модальный, не закрывается Esc/кликом мимо; если его закрыла смена экрана — показывается снова):
   - заголовок «Подключение через XRAY», текст «…только через ваш сервер XRAY… пока ссылки нет, никуда не подключается»;
   - одно поле «ссылка» (`vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`), если ссылка в буфере — подставить;
   - под полем живое превью: «Сервер: vless · host · имя» или «Ошибка: …» (та же проверка, что в Edit proxy, с задержкой
     ~300 мс после ввода);
   - кнопка **«Подключить»**: сохранить ссылку, добавить XRAY-запись в список прокси, выбрать её, включить прокси →
     блокировка снимается, сессии перезапускаются через XRAY;
   - внизу неприметная ссылка **«Подключиться без XRAY (напрямую)»** → подтверждение («провайдер увидит соединение…»,
     красная кнопка «Подключиться напрямую») → `directAllowed = true`, применяются обычные настройки прокси
     (напрямую или ранее выбранный не-XRAY прокси).
4. **Когда появляется:** при старте, если заблокировано (первый запуск, старый профиль без XRAY), и сразу после
   удаления последней XRAY-записи (перед этим — подтверждение «Это последняя XRAY-запись…»).
4а. **Сохранённые серверы** (уточнение владельца): если XRAY-ссылки уже были (например, удалили последнюю запись),
   экран сверху показывает их выбор — «XRAY · vless · host · имя» по одному на ссылку — и пункт «Новая ссылка»;
   поле для ссылки видно только при «Новая ссылка». Если в буфере ссылка, по умолчанию выбрана «Новая ссылка».
   Выбор сохранённого → запустить её xray, вернуть запись в список прокси и выбрать её.
   Ссылки удалённых записей поэтому не выбрасываются при старте, а хранятся в `xraygram.json` как неактивные (xray
   для них не запускается). Явной кнопки «забыть ссылку» пока нет — это следующий шаг, если нужен.
5. **Сброс выбора «напрямую»:** при добавлении любой XRAY-ссылки `directAllowed` сбрасывается. Значит, если потом
   удалить последнюю XRAY-запись, экран снова появится.
6. **Если пользователь уже вошёл и XRAY-записи есть — ничего не меняется.**

### Где это в tdesktop

- `xraygram/xraygram_core.{h,cpp}`: `HasXrayEntries()`, `NetworkBlocked()`, `BlockedProxy()`, `AllowDirect()`;
  флаг `directAllowed` в `tdata/xraygram.json`.
- Точки блокировки: `mtproto/session.cpp` (`Session::refreshOptions`), `mtproto/mtp_instance.cpp` (`ConfigLoader`
  с `proxyEnabled`), `core/sandbox.cpp` (`Sandbox::refreshGlobalProxy`).
- Экран: `xraygram/xraygram_gate.{h,cpp}` (`ShowGateIfNeeded`, `RefreshGate`); показ — `Core::Application::run()`
  после первого показа окна и `ProxiesBoxController::setDeleted` при смене состояния.

### Подсказки для Android/iOS

- Android (`DrKLO/Telegram`): аналог «чёрной дыры» — в `ConnectionsManager.init/setProxySettings` при блокировке
  отдавать в native SOCKS5 `127.0.0.1:1`, а `native_setUseIpv6`/DoH-фолбэк (`ConnectionsManager.ResolveHostByNameTask`,
  `FirebaseTask`, `DnsTxtLoadTask`) не запускать. Экран — до `LoginActivity`/`IntroActivity` и поверх `LaunchActivity`.
- iOS (Telegram-iOS): блокировать в `MTContext`/`Network` на уровне `MTSocksProxySettings` + выключить
  `MTBackupAddressSignals` (DoH-фолбэк) при блокировке. Экран — до `AuthorizationSequence`.

## 2026-11-18 — Выравнивание по product/parity.md (PAR-08m, 04, 06, 03, 01, 07, 10, 11, 14)

- **PAR-08m (F04-02):** v1 `InstanceImpl` (2.7.7/5.0.0) через XRAY не годится: в `NetworkManager.cpp` TURN-серверы только UDP
  (TCP пропускаются), `DISABLE_UDP` не трогает UDP-relay, а `BasicPacketSocketFactory` в tg_owt умеет только HTTPS-прокси.
  Поэтому при активной XRAY-записи `CollectVersionsForApi()` отдаёт только версии ≥ 7 (V2 7,8,9,12,13 и Reference 10,11 —
  обе реализации пропатчены); если всё же согласована другая — звонок завершается с ошибкой, без прямого соединения.
- **PAR-04 (проверка):** «Поделиться», QR, «Поделиться списком», кнопка в окне прокси и подтверждение ссылки — все идут
  через `ProxyDataIsShareable()`, для XRAY-записи она `false` → `tg://socks?server=127.0.0.1…&pass=…` не отдаётся.
  Даже если в окне записи переключить тип на SOCKS5, `ShareProxy` откажет. `external_control.cpp` пароль не показывает.
- **PAR-06:** BUG-06 — удалённая запись сразу гасит своё ядро (`SetEntryActive(false)`), восстановление (undo) — запускает;
  ссылка остаётся в сохранённых. BUG-07 — строка записи показывает `XRAY: не удалось запустить` /
  `XRAY: перезапуск через N с` / `XRAY: нет свободного локального порта` вместо штатного статуса (красным);
  обновляется по событиям ядра (`Xraygram::StateChanges()`).
- **PAR-03/01:** ошибки ссылки по таблице FEAT-01; сопоставление в C++ по ответу `xraygram-core check`
  (`empty link`, `unsupported share format`, `no valid outbound found`), `http(s)://` ловится до вызова ядра, таймаут/нет
  ядра — «Не удалось проверить ссылку…». Сырой текст — в логе. Тексты экрана XRAY, подсказки, диалогов удаления
  последней записи и «Подключиться напрямую?», «XRAY» заглавными в предупреждении о групповых звонках — по FEAT-01…04.
- **PAR-07:** порт в превью (`xraygram-core` отдаёт `host:port`), «Сохранённые серверы», максимум 20, новые сверху; новая
  ссылка, совпадающая с сохранённой, переиспользует её (без дубля).
- **PAR-10:** виджет соединения с кнопкой прокси виден на экране входа всегда (`window_connecting_widget.cpp`); с XRAY он
  и так виден постоянно (прокси включён).
- **PAR-11:** экран XRAY закрывается сам, когда блокировка снята другим путём (`proxyChanges`/`connectionTypeChanges`).
- **PAR-14:** иконка — CMake-опция `XRAYGRAM_ICNS` (путь к `branding/macos/Xraygram.icns`), бинарник в патч не кладём;
  `build-local.sh configure` передаёт её сам. CI должен передать `-DXRAYGRAM_ICNS=$GITHUB_WORKSPACE/xraygram/branding/macos/Xraygram.icns`.
- **Отклонение (согласовать с продуктом):** FEAT-04 п. 6 говорит «…или начинает трансляцию». На macOS окно «Без XRAY» не
  показывается для RTMP-трансляций: зритель получает поток через MTProto (`upload.getFile`), то есть через XRAY.
- **PAR-04 (В1 → а, FEAT-15 этап 1):** у XRAY-записи «Поделиться сервером» в меню строки и кнопкой в окне записи →
  каждый раз «Поделиться сервером?» (Показать/Отмена) → окно `XRAY · <имя>`: QR ровно сохранённой ссылки (штатный
  `ProxyQrTile`), подпись, «Копировать ссылку» (уведомление «Ссылка скопирована»), «Закрыть»; текста ссылки на экране нет,
  в лог не пишется. «Поделиться списком» и штатные `tg://socks` для XRAY по-прежнему недоступны.
- **PAR-05 (В2 → а):** в окне прокси выбор «Без прокси»/«Системный», пока прокси включён и есть XRAY-записи, —
  радиокнопка возвращается, диалог «Подключиться напрямую?» (тексты FEAT-03); «Подключиться напрямую» применяет режим.
  Переход на обычный прокси — без диалога.
- **PAR-02 (В3 → а, канон продукта):** все наши строки через `Xraygram::Tr(ru, en)`: язык приложения, если пользователь
  выбрал его сам (у `Lang::Instance` до выбора пустой `id()`), иначе язык системы (`systemLangCode()`); русский, если
  выбранный/системный язык (или базовый язык пакета) — `ru*`, иначе английский.

## 2026-11-18 — Баги QA по macos-20261118-2

- **BUG-17 (прямые соединения при экране XRAY, не подтверждён):** по коду обходов нет — все MTP-соединения (включая
  тестовые :80/:443) берут прокси только из `Session::refreshOptions()`, где стоит блокировка; HTTP — через прокси;
  `ConfigLoader` при блокировке считает прокси включённым (без DoH); до загрузки ядра `NetworkBlocked()` по умолчанию
  «заблокировано». Прямые соединения возможны только после снятия блокировки, т.е. после «Подключиться без XRAY».
  Чтобы различать: в `log.txt` теперь `Xraygram: network BLOCKED/unblocked (XRAY entries: …, direct allowed: …)` при
  каждой смене и `Xraygram: the user chose to connect directly, without XRAY.`
- **BUG-09 (тестовый экземпляр выходит вперёд):** `scripts/make-qa-app.sh` делает QA-копию бандла (bundle id
  `io.github.xraygram.desktop.qa`, имя «Xraygram QA», `LSUIElement` + `LSBackgroundOnly`), `scripts/run-qa.sh`
  запускает её бинарником напрямую с `-workdir` и `-startintray`. Проверено: передний план не меняется (24 замера за
  12 с), значка в Dock нет, приложение стартует полностью (экран XRAY в логе).
- **BUG-11 (`SO_REUSEPORT` на SOCKS-порту):** xray-core ставит `SO_REUSEPORT` всем своим listener'ам безусловно
  (`transport/internet/system_listener.go`), а SOCKS-вход xray не умеет unix-сокеты. Поэтому SOCKS5 (CONNECT,
  логин/пароль, ответ 7 на UDP ASSOCIATE) теперь обслуживает сам `xraygram-core`: `net.Listen` без reuseport,
  соединения — в ядро через `core.Dial`; у xray своих слушающих сокетов нет. Проверено: второй `bind` с
  `SO_REUSEPORT` на тот же порт → `EADDRINUSE`; без пароля `05ff`, неверный пароль `0101`.
- **BUG-16:** закрыт PAR-08m (при XRAY только версии ≥ 7).
- **BUG-12 / PAR-16:** приветствие — «Xraygram» и «Неофициальный клиент Telegram, который подключается через ваш сервер
  XRAY.» / "An unofficial Telegram client that connects through your own XRAY server." (FEAT-06).
- **PAR-15:** переход 1:1 → конференция (добавить участника из окна звонка, принять приглашение в конференцию, войти по
  ссылке конференции во время звонка) — тот же диалог «Без XRAY». Без `show` берём панель текущего звонка или главное
  окно. «Отмена» — звонок 1:1 остаётся через XRAY; при принятии приглашения — приглашение отклоняется (иначе звонок
  висел бы в «обмене ключами»).

## 2026-11-19 — FEAT-19 (ребрендинг): как сделано в tdesktop

**Подмена «Telegram» — по списку ключей** (PAR-20). Единая точка — `Lang::Instance::getValue`
(`lang/lang_instance.h`): для ключа из списка значение проходит через `Xraygram::BrandValue`
(`xraygram/xraygram_brand.cpp`): `Telegram Desktop` / `Telegram` (целое слово) / `Телеграм(м)…` → `Xraygram`.
Так подменяются и встроенные строки, и облачные языковые пакеты (F19-12). Ключи вне списка не трогаются.

Список ключей (держать в синхроне с `CollectBrandKeys()`; QA — для F19-09/10):

| Группа | Ключи |
|---|---|
| Трей, запуск | `lng_open_from_tray`, `lng_quit_from_tray`, `lng_tray_icon_text`, `lng_error_start_minimized_passcoded`, `lng_settings_auto_start` |
| Приложение, обновление | `lng_intro_about`, `lng_update_telegram`, `lng_new_version_wrap`, `lng_outdated_soon`, `lng_outdated_now`, `lng_sure_save_language`, `lng_proxy_unsupported` |
| Код-пароль, блокировка | `lng_settings_passcode_lock_app`, `lng_settings_use_touchid_about`, `lng_settings_use_applewatch_about`, `lng_settings_use_systempwd_about`, `lng_passcode_about`, `lng_passcode_about2`, `lng_passcode_about3`, `lng_passcode_unlock_about`, `lng_wallet_protection_open_warning_lock` |
| Хранилище, темы | `lng_local_storage_device_telegram`, `lng_local_storage_device_usage`, `lng_theme_no_desktop` |
| «Не поддерживается этим приложением» | `lng_bad_photo`, `lng_bad_video`, `lng_message_unsupported`, `lng_unsupported_message_text`, `lng_unsupported_block_text`, `lng_stories_unsupported`, `lng_bot_share_location_unavailable` |
| Звонки, доступы macOS | `lng_call_status_group_invite`, `lng_call_box_about`, `lng_confcall_join_text`, `lng_group_call_mac_access`, `lng_group_call_mac_input`, `lng_group_call_mac_accessibility`, `lng_group_call_mac_screencast_access`, `lng_group_call_mac_recording`, `lng_no_mic_permission` |
| Экранный диктор | `lng_screen_reader_bar_text`, `lng_screen_reader_confirm_text` |

Сомнительные — **не подменены**, вопрос продукту: `lng_language_not_ready_about` (перевод «для Telegram Desktop»),
`lng_settings_passkeys_unsigned_error`, `lng_wallet_protection_open_about`, `lng_wallet_protection_hardware_unavailable`,
`lng_mini_apps_disclaimer`, `lng_age_verify*`, `lng_intro_qr_title` («Войдите в Telegram по QR-коду»),
`lng_settings_faq` / `lng_settings_features` / `lng_settings_ask_sure` (справка сервиса — по спеке остаются).

Строки в коде (не ключи): уведомление-пример и пример в настройках уведомлений, окно сбоя, ссылка внизу главного
меню (→ github.com/vizacv/xraygram). Водяной знак видео-кружочков (самолётик + круговая надпись, вшиваются в
видео) — выключен (`kXraygramNoWatermark`, `round_video_recorder.cpp`), F19-18.

**Картинки** (PAR-19): не в патче, а из `branding/` при сборке. Опция CMake `XRAYGRAM_BRANDING_DIR` генерирует
`build/Telegram/xraygram_branding.qrc` (префикс `:/xraygram/`): `logo.png` ← `macos/xraygram-macos-1024.png`,
`logo_square.png` ← `xraygram-icon-1024.png`, `tray*.png` ← `macos/tray/mac_tray_icon*.png` (альфа-маски 22/44/66,
красятся как штатный значок — светлая/тёмная строка меню). Без опции — значки upstream. Где используется:
иконка окна и Dock (`Window::Logo`), «О приложении»/круглая иконка в настройках, трей (`tray_mac.mm`),
служебный чат 777000 — **остаётся** логотип Telegram (спека §2). Центр QR (вход, прокси/«Поделиться сервером»,
профиль/группа/ссылки — `peer_qr_surface`) — пустой (`Xraygram::kPlainQr`), без знаков (спека §3: на отдаваемом наружу — ни Telegram, ни Xraygram).

**Вступление** (PAR-18): один экран `Intro::StartWidget`. Обложка `Step::paintXrayCover` — иконка + луч
(`accent` 55 % полоса и линия `#8FFBE0`, 1,2 с, один раз при показе; при `anim::Disabled()` — без луча).
`XRAYGRAM` — системный моноширинный 28, разрядка 6 (рисуется вручную, у FlatLabel нет разрядки). «Начать».
Внизу «Русский · English» (вместо ссылки «Продолжить на …»). Выбор (`Xraygram::SetUiLanguage`):
экраны Xraygram — сразу (переопределение в `tdata/xraygram_ui.json`); Telegram: EN — `resetToDefault()` (без сети),
RU — `switchToLanguage("ru")`, применяется, когда сеть есть (после XRAY). Переопределение снимается, когда язык
Telegram догнал выбор или пользователь выбрал другой язык в настройках. Порядок: Tr → выбор на вступлении →
язык приложения → язык системы. Цвета обложки — из текущей темы (тема «Рентген» — FEAT-20, не начата).

**«О приложении»** (PAR-21): `Xraygram 0.4`, «Неофициальный клиент Telegram…», мелко «На основе Telegram Desktop
<версия>. Исходный код: github.com/vizacv/xraygram». Ссылка на changelog и FAQ убраны. Версия Xraygram — константа
`Xraygram::kVersion` (политика версий — вопрос оркестратору).
