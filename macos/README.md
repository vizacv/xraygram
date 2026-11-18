# Xraygram macOS

Основа: Telegram Desktop (`telegramdesktop/tdesktop`, тег **v7.4.4**). Цель первого этапа: тестовая сборка
под Apple Silicon (arm64), в которой можно вставить `vless://` ссылку и Телега ходит через встроенный xray.

База знаний этой системы ведётся здесь (ведёт тема «Xraygram macOS»).

- [research.md](research.md) — что нашли в tdesktop и libXray: прокси-код, сборка, api_id, как устроен патч.
- [decisions.md](decisions.md) — принятые решения и почему.
- [patches/](patches/) — патч против tdesktop `v7.4.4`.
- [core/](core/) — Go-помощник `xraygram-core` (libXray `share` + `xray`), кладётся в `Xraygram.app/Contents/MacOS/`.
- [build-macos.yml](../.github/workflows/build-macos.yml) — GitHub Actions workflow (лежит в `.github/workflows/`).

## Статус

- [x] Исследование tdesktop: прокси-код, сборка macOS, upstream CI, api_id
- [x] Способ встраивания xray: дочерний процесс `xraygram-core` (Go, libXray), SOCKS5 на 127.0.0.1
- [x] Патчи (`patches/0001-xraygram-xray-socks.patch`, чисто применяется к `v7.4.4`)
- [x] GitHub Actions workflow (`.github/workflows/build-macos.yml`)
- [ ] Секреты api_id/api_hash; первый прогон CI (запущен без секретов, на тестовых ключах)
- [ ] Исправить ошибки компиляции по итогам CI (локально не собирали)
- [ ] Тест на MacBook Air M5 (macOS 26.7) с реальной `vless://` ссылкой

## Как собрать (CI)

1. Workflow: `.github/workflows/build-macos.yml` (каноничная копия, правится там).
2. Секреты репозитория: `TDESKTOP_API_ID`, `TDESKTOP_API_HASH` (свои, с https://my.telegram.org).
   Без них сборка пройдёт на тестовых ключах upstream, но войти в аккаунт, скорее всего, не получится.
3. Actions → «Xraygram macOS» → Run workflow (Release по умолчанию).
4. Артефакт `Xraygram-macos-arm64` → `Xraygram-v7.4.4-<sha>-macos-arm64.dmg` (+ `.sha256`).

Задания: `core` (ubuntu, ~3 мин: собирает `xraygram-core` для darwin/arm64 и гоняет smoke-тест на Linux),
`macos` (macos-latest: brew-зависимости, tg_owt/tde2e/rnnoise/Rust с кэшем, tdesktop + патч, `macdeployqt`,
сборка бандла, ad-hoc подпись, DMG). Первый прогон — ориентировочно 1,5–2,5 ч, повторные ~1 ч.

## Как запускать на Mac

```bash
xattr -dr com.apple.quarantine /Applications/Xraygram.app
```

Дальше: Настройки → Продвинутые → Тип соединения (или значок прокси на экране входа) → «⋮» → «Xray: ссылка vless://»
→ вставить ссылку → «Сохранить и подключить». В списке появится запись `127.0.0.1:<порт> XRAY`.

Данные: `~/Library/Application Support/Xraygram/` (официальный Telegram не затрагивается).
Ссылка хранится в `tdata/xraygram.json` (права 0600). Логи xray — в `DebugLogs` при включённом debug-логе Телеги.

Обновление патча после правок в `upstream/tdesktop` (ветка `xraygram`):

```bash
cd ~/xraygram/upstream/tdesktop && git add -A && git diff --cached --binary v7.4.4 > ../../macos/patches/0001-xraygram-xray-socks.patch
```
