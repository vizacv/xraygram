# Исследование: встраивание Xray в Telegram Android

Перенесено из сессии «Пересборка Telegram с ядром Xray» (2026-11-18).

## Исходники

| Репозиторий | Версия на момент исследования | Где лежит локально |
|---|---|---|
| `DrKLO/Telegram` | `21f7d109` — 13.2.2 (7303), 2026-11-12 | `upstream/tg` (shallow + sparse checkout) |
| `XTLS/libXray` | `5a0f7d8`, тег `v26.11.9`, 2026-11-09 | `upstream/libxray` (shallow) |

`upstream/` не коммитим (см. `.gitignore`), это рабочие клоны для чтения кода.

## Почему не MTProto

MTProto-прокси (`mtg`, fake-TLS) у пользователя не работает уже почти год, поэтому
нужен VLESS+Reality через xray.

## Архитектура

Сетевой код Телеги (tgnet, C++) не трогаем. Схема:

1. libXray собирается через `gomobile bind` в `libXray.aar` → Java-класс `libXray.LibXray`, метод `invoke(String json)`.
2. `XrayTransport` (Java) поднимает in-process xray с inbound `socks` на `127.0.0.1:<свободный порт>`
   и outbound из share-ссылки (`vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`).
3. tgnet получает обычный SOCKS5 `127.0.0.1:<port>` через `native_setProxySettings`.

Образец, как это сделано у самой Телеги: тип прокси `WEB` (`WebProxyTransport`) работает ровно так же —
поднимает локальный порт и отдаёт его в native. Xray-тип делаем по этому шаблону.

## Ключевые места в коде Telegram

Пути относительно `TMessagesProj/src/main/java/org/telegram/`.

- `utils/proxy/ProxySettings.java` (540 строк) — модель прокси. `enum Type { SOCKS5, MTPROTO, WEB }`,
  `fromUri(Uri)`, `fromSharedPreferences(...)`, `typeToInt/intToType`. Сюда добавить `Type.XRAY`
  и хранить share-ссылку (вероятно, в поле `secret`).
- `utils/proxy/WebProxyTransport.java` — шаблон: `static int start(address, secret)` → локальный порт, `static void stop()`.
- `utils/proxy/WebProxyConnectionTester.java` — шаблон для проверки пинга.
- `tgnet/ConnectionsManager.java`:
  - `init(...)` (~строка 482): читает `ProxySettings.fromSharedPreferences`, для `Type.WEB` делает
    `WebProxyTransport.start(...)` и передаёт `127.0.0.1:port` в native. Добавить ветку для `XRAY`.
  - `setProxySettings(...)` — то же самое при смене прокси.
  - `checkProxy(settings, delegate)` (~строка 962): для `WEB` идёт через tester, иначе `native_checkProxy`.
    Для `XRAY` — если запущен этот же линк, `native_checkProxy("127.0.0.1", port, ...)`, иначе `XrayTransport.checkTcp`.
- `messenger/SharedConfig.java`:
  - `ProxyInfo` (~строка 380), сериализация `fromSerializedData/serializeToStream`, схемы `PROXY_SCHEMA_V2/V3`
    (V3 пишет `typeToInt`). Новый тип должен корректно сериализоваться — проверить `intToType` на неизвестных значениях.
  - `loadProxyList()` (~строка 1442), `currentProxy`.
- `ui/ProxySettingsActivity.java` (927 строк) — экран добавления прокси: переключатель типа (`typeCell[]`),
  вставка из буфера через `ProxySettings.fromUri(clipText)` (~строка 670), валидация (~строка 723).
- `ui/ProxyListActivity.java` — подпись в списке (~строка 196): `address:port` или `address (WEB)`.
- `messenger/AndroidUtilities.java` — `handleProxyIntent` / `showProxyAlert` (~строки 4692–4731): открытие ссылок-прокси.
- `ui/LaunchActivity.java` (~строка 438) — фильтр `tg:webproxy` / `tg://socks` и т.п.
- `RequestTimeDelegate` — `void run(long time)`.

## Сборка Telegram

- AGP `8.13.2`, Kotlin `2.1.0`, `ndkVersion "27.2.12479018"`, `minSdkVersion 23`, `namespace 'org.telegram.messenger'`.
- Модули: `TMessagesProj` (библиотека), `TMessagesProj_App`, `_AppStandalone`, `_AppHuawei`, `_AppHockeyApp`, `_AppTests`.
  Для форка берём **`TMessagesProj_AppStandalone`** (без Play-зависимостей обновлений).
- `buildSrc/.../TelegramBuildAppPlugin.kt` — общий плагин сборки app-модулей.
- Много сабмодулей в `TMessagesProj/jni/third_party` (ffmpeg, libvpx, dav1d, boringssl, opus, libyuv, openh264...) —
  нативная часть тяжёлая, поэтому собираем в GitHub Actions, а не локально.
- В репо лежит `Dockerfile` для reproducible build — можно использовать как опору для CI.
- В `BuildVars.java` надо подставить **свои `APP_ID`/`APP_HASH`** с my.telegram.org; release keystore и
  `google-services.json` в репо фиктивные.
- `TMessagesProj/libs/` — сюда кладём `libXray.aar` (или подключаем как `implementation files(...)`).
- `proguard-rules.pro` — добавить `-keep class libXray.** { *; }` и `-keep class go.** { *; }`.
- Требования Telegram к форкам: не называть «Telegram», не использовать их логотип, публиковать код (GPL).

## Сборка libXray

- `build/main.py android` → `build/app/android.py`: `go install golang.org/x/mobile/cmd/gomobile@<ver>`, `gomobile init`,
  затем `gomobile bind -target android -androidapi $LIBXRAY_ANDROID_API (по умолчанию 21) -trimpath
  -ldflags="-checklinkname=0 -s -w -buildid= -extldflags=-Wl,-z,max-page-size=16384,..."`.
- На выходе `libXray.aar` + `libXray-sources.jar`. Для minSdk 23 ставим `LIBXRAY_ANDROID_API=23`.
- Нужны Go (версия из `go.mod`), Android SDK + NDK.

## API libXray (Invoke)

`LibXray.invoke(json)` → `{"success": bool, "data": ..., "error": "..."}`. Запрос:
`{"apiVersion": 3, "method": "<name>", "payload": {...}}`.

| method | payload | data |
|---|---|---|
| `convertShareLinksToXrayJson` | `{"text": "<ссылки>"}` | xray JSON с `outbounds` |
| `decodeSubscriptionText` | `{"text": ...}` | `{"text": ...}` |
| `runXray` | `{"xrayJson": "<config string>"}` | — |
| `stopXray` | — | — |
| `getXrayState` | — | `{"running": bool}` |
| `xrayVersion` | — | `{"version": ...}` |
| `testXray` | `{"xrayJson": ...}` | — |
| `getFreePorts` | ... | ... |
| `pingBatch` | ... | работает **только без запущенного** xray в процессе |

В процессе может жить только один экземпляр xray.

## Окружение Mac (на 2026-11-18)

- Нет: `gh`, `go`, `gradle`, `gomobile`, Java runtime (`/usr/bin/java` — заглушка), `~/.gitconfig`.
- Есть: `brew`, `sdkmanager`, `adb` (homebrew), Android SDK в `~/Library/Android/sdk` отсутствует.
- SSH-ключа для GitHub нет (`ssh -T git@github.com` → Host key verification failed).
- Вывод: локально собирать не будем, сборка в **GitHub Actions**.

## Похожие проекты

NekoX (`MGislv/NekoX`, `dic1911/NekoX`) — форк с встроенными VMess/Trojan/SS, заброшен, VLESS Reality нет.
Также TeleTux. Годятся как пример, не как база.
