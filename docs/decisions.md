# Решения

- **2026-11-18** — xray встраиваем как локальный SOCKS5 (in-process или дочерний процесс),
  сетевой код Telegram не переписываем. Причина: MTProto/mtg не работает ~год, нужен VLESS+Reality.
- **2026-11-18** — сборки только в GitHub Actions: на Mac нет Go/Java/Gradle/Xcode, а нативная часть Telegram тяжёлая.
- **2026-11-18** — первый тестовый вариант: **macOS, Telegram Desktop (tdesktop)**, arm64 (Apple Silicon).
  Почему не нативный Swift-клиент (`overtake/TelegramSwift`): у tdesktop есть рабочий upstream CI для macOS
  и тот же форк потом даёт Windows/Linux; сборка TelegramSwift под Xcode 26 сейчас сломана, CI нет.
- **2026-11-18** — Android на паузе; материалы в `android/`.
