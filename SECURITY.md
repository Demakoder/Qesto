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

Публикуйте только по HTTPS. CSP в `web/index.html` является минимальной защитой;
на хостинге продублируйте её HTTP-заголовком и добавьте:

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

1. `flutter analyze` и `flutter test` проходят полностью.
2. Python-тесты сервиса: `python -m unittest discover -s tests -v`.
3. В Git нет `.env`, `key.properties`, `*.jks`, токенов и реальных выписок.
4. APK подписан release-ключом, а не debug-сертификатом.
5. Web размещён по HTTPS с заголовками выше.
6. Зависимости и Android SDK обновлены, результаты Dependabot просмотрены.
