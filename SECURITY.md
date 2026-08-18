# Безопасность Qesto

Qesto пока не следует считать банковским приложением или сертифицированным
хранилищем финансовых данных. Приложение не запрашивает логины, пароли, PIN,
CVV и SMS-коды банка. Open Banking в текущей сборке программно отключён.

Пофайловое объяснение реализации и модели угроз находится в
[`docs/SECURITY_IMPLEMENTATION_RU.md`](docs/SECURITY_IMPLEMENTATION_RU.md).

## Как сообщить об уязвимости

Не публикуйте секреты, персональные данные и рабочий пример эксплуатации в
обычном Issue. Используйте GitHub Private Vulnerability Reporting, если он
включён для репозитория, либо свяжитесь с владельцем репозитория приватно.
Укажите затронутую версию, платформу, шаги воспроизведения и ожидаемое влияние.

## Что уже защищено

- Финансовое состояние шифруется AES-256-GCM. Случайный мастер-ключ находится в
  системном защищённом хранилище, а не рядом с данными. Старое открытое
  хранилище мигрирует при первом чтении.
- Буфер банковских уведомлений Android отдельно шифруется ключом Android
  Keystore, хранит не более 100 элементов и удаляет записи старше 7 дней.
- Android Backup и перенос данных между устройствами отключены: ключи Keystore
  нельзя корректно восстановить вместе с шифротекстом.
- Release APK не может незаметно подписаться общедоступным debug-ключом.
- Cleartext HTTP запрещён в release-манифесте Android. Debug-манифест оставляет
  его только для локальной разработки и `adb reverse`.
- Локальный сервис акций слушает `127.0.0.1`; LAN-доступ требует явного флага.
  Ручной `/sync` выключен без токена.
- PDF/XLSX ограничены по размеру и структуре; исполняемые макросы не запускаются.
- Голос на Android распознаётся только локальным системным движком; облачный
  fallback отключён. На Windows используется локальный Whisper.
- Архив Whisper и модель проверяются по закреплённым SHA-256 до использования.
- Windows release собирается отдельным fail-closed скриптом: EXE/DLL приложения,
  установщик и деинсталлятор подписываются Authenticode и проверяются до выдачи
  артефакта.
- Внешние ответы Telegram/MAX, отдельные сообщения и тело Deals API ограничены
  по размеру; MAX требует HTTPS и не передаёт API-токен при cross-origin
  redirect.

Шифрование данных на диске не защищает уже разблокированное приложение от
вредоносного ПО с правами пользователя, root-доступа, чтения памяти процесса
или XSS в открытой веб-вкладке. Веб-версию следует публиковать только по HTTPS.

## Подпись Android release

Создайте ключ вне репозитория:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.android-keys"
keytool -genkeypair -v `
  -keystore "$env:USERPROFILE\.android-keys\qesto-release.jks" `
  -alias qesto-release -keyalg RSA -keysize 4096 -validity 10000
Copy-Item android\key.properties.example android\key.properties
```

Заполните `android/key.properties`. Этот файл и `*.jks` уже исключены из Git.
Сделайте отдельную зашифрованную резервную копию ключа: потерянный ключ нельзя
восстановить, а обновление уже опубликованного APK без него невозможно.

Для Windows-сборки включите системный Developer Mode: Flutter использует
символические ссылки для подключения нативного защищённого хранилища. Открыть
нужную страницу можно командой `start ms-settings:developers`.

Для одноразовой локальной release-сборки допускается debug-подпись:

```powershell
$env:QESTO_ALLOW_DEBUG_RELEASE_SIGNING='1'
flutter build apk --release
```

Такую сборку нельзя распространять.

## Подпись Windows release

Импортируйте Authenticode-сертификат с закрытым ключом в хранилище сертификатов
Windows и задайте только его SHA-1 thumbprint:

```powershell
$env:QESTO_WINDOWS_CERT_SHA1='<40 hex characters>'
./apps/qesto_app/windows/build_signed_release.ps1
```

Скрипт собирает Windows release, подписывает и проверяет все его EXE/DLL, затем
передаёт Inno Setup обязательный `SignTool`. Inno Setup подписывает установщик и
деинсталлятор; итоговый установщик повторно проверяется через `signtool verify`.
Прямой запуск `ISCC qesto.iss` без настроенного sign tool должен завершиться
ошибкой.

Для GitHub Actions настройте encrypted secrets
`WINDOWS_SIGNING_CERTIFICATE_BASE64` и
`WINDOWS_SIGNING_CERTIFICATE_PASSWORD`, затем запускайте workflow
`Signed Windows release`. PFX временно импортируется в хранилище runner и
удаляется после сборки.

## Сетевой сервис акций

Обычный запуск доступен только локально:

```powershell
python scripts/run_qesto.py --device <android-device-id>
```

Если `adb reverse` невозможен, LAN нужно разрешить явно:

```powershell
python scripts/run_qesto.py --allow-lan --device <android-device-id>
```

Для ручного вызова `POST /sync` задайте длинный случайный
`QESTO_DEALS_SYNC_TOKEN` и отправляйте `Authorization: Bearer <token>`.
Дополнительные веб-origin перечисляются через запятую в
`QESTO_DEALS_ALLOWED_ORIGINS`.

## Требования к публикации Web

Публикуйте только по HTTPS. `web/_headers` содержит CSP и остальные обязательные
заголовки в формате Cloudflare Pages/Netlify. На другом хостинге перенесите их
в конфигурацию сервера без ослабления `frame-ancestors`, `script-src` и
`connect-src`.

```text
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
Referrer-Policy: no-referrer
Permissions-Policy: camera=(), microphone=(), geolocation=()
Cross-Origin-Opener-Policy: same-origin
```

Если домены API меняются, расширяйте `connect-src` точечно, не заменяйте его на
`*`. Не помещайте банковские секреты и токены в `--dart-define`: значения из
веб-сборки может прочитать пользователь браузера.

## Проверка перед релизом

1. `python scripts/check_security_invariants.py` проходит.
2. `flutter analyze` и `flutter test` проходят полностью.
3. Python-тесты сервиса: `python -m unittest discover -s tests -v`.
4. OSV-проверка проходит: `python scripts/check_pub_advisories.py --project apps/qesto_app`.
5. В Git нет `.env`, `key.properties`, `*.jks`, токенов и реальных выписок.
6. APK подписан release-ключом, а не debug-сертификатом.
7. Windows-установщик создан только `build_signed_release.ps1`, подписи EXE/DLL, setup и uninstaller проверены.
8. Web размещён по HTTPS с заголовками из `web/_headers`.
9. Зависимости и Android SDK обновлены, результаты Dependabot просмотрены.
