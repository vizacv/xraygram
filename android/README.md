# Xraygram Android

Основа: Telegram для Android (`DrKLO/Telegram`, **13.2.2**, `21f7d109`), модуль `TMessagesProj_AppStandalone`.
Внутри — ядро Xray (libXray): вставляете `vless://` ссылку, и Телега ходит через встроенный xray
(локальный SOCKS5 на 127.0.0.1). Ставится рядом с официальным Telegram (`io.github.xraygram`).

База знаний этой системы (ведёт тема «Android»):

- [research.md](research.md) — код Telegram Android и libXray: где прокси, как собирается, API libXray, звонки.
- [decisions.md](decisions.md) — решения и почему (xray в процессе, один xray на все записи, UX, ребрендинг, подпись).
- [patches/0001-xraygram.patch](patches/0001-xraygram.patch) — патч против `21f7d109`;
  [patches/tgcalls/](patches/tgcalls/) — патч сабмодуля tgcalls (звонки через SOCKS5 xray), общий с macOS.
- [scripts/](scripts/) — `build-local.sh` (сборка), `update-patch.sh` (выгрузка патчей), `smoke-emulator.sh`
  (смоук в эмуляторе против тестового сервера), `common.sh`.

## Статус

- [x] Исследование освежено: DrKLO/Telegram 13.2.2 (последний), полный клон с сабмодулями в `upstream/tg-android`
- [x] Способ встраивания: libXray `.aar` в процессе, один xray на все XRAY-записи ([decisions.md](decisions.md))
- [x] `ProxySettings.Type.XRAY`, ветки в `ConnectionsManager` (init / setProxySettings / checkProxy)
- [x] UI: тип «XRAY (VLESS)» первым, одно поле ссылки, подстановка из буфера, превью сервера, проверка ссылки xray'ем
- [x] Список: `XRAY · <имя>`, несколько записей, пинг у каждой; QR ссылки; открытие `vless://` ссылок
- [x] Ребрендинг: Xraygram, `io.github.xraygram`, без обновлений upstream, свои api_id/api_hash
- [x] Скрипты локальной сборки (deps → src → libxray → keystore → apk), подпись своим ключом из `.secrets/`
- [x] APK собран (arm64-v8a, 51 МБ, подпись своим ключом)
- [x] Эмулятор (Pixel 7, Android 16, arm64) против тестового VLESS/Reality-сервера на Маке (2026-11-18):
      запуск; `vless://` → окно «Прокси-сервер» `XRAY · vless · host:port · имя`; «Подключить» → через ~3 с
      соединения к DC Telegram идут только через встроенный xray (SOCKS `127.0.0.1:<порт>` → Reality → сервер),
      прямых соединений нет; список прокси «XRAY · mac-plain — Подключено, пинг 257 мс»; холодный старт с
      сохранённой записью — через xray за ~1 с
- [x] Экран «Подключение через XRAY» (MAC-05): при пустом списке — ни одного сокета наружу за 30 с; ссылка в поле →
      превью «✓» → «Подключить» → через xray; удаление последней XRAY-записи → предупреждение → экран с
      «Сохранёнными серверами», наружу только отказ на `127.0.0.1:1`; «Напрямую» с подтверждением → прямое соединение,
      флаг сохраняется; новое добавление XRAY сбрасывает флаг
- [x] FCM выключен: в `android-20261118-1/-2` было соединение с Google (Firebase token) мимо xray, в `-3` нет
- [x] Смоук `smoke-emulator.sh` на `android-20261118-3`: GATE / XRAY (Reality) / COLD / без крэшей — всё PASS
- [x] Звонки: патч tgcalls перенесён, личный звонок с XRAY-записью идёт через SOCKS5 xray (только TCP-relay)
- [x] `android-20261119-1`: FEAT-09 ред. 2 (FCM на проекте владельца из `.secrets/google-services.json`, запасной
      путь), PAR-04/05/06a/08/09/10/13/15/16, тексты по спекам FEAT-01…04, BUG-13; смоук — PASS
- [x] F07-04: `crunchPngs false` для `standalone` — PNG иконок в APK как в `branding/`
- [x] FEAT-19 (PAR-17…21, сборка после `android-20261119-1`): имя во всех языках, заставка и своё вступление в цветах
      «Рентген», порядок «вступление → Начать → экран XRAY → номер», без логотипа Telegram (заголовок чатов, QR,
      шторка — пока заглушка), подмена «Telegram» по списку ключей, «О приложении». Подробно — [decisions.md](decisions.md),
      инвентаризация — [rebrand-inventory.md](rebrand-inventory.md)
- [ ] Монохромный силуэт для шторки уведомлений (готовит оркестратор) — сейчас заглушка
- [ ] Регистрация FCM-токена в Telegram, живой пуш при закрытом приложении (нужен аккаунт)
- [ ] Звонок вживую (нужны два аккаунта) — не проверен
- [x] Групповые звонки/видеочаты/конференции — диалог «Без XRAY» перед входом (RTMP — без диалога)
- [ ] Телефон: вход в аккаунт через реальный сервер владельца
- [ ] FEAT-20: тема «Рентген» по умолчанию и значок статуса XRAY над чатами
- [ ] CI (GitHub Actions) — по образцу macOS, по запросу оркестратора

## Как поставить на телефон

1. Скопировать APK на телефон (`upstream/android-work/dist/Xraygram-13.2.2-arm64-v8a-<дата-время>.apk`, самый
   свежий — `Xraygram-latest.apk`; старые файлы не перезаписываются) — через AirDrop нельзя,
   удобно: отправить себе в «Избранное» официального Telegram, скачать на телефоне и открыть; или по USB:

   ```bash
   android/scripts/build-local.sh install
   ```

   (нужна «Отладка по USB» в «Для разработчиков»).
2. При установке из файла Android попросит разрешить установку из этого источника — разрешить.
   Play Protect может предупредить о неизвестном разработчике — «Всё равно установить».
3. Открыть Xraygram. Первым откроется экран **«Подключение через XRAY»**: пока ссылки нет, приложение никуда не
   подключается. Если `vless://` ссылка скопирована — она уже в поле, под ним «Сервер: vless · host:port · имя ✓».
   **Подключить**. (Внизу есть неприметное «Подключиться без XRAY (напрямую)» с подтверждением — на случай, если
   сервер умер.) Дальше — обычный вход по номеру.
   Добавить ещё серверы: Настройки → Данные и память → Прокси → **Добавить прокси** — тип **XRAY (VLESS)** выбран,
   ссылка из буфера подставится.
4. В списке прокси запись выглядит как `XRAY · <имя>` со статусом «Подключено, пинг N мс». Записей может быть
   несколько, переключение — тапом, как у обычных прокси.

Ссылку можно и просто открыть (тап по `vless://...` в браузере/заметках/чате) — Xraygram покажет окно
«Подключить прокси?».

### Уведомления в фоне

Пуши Firebase в форке не работают (ключи привязаны к официальному приложению) и выключены совсем, чтобы не было трафика в Google мимо xray. Чтобы приходили уведомления:
Настройки → Уведомления и звуки → внизу включить **Keep-Alive Service** («перезапускать приложение») и
**Background Connection** («фоновое соединение»), и разрешить Xraygram работать в фоне без ограничений (Настройки Android → Приложения → Xraygram → Батарея → «Без ограничений»).
Xray живёт внутри процесса приложения: пока процесс жив, жив и прокси.

## Локальная сборка

Всё рабочее — в `upstream/` (не в git):

| Что | Где |
|---|---|
| исходники Telegram + сабмодули, ветка `xraygram` с патчем | `upstream/tg-android` |
| libXray (исходники) | `upstream/libxray` |
| Android SDK / NDK / CMake / эмулятор | `upstream/android-work/sdk` |
| Gradle (`GRADLE_USER_HOME`), кэши Go, gomobile | `upstream/android-work/gradle`, `upstream/android-work/go` |
| `libXray.aar` | `upstream/android-work/libxray` |
| готовые APK (+ `.sha256`, `Xraygram-latest.apk`) | `upstream/android-work/dist` |
| логи шагов | `upstream/android-work/logs` |
| AVD, `ANDROID_USER_HOME` | `upstream/android-work/avd`, `upstream/android-work/android-user` |
| тестовый VLESS/Reality-сервер для эмулятора (xray-core 26.11.9, только `127.0.0.1:10086` plain и `:10443` Reality; эмулятор видит Мак как `10.0.2.2`; ссылки `link-*.txt`) | `upstream/android-work/testserver` |

Секреты (в `.gitignore`, права 0600): `.secrets/api.env` (`TDESKTOP_API_ID`, `TDESKTOP_API_HASH` — те же, что для
macOS), `.secrets/android-release.jks` + `.secrets/android-keystore.env` (ключ подписи; создаётся при первой сборке,
**его нужно сохранить** — без него новые сборки не встанут поверх старой).

Команды (из корня репозитория):

```bash
android/scripts/build-local.sh            # всё: deps → src → libxray → keystore → apk
```

```bash
android/scripts/build-local.sh quick      # после правки Java в upstream/tg-android: инкрементальная пересборка APK
```

```bash
android/scripts/build-local.sh install run   # поставить на телефон/эмулятор и запустить
```

```bash
android/scripts/build-local.sh emulator   # создать (1 раз) и запустить эмулятор Pixel 7, Android 16, arm64
```

```bash
android/scripts/build-local.sh status
```

Смоук в эмуляторе (держит очередь: на перегруженном Маке эмулятор зависает, ANR system_server):

```bash
tools/heavy-build.sh android android/scripts/smoke-emulator.sh reality
```

Поиск кнопки через `uiautomator dump` на Android 16 может зависать — тогда жать по координатам (`adb shell input tap`).

Тяжёлые шаги (`libxray`, `apk`) идут через очередь `tools/heavy-build.sh android ...` (на Маке параллельно собирает
iOS-тема). `quick` идёт без очереди.

**Не правьте `android/scripts/*.sh`, пока идёт сборка:** bash дочитывает скрипт на ходу и после правки продолжает
не с того места (так один раз обёртка «ушла» в `step_emulator` и повисла на `adb wait-for-device`).

Правки патча: меняем файлы в `upstream/tg-android`, потом

```bash
android/scripts/update-patch.sh
```

Он выгружает `git diff` против `21f7d109` в `patches/0001-xraygram.patch` и проверяет, что патч чисто применяется.

Время на MacBook Air M5 (10 ядер, 16 ГБ), 2026-11-18:

| Шаг | Время |
|---|---|
| клон Telegram + сабмодули `--depth 1` | 4 мин 10 с (3,4 ГБ) |
| Android SDK/NDK/CMake | ~3 мин (загрузка) |
| `libXray.aar` (arm64) | 42 с |
| загрузка образа эмулятора (4,3 ГБ) | 4 мин |
| APK с нуля (вкл. загрузку Gradle 8.13 и зависимостей, нативная часть arm64) | **22 мин 51 с** |
| APK после правки Java (R8 заново) | 3 мин 50 с – 6 мин 20 с |
| запуск эмулятора | ~50 с |
