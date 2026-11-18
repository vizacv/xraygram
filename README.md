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
| [macos/](macos/) | Telegram Desktop (`telegramdesktop/tdesktop`) | **в работе:** тестовая сборка под Apple Silicon |
| [android/](android/) | `DrKLO/Telegram` | исследование готово, есть черновик `XrayTransport.java`; на паузе |

## Общее

- `upstream/` — локальные клоны исходников для чтения кода (в git не коммитятся).
- Ядро: [XTLS/libXray](https://github.com/XTLS/libXray) (`Invoke` API, см. [android/research.md](android/research.md#api-libxray-invoke)).
- Сборки — в GitHub Actions, публикация в GitHub-репозиторий проекта.
