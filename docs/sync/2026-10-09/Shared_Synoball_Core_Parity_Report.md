# Qesto Sync — Shared Synoball Core & Parity

Дата: 09.10.2026. Ограниченный implementation slice №1. Сетевая синхронизация
не реализована. Рабочая версия приложения остаётся **1.0.68+69**.

## 1. Исследование и решение

Повторно проверены текущее ядро, canonical models, adapters, enrichment,
reconciliation, identity, app bridge/read models, codec и тесты; сверены документы
A–E от 08.10.2026. Baseline снят с **реального рабочего дерева**, не с git HEAD:
предыдущие незакоммиченные мобильные и финансовые изменения сохранены.

`QESTO_AI_DEVELOPMENT_PROTOCOL_v0.1` и `AGENTS.md` в репозитории и проверенных
родительских каталогах не найдены. Проверка соответствия отсутствующему
документу не объявляется выполненной; его требования не выдумывались.

Минимальная граница для повторного использования reconciliation — существующие
canonical models + core + deduplicator/trust + enrichment/category/calendar +
normalized input adapters/identity. Enrichment необходим, потому что core
использует его при import, update и восстановлении. Flutter, BudgetController,
публичный API приложения и persistence не потребовалось рефакторить.

## 2. Что изменено и зачем

Создан приватный pure Dart пакет `packages/qesto_synoball_core`. В нём находится
**единственная** реализация Synoball. Библиотека не импортирует Flutter, Qesto,
`dart:io`, сеть, UI или хранилище; это дополнительно проверяет architecture test.

11 перенесённых файлов совпадают с исходными после нормализации переводов строк.
В двенадцатом, `SynoballCore`, единственное изменение — необязательный
`DateTime Function()? clock` с прежним default `DateTime.now`; восемь bookkeeping
вызовов используют его. Обратная подстановка этих изменений даёт исходный core.
Бизнес-даты и source observation timestamps не заменялись clock-ом.

Старые app-файлы теперь compatibility exports. Поэтому старые и новые импорты
имеют **одни и те же** типы, алгоритм и static process sequence ID-фабрики, что
проверяет app compatibility test. Не создана альтернативная дедупликация.

App подключает локальный path dependency. Runtime dependency `cryptography`
уже существовал в Qesto и нужен прежнему SHA-256 source identity. Новый `test` —
только dev dependency для standalone Dart runner; Flutter runner пакету не нужен.
Dependency resolution выполнен offline из cache. В CI добавлены три шага для
resolve/analyze/parity пакета, чтобы app suite не оставался единственным gate.

## 3. Полный список файлов данного slice

Каждый модуль ниже перенесён в `packages/qesto_synoball_core/lib/<модуль>`;
его прежний путь `apps/qesto_app/lib/synoball/<модуль>` заменён экспортом:

| Модуль | Изменение реализации |
| --- | --- |
| `core/models.dart` | Нет |
| `core/synoball_core.dart` | Только optional bookkeeping clock |
| `ingestion/adapter.dart` | Нет; ID factory неизменна |
| `reconciliation/deduplication.dart` | Нет |
| `reconciliation/source_trust_policy.dart` | Нет |
| `enrichment/enrichment.dart` | Нет |
| `enrichment/category_policy.dart` | Нет |
| `enrichment/recurrence_calendar.dart` | Нет |
| `adapters/adapters.dart` | Нет |
| `adapters/transaction_inputs.dart` | Нет |
| `adapters/notification_identity.dart` | Нет |
| `adapters/source_identity.dart` | Нет |

Остальные добавленные/изменённые файлы:

- `packages/qesto_synoball_core/lib/qesto_synoball_core.dart` — публичный barrel.
- `packages/qesto_synoball_core/pubspec.yaml`, `pubspec.lock`, `.gitignore`,
  `README.md` — пакет, зависимости, воспроизводимые проверки и контракт границы.
- `packages/qesto_synoball_core/test/parity_test.dart`.
- `packages/qesto_synoball_core/test/runtime_contract_test.dart`.
- `packages/qesto_synoball_core/test/support/parity_scenarios.dart`.
- `packages/qesto_synoball_core/test/goldens/legacy_manifest.json` — baseline и
  SHA-256 двенадцати прежних source-файлов.
- 13 `packages/qesto_synoball_core/test/goldens/legacy/<сценарий>.json`;
  точные имена перечислены в следующем разделе.
- `apps/qesto_app/test/shared_synoball_core_compatibility_test.dart`.
- `apps/qesto_app/pubspec.yaml`, `pubspec.lock` — local package dependency.
- `.github/workflows/ci.yml` — standalone core checks.
- Этот отчёт: `docs/sync/2026-10-09/Shared_Synoball_Core_Parity_Report.md`.

Временный capture tool удалён после фиксации прежних goldens: updater из нового
core намеренно не оставлен. Это предотвращает подмену oracle текущими результатами.

## 4. Parity и обратная совместимость

**До переноса** сняты полные результаты 13 сценариев старого core. После переноса
сравниваются command outcomes и полное JSON-состояние каждого шага: деньги,
canonical/provider IDs, source scope, raw payload, evidence, user locks, batches,
pending candidates, events/audit, корзина и восстановление.

| Golden filename без `.json` | Сценарий |
| --- | --- |
| `repeated-stable-provider` | Повторный import до/после restart |
| `two-similar-distinct-purchases` | Два provider ID при одинаковых сумме/времени; отличие в копейку |
| `notification-statement-receipt` | Уведомление, выписка и чек → один факт, три evidence |
| `user-overrides-and-field-locks` | Сумма, merchant, description, note и категория пользователя |
| `trash-replay-restore-posted` | Delete/replay/explicit restore posted |
| `trash-replay-restore-pending` | Сохранение pending lifecycle через корзину |
| `trash-replay-restore-cancelled` | Сохранение reversed lifecycle через корзину |
| `ambiguous-cross-source-batch-false` | Неоднозначный batch → review, без слепого merge |
| `ambiguous-cross-source-batch-true` | Тот же конфликт при обратном порядке кандидатов |
| `unconfirmed-deleted-identity-needs-review` | Похожая новая identity возле tombstone |
| `same-provider-different-source-scope` | Provider ID не сливает разные connections |
| `manual-ids-remain-distinct` | Два существующих ручных ID сохраняются отдельно |
| `money-currencies-directions-and-types` | RUB/USD/EUR/CNY, точные minor units, направления, account type и transfer tags |

Нормализованы **только** недетерминированные timestamps bookkeeping старого core:
canonical `createdAt`/`updatedAt`, event/audit `occurredAt`, event `changedAt`.
Никакие IDs, бизнес-даты, деньги или provenance не нормализуются. Новые runtime
tests отдельно проверяют настоящий clock, default clock, прежний формат/sequence
ID и полный JSON round trip **без** нормализации timestamps.

App compatibility tests проверяют идентичность типов/ID sequence через старые
импорты, codec round trip, корзину, исходные IDs и все существующие app transaction
types через legacy bridge/read model в четырёх валютах. До/после этой проекции
совпадают точные income, expenses, net Cash Flow и исключённые internal transfers.
Сами расчёты не изменялись. Canonical `FinancialEventType.observed` не подменялся
новым expense/income enum: направление и имеющиеся tags продолжают выполнять
свою существующую роль.

Схемы остаются прежними: Synoball schema **1**, model **1.0.0**, codec **7**.
Production IDs не переписаны; factory default и алгоритмы source identity
перенесены без изменений. Optional core clock не передаётся автоматически в
default ID factory: тестовый clock не меняет production ID epoch.

## 5. Результаты проверок

| Проверка | До изменений | После изменений |
| --- | --- | --- |
| Полный `flutter test --no-pub --reporter expanded` | 936 passed, 12 skipped, exit 0 | 939 passed, 12 skipped, exit 0 |
| `flutter analyze --no-pub` | No issues, exit 0 | No issues, exit 0 |
| Standalone `dart test --reporter expanded` | Пакета ещё нет; снят oracle прежнего core | 33 passed, exit 0; все 13 goldens совпали |
| Standalone `dart analyze` | Пакета ещё нет | No issues, exit 0 |
| App compatibility test | Теста ещё нет | 3 passed, exit 0; входят в 939 |
| `dart tool/storage_crash_regression.dart` | Дополнительно не запускался | 8 subprocess crash/recovery cases passed |
| `scripts/check_security_invariants.py` | Дополнительно не запускался | Passed для 9590 repository files, exit 0 |
| Format новых tests/barrel | — | 0 changes, exit 0 |
| `git diff --check` по изменённым tracked путям | — | Exit 0; только обычные LF/CRLF warnings |

Неуспешные промежуточные проверки не скрываются: первый новый compatibility test
не компилировался из-за nullable state и ошибочного имени legacy adapter; две
новые assertions ошибочно ожидали несуществующий expense/income event enum и
receiptId, не заданный input fixture. Исправлены тесты, **не production logic**;
frozen goldens не обновлялись. Первый post-change analyzer также нашёл два
style-замечания в import prefixes теста; после исправления analyzer и тест чистые.
Первый offline pub get упёрся в право записи SDK cache; повтор с разрешённым
cache access успешен, без загрузки финансовых данных/сетевой синхронизации.
Системный `python` оказался недоступным WindowsApps alias, а `py -3` не нашёл
установленный interpreter; security check успешно повторён bundled Python.

12 skips существовали до изменений и остались теми же: opt-in native bridge/OCR
и private local replay/corpus fixtures. Это не доказательство проверки реального
банковского профиля или физических устройств. Release APK/Windows build и
установку в этом slice не выполняли; platform-specific code не менялся.
CI-файл обновлён, но удалённый CI не запускался и PR не публиковался.

## 6. Границы неизменности

Сверены SHA-256 **511** существовавших на старте файлов `lib`, `test` и
`pubspec.yaml/lock` приложения. Изменились только ожидаемые 12 export shims и два
pubspec-файла; добавился один compatibility test. В частности, BudgetController,
UI, bank scenario/DOM adapters, bridge/read models, calculations, repositories,
codec и native financial storage не изменились относительно начала этого slice.
Разница этих файлов относительно git HEAD может содержать более раннюю работу —
она не откатывалась и не приписывается этому этапу.

Production-профиль не открывался и не редактировался; установленное приложение
не запускалось/не обновлялось. Новые tests используют только синтетические входы;
crash harness создаёт собственные временные файлы. Ни миграций, ни PostgreSQL,
ни изменения SQLite/JSON-хранилища, ни облачной авторизации/передачи данных нет.

## 7. Что доступно будущему серверу, что осталось снаружи

Будущий **Dart host** может импортировать этот пакет без Flutter и использовать:
normalized ingestion, существующее reconciliation/dedup/source trust, canonical
Money/state/evidence, source identities, user overrides/locks, delete/restore,
category/enrichment/recurring policy и JSON serialization/restoration. Состояние
в памяти; host самостоятельно обеспечивает транзакционное сохранение результата.
В существующий Python deals backend пакет автоматически не встраивается: выбор
server runtime/границы сервисов остаётся будущим решением.

Flutter-зависимы UI, navigation и BudgetController. Repository/vault, CEF и OS
capture остаются app/platform boundary. Bridge/read models и некоторые parsers
уже pure Dart, но связаны с app-моделями и не нужны shared reconciliation — они
оставлены в Qesto, а не ошибочно объявлены Flutter-зависимыми.

## 8. Оставшиеся риски и следующий gate

- Выделение не решает global user/entity/account/source binding: текущие локальные
  IDs, aliases и connection scopes сохранены, а не автоматически глобализованы.
- Default ID factory сохраняет прежние wall-clock/process ограничения; это не
  гарантия глобальной uniqueness между устройствами/процессами. Менять IDs и
  финансовые записи ради этого в данном slice запрещено и не выполнялось.
- Mutable core не является concurrent multi-tenant service: нужны проверка
  владельца, сериализация команд, atomic storage/outbox и revision/conflict policy.
- Raw/provenance может содержать приватные данные; pure Dart package не означает
  разрешение отправлять их в облако. Такое разрешение по-прежнему отсутствует.
- Время source facts должен задавать host; healthCheck остаётся wall-clock
  diagnostic. Goldens доказывают заявленные сценарии, не все возможные истории.
- Протокол разработки не предоставлен, физические Windows/Android и private
  profile replays не проверялись в этом slice.

**Можно переходить к отдельному native encrypted SQLite feasibility spike** для
Windows/Android на синтетическом изолированном хранилище: shared-core extraction
больше не является блокером. Сам spike, выбор encryption/native dependency,
данные пользователей, миграция и интеграция outbox требуют отдельного этапа.
Этот этап завершён; следующую реализацию автоматически не начинаем.
