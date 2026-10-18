# QESTO Mobile Stage 3 — операции, источники и редактор

Дата: 05.10.2026. Версия для проверки: **1.0.65+66**.

Статус: программная часть и проверки без телефона выполнены. Физическая Android QA отложена по просьбе пользователя; Stage 3 нельзя считать окончательно принятым до этой проверки. Stage 4 не начат. Новый PR не создавался.

## Исправленные safety-проблемы

1. Исправление входящего уведомления больше не открывает `AddExpenseScreen(addInitialAsNew: true)`. Этот путь записывал исправление через expense-specific команду. Теперь редактор возвращает только UI draft, а отдельное «Добавить» вызывает прежний notification/SMS intake с исходным типом, направлением, валютой и банковским provenance.
2. Сумма разбирается в целых minor units без double/округления: `123,45` → `12345`. Доход, возврат, перевод и расход сохраняют исходную семантику. Новые типы не введены.
3. Draft привязан к Android slot + delivery version. Открытие, Back и исправление не создают canonical operation/бюджетный период и не подтверждают raw notification. Ack выполняется прежним механизмом после сохранения; ошибки и retry не создают дубль.
4. Обычный mobile manual editor сохраняет стабильный draft ID при retry, передаёт точную сумму в существующий `addExpense`. Desktop вызовы с целым amount остаются совместимыми.
5. Исправлена потеря явного удаления подкатегории: legacy bridge теперь передаёт `clearSubcategoryId`, если seed действительно содержит null. Раньше canonical `copyWith` оставлял прежнюю подкатегорию.
6. Банковский pending статус нельзя подтвердить переключателем «Проверено». Служебные теги, raw description, тип, направление и identity остаются неизменными.
7. В mobile журнале вместо скрытого подтверждения всех кандидатов как «голосовых» — явный source-aware review route. `confirmVoiceCandidate` проверяет, что источник действительно manualVoice. Другие источники требуют своего review/import flow.
8. Повторное сохранение после ошибки подтверждения voice или удаления повторяет persistence по той же identity, не создавая второе подтверждение/операцию/soft delete.
9. Голосовой preview не создаёт бюджетный период при открытии. Отмена получения данных, preview и editor проверена на неизменность canonical данных.

## Маршруты и Back contract

```text
Обзор / Операции / Бюджет / Капитал — сохранённые root Navigators
  ├─ аналитика → /operations/selection (exact IDs) → /transaction/:id
  ├─ журнал → /transaction/:id → /transaction/:id/edit
  ├─ quality indicator → /operations/attention → /transaction/:id
  └─ Ещё → Источники → notification inbox → /sources/notification/correct

+ → manual editor / voice review / receipt / screenshot / statement / Excel
  ├─ voice → /sources/voice/review → явное подтверждение
  └─ screenshot preview → /sources/screenshot/correct → явный импорт

Операция → Delete + confirm → существующая корзина → Restore
```

Editor без изменений закрывается сразу. Несохранённые изменения требуют confirm discard. При Save кнопка блокируется; при ошибке остаются поля и сообщение для retry. Save находится в нижней безопасной области над keyboard inset. Android Back использует тот же PopScope contract. Успешный Save возвращает detail либо исходный review; exact-ID analytics selection и её State не заменяются общим журналом.

Очередь «Требуют внимания», открытая из аналитики, использует исходный `StatisticsController`: сохраняются период, фильтры и исключённые пользователем issues. При закрытии очереди заимствованный controller не уничтожается. Новый пустой manual draft не считается изменённым только из-за нулевой начальной суммы; валидация Save и проверка несохранённых изменений разделены.

## Detail/editor

- `MobileTransactionDetail` читает операцию по ID из существующего controller. Показывает точную сумму, тип/направление, дату/время, категорию/подкатегорию, контрагента, счёт, комментарий, tags, review/confidence, provenance и состав чека при наличии.
- `TransactionEditorScreen` — presentation над существующим `BudgetTransaction`, не mobile финансовая модель. Изменяет только поддерживаемые поля через прежний controller.
- Тип/направление read-only. Currency/system tags/bank description/receipt не меняются. При изменении типа другим процессом Save просит переоткрыть editor.
- Draft correction не имеет собственного ledger/repository. Comment/tags недоступны там, где intake их не поддерживает; это явно показано.
- Category/rule scope использует существующие `classification_actions`, не вторую систему правил.
- Selection toolbar адаптирует прежние category/tags/review/delete/export actions. Bank-pending записи не становятся posted. Delete/restore — прежняя корзина.

## Источники и imports

| Flow | Что работает в этом slice |
| --- | --- |
| Notification / SMS inbox | Typed preview, исправление, точные копейки, явное подтверждение, прежний identity review/ack/retry |
| Manual expense | Общий editor, exact minor units, прежний ManualInputAdapter, stable-ID retry |
| Android voice | Прежний typed parser/form, теперь полноценный mobile review route, явный confirm, read-only cancel |
| Чек / QR / фото чека | Прежний typed receipt preview и correction магазина/категории/счёта; прежний импорт/прикрепление чека |
| Bank screenshot | Прежний OCR/identity adapter, mobile draft editor вместо desktop candidate dialog, тип сохраняется, explicit batch import/retry |
| PDF/TXT statement / Excel | Прежний picker/parser и preview количества/типов/selected rows, прежняя account selection и explicit batch import |

SMS здесь означает уже поддерживаемые SMS-уведомления/вставленный текст, не новое разрешение READ_SMS. Банковский CEF не переносился на Android.

Notification capture определяется платформой, не шириной: Android tablet имеет те же capabilities. «Нет доступа» → объяснение → native settings → lifecycle resume → re-check. Enabled/denied/unavailable/error/empty/pending статусы не декоративные. Уже записанный inbox остаётся доступен при отозванном разрешении. Host сохраняет одну существующую event subscription; status controller только читает состояние и не импортирует данные.

Внешняя source attention indication foundation сохранена. Возврат из inbox обновляет статус, но сам по себе не запускает новый intake/не подтверждает отменённый draft.

## Файлы Stage 3

Новые production-файлы:

```text
lib/features/budget/
  transaction_editor_screen.dart
  transaction_route_scope.dart
  mobile_selection_toolbar.dart
lib/mobile/transactions/
  mobile_transaction_detail.dart
  mobile_attention_queue.dart
  mobile_pending_review.dart
```

Изменены mobile shell/adapters/source status, `desktop_app_shell.dart`, journal и attention dispatch, notification/screenshot/voice presentation, analytics drilldown dispatch, `budget_controller.dart`, `qesto_legacy_bridge.dart`, версия `pubspec.yaml`.

Старые detail/AddExpenseScreen/desktop drawer не используются основным mobile lifecycle. Сохранены для desktop и не подключённых legacy screens. Foundation adapters остальных доменов сохранены, mass redesign не проводился.

### Изменения за пределами presentation

- Financial models: **не менялись в Stage 3**.
- Synoball: только bounded bug fix `qesto_legacy_bridge.clearSubcategoryId`; core/adapters/schema/расчёты не переписывались.
- BudgetController: обратно совместимые optional exactAmountMinor/transactionId для manual expense; source guard и evidence-based retry voice confirmation; повтор persistence удаления. Это существующие intake/update/trash commands, не новый engine.
- Repository, persistence codec/schema, migrations: **без изменений**.
- Native Android bridge/MainActivity/permissions: **без изменений**; использован прежний openSettings/lifecycle/capture.

В worktree присутствовали предыдущие foundation/recurring/model изменения. Они сохранены и входят в regression/build, но не являются изменениями этой Stage 3 задачи. Установленный Windows профиль и финансовые данные не открывались и не редактировались; Windows приложение не переустанавливалось.

## Автоматическая проверка

Новые тесты:

- `mobile_transaction_editor_test.dart`: все существующие типы/transfer directions, integer/fractional amounts, canonical result, account/category/subcategory/note/tags, raw evidence, dirty/clean Back, double Save, persistence retry, delete/restore, manual exact retry.
- `pending_notification_editor_safety_test.dart`: expense/income/refund/transfer × integer/fraction, correction merchant/category/account, canonical direction/minor units/source evidence, discard/no period mutation, retry persistence/ack без дублей.
- `mobile_stage3_lifecycle_test.dart`: keyboard inset/hittable Save, очередь quality после исправления, bulk delete/error/retry/restore, voice candidate Back/confirm retry.
- Отдельный lifecycle regression проверяет заимствование периода/фильтров attention queue и сохранение владельца read model после Back.
- `mobile_screenshot_review_test.dart`: четыре типа × draft correction/error/retry → canonical import, scanner cancellation, 320 px layout.
- Расширены foundation route/back/scope tests и общие picker/voice/manual cancel tests; permission/status/large Android capability tests сохранены.

Окончательная проверка на неизменном production-коде:

- `flutter test --no-pub --concurrency=1 --reporter expanded`: **839 passed, 12 skipped, 0 failed**, 4 мин 5 с. Включены existing desktop regression, финансовые/import/native-contract тесты и новые mobile тесты. Opt-in/native проверки с пропусками не объявляются выполненными.
- `flutter analyze --no-pub`: **No issues found**, 6,5 с.
- Дополнительный targeted прогон editor + общих import/cancel widgets: **36 passed**.
- Renderer `tool/mobile_stage3_preview_test.dart`: **1 passed**, получены семь PNG.

В промежуточном parallel прогоне существующий `bank_sync_ui_test` получил `pumpAndSettle` timeout; отдельно и в полном последовательном прогоне он прошёл без изменения bank production/test кода. Последний баг clean Back у нового нулевого manual draft исправлен и проверен заново полным suite; окончательный прогон выше уже содержит это исправление.

### APK

- `flutter build apk --release --no-pub`: **успешно**, Gradle assembleRelease 254,7 с.
- [Qesto-1.0.65-mobile-stage3.apk](C:/Users/ARM/Documents/Qesto/apps/qesto_app/build/app/outputs/flutter-apk/Qesto-1.0.65-mobile-stage3.apk): **1.0.65+66**, package `ru.qesto.qesto`, 98 468 332 байта (93,9 MiB).
- ABI: arm64-v8a / armeabi-v7a / x86_64; min SDK 24, target SDK 36. Проверено чтением готового APK через `aapt`, не только `pubspec`.
- `apksigner verify`: подпись **валидна**, APK Signature Scheme v2. Это локальная **тестовая release-сборка с Android Debug подписью**, не production/store signing. Сертификат SHA-256 `5ad742281bf9eb813f3e71ed722e77d09ad08d1120954deec8a219fc7871a916` совпадает с сохранённым foundation APK 1.0.64, поэтому подпись совместима с обновлением поверх той сборки.
- SHA-256 APK: `4162744a589b7639baacd2673bf5573e23b461fc1062ec22ee8297964caa4797`.
- Foundation APK сохранён без перезаписи. На телефон APK **не установлен**. Windows приложение, его банковский профиль и пользовательское финансовое хранилище не менялись этой сборкой.
- В build log есть не блокирующее SDK XML version warning от Android toolchain; сборка и проверка подписи завершились успешно. SDK/toolchain в этой задаче не обновлялся.

Диагностические renders (реальные widgets, синтетические данные, не телефон):

- [Operations](stage3-20261005/01-operations.png)
- [Transaction Detail](stage3-20261005/02-transaction-detail.png)
- [Transaction Edit](stage3-20261005/03-transaction-editor.png)
- [Attention queue](stage3-20261005/04-attention.png)
- [Sources](stage3-20261005/05-sources.png)
- [Permission denied](stage3-20261005/06-permission-denied.png)
- [Import review](stage3-20261005/07-import-review.png)

Воспроизводимый renderer: `tool/mobile_stage3_preview_test.dart`; не читает установленный профиль, реальный inbox или банк.

Рендеры визуально проверены: видны route Back и нижние действия, нет debug banner/overflow; screenshot review дополнительно проверен на ширине 320 px. Это снимки widgets, а не свидетельство проверки устройства.

## Ограничения и проверка на телефоне

1. Физический smoke-test **ещё не выполнен**: пользователь подключит телефон позже. Автоматические renders не заменяют native settings/IME/Android back gestures/OCR/camera проверку.
2. Обычный journal всё ещё использует адаптированный lazy desktop page; toolbar/detail/editor/review routes мобильные. Overview/Budget/Capital redesign отложен.
3. Category/rule/tag selection, delete confirmation и date/time pickers остаются стандартными dialogs; это не desktop state details. Receipt preview и statement preview используют прежние экраны. Capital overlays не мигрировались.
4. Voice parser по-прежнему whole-currency; fractional UI поддержана для manual/notification/screenshot/canonical editor, не заявляется новая voice NLP поддержка.
5. Statement per-row correction не изобреталась там, где её не было в прежнем intake: доступны существующие selection/account mapping. После импорта — общий editor.
6. У не-voice pending candidates нет универсального подтверждения: требуется исходный review. Это намеренная защита, а не создание второго pipeline.
7. Persistence команды по-прежнему могут применяться in-memory до завершения записи. При ошибках поддержан same-ID retry; новая транзакционная rollback/storage архитектура не вводилась.

Когда телефон будет доступен, установить APK поверх foundation без удаления данных и проверить: Operations → Detail → Edit/Save/Back/discard; category/rule; delete/restore и bulk; denied → settings → grant → resume; income/refund/transfer/fraction notification correction; picker/scanner/preview cancel и error/retry; keyboard верхние/нижние поля/Save; scoped analytics → operation → edit → Back в исходную выборку. Stage 4 требует отдельного согласования.
