# Xraygram Android

Основа: `DrKLO/Telegram` (13.2.2). Статус: на паузе.

- [research.md](research.md) — исследование кода Telegram Android и libXray, план изменений.
- [patches/](patches/) — черновик `XrayTransport.java` (обёртка libXray → локальный SOCKS). Не компилировался.

## Что дальше

- [ ] `ProxySettings.Type.XRAY` + сериализация в `SharedConfig`
- [ ] Ветки XRAY в `ConnectionsManager.init / setProxySettings / checkProxy`
- [ ] UI: тип «Xray» в `ProxySettingsActivity`, вставка `vless://`, подпись в `ProxyListActivity`
- [ ] Открытие `vless://` ссылок (`AndroidUtilities.handleProxyIntent`)
- [ ] Ребрендинг, свои `APP_ID`/`APP_HASH`
- [ ] GitHub Actions: `libXray.aar` → APK (`TMessagesProj_AppStandalone`)
