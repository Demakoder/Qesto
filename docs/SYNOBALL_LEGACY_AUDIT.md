# Аудит legacy-финансового слоя Qesto

Дата аудита: 13 августа 2026 года.

## Резюме

До миграции Qesto не имел отдельной серверной финансовой БД. Все пользовательские данные сохранялись одним JSON-документом `qesto.user-financial-data.v1` в `SharedPreferences`. Главной операционной моделью была `BudgetTransaction`; UI бюджета, статистика, импорт выписок, уведомлений и чеков создавали или читали её напрямую.

Новый слой Synoball добавлен внутрь Flutter-проекта в `apps/qesto_app/lib/synoball`. Состояние ядра сохраняется в том же пользовательском документе как независимый раздел `synoball`, поэтому миграция не требует серверной инфраструктуры и не теряет существующую локальную историю. `BudgetTransaction` пока оставлен как совместимая Qesto read model, но больше не является финансовым source of truth.

## Legacy storage и модели

| Область | До миграции | Кто создавал | Кто читал | Решение |
|---|---|---|---|---|
| Пользовательский документ | `lib/data/persistence/user_financial_data_codec.dart`, SharedPreferences | `LocalQestoRepository` | `QestoApp` | Схема документа поднята до v2; decoder продолжает читать v1 |
| Пользователь | `QestoUser` | пустая fixture / repository | shell, профиль | Маппится в `SynoballEntity(PERSON)`, Qesto user остаётся продуктовой сущностью |
| Счета и баланс | `QestoAccount`, сумма в целых рублях | fixture, импорт выписки | бюджет, статистика, экраны счетов | Маппятся в `SynoballAccount`, canonical balance хранится в minor units |
| Транзакции | `BudgetTransaction`, сумма в целых рублях | ручной ввод, уведомления, чеки, выписки, fixture | бюджет, статистика, история, детали | Мигрируют через `LegacyQestoAdapter`; Qesto получает read model из canonical transactions |
| Категории | `BudgetCategory`, `CategoryBudget`, fixture `budget_categories.dart` | системная конфигурация, выбор пользователя | бюджет, статистика, фильтры | Бюджеты остаются Qesto-объектами; category/provider/user override разделены в canonical transaction |
| План бюджета | `BudgetPeriod`, `CategoryBudget`, `BudgetPlanPoint` | fixture / UI controller | budget services и графики | Не превращается в transaction; продолжает считать выполнение по canonical read model |
| Планируемые траты | `UpcomingExpense` | editor, fixture | бюджет, forecast | Остаются пользовательскими планами; не смешиваются с Synoball expected events |
| Чек и позиции | `TransactionReceiptDetails`, `TransactionReceiptItem` | QR/OCR receipt flow | экран деталей транзакции | Мигрируют в `SynoballReceipt` / `ReceiptItem`, связаны с canonical transaction |
| Регулярность | `BudgetTransaction.isRecurring`, `UpcomingExpenseSource` | fixture / ручные данные | бюджет, статистика | Дополнительно вычисляется `RecurringStream`; legacy-флаг сохраняется при миграции |
| Действия и undo | `FinancialAction` | `BudgetController` | журнал действий | Остаётся Qesto UX-моделью; undo меняет canonical state |
| Накопления | `SavingsGoal` | fixture | экран накоплений | Пока не входит в transaction core; сохраняется без изменений |
| Выгода | `Deal`, `TrackedProduct`, отдельный Python deals service | deals API / fixture | экраны выгоды | Не является финансовым ядром, не мигрируется в Synoball |

## Источники данных

### Ручной ввод

- UI: `lib/features/budget/add_expense_screen.dart`.
- Старый write path: `BudgetController.addExpense` сразу создавал `BudgetTransaction`.
- Новый path: `ManualInputAdapter → IngestionRecord → TransactionCandidate → reconciliation → CanonicalTransaction`.
- Пользовательское сохранение считается подтверждением, поэтому candidate подтверждается автоматически.

### Голосовой ввод

В репозитории до миграции не было реализации speech-to-text, voice UI или voice parser. Упоминание голосового ввода в исходном ТЗ описывало целевую возможность, а не существующий код. Созданы `VoiceInputAdapter`, pending candidate и отдельное подтверждение. Это позволяет подключить будущий speech UI, не меняя бюджет, аналитику и core.

### Android-уведомления

- Native capture: `android/app/src/main/kotlin/ru/qesto/qesto/BankNotificationListener.kt` и `NotificationInbox.kt`.
- Flutter bridge: `notification_capture_service.dart`.
- Parser: `bank_notification_parser.dart` + `merchant_category_classifier.dart`.
- Старый write path: screen вызывал общий `addExpense`, источник после сохранения терялся в комментарии.
- Новый path: screen передаёт неизменённые title/text в `AndroidNotificationAdapter`; raw payload, notification key, confidence и evidence сохраняются отдельно.

### Кассовые чеки

- QR parser: `receipt_qr_parser.dart`.
- OCR parser: `receipt_ocr_parser.dart`.
- Scanner services: `receipt_scanner_service_*`.
- Старый matcher: `receipt_transaction_matcher.dart` искал близкую операцию по округлённой сумме и дате.
- Новый path: `ReceiptAdapter` хранит raw QR/OCR, точную сумму в копейках, fiscal fingerprint, позиции и user corrections; core reconciliation либо создаёт transaction, либо добавляет evidence к существующей.

### Банковские выписки

- File readers: `bank_statement_file_service_*` и web PDF.js reader.
- Parser: `sberbank_statement_parser.dart`.
- Старый write path: screen создавал список `BudgetTransaction`, округляя копейки и сохраняя точное значение только в комментарии.
- Новый path: один `StatementAdapter` создаёт `ImportBatch`, raw statement, candidates и account; canonical money получает точные minor units. Qesto UI по-прежнему показывает округлённые рубли для визуальной совместимости.

### Legacy data

`QestoLegacyBridge` и `LegacyQestoAdapter` выполняют одноразовую lazy-миграцию при первом открытии v1-документа. Каждому старому id соответствует тот же canonical id. Legacy records намеренно не объединяются между собой автоматически: ранее видимые операции сохраняются, а потенциальные дубли остаются в Data Quality до появления более надёжного evidence.

### Будущий Open Finance

Создан fixture-oriented `CbrOpenFinanceAdapter` версии `mock-1.0.0` для Institution, Connection, Consent, Accounts, Balances и Transactions. Модель ЦБ не используется как внутренняя canonical schema.

## Аналитика и прямые зависимости

До миграции следующие компоненты напрямую работали с `List<BudgetTransaction>`:

- `BudgetCalculationService`, `BudgetForecastService`, `CategoryBudgetCalculationService`;
- `StatisticsCalculationService`, `StatisticsInsightsService`, `DataQualityService`;
- `StatisticsController` и drilldown screens;
- receipt matcher и transaction details;
- экраны категорий, budget dynamics, spending donut и списки операций.

Они не переписаны вслепую. Теперь `BudgetController` строит этот список через `QestoReadModelService` исключительно из `SynoballState.transactions`. Поэтому старые расчёты и графики продолжают работать, но source-specific модели больше не попадают в них напрямую.

## Активы, долги, инвестиции, доходы и расходы

- Доход, расход, перевод, возврат, перевод в накопления и инвестиция были вариантами `TransactionType`. В canonical schema они представлены независимыми `direction`, tags и provenance.
- Активы/долги/инвестиции существовали частично через `AccountType` и экран счетов, но отдельного asset ledger, debt schedule или investment engine не было.
- `FinancialStateService` теперь выводит liquid money, income, expenses, free cashflow, assets, debts и investments из canonical accounts/transactions. Полноценный investment engine намеренно не добавлялся.

## API

До миграции финансового API не существовало. Единственный сетевой API приложения относился к акциям/промокодам (`services/deals_ingestion`) и не связан с пользовательскими финансами.

Созданы внутренний `SynoballApiV1` и transport-neutral OpenAPI contract. Текущая локальная реализация не поднимает HTTP-сервер и не отправляет финансовые данные с устройства.

## Что можно удалить только после проверки миграции

- Прямое JSON-поле `transactions` и legacy codec для него — после нескольких релизов успешной v1→v2 миграции.
- Legacy-флаги внутри `BudgetTransaction` — после перевода оставшихся экранов на native Synoball read models.
- Старый `ReceiptTransactionMatcher` — после полного переключения receipt UX на reconciliation result ядра.
- Source-specific helpers в presentation layer — после того, как screens будут передавать adapter inputs без промежуточного `BudgetTransaction`.

Сейчас ничего из этого не удалено: совместимость и восстановимость важнее чистоты папок.

## Выявленные ограничения legacy-продукта

- Нет регистрации/серверной синхронизации и шифрованной remote DB.
- Нет voice capture UI.
- Нет пользовательского CRUD категорий; есть системный справочник и выбор категории операции.
- Нет реальных bank/Open Finance connections, consent и credentials.
- Нет отдельного asset/debt/investment ledger.
- Денежный UI исторически работает в целых рублях. Canonical core уже хранит копейки, но часть Qesto-компонентов отображает округлённое значение.

Эти ограничения не замаскированы фиктивными реализациями и не блокируют расширение core.
