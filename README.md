# Xraygram

Форки Telegram со встроенным ядром Xray (VLESS+Reality и др.): клиент сам поднимает xray
с локальным SOCKS5 и ходит через него. MTProto-прокси у нас не работают почти год.

## Как устроена работа

- **Оркестратор** — главная тема (сессия) в `~/xraygram`. Там общаемся, ищем, проверяем,
  ставим задачи и принимаем результаты. Ведёт `docs/`.
- **Системные темы** — по одной на платформу. Каждая работает только в своей папке
  и ведёт там свою базу знаний (`<система>/README.md` + заметки).
- **Регламент (роли, поток, реестры): [docs/process.md](docs/process.md).**
- Бэклог: [docs/backlog.md](docs/backlog.md) · баги: [docs/bugs.md](docs/bugs.md) · сборки: [docs/builds.md](docs/builds.md).
- Реестр тем: [docs/orchestration.md](docs/orchestration.md).
- Решения: [docs/decisions.md](docs/decisions.md).

## Системы

| Папка | Основа | Статус |
|---|---|---|
| [macos/](macos/) | Telegram Desktop (`telegramdesktop/tdesktop`) | **работает** (проверено владельцем): тип прокси XRAY (VLESS), локальная сборка |
| [ios/](ios/) | `TelegramMessenger/Telegram-iOS` | в работе: тест на iPhone друга (бесплатный Apple ID) |
| [android/](android/) | `DrKLO/Telegram` | в работе: локальная сборка APK |
| [testing/](testing/) | — | QA: тест-планы, автосмоук, отчёты |
| [product/](product/) | — | продукт: спецификации фич, паритет платформ |

## Общее

- `upstream/` — локальные клоны исходников для чтения кода (в git не коммитятся).
- **Место на диске:** `upstream/` не больше 30 ГБ — только исходники, инструменты и последняя сборка каждой платформы. Кэши и старые сборки чистит `tools/cleanup.sh` после выдачи сборок (`tools/cleanup.sh size` — текущий размер). Правило — `docs/orchestration.md`.
- Ядро: [XTLS/libXray](https://github.com/XTLS/libXray) (`Invoke` API, см. [android/research.md](android/research.md#api-libxray-invoke)).
- Сборки — локально на Маке по очереди (`tools/heavy-build.sh`); CI — эталонные сборки по кнопке.
