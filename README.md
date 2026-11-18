# Xraygram

Форки Telegram со встроенным ядром Xray (VLESS+Reality и др.): клиент сам поднимает xray
с локальным SOCKS5 и ходит через него. MTProto-прокси у нас не работают почти год.

## Как устроена работа

- **Оркестратор** — главная тема (сессия) в `~/xraygram`. Там общаемся, ищем, проверяем,
  ставим задачи и принимаем результаты. Ведёт `docs/`.
- **Системные темы** — по одной на платформу. Каждая работает только в своей папке
  и ведёт там свою базу знаний (`<система>/README.md` + заметки).
- Реестр тем и правила: [docs/orchestration.md](docs/orchestration.md).
- Решения: [docs/decisions.md](docs/decisions.md).

## Системы

| Папка | Основа | Статус |
|---|---|---|
| [macos/](macos/) | Telegram Desktop (`telegramdesktop/tdesktop`) | **работает** (проверено владельцем): тип прокси XRAY (VLESS), локальная сборка |
| [ios/](ios/) | `TelegramMessenger/Telegram-iOS` | в работе: тест на iPhone друга (бесплатный Apple ID) |
| [android/](android/) | `DrKLO/Telegram` | в работе: локальная сборка APK |
| [testing/](testing/) | — | тест-планы и отчёты по всем платформам |

## Общее

- `upstream/` — локальные клоны исходников для чтения кода (в git не коммитятся).
- Ядро: [XTLS/libXray](https://github.com/XTLS/libXray) (`Invoke` API, см. [android/research.md](android/research.md#api-libxray-invoke)).
- Сборки — в GitHub Actions, публикация в GitHub-репозиторий проекта.
