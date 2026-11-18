# Xraygram macOS

Основа: Telegram Desktop (`telegramdesktop/tdesktop`). Цель первого этапа: тестовая сборка
под Apple Silicon (arm64), в которой можно вставить `vless://` ссылку и Телега ходит через встроенный xray.

База знаний этой системы ведётся здесь (ведёт тема «Xraygram macOS»).

## Статус

- [ ] Исследование tdesktop: прокси-код, сборка macOS, upstream CI
- [ ] Способ встраивания xray (дочерний процесс xray vs libXray c-shared)
- [ ] Патчи
- [ ] GitHub Actions workflow
- [ ] Тест на MacBook Air M5
