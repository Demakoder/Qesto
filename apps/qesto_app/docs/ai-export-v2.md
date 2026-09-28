# AI Export v2 — семантика и границы

Актуальное дополнение для 1.0.50: [Compact / Diagnostic и расследование дублей](ai-export-v2-compact-reconciliation.md).
Режим по умолчанию — `detailLevel: compact`; полный прежний набор metadata
доступен как `diagnostic`. `confirmed_unique` заменён на `source_identified`,
а `deduplicationCompleteness` — на отдельный `deduplicationProcessing`.
`historyCompleteness` теперь только в `dataQuality`. Примеры ниже описывают
исходный расширенный v2; актуальные различия и проверка реальных данных — в дополнении.

По умолчанию «ИИ → Экспорт для ИИ» формирует `qesto.ai-export.v2`.
В том же диалоге доступен `v1 — совместимость`. Файловое сохранение, периоды,
privacy и защищённый HMAC-ключ переиспользуются. LLM и сетевого отправителя нет.

## Подготовка канонических фактов

`synoball/analytics/canonical_snapshot.dart` — read-only нормализованное
представление существующего Synoball. Это не повторный парсер и не финансовая
модель, которую ИИ должен восстанавливать из сырья. Существующие БД, ingestion,
адаптеры и денежные расчёты приложения не мигрируются и не изменяются экспортом.
Нормализация старого cash/date-only/unknown представления происходит в этом
каноническом read model, перед DTO и фильтрацией приватности.

- Несколько evidence одной canonical transaction дают одну операцию.
- Старые отдельные canonical записи объединяются только по точному provider ID
  в одном source/bank/connection scope и совместимым финансовым фактам.
  Сохраняется ранняя каноническая идентичность, реальный счёт предпочтительнее
  виртуального, явная пользовательская правка имеет приоритет.
- Противоречивые ручные правки, различные реальные счета, направления, валюты,
  суммы или несовместимые даты не разрешаются молчаливым выбором победителя.
- Существующий TransactionDeduplicator применяется для выявления похожих записей
  разных источников. Эвристика только ставит `possible_duplicate`: она НЕ удаляет
  операции. Две покупки с разными ID одного источника остаются раздельными.
- `confidence` дедупликации — эвристическая оценка Synoball, ограниченная
  уверенностью источников, не калиброванная вероятность. Если метрики нет — null.
- `unresolved` честно сообщает отсутствие подтверждённой идентичности.
  `dataQuality.deduplicationCompleteness` не даёт выдать такой snapshot за полностью
  проверенный. Это не поручение ИИ удалять дубли: он должен оговаривать ограничения.
- Слияние только в read model не исправляет существующую базу задним числом.
  Все исходные записи/evidence сохраняются для последующей проверки пользователем.

Снимок экспортера содержит только минимальные поля и компактные факты.
Канонические rawDescription, полные evidence/records и payload в него не переносятся.

## Счета и деньги

- Каждый account имеет `type`, `subtype`, `resolutionStatus`, `balanceNature`.
  Проверенный банковский cash нормализуется в bank_account; настоящие наличные
  остаются cash. Loan — liability. Credit card — mixed: существующий общий баланс
  сам по себе не доказывает, что это задолженность, а не доступный лимит.
- Неизвестный счёт/остаток и виртуальный нулевой placeholder → unknown/null.
  Реальный нулевой остаток остаётся known/"0.00".
- `capturedAt` заполняется только известной датой снимка баланса, не временем
  создания JSON. Для обычных банковских счетов эта дата сейчас часто отсутствует.
- Известный снимок старше 7 суток помечается stale. Унаследованные автоматические
  метаданные legacy-debt/legacy-investment не выдаются за новый снимок баланса.
- Явные данные связанного кредита/инвестиционного счёта используются по account ID
  и валюте. Суммы principal/payment берутся из существующей целочисленной модели
  этих разделов. Общий долг не выдаётся за тело кредита; общий брокерский баланс
  не выдаётся за стоимость портфеля или свободные деньги. Неизвестные поля null.
- Денежные значения — строки из Money; amount положительный, direction отдельно.
  Валюты не конвертируются и не складываются между собой.
- `balancesCompleteness` описывает наличие балансов, не их свежесть.
  Отдельное `balanceFreshness=not_verified` предупреждает об отсутствующих датах.

## Даты и связи

Date-only → occurredDate + occurredAt:null + timePrecision:date.
Известная полночь сохраняется только при явном признаке точного времени.
Время получения уведомления/legacy fallback помечается approximate, а не точным
временем покупки. При datetime локальный timestamp не получает выдуманный UTC offset.

Внутренние переводы сохраняют internalTransfer. Возвраты получают type:refund и
cashFlowTreatment:refund, а не доход. Это версия экспортного контракта, без смены
существующего CashFlowCalculationService или UI-статистики.

Подтверждённые отношения поддерживаются через нормализованные события Synoball:

- `transaction.refund-linked`: subjectId возврата, payload.originalTransactionId;
- `transaction.transfer-linked`: outgoingTransactionId/incomingTransactionId.

Они проверяются на существование, валюту, направление и экономическую совместимость.
У текущих импортов такие подтверждения чаще отсутствуют: экспорт НЕ создаёт их
по одному совпадению суммы. Единственный похожий расход того же известного счёта
и продавца может дать возврату possible_match, но не matched. Иначе unmatched.
Это ограничение исходных данных, не выполненный универсальный refund matcher.

Подтверждённый возврат наследует категорию покупки, если пользователь сам не
назначил возврату другую категорию. Если покупка вне периода, ссылка в JSON null,
`originalTransactionScope: outside_period`: висячего ID нет. Для перевода все
счета находятся в accounts; непарный перевод явно помечен unmatched.

## Происхождение, качество и пользовательские правки

sourceTypes — безопасные типы источников, evidenceCount — количество уникальных
наблюдений; повторная доставка одного provider observation не увеличивает число.
Сами provider IDs, банковские/внутренние идентификаторы не экспортируются.
Category origin отделён от categoryAssignment.source. User locks и ручные
категории отражаются в userEditedFields. Неизвестная уверенность не заменяется 1.0.

historyCompleteness по умолчанию not_verified. Для будущей подтверждённой сверки
поддержано событие `history.verified` на каждый account со status:complete,
startDate/endDateInclusive. Оно должно покрывать выбранный диапазон и не предшествовать
изменению операций счёта. Текущий успешный импорт сам по себе таких событий не
создаёт. Поэтому полнота реальной истории автоматически не обещается.

## Приватность и совместимость

HMAC-SHA256 и secret v1 не меняются: acc/txn/cat идентичны между версиями для тех же
канонических сущностей. Добавлены отдельные пространства dup/trf. Group ID зависит
от состава группы; при изменении состава он может измениться. При reconciliation
с изменением исходного canonical ID экспортный ID также может измениться.

Оба скрытия названий включены по умолчанию. Никаких cookies, PIN, токенов, ключей,
raw payload, OCR, source/provider/connection IDs, путей или debug metadata в DTO.
JSON не зашифрован, суммы/даты остаются чувствительными. ИИ ничего не получает
автоматически. `qestoAiV2SystemContext` содержит правила будущего провайдера,
включая отношение к названиям как к данным, а не инструкциям.

## Пример v2 (синтетический)

```json
{
  "schemaVersion": "qesto.ai-export.v2",
  "generatedAt": "2026-09-24T12:00:00.000Z",
  "period": {"startDate":"2026-09-01","endDateInclusive":"2026-09-24","dateBasis":"stored_calendar_date"},
  "privacy": {"transactionNamesHidden":true,"accountNamesHidden":true,"categoryNamesProtected":true,"idScope":"persistent_pseudonymous"},
  "selection": {"transactionPolicy":"posted_monetary","balances":"latest_stored","historyCompleteness":"not_verified","snapshotCapturedAt":"2026-09-24T11:59:00.000Z","excluded":{}},
  "dataQuality": {"historyCompleteness":"not_verified","balancesCompleteness":"unknown","balanceFreshness":"not_verified","hasUnresolvedAccounts":true,"hasPossibleDuplicates":false,"deduplicationCompleteness":"not_verified"},
  "accounts": [{"id":"acc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","name":"Счёт 1","type":"bank_account","subtype":"unknown","isVirtual":true,"resolutionStatus":"unresolved","balanceNature":"asset","latestStoredBalance":{"status":"unknown","value":null,"currency":"RUB","capturedAt":null}}],
  "categories": [],
  "transactions": [{"id":"txn_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","canonical":true,"accountId":"acc_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","categoryId":null,"accountResolution":"unresolved","occurredDate":"2026-09-20","occurredAt":null,"timePrecision":"date","name":"Операция 1","amount":{"value":"506.00","currency":"RUB"},"status":"posted","type":"expense","direction":"outflow","cashFlowTreatment":"externalOutflow","provenance":{"sourceTypes":[],"evidenceCount":0,"merged":false},"deduplication":{"status":"unresolved","groupId":null,"confidence":null},"categoryAssignment":{"source":"unknown","confidence":null},"confidence":{},"userEdited":false,"userEditedFields":[]}]
}
```

## Основные файлы

- `lib/synoball/analytics/canonical_snapshot.dart`: нормализованные факты, связи,
  безопасное разрешение идентичности и ограничения полноты.
- `lib/features/ai_export/data/ai_export_snapshot.dart`: согласованный минимальный
  снимок и существующие метаданные кредитов/инвестиций.
- `lib/features/ai_export/domain/ai_export_v2.dart`: явный контракт и AIExportV2Builder.
- `lib/features/ai_export/domain/ai_export_mapper.dart`: неизменный v1 через
  AIExportV1Builder; новые правила к старому формату не применяются.
- `lib/features/ai_export/presentation/ai_export_dialog.dart`: выбор v2/v1,
  совпадающий с экспортом preview и предупреждение о возможных дублях.
- `test/ai_export_v2_test.dart`: сценарии ТЗ и пограничные конфликты идентичности.

Нормализация не заменяет аудит полноты банковского парсера. Без доказанных связей
экспорт сообщает неопределённость, а не создаёт недостающие финансовые факты.

## Проверки — 24 сентября 2026

- 45 тестов экспорта v1/v2, сохранения и UI прошли (включая 28 новых сценариев v2
  и переключения версии). Сохраняется проверка истории из 10 000 операций.
- Вместе со связанными тестами Synoball, cash flow, корзины, Sber import,
  financial codec, периодов, desktop shell и mobile parity: 159 прошли,
  1 пропущен из-за отсутствия локального входного файла. После этого добавлен
  ещё один случай реального счёта с произвольным названием и повторно пройдены
  все 45 тестов экспорта.
- Проверки не выгружали реальные финансовые данные пользователя.
- `flutter analyze --no-pub`: замечаний нет. Windows release `1.0.49+50` собран
  и установлен по прежнему ярлыку. Хэши установленного exe и data/app.so совпадают
  со сборкой; перед установкой сохранены данные, secure storage, банковский профиль
  и предыдущая версия в локальной резервной копии. Автоматически приложение не
  запускалось; реальное окно сохранения пользователь проверяет отдельно.
- Android native save bridge не изменялся; тест на реальном телефоне остаётся
  отдельным шагом. Нового APK эта задача не устанавливает.
