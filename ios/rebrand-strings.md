# iOS — подмена «Telegram» → «Xraygram» в строках (FEAT-19, PAR-20)

Список ключей (канон, 79 ключей): `Telegram/Telegram-iOS/XraygramRebrandKeys.txt` в дереве Telegram-iOS (входит в
`ios/patches/0001-xraygram-ios.patch`). Для QA (F19-09/10/12) — этот файл и список ниже.

## Механизм

- `build-system/GenerateStrings/GenerateStrings.py --rebrandKeys …` встраивает список в сгенерированный
  `PresentationStrings.m`. Словарь каждого `_PresentationStringsComponent` (бандл en, облачные пакеты, в том числе
  уже скачанные, экран входа) и запасной en-словарь в `getSingle` проходят `xgRebrandDict` один раз при загрузке языка.
- Внутри значения ключа из списка: `TELEGRAM` → `XRAYGRAM`, `Telegram` / `Телеграм(м)…` → `Xraygram`, **кроме**
  защищённых словосочетаний: после слова идёт Premium/Stars/Business/Passport/Gateway/Ads/Wallet/account/servers/cloud/
  API/users/FAQ/Support/Features/Desktop/Web, или перед ним «on »/«аккаунт(е) »/«серверах »/«серверы »/«облаке ».
  URL (`telegram.org`, `t.me`) не трогаются (регистр). Множественные формы — по базовому ключу (`_0/_1/_2/_3_10/_many/_any`).
- `LegacyComponents/TGLocalization.m` больше не меняет «Telegram» глобально (получает уже подменённый словарь).
- Ключи вне списка не меняются никогда.

## Мимо PresentationStrings

- Системные запросы доступа: `Telegram/Telegram-iOS/*.lproj/InfoPlist.strings` и usage descriptions в `Telegram/BUILD`
  — «Telegram» → «Xraygram» (в описании контактов: «Xraygram … в облаке Telegram»; в RU контакты — «облако Telegram»,
  не трогали). В `ar`/`ko` удалён `CFBundleDisplayName` («Telegram» по-местному под иконкой).
- Siri: `AppIntentVocabulary.plist` (фразы «Send a Telegram message») больше не входят в сборку.
- Письмо в поддержку при ошибке входа: строка версии «Xraygram: <версия>» (`AuthorizationSequenceController.swift`).
- **Не трогаем** (решение продукта): альбом «Telegram» в «Фото» (остаётся после удаления приложения — «не светиться»),
  метку «Telegram» у контакта в «Контактах», сеанс «Telegram iOS» в «Устройствах» (с сервера).

## Группы ключей

| Группа | Ключи |
|---|---|
| Доступ (камера, микрофон, фото, контакты, геопозиция) | `AccessDenied.*` (23), `Attachment.CameraAccessText`, `Attachment.LimitedMediaAccessText`, `Contacts.AccessDenied*`, `Contacts.LimitedAccess.Text`, `Contacts.PermissionsText`, `Media.LimitedAccessText`, `Story.Camera.AccessPlaceholderTitle`, `Map.HomeAndWorkInfo`, `InfoPlist.NSLocation*` |
| Звонки | `Call.StatusIncoming`, `Call.StatusOngoing`, `Call.PhoneCallInProgressMessage`, `Calls.RatingTitle`, `Chat.Context.Phone.TelegramVoiceCall/VideoCall`, `UserInfo.TelegramCall/VideoCall`, `Privacy.Calls.IntegrationHelp` |
| Код-пароль | `DialogList.PasscodeLockHelp`, `EnterPasscode.EnterPasscode/EnterTitle/TouchId`, `Passcode.AppLockedAlert`, `PasscodeSettings.EncryptDataHelp`, `PasscodeSettings.LockTelegram` |
| Хранилище | `Cache.Indexing`, `ClearCache.ClearCache/StorageCache/StorageServiceFiles`, `StorageManagement.DescriptionAppUsage/DescriptionChatUsage`, `AppUpgrade.Running` |
| Обновление | `Update.AppVersion/Title/UpdateApp`, `Conversation.UpdateTelegram`, `Conversation.UnsupportedMedia(.Text, Placeholder)`, `Story.UnsupportedAction/UnsupportedText`, `Login.ErrorAppOutdated`, `Gift.Transfer.UpdateRequired.Text`, `Passport.UpdateRequiredError` |
| Прочее | `Application.Name`, `ChatImportActivity.OpenApp`, `Share.AuthDescription`, `Intents.ErrorLockedText`, `Permissions.CellularDataText.v0`, `PowerSavingScreen.OptionAutoplayEffectsText`, `WebBrowser.Telegram`, `WebBrowser.ClearCookies.Info` |

## Оставлены «Telegram» (сознательно)

- Пограничные по таблице FEAT-19 п. 3: `Login.CodeSentInternal`, `Login.EnterCodeTelegramText`,
  `Login.CheckOtherSessionMessages` (код приходит в Telegram), `Contacts.InviteToTelegram`, `Contacts.ShareTelegram`,
  `InviteText.*`, `PeerInfo.UnofficialSecurityRisk`, Premium-only.
- Сервис: аккаунт, серверы, облако, модерация (`Report.Succeed`, `Group.AdminLog.AntiSpam*`), розыгрыши, платежи
  (`Checkout.*`), письма в поддержку Telegram (`Login.*EmailBody/Subject`), `AuthCode.Alert`, `AuthConfirmation.*`,
  `Settings.LogoutConfirmationText`, `DownloadList.ClearAlertText`, `WebApp.DisclaimerText`, `WebBrowser.AutoLogin`.
- Клиент собеседника: `Compatibility.SecretMediaVersionTooLow`, `Profile.CreateEncryptedChatOutdatedError`.
- `Tour.Text1` («неофициальный клиент Telegram»); `Tour.Text2…6` не показываются (своё вступление).
- Сомнительный, решение за продуктом: `Notifications.TelegramTones` («TELEGRAM TONES» — встроенные звуки upstream;
  свои звуки не делаем, поэтому оставлено).
