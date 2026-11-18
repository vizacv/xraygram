# Реестр сборок

Регистрирует платформа (сразу после сборки), вердикт ставит QA. ID: `<платформа>-<ГГГГММДД>-<N>`.
Файлы — в `upstream/` (не в git), с ID в имени; файл «у владельца» не перезаписывать.

| ID | Файл | Что внутри (FEAT/BUG) | Вердикт QA | У владельца |
|---|---|---|---|---|
| macos-20261118-1 | `upstream/xraygram-local/dist/Xraygram.app` (14:26) | FEAT-01, 02, 06 | ⚠️ утечек нет, звонки мимо xray (macos-report) | ✅ вход и подключение работают |
| macos-20261118-2 | `upstream/xraygram-local/dist/Xraygram-macos-20261118-2.app` (16:44; та же сборка — текущий `dist/Xraygram.app`) | + FEAT-03, FEAT-04 (патч tgcalls), BUG-04, предупреждение FEAT-05 | — не проверялась QA | 👤 ждёт живого звонка |
| android-20261118-1 | `upstream/android-work/dist/Xraygram-13.2.2-arm64-v8a.apk` (15:59) | FEAT-01, 02, 08, частично 06 | ⚠️ смоук в эмуляторе (платформа), QA не проверял | 👤 отдан владельцу 2026-11-18 |
| android-20261118-2 | `upstream/android-work/dist/Xraygram-android-20261118-2.apk` (18:01) | FEAT-03, FEAT-04 (патч tgcalls), BUG-04, BUG-05 | 🚫 не выдавать: смоук платформы нашёл FCM-соединение с Google (172.217.x) в обход xray, исправлено в -3 | нет |
| android-20261118-3 | `upstream/android-work/dist/Xraygram-android-20261118-3.apk` (18:06) | FEAT-03, FEAT-04 (патч tgcalls, живой звонок не проверен), BUG-04, BUG-05; FCM выключен (FEAT-09: только фоновое соединение); intro «Xraygram» | 🧪 ждёт QA (смоук платформы: GATE/XRAY/COLD — всё PASS) | нет |
| ios-20261118-1 | `upstream/xraygram-ios/dist/Xraygram-ios-20261118-1-sim.app` (симулятор, 17:07, bundle `io.github.vizacv.xraygram`) | FEAT-01, 02, 03, 04 (компилируется; при XRAY только версии звонков 7–13), 06; BUG-01, 04, 05; поиск запасных адресов MtProtoKit мимо прокси выключен | 🧪 ждёт QA (смоук платформы в симуляторе пройден) | нет (нужны iPhone + Apple ID) |

С этого момента новые сборки — с ID в имени файла и регистрацией здесь.
