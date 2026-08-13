# Миграция аналитики Qesto на Synoball

## Новый read path

```text
Source adapter
  → raw payload / ingestion record
  → transaction candidate
  → reconciliation + evidence
  → canonical transaction
  → QestoReadModelService
  → BudgetController.transactions
  → существующие budget/statistics services
  → UI и графики
```

Ни один экран Qesto не читает Android notification, receipt, statement или CBR payload. Source-specific код заканчивается в adapter layer.

## Почему сохранена `BudgetTransaction`

Существующая статистика уже покрыта тестами и реализует много продуктовой логики: периоды, фильтры, сравнения, heatmap, merchant/category drilldown, возвраты, переводы, накопления и качество данных. Немедленная замена всех view-моделей дала бы высокий риск расхождения цифр без пользовательской пользы.

Поэтому `BudgetTransaction` стала временной read model Qesto. Она пересчитывается из canonical state и не является источником истины. Следующим этапом отдельные тяжёлые графики можно переводить на `SynoballAnalyticsReadService` без изменений ingestion.

## Compatibility checklist

| Возможность | До | После | Проверка |
|---|---|---|---|
| Обзор месяца | `BudgetCalculationService` | тот же сервис над canonical read model | widget + budget tests |
| Расходы/доходы | `TransactionType` | direction → совместимый `TransactionType` | statistics tests |
| Фильтры | account/category/merchant/date по legacy list | те же поля из read model | widget/statistics tests |
| Категории и цвета | `BudgetConfiguration` | Qesto config сохранён, canonical category mapped by id | widget tests |
| Merchant analysis | `normalizedMerchant` | Synoball merchant resolver → read model | statistics tests + core tests |
| Cash-flow | расчёт по legacy list | расчёт по canonical read model; доступен и native `CashflowSummary` | statistics/core tests |
| Динамика расходов | budget services | без изменений входного контракта | budget/widget tests |
| Heatmap по дням | statistics services | даты canonical transaction | statistics tests |
| Самая дорогая категория дня | statistics aggregation | category read model | statistics tests |
| Повторяющиеся операции | legacy bool | `RecurringStream` + совместимый bool | core/statistics tests |
| Подписки | частично recurring/upcoming | recurring streams и expected events | core tests |
| Планируемые расходы | `UpcomingExpense` | сохранены отдельно от expected events | widget tests |
| Общий бюджет | `BudgetPeriod` | отдельная Qesto-сущность, считает canonical read model | budget tests |
| Бюджеты категорий | `CategoryBudget` | без изменения product model | widget/budget tests |
| Активы/долги/инвестиции | account type, частично | canonical account types + derived Financial State | core tests |
| Качество данных | legacy flags | legacy flags сохранены; native quality дополнена freshness/completeness/reliability | statistics/core tests |

## Денежная точность

Synoball хранит деньги только в minor units и сериализует API-значение строкой (`1490.50`). Выписки и чеки больше не теряют копейки. Для визуальной совместимости текущий Qesto read model округляет сумму к целым рублям, потому что существующие форматтеры и графики используют `int` рублей. Точное значение остаётся в canonical state и может использоваться новым UI без повторного импорта.

## Контроль совпадения

Автоматически проверены старые widget/unit сценарии, включая:

- итог бюджета и добавление расхода;
- импорт PDF-выписки и undo;
- QR/OCR чек и позиции;
- Android notification;
- статистические периоды, фильтры, merchant/category grouping;
- потенциальные дубли и data quality;
- сохранение/восстановление пользовательского документа.

Дополнительные Synoball tests проверяют объединение notification + bank + receipt, recurring stream, voice confirmation, bulk statement reconciliation, Financial State, AI Context и CBR fixture adapter.

## Отключение legacy path

Legacy `transactions` пока dual-written как восстановимая Qesto read model внутри пользовательского документа. Удалять её безопасно только после:

1. миграционной телеметрии нескольких релизов;
2. проверки документов v1/v2 на реальных устройствах;
3. перевода всех экранов редактирования на canonical DTO;
4. отдельной backup/export функции;
5. сравнения месячных расходов, категорий и cash-flow до/после на пользовательских fixtures.
