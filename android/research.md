# Исследование: встраивание Xray в Telegram Android

Начато в сессии «Пересборка Telegram с ядром Xray», обновлено системной темой Android 2026-11-18.

## Исходники

| Репозиторий | Версия | Где лежит локально |
|---|---|---|
| `DrKLO/Telegram` | `21f7d109` — 13.2.2 (7303), 2026-11-12 (= `master` на 2026-11-18, тегов нет) | `upstream/tg-android` — полный клон, сабмодули `--depth 1` (3,4 ГБ), ветка `xraygram` с нашими правками |
| `XTLS/libXray` | `5a0f7d8`, тег `v26.11.9` (Go-модуль `v1.261109.0`), xray-core `v1.260327.1-…676eaf66f8f0` (Xray 26.11.9) | `upstream/libxray` (shallow) |

`upstream/tg` — старый sparse-клон для чтения, больше не нужен.

## Почему не MTProto

MTProto-прокси (`mtg`, fake-TLS) у владельца не работает почти год, нужен VLESS+Reality через xray.

## Архитектура (реализовано)

Сетевой код Телеги (tgnet, C++) не трогаем:

1. libXray собирается `gomobile bind` в `libXray.aar` → `libXray.LibXray.invoke(String json)`.
2. `org.telegram.utils.proxy.XrayTransport` держит **один** xray в процессе. Конфиг — из всех XRAY-записей списка:
   на каждую ссылку inbound `socks` `127.0.0.1:<порт>` (логин `xraygram` + случайный пароль) и свой outbound,
   маршрут `inboundTag → outboundTag`.
3. tgnet получает обычный SOCKS5 `127.0.0.1:<порт>` с логином/паролем через `native_setProxySettings`
   (`secret = ""`, иначе tgnet решит, что это MTProto).

Почему так, а не отдельным процессом — [decisions.md](decisions.md).

## Ключевые места в коде Telegram (13.2.2)

Пути относительно `TMessagesProj/src/main/java/org/telegram/`.

- `utils/proxy/ProxySettings.java` (540 строк) — модель прокси, `enum Type { SOCKS5, MTPROTO, WEB }`,
  `typeToInt/intToType` (0/1/2, неизвестное → SOCKS5), `fromUri` (t.me/tg:// ссылки), `toSharedPreferences`
  (`proxy_type/ip/port/user/pass/secret` в `mainconfig`). Тип `WEB` = MTProto поверх WebSocket через локальный
  порт (`WebProxyTransport`) — шаблон для XRAY.
- `tgnet/ConnectionsManager.java`:
  - `init(...)` (~строка 673): текущий прокси из `mainconfig` → `native_setProxySettings`; для `WEB` — локальный порт.
  - `checkProxy(settings, delegate)` (~777): `WEB` → `WebProxyConnectionTester`, иначе `native_checkProxy`
    (MTProto-пинг через прокси). Делегат: `-1` = недоступен, иначе пинг в мс.
  - `static setProxySettings(enabled, settings)` (~989): включение/смена прокси для всех аккаунтов.
- `messenger/SharedConfig.java`: `ProxyInfo` (~380), сериализация списка (`PROXY_SCHEMA_V3` пишет тип числом),
  `loadProxyList` / `saveProxyList` / `addProxy` / `deleteProxy` (~1442–1560), `currentProxy`.
- `ui/ProxySettingsActivity.java` (927 строк) — экран добавления: `typeCell[]` (RadioCell), `inputFields[5]`,
  «Вставить из буфера» (`updatePasteCell` → `ProxySettings.fromUri`), «Поделиться» (QR), `setProxyType` прячет поля.
- `ui/ProxyListActivity.java` — подпись строки (~196), `checkProxyList` (~689, пинг раз в 2 мин).
- `messenger/AndroidUtilities.java` — `handleProxyIntent` (~4682) / `showProxyAlert` (~4731): окно «Подключить прокси?».
- `ui/LaunchActivity.java` — `handleIntent` → `handleProxyIntent` (~1560); `checkAppUpdate` (~6120).
- `messenger/ProxyRotationController.java` — ротация прокси, тоже через `checkProxy`.
- `messenger/MessagesController.java:10905` — `proxy_secret` читается только для локального сравнения promo-канала.
- `messenger/BuildVars.java` — `APP_ID=4`/`APP_HASH` официального клиента, `CHECK_UPDATES`, `SAFETYNET_KEY`,
  `SUPPORTS_PASSKEYS/FPNV`, `IS_BILLING_UNAVAILABLE`.
- `messenger/LocaleController.java` — `getStringV2` (~4783): облачные строки поверх ресурсов.
- `ui/IntroActivity.java:159` — заголовок первой страницы: строка `Page1Title` с картинкой-логотипом (`telegram_logo`) поверх.
- Нативный tgnet (`jni/tgnet/ConnectionsManager.cpp:701`): DoH/backup-адреса (`onRequestNewServerIpAndPort`)
  запрашиваются только без прокси (или при TLS-hash mismatch у MTProto-прокси с секретом).

### Звонки

- `messenger/voip/VoIPService.java:3630` — `Instance.makeInstance(..., endpoints, null /* proxy */, ...)`:
  прокси для звонков не передаётся вовсе. `Instance.Proxy(host, port, login, password)` и JNI
  (`jni/voip/org_telegram_messenger_voip_Instance.cpp:992`) поддержку сохранили.
- tgcalls v1 (`tgcalls/NetworkManager.cpp:143`) ставит `rtc::ProxyInfo` SOCKS5 в port allocator.
- tgcalls v2 (`tgcalls/v2/NativeNetworkingImpl.cpp:596`) при наличии прокси только выключает UDP/STUN
  (остаётся TURN по TCP), SOCKS не подключает; в встроенном webrtc нет `AsyncSocksProxySocket`.
- Сабмодуль `TMessagesProj/jni/tgcalls` — `545f5ae`. Патч macOS (`0001-socks5-tcp-relay.patch`) лёг на него, кроме
  куска с логом в `InstanceV2ReferenceImpl.cpp`; SOCKS5-адаптер самодостаточен (в `jni/voip/webrtc` его нет).
  Перенос и Java-часть — decisions.md.

## Сборка Telegram

- Gradle wrapper 8.13, AGP `8.13.2`, Kotlin `2.1.0`, JDK 17, `compileSdk 36`, `buildTools 36.0.0`,
  `ndkVersion 27.2.12479018`, CMake `3.22.1`, `minSdk 23`.
- Модули: `TMessagesProj` (библиотека + вся нативная часть через CMake: `tmessages.49`, `twidget`),
  `TMessagesProj_App`, `_AppStandalone`, `_AppHuawei`, `_AppHockeyApp`, `_AppTests`, `TMessagesProj_Modules/media`
  (media3), `jlatexmath`.
- `TMessagesProj_AppStandalone`: `applicationId = APP_PACKAGE` (+ суффикс `.web` у upstream), вариант `afat`
  (4 ABI), `standalone` (R8 + shrinkResources), `useLegacyPackaging = true`, `localeFilters "zz"`,
  подпись — `TMessagesProj/config/release.keystore` (пароль `android`), APK → `build/outputs/apk/afat/standalone/app.apk`.
- `google-services` плагин требует клиента с нужным `package_name` в `google-services.json` модуля.
- Сабмодули `TMessagesProj/jni/...`: td, tgcalls, absl, boost-regex, boringssl, dav1d, ffmpeg, libvpx, libyuv,
  openh264, wamr, xiph (ogg/opus/opusfile), libprisma, tlottie, twidget (+widget-sandbox), wallet-engine;
  `TMessagesProj/lib/jlatexmath`, `TMessagesProj_Modules/media`.
- Требования Telegram к форкам: не называть «Telegram», не использовать их логотип, свои api_id, код открыт (GPL).

## Сборка libXray

- `build/app/android.py`: `gomobile bind -target android -androidapi $LIBXRAY_ANDROID_API -trimpath
  -ldflags="-checklinkname=0 -s -w -buildid= -extldflags=-Wl,-z,max-page-size=16384,<relocs>"`.
  gomobile — версия `golang.org/x/mobile` из `go.mod` libXray (`v0.0.0-20261011034528-197770444867`).
- Мы собираем то же, но `-target android/arm64` (только нужные ABI) и `-androidapi 23` (+ `--pack-dyn-relocs=android`).
  Результат: `libXray.aar` 12 МБ (arm64), 42 с на M5.
- Go 1.27.4 из Homebrew (libXray требует ≥ 1.27.3). NDK — тот же 27.2, что у Телеги.

## API libXray (Invoke)

`LibXray.invoke(json)` → `{"success": bool, "data": ..., "error": "..."}`. Запрос:
`{"apiVersion": 3, "method": "<name>", "payload": {...}}`.

| method | payload | data |
|---|---|---|
| `convertShareLinksToXrayJson` | `{"text": "<ссылки>"}` | xray JSON с `outbounds` (tag = имя из `#`) |
| `runXray` | `{"xrayJson": "<config string>"}` | — (`xray is already running`, если уже запущен) |
| `stopXray` | — | — |
| `getXrayState` | — | `{"running": bool}` |
| `xrayVersion` | — | `{"version": ...}` |
| `testXray`, `pingBatch`, `getFreePorts`, `decodeSubscriptionText`, ... | | `pingBatch` — только без запущенного xray |

На Android есть ещё `RegisterDialerController`/`SetDNS` (нужны в VPN-режиме, чтобы сокеты xray не шли в свой же
туннель) — нам не нужны: мы не VPN, а локальный SOCKS для одного приложения.
`memory.InitForceFree` (агрессивный GC) включается только на iOS.

## Окружение Mac (2026-11-18)

- JDK 17: `openjdk@17` из Homebrew уже стоял (keg-only, `/opt/homebrew/opt/openjdk@17`).
- `sdkmanager` (Homebrew cask `android-commandlinetools`) использован один раз, чтобы поставить SDK в
  `upstream/android-work/sdk` (`--sdk_root`): cmdline-tools, platform-tools, platforms;android-36, build-tools 36.0.0,
  NDK 27.2.12479018, CMake 3.22.1, emulator, system-images;android-36;google_apis;arm64-v8a.
- `~/.android` уже был (adb из Homebrew, октябрь) — мы пишем в `upstream/android-work/android-user`
  (`ANDROID_USER_HOME`), AVD — `upstream/android-work/avd`, Gradle — `upstream/android-work/gradle`.

## Похожие проекты

NekoX (`MGislv/NekoX`) — форк с встроенными VMess/Trojan/SS, заброшен, VLESS Reality нет. v2rayNG — libXray-подобное
ядро (AndroidLibXrayLite) в процессе приложения через gomobile: тот же подход, что у нас.
