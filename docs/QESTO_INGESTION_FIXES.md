# Qesto — выполнение плана укрепления импорта

Дата: 2026-09-06. Основание: `QESTO_INGESTION_AUDIT.md` и `NEXT_CODEX_SPEC_INPUT.md`.

Последующие пакеты: [корзина и восстановление](QESTO_TRANSACTION_TRASH.md), [устойчивые ID уведомлений, Excel и OCR](QESTO_SOURCE_IDENTITY.md), [локальная сверка Сбера и диагностика строк](QESTO_SBER_RECONCILIATION.md). Таблица ниже описывает границы первого пакета; актуальные дополнения и оставшиеся ограничения указаны в этих документах.

## Что изменено

Это **первый проверяемый пакет**, а не объявление всех 13 этапов завершёнными. Изменения выполнялись поверх существующего dirty working tree `codex/sber-browser-sync`, HEAD `5b4ac1829e215d15c57031b0a117e2ed3e673921`. Прежняя работа с CEF, интерфейсом и планировщиком сохранена. Пользовательские финансовые файлы, банковская сессия и установленный EXE не изменялись. Git commit/push не выполнялись.

| Этап | Реализовано в этом пакете | Что ещё не закрыто |
|---|---|---|
| S01 | Конфликты известных account/currency/connection/institution запрещают автоматическое объединение. Равные лучшие совпадения становятся pending review, не выбираются по порядку. Конфликт canonical ID / tombstone не создаёт второй объект с тем же ID | Полный mapping принадлежности, передача connection scope из каждого источника и все перестановки восьми источников требуют дальнейшей работы/D01 |
| S02 | Повтор одного уже сохранённого unresolved notification/SMS delivery переиспользует pending candidate. Android acknowledgement сверяет key + opaque deliveryVersion, поэтому старая обработка не удаляет новое уведомление. Sber/generic OCR сохраняют отдельные одинаковые строки внутри одного изображения; первый legacy ID сохранён, дополнительные строки получают occurrence suffix | Excel filename/cell identity, Sber fingerprint migration и сопоставление разных скриншотов остаются. Notification deliveryVersion не является economic identity: переиспользование OS key для другой покупки ещё требует отдельного решения. Нужны D02/D03 и migration manifest |
| S03 | UI DTO сохраняет optional exact minor units; legacy read/write и codec их передают. Sber web не теряет копейки суммы и основного баланса. Cash Flow суммирует minor units и округляет только итоговую подпись. Знак отрицательного баланса исправлен | Остальные графики/целочисленные подписи сохраняют текущий UX; полный precision audit капитал/долги/все UI consumers и восстановление уже потерянных копеек не выполнены |
| S04 | Убран full-object user-confirmed writer из повторного импорта. Пользовательские изменения помечают принадлежащие пользователю поля, source refresh их сохраняет. Есть явное снятие category override | Исторический userConfirmed не сбрасывается автоматически: авторство старых полей неоднозначно (D04) |
| S05 | Posted не откатывается в pending; старое наблюдение того же источника не заменяет более новое. Active status/type flags согласуются; Cash Flow понимает generic pending/cancelled | Полная модель refund/reversal/transfer legs, fees и финансовая сверка требуют D06; не заявлена полная parity всех аналитических consumers |
| S06 | Общий resolver исключает заведомо другой банк/валюту. Доказанный virtual placeholder можно обогатить реальным счётом; известный счёт не заменяется placeholder | PDF/web/card aliases, несколько CEF профилей и произвольный fallback веб-импорта остаются отдельной задачей D01 |
| S07 | Ошибка decode/future schema — ошибка восстановления, а не пустой профиль. После failed load autosave запрещён. Recoverable JSON writer сохраняет last-known-good backup, сериализует read-modify-write и использует файловую блокировку. UI notification выполняется после save. Failed/unresolved native import не ack ни автоматически, ни кнопкой обычного добавления; batch с pending не complete. Screenshot preview не закрывается как success при unresolved/failed | Инъекции исключений проверены, hard process kill/power loss — нет. Файловая блокировка не является полной изоляцией двух независимых app-level snapshots. Android durable storage/native inbox остаются gate S12 |
| S08 | `partial` проходит от коннектора до результата планировщика и не продвигает lastSuccessfulSyncAt. Неизвестный hasMore не считается концом истории. Core отдаёт ordered candidate→canonical resolution в результате команды (без изменения JSON schema). Список/счётчики транзакций Сбера сравнивают состояние до и после успешного save; учитывают копейки и защищённые user fields. Unresolved/failed имеют отдельную подпись и неполный итог | Incremental coverage cursor, полная детализация причин failed/rejected и построчная сверка текущего Сбера не выполнены (D08). Счётчики счетов пока считают upsert-предложения относительно предыдущего состояния, merge отображается отдельно |
| S09 | Zone lease отменяет право поздней финансовой записи; timed-out browser job удерживает ownership до фактического завершения. Generation защищает от импорта результата, начатого до wipe/dispose. Profile metadata изменяется атомарным read-modify-write с recovery backup | Полный multi-process application lock, все native close failure scenarios, все пути удаления/импорта и состав полного wipe требуют дальнейшей проверки/D05/D07 |
| S10 | Изменённая версия наблюдения с тем же provider ID сохраняет новое evidence; точный повтор не множит evidence и обновляет latest delivery link/observedAt. Время наблюдения отделено от времени покупки | Universal resolved-candidate lineage, replay command, raw retention/cleanup и восстановление не сохранённых ранее raw данных не реализованы; D02/D04/D05 |
| S11 | Положительная сумма, формат currency code и строгая точность Money JSON проверяются; неверные дополнительные десятичные разряды не отбрасываются молча | Не введён полный ISO currency/exponent catalogue. Aggregate-versus-detail accounting, inferred screenshot amounts/dates и строгая проверка ownership требуют D03/D06 |
| S12 | Unit/widget, synthetic source flows и реальные временные JSON-файлы на Windows проверены. Android `:app:compileDebugKotlin --offline --console=plain --no-daemon` прошёл, включая новый native acknowledgement | Реальный Android, opt-in native OCR/PDF/Whisper, private Excel corpus, live CEF/bank, process-kill acceptance не запускались. Компиляция не заменяет проверку NotificationListener/Keystore на телефоне |
| S13 | Подтверждение Android voice preview вызывает core confirmation; stable command ID сохраняется при retry; save failure не закрывает preview как success. Desktop speech остаётся pending до подтверждения | Физический Android microphone/persistence acceptance — S12 |

## Регрессионные проверки

Новые проверки сначала воспроизвели потерю голосовой операции, ложное объединение разных счетов, выбор первого из равных совпадений и потерю копеек при reimport. После исправлений эти сценарии проходят.

- `test/synoball_safety_test.dart`: разные accounts/connections, provider scope, ambiguity, stale lifecycle, observation versions, strict Money.
- `test/financial_write_safety_test.dart`: точная сумма/reimport/edit/codec, Cash Flow minor totals, отрицательный баланс, bank/currency conflicts, stale result после wipe.
- `test/storage_recovery_safety_test.dart`: malformed/future schema; interruption после staging/backup/commit, повторный сбой во время recovery; concurrent writes; удалённое значение не восстанавливается из backup после успешного remove.
- Дополнены voice, Sber extractors, bank schedule и browser profile tests.
- Notification tests моделируют обновление inbox между read/save/ack, в том числе legacy delivery без версии и замену неподдерживаемого сообщения банковской операцией. MethodChannel test проверяет передачу expectedVersion.
- Sber report tests проверяют конфликт валюты (review, не «принято»), изменение только копеек, сохранённые пользовательские поля вместо предложенных парсером.
- Два OCR regression tests сначала упали с `1` вместо `2` строк. После исправления Sber/generic parser сохраняют обе; synthetic Synoball flow добавляет две покупки на 40000 minor и не добавляет новых при точном повторе.
- В старых tests обогащения счёта теперь явно обозначен virtual unresolved account. Это не разрешение объединять два известных разных счёта: отдельные negative tests это запрещают.
- Tests автоматической переклассификации теперь создают исходную запись через адаптер, а не через legacy user-confirmed migration. Неоднозначные исторические пользовательские данные не стали автоматически изменяемыми ради прохождения теста.
- UI test переключателя запускает реальную файловую запись в `tester.runAsync`, чтобы synthetic fake zone не блокировала ожидание сериализованного real I/O.

Итоговый прогон после всех правок этого пакета:

- `flutter test --no-pub --reporter expanded`: **356 passed, 7 skipped**, exit 0 (48 секунд). Пропущены только opt-in Windows OCR/PDF/Whisper и private Excel fixtures.
- `flutter analyze --no-pub`: **No issues found**, exit 0.
- Android `:app:compileDebugKotlin --offline --console=plain --no-daemon`: **BUILD SUCCESSFUL**, exit 0. Есть прежние предупреждения Gradle/AGP/Kotlin о deprecated flags и совместимости версии SDK XML; миграция build system не включалась в пакет.
- `git -c core.safecrlf=false diff --check`: без ошибок whitespace.

Android compile выполнялся после всех изменений Kotlin; последующие изменения Dart дополнительно проверены полным прогоном test/analyze. Установочный APK/EXE не собирался и не развёртывался.

## Совместимость и ограничения выпуска

- Canonical Synoball JSON contract не расширялся новыми обязательными полями. Optional exact-amount DTO fields читаются с fallback `major × 100`; codec version оставлен 6, обязательная миграция данных не запускается.
- Новые source/user-field tags и optional bank sync status используются только новым кодом. Старый EXE не следует запускать параллельно с будущей новой сборкой: старые writers не знают новых защит.
- Последняя валидная копия хранится рядом с JSON. Удаление ключа записывает уже очищенное состояние и в backup, чтобы удалённые финансовые данные не появились из старой копии после следующей ошибки primary. Исходные документы пользователя и CEF cookies не удаляются.
- Массового merge/reclassification/reimport исторических данных нет. Потерянные ранее суммы и пропущенные операции не выдумываются.
- OCR occurrence suffix сохраняет кратность строк внутри изображения и старый ID первой строки. Он не доказывает identity одинаковых покупок на разных изображениях: существующая межкадровая эвристика ещё требует замены на сопоставление с явной неоднозначностью, без исторического cutover в этом пакете.
- Native notification queue добавляет необязательный deliveryVersion к уже существующему encrypted envelope. Старые записи читаются с пустой версией; новый Android channel требует expectedVersion при acknowledgement. Смена экономического смысла под прежним OS key — не решённая этим revision-token задача.
- Этот пакет **не доказывает устранение прежнего расхождения 68/70 против 125 операций или конкретного Cash Flow пользователя**. Для этого нужен отдельный одинаковый диапазон/набор счетов и независимый row manifest.

## Требуются решения перед следующим пакетом

D02 подтверждён пользователем и реализован отдельным дополнением: ручное удаление → бессрочная корзина → явное восстановление, источник не отменяет удаление. См. `QESTO_TRANSACTION_TRASH.md` для реализации, тестов и границ будущей серверной доставки. D03 (Excel aggregate/detail) и D05 (состав полного wipe) пока не решены. Исторические source IDs не мигрируются. Отдельно остаются D01 (account/card/connection evidence), D06 (refund/own-transfer semantics), D07 (живое/закрытое приложение) и D08 (разрешённая live/fixture проверка полноты).

Следующий технический пакет: стабильные source identity builders с совместимыми aliases, scope/ambiguity для перекрывающихся OCR кадров и переиспользованных OS keys, полный per-row import result и review UI. Для исторического cutover сначала read-only manifest, проверка counts/minor totals/user edits и согласованный rollback.
