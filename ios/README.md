# Xraygram iOS

Основа: Telegram-iOS (`TelegramMessenger/Telegram-iOS`, master `24638bc6`, версия 13.2). Цель: тестовая сборка для
iPhone со встроенным xray (VLESS+Reality и др.), которую можно поставить на iPhone друга с **бесплатного Apple ID**.

База знаний этой системы ведётся здесь (тема «Xraygram iOS»).

- [research.md](research.md) — сборка Telegram-iOS, бесплатная подпись, прокси-код, звонки, xray внутри процесса.
- [decisions.md](decisions.md) — принятые решения и почему.
- [patches/](patches/) — патч против Telegram-iOS `24638bc6` и `patches/tgcalls/` — звонки через SOCKS5 (перенос
  `macos/patches/tgcalls`, база tgcalls `c1de0882`).
- [xraykit/](xraykit/) — переиспользуемое ядро: `go/` (XraygramCore, Go c-archive на libXray + Xray-core) и
  `swift/XraygramKit` (Swift-обёртка, только Foundation — пригодится и для Swift-клиента macOS).
- [scripts/](scripts/) — сборка (`build.sh`, `build-core.sh`, `signing-stub.sh`, `update-patch.sh`, `common.sh`).

## Статус

- [x] Исследование: сборка (Bazel/Make.py, Xcode 27.2 через `--overrideXcodeVersion`), конфигурация, бесплатная подпись
- [x] Исследование: прокси-код TelegramCore/MtProtoKit, UI, ссылки `tg://socks`, звонки (tgcalls → SOCKS5/TCP)
- [x] Ядро `XraygramCore.xcframework` (iOS, симулятор, macOS arm64) — собирается за ~30 с; C API проверен на macOS:
      разбор ссылки, SOCKS5 с паролем, несколько экземпляров, остановка
- [x] `XraygramKit` (Swift): проверен на macOS — старт/порт/перезапуск после простоя на том же порту
- [x] Патч: тип `.xray(link:)`, сеть через локальный SOCKS5, UI «XRAY (VLESS)», `XRAY · имя` в списке,
      звонки, возврат из фона, ребрендинг, Make.py без расширений/push, кнопка «Прокси» на экране входа
- [x] Сборка для симулятора (`debug_sim_arm64`): первая — 15,5 мин, инкрементальная — ~40 с (2026-11-18).
      Go-рантайм только в `TelegramCoreFramework` (проверено `nm`), имя «Xraygram», bundle `io.github.vizacv.xraygram`
- [x] Проверено в симуляторе (iOS 27.2) с тестовой ссылкой (выдуманный сервер): экран входа → «Прокси» → Add Proxy →
      «XRAY (VLESS)» → вставка ссылки → превью `Сервер: vless · example.com:443 · Test NL` → Готово →
      в списке `XRAY · Test NL`, активна, «connecting»; xray слушает 127.0.0.1:<порт> внутри приложения,
      SOCKS5 без пароля и с чужим паролем отклоняет; после фона порт тот же; при холодном старте xray поднимается сам
- [x] Компиляция и линковка для iPhone (`debug_arm64`, без профиля — `build.sh device-check`): 13,6 мин,
      `TelegramCoreFramework` arm64 iOS с ядром собран (2026-11-18). Само `.app` для устройства — после профиля
- [x] **Экран «Подключение через XRAY»** (правила — `macos/decisions.md`, «Экран XRAY»): пока нет XRAY-записей и не
      выбрано «напрямую», MTProto идёт в «чёрную дыру» `127.0.0.1:1`, поиск запасных адресов (DoH и прямые IP)
      выключен. Проверено в симуляторе: первый запуск → экран поверх входа, смахнуть нельзя; вставка ссылки →
      «Подключить» → экран закрылся, MTProto через xray; удаление последней XRAY-записи → подтверждение → экран снова,
      с выбором сохранённого сервера и «Новая ссылка»; «Подключиться без XRAY» → подтверждение → напрямую (2026-11-18)
- [x] Звонки: перенесён патч tgcalls (SOCKS5 к TCP-ретрансляторам, только relay); при XRAY прокси в звонке всегда,
      P2P выключен, версии звонков — только 7–13 (те, что идут через патч). Компилируется; живьём не проверено
- [x] Сборка `ios-20261118-2` (2026-11-18 19:11): выравнивание по спекам продукта — PAR-09 «Без XRAY», PAR-01/02/03
      тексты RU/EN и понятные ошибки, PAR-07, PAR-05, PAR-04 «Поделиться сервером», PAR-14 иконка; BUG-12/13/14;
      SOCKS5 к IPv6-адресам DC. Проверено в симуляторе (кроме «Без XRAY» — нужен вход); arm64 для iPhone компилируется
- [x] Сборка `ios-20261119-1` (2026-11-19 01:40): PAR-15 «Без XRAY» перед переходом звонка 1:1 в конференцию (добавить участника,
      ссылка, приглашение, перевод собеседником); RTMP-трансляции без диалога; PAR-16 текст первого экрана; новая
      иконка (обезьянка); подсказка у поля ссылки про кнопку «Вставить»
- [x] Для QA: XRAY-запись без UI в симуляторе — `SIMCTL_CHILD_XRAYGRAM_ADD_LINK='vless://…' xcrun simctl launch …`
- [ ] Проверка с реальным сервером и входом в аккаунт (нужна рабочая ссылка владельца; в симуляторе или на iPhone)
- [ ] Подпись бесплатным Apple ID (нужен владелец: Apple ID в Xcode, iPhone по кабелю, Developer Mode)
- [ ] Сборка для iPhone и установка

## Как собрать (на этом Маке)

Всё рабочее лежит в `upstream/` (не в git): исходники `upstream/telegram-ios` (ветка `xraygram`),
сборка/кэши/результаты — `upstream/xraygram-ios/` (`bazel-root`, `bazel-cache`, `go`, `logs`, `dist`, `signing`).
Xcode берётся из `/Applications/Xcode.app` через `DEVELOPER_DIR`, `xcode-select` и sudo не нужны.
Ключи API — `.secrets/api.env` (те же, что для macOS).

**Место на диске** (бюджет `upstream/` — 30 ГБ, `docs/orchestration.md`):
- кэш Bazel ограничен в `Make.py` флагом `--experimental_disk_cache_gc_max_size=8G` (переменная
  `XRAYGRAM_DISK_CACHE_MAX`, `0` — без лимита); чистится, пока сервер Bazel простаивает (1 мин);
- `build.sh snapshot` делает APFS-клон и оставляет в `dist/` новую и предыдущую сборки;
  после вердикта QA — `build.sh prune-dist` (только последняя); `build.sh disk` — размеры;
- первая сборка после чистки кэшей — около часа.

```bash
ios/scripts/build.sh src        # клон Telegram-iOS + сабмодули + патч (один раз, ~1 ГБ)
```

```bash
ios/scripts/build.sh core       # XraygramCore.xcframework (Go)
```

```bash
tools/heavy-build.sh ios ios/scripts/build.sh sim       # сборка для симулятора → dist/Xraygram-sim.app
```

```bash
ios/scripts/build.sh run-sim    # поставить и запустить в симуляторе «Xraygram iPhone»
```

```bash
ios/scripts/build.sh status
```

Первый раз Xcode 27 может потребовать Metal Toolchain (ошибка `missing Metal Toolchain`): ставится без sudo —

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -downloadComponent MetalToolchain
```

(уже поставлен 2026-11-18, 839 МБ). `XRAYGRAM_KEEP_GOING=1` — все ошибки компиляции за один проход.
`build.sh device-check` — сборка для iPhone без профиля (проверка компиляции, ставить нельзя).

**Сборка-кандидат по регламенту** (`docs/process.md`): после удачной сборки снять её под ID и зарегистрировать —

```bash
ios/scripts/build.sh snapshot   # → dist/Xraygram-ios-ГГГГММДД-N-sim.app (и/или .ipa), ID печатается
```

затем строка в `docs/builds.md` (ID, файл, FEAT/BUG) и сообщение QA (`xraygram-tester`). Файл «у владельца» не
перезаписывается: `snapshot` всегда кладёт новую копию с новым ID.

Правки делаем прямо в `upstream/telegram-ios` (Swift-код кита — в `ios/xraykit/swift`), потом:

```bash
ios/scripts/update-patch.sh     # → ios/patches/0001-xraygram-ios.patch + проверка, что патч применяется
```

## Как поставить на iPhone друга (шаги владельца)

Подпись бесплатным Apple ID живёт **7 дней**, потом шаги 4–6 повторить (данные в приложении сохранятся).
Ограничения: нет push-уведомлений (сообщения приходят, пока приложение открыто), входящие звонки не будят
телефон, нет «Поделиться» из других приложений, виджетов и Siri.

1. **Apple ID в Xcode** (один раз): Xcode → Settings… → Accounts → «+» → Apple Account → войти.
   Подойдёт любой Apple ID, платить не нужно; появится команда «<Имя> (Personal Team)».
2. **Подключить iPhone** кабелем к Маку, разблокировать, на вопрос «Доверять этому компьютеру?» — «Доверять».
3. **Developer Mode на iPhone** (один раз, iOS 16+): Настройки → Конфиденциальность и безопасность →
   Режим разработчика → включить → перезагрузка → после неё подтвердить «Включить».
   (Пункт появляется после того, как iPhone хоть раз подключили к Маку с Xcode.)
4. Выпустить профиль (Xcode зарегистрирует bundle id, группу и iPhone в Personal Team):
   ```bash
   ios/scripts/build.sh signing-stub
   ```
   ```bash
   ios/scripts/build.sh signing
   ```
5. Собрать и поставить:
   ```bash
   tools/heavy-build.sh ios ios/scripts/build.sh device
   ```
   ```bash
   ios/scripts/build.sh install
   ```
6. На iPhone при первом запуске: Настройки → Основные → VPN и управление устройством → «Apple Development: <Apple ID>» →
   «Доверять».

Дальше в Xraygram: при первом запуске сразу открывается экран **«Подключение через XRAY»** (пока ссылки нет,
приложение никуда не подключается). Скопировать ссылку `vless://…` (например, из сообщения) → «Вставить ссылку из
буфера» (iOS спросит разрешение на вставку — «Разрешить») или долгое нажатие в поле → «Вставить» → под полем
«Сервер: vless · …» → **«Подключить»**. Экран закроется, дальше — обычный вход по номеру телефона.
Ещё серверы: Настройки → Данные и память → Прокси (до входа — кнопка «Прокси» на экране ввода номера).

На iOS 27 приложение не может само прочитать буфер при открытии экрана (система молча отказывает), поэтому
ссылка не подставляется автоматически, как на macOS, — нужна кнопка или «Вставить».
