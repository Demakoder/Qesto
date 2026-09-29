# AI JSON Export v1

Первый этап ИИ: только локальная выгрузка. LLM, чат, сервер, сетевой клиент и
повторный парсинг источников в feature отсутствуют.

## Источник и контракт

`captureAiExportSnapshot` синхронно читает активный профиль: канонические счета,
операции Synoball, прикладные операции BudgetController и каталог категорий.
Прикладная запись соединяется с канонической по ID. Статус, сумма, направление
и время берутся из канонической записи; тип и выбранная категория — из того
же прикладного представления, что используется UI. Cash flow treatment вычисляет
существующий сервис контроллера. Текст повторно не классифицируется.

Snapshot не содержит raw payload, evidence, документов или банковской авторизации.
При открытии диалога данные фиксируются; фоновая синхронизация не меняет уже
показанные количества. Один AiExportSelection используется и для preview, и
для DTO. Все JSON-ключи перечислены явно в `ai_export_document.dart`.

Все счета профиля присутствуют независимо от периода операций. Категории —
только используемые выбранными операциями. Для неразрешённого счёта ссылка null,
`accountResolution: unresolved`; существующий виртуальный счёт помечен `virtual`.
Никаких новых счетов в финансовой системе экспорт не создаёт.

Включаются только posted/observed денежные записи, представленные в приложении
и подтверждённые. Deleted, reversed/cancelled, pending, unconfirmed, non-cash,
expected/inferred и отсутствующие прикладные записи исключаются. Счётчики
`selection.excluded` относятся к каноническим записям выбранного периода, а не
ко всем исходным уведомлениям/кандидатам импорта.

`latestStoredBalance` — последнее сохранённое значение, НЕ остаток на конец
периода. Исторический opening/closing balance и полнота истории не вычисляются.
Даты фильтруются по сохранённой календарной дате, обе границы включительны.
Offset для локальных дат не выдумывается. 3/6/12 месяцев начинаются с первого
числа соответствующего месяца, включая текущий неполный месяц, как в статистике.
Все пресеты заканчиваются referenceDate приложения; будущие даты доступны
только через произвольный диапазон. Пустой экспорт допустим.

Суммы — десятичные строки из Money, без double, округления UI или конвертации.
Текущая Money-модель использует два дробных разряда. Тип refund сохраняется;
internalTransfer остаётся отдельной cash-flow treatment, а не расходом.

## Идентификаторы и приватность

HMAC-SHA-256 от JSON-массива `[version, profileScope, entityType, canonicalId]`.
Полный 256-битный результат с префиксом acc_/txn_/cat_. Секрет — 32 случайных
байта Random.secure(), ключ `qesto.ai-export.pseudonym-key.v1` в существующем
PlatformSecureStringStore/FlutterSecureStorage, не в preferences. Это отдельный
секрет, не банковский credential и не ключ шифрования финансового хранилища.
Повреждённый ключ вызывает ошибку, а не молчаливую смену идентичности.

IDs стабильны между экспортами при прежних локальном секрете, профиле и
каноническом ID. Очистка secure storage, новая установка/профиль или смена
канонического ID при reconciliation могут изменить результат. Нейтральные
названия «Счёт 1»/«Операция 1» — подписи, а не идентичность: связывать экспорты
нужно по id. Обратная таблица никогда не сериализуется.

Оба переключателя скрытия включены по умолчанию. Если включён хотя бы один,
категории используют стандартные имена из системного каталога; неизвестные
категории получают нейтральные названия. Когда оба выключены, разрешены
прикладные названия операций, счетов и категорий, но не отдельные технические поля.

Всегда исключены: PIN/credentials, токены/cookies, банковские профили, secret,
encryption keys, raw/source/provider/connection IDs, user ID и профиль/аватар,
evidence/audit/debug, произвольные tags, пути, исходные выписки и изображения,
позиции чеков, receipt/fiscal identifiers и комментарии.

Это псевдонимизация, не анонимность. Суммы и даты остаются чувствительными.
Сохранённый JSON не зашифрован. Приложение не загружает его во внешние сервисы.

## Файл и платформы

- Windows: SaveFileDialog, UTF-8 запись через Dart с временным файлом в выбранной
  папке и rename после flush. PowerShell получает только безопасное имя файла,
  но не финансовый JSON. Отмена не пишет файл; системные ошибки не показывают пути.
- Android: ACTION_CREATE_DOCUMENT, JSON bytes по отдельному MethodChannel,
  запись ContentResolver вне UI thread. Широкие storage permissions не нужны.
- Web: Blob/download с освобождением object URL. Показывается «скачивание передано
  браузеру», поскольку браузер не подтверждает фактическую запись на диск.
- Другие native платформы: явное сообщение о неподдерживаемом сохранении.

Имя: `qesto-ai-export-YYYY-MM-DD.json`, без имени пользователя или банка.
JSON pretty-printed UTF-8. Тяжёлая сериализация выполняется через compute;
при HMAC-маппинге больших историй управление периодически возвращается UI.
При ошибке создания файла возможен неполный документ у Android document provider;
успех в этом случае не сообщается.

## Пример контракта

Ниже синтетические значения. IDs иллюстративные; это не пользовательский экспорт.

```json
{
  "schemaVersion": "qesto.ai-export.v1",
  "generatedAt": "2026-09-23T12:00:00.000Z",
  "period": {
    "startDate": "2026-08-25",
    "endDateInclusive": "2026-09-23",
    "dateBasis": "stored_calendar_date"
  },
  "privacy": {
    "transactionNamesHidden": true,
    "accountNamesHidden": true,
    "categoryNamesProtected": true,
    "idScope": "persistent_pseudonymous"
  },
  "selection": {
    "transactionPolicy": "posted_monetary",
    "balances": "latest_stored",
    "historyCompleteness": "not_verified",
    "snapshotCapturedAt": "2026-09-23T11:59:00.000Z",
    "excluded": { "pending": 1 }
  },
  "accounts": [
    {
      "id": "acc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "name": "Счёт 1",
      "type": "checking",
      "isVirtual": false,
      "latestStoredBalance": { "value": "10000.25", "currency": "RUB" }
    }
  ],
  "categories": [
    {
      "id": "cat_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "name": "Продукты"
    }
  ],
  "transactions": [
    {
      "id": "txn_cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      "accountId": "acc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "categoryId": "cat_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "accountResolution": "resolved",
      "occurredAt": "2026-09-22T15:30:00.000",
      "name": "Операция 1",
      "amount": { "value": "1200.25", "currency": "RUB" },
      "status": "posted",
      "type": "expense",
      "direction": "outflow",
      "cashFlowTreatment": "externalOutflow"
    }
  ]
}
```

## Ограничения v1

Нет goals/debts/investments как самостоятельных разделов, cards, recurring,
receipt items, прогнозов, AI-summary или суммарного пересчёта разных валют.
Канонический счёт типа investment/loan остаётся счётом; отдельный портфель/долг
к нему не добавляется, чтобы избежать двойного учёта. Нет независимой проверки
корректности импортированной истории; выгружаются уже принятые Qesto данные.

Нативные UI-проверки на реальных устройствах выполняются отдельно от widget
tests: открыть диалог, отменить, сохранить, повторить экспорт, сравнить IDs,
выбрать недоступную папку/провайдер. Банковский вход для этих проверок не нужен.

## Существенные файлы

- `lib/features/ai_export/domain/ai_export_models.dart`: настройки, минимальный
  неизменяемый snapshot, единая выборка для preview и экспорта.
- `domain/ai_export_document.dart` и `domain/ai_export_mapper.dart` внутри feature:
  явный DTO-контракт, связи сущностей, приватные имена, точные денежные значения.
- `data/ai_export_snapshot.dart`: чтение существующего состояния Qesto/Synoball
  без изменения финансовых данных или повторной классификации.
- `data/ai_export_ids.dart`: отдельный локальный секрет и стабильные HMAC IDs.
- `data/ai_export_service.dart` и `data/ai_export_file*.dart`: сборка JSON,
  платформенное сохранение, отмена и безопасные ошибки.
- `presentation/ai_export_page.dart` и `presentation/ai_export_dialog.dart`:
  заглушка ИИ, период, приватность, количества, состояния выполнения.
- `lib/desktop/pages/desktop_support_pages.dart`: подключение новой страницы
  через существующий DesktopInsightsPage без изменения навигации.
- `lib/features/statistics/domain/services/statistics_period_range.dart`:
  выделенная существующая логика пресетов; StatisticsController использует её
  без изменения смысла периодов.
- `android/app/src/main/kotlin/ru/qesto/qesto/AiExportFileBridge.kt` и
  `MainActivity.kt`: Android document picker и жизненный цикл вызова.
- `test/ai_export_test.dart`, `test/ai_export_file_test.dart`,
  `test/ai_export_ui_test.dart`: контракт, приватность, периоды, деньги, ID,
  платформенные вызовы, запись файлов и UI. Обновлены только light/dark эталоны ИИ.
- `pubspec.yaml`: версия локальной сборки `1.0.48+49`; новых зависимостей нет.

## Проверка и локальная установка — 24 сентября 2026

- `flutter analyze --no-pub`: замечаний нет.
- 17 новых тестов экспорта проходят, в том числе история из 10 000 операций,
  фактическая UTF-8 запись/замена временного файла и узкий/desktop light/dark UI.
- Связанная регрессия: 115 тестов прошли, 1 пропущен из-за отсутствия локальных
  файлов. Проверены Synoball, cash flow, корзина, Sber import/compatibility,
  financial codec, периоды, desktop shell и mobile/desktop parity.
- Полный прогон: 578 прошли, 8 пропущены, 2 упали. Оба падения — существующие
  light/dark golden-тесты инвестиций: подпись «Обновлено N дн. назад» зависит
  от DateTime.now(). Разница 272 пикселя (около 0,03%); экран инвестиций и его
  эталоны в этой задаче не изменялись. Полный набор не объявляется зелёным.
- Windows release и Web production build собраны; Android compileDebugKotlin
  прошёл. APK не устанавливался, реальный Android document provider не проверен.
- Windows `1.0.48+49` установлен по прежнему ярлыку `Qesto.lnk`. Перед заменой
  созданы проверенные резервные копии финансового хранилища, secure storage,
  банковского профиля и предыдущей версии. Банковские данные оставлены на месте.
- Нативное окно сохранения в установленном приложении ещё требует ручного
  smoke test: «ИИ» → «Экспорт для ИИ» → выбрать период → сохранить JSON.
  Проверки не создавали экспорт реальных пользовательских данных и не отправляли
  их наружу. Изменения не коммитились и не отправлялись на GitHub в этой задаче.
