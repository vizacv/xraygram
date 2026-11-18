# Тестирование Xraygram (QA)

Регламент: [docs/process.md](../docs/process.md). Реестры: [docs/builds.md](../docs/builds.md) (вердикты QA),
[docs/bugs.md](../docs/bugs.md) (баги, ведёт QA). Общий чек-лист: [plan.md](plan.md).

## Как проверяется сборка

1. Платформа регистрирует сборку в `docs/builds.md` и пишет QA: ID, путь, что изменилось.
2. QA гоняет смоук платформы (тяжёлые — через очередь `tools/heavy-build.sh qa ...`):

   ```bash
   testing/scripts/smoke-macos.sh -a upstream/xraygram-local/dist/Xraygram-macos-<ID>.app -b macos-<ID>
   ```

   ```bash
   tools/heavy-build.sh qa testing/scripts/smoke-android.sh -a upstream/android-work/dist/Xraygram-android-<ID>.apk
   ```

   ```bash
   tools/heavy-build.sh qa testing/scripts/smoke-ios.sh -a upstream/xraygram-ios/dist/Xraygram-ios-<ID>-sim.app -b ios-<ID>
   ```

3. Плюс критерии приёмки затронутых FEAT (спеки `product/features/FEAT-NN.md`), что можно проверить без рук.
4. Вердикт в `docs/builds.md`: ✅ / ⚠️ (с ограничениями) / ❌. Новые баги — в `docs/bugs.md`. Коротко — оркестратору.

Результаты: `testing/results/<ID>/smoke-<платформа>.txt` (+ скриншоты). Секретов там нет: ссылки и пароли не
печатаются. Ссылка тестового сервера — только локальная (127.0.0.1).

## Скрипты

| Скрипт | Что делает |
|---|---|
| `scripts/smoke-macos.sh` | бандл, `xraygram-core` отдельно, FEAT-03 (экран XRAY без сети), подключение через тестовый сервер, падение core, Cmd+Q, система до/после. Запуск через `open -g` с отдельным `-workdir`, чужой Xraygram не трогает |
| `scripts/smoke-android.sh` | статика APK (id, подпись, разрешения, схемы, libXray, строки FEAT-03) + эмуляторный набор Android-темы `android/scripts/smoke-emulator.sh` (GATE → XRAY → COLD) |
| `scripts/smoke-ios.sh` | бандл, своё устройство «Xraygram QA», чистая установка, FEAT-03: 20 с без соединений, скриншот |
| `scripts/net-watch.sh` | слежка за сетью Xraygram на Маке: утечки, UDP, WebView |
| `scripts/sys-check.sh` | снимок влияния на систему (прокси, туннели, автозапуск, процессы, порты) |

Тестовый сервер VLESS/Reality — `upstream/android-work/testserver` (Android-тема): 127.0.0.1:10443 Reality,
:10086 plain. Если не запущен, смоуки поднимают его сами и гасят после.

## Ограничения автоматики

- Живые звонки, вход в аккаунт, реальный VPS, сон/смена сети — только руками ([macos-manual.md](macos-manual.md)).
- macOS: смоук запускает тихую QA-копию `<app>-QA.app` (bundle id `*.qa`, без Dock и окна, `macos/scripts/run-qa.sh`;
  сделать копию — `macos/scripts/make-qa-app.sh <app>`). Кнопки в ней не нажать, поэтому UI-шаги остаются ручными.
- iOS: в симуляторе кнопка «Вставить из буфера» не работает (iOS 27), а набор текста теряет символы. Путь «подключено» проходится вручную инструментом симулятора: `simctl pbcopy` ссылки → долгое нажатие в поле → Paste → «Подключить». Проверка сети — `lsof` по PID процесса симулятора (не по имени «Telegram»: рядом Telegram Desktop владельца) и логи `<AppGroup>/telegram-data/logs/app-logs/` (`via 127.0.0.1:…`).
