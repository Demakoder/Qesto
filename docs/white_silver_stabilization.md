# White Silver stabilization — 1.0.47+48

## Подтверждённые причины

### Масштаб после холодного запуска

Windows запускает официальный CEF bootstrap `qesto.exe`; Flutter runner собран в `qesto.dll`. Объявление `PerMonitorV2` присутствовало в манифесте DLL, но отсутствовало в манифесте EXE. Старый сборочный шаг переносил только VERSIONINFO. Манифест DLL не устанавливает начальный DPI-режим процесса EXE.

На установленной 1.0.46 проведён последовательный read-only замер: после холодного запуска основной HWND процесса 24056 имел DPI **96**, awareness **0 (unaware)**. После открытия встроенного Сбера и возврата тот же процесс имел DPI **144**, awareness **2 (per-monitor)**. Синхронизация для этого не требовалась. Во время замеров окно было свёрнуто: нулевой client rect не использован как свидетельство размера видимого Flutter workspace.

CEF инициализируется лениво при открытии браузера. Именно начало работы браузерного runtime совпало с изменением DPI-режима, а не обычный `setState` страницы. В просмотренном browser flow не найдено изменения размера host-окна через `ShowWindow`/`SetWindowPos`. Не добавлялись таймеры, принудительные resize/rebuild или ранний запуск банка.

Исправление: сборка переносит DPI-декларации runner в **манифест исполняемого bootstrap**. Сохраняет исходные trustInfo, Common Controls dependency, compatibility и identity CEF. Режим применяется Windows до создания HWND. Проверяется результат в самом PE-файле, повторное применение идемпотентно.

Дополнительно убрано глобальное ограничение root до 520 px на узком окне и синтетическое переопределение MediaQuery. Рабочее пространство получает настоящие размеры View; DesktopAppShell продолжает реактивно выбирать компоновку через LayoutBuilder.

Документация Windows: [initial process DPI awareness](https://learn.microsoft.com/en-us/windows/win32/hidpi/setting-the-default-dpi-awareness-for-a-process), [SetProcessDpiAwarenessContext](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setprocessdpiawarenesscontext).

### График Overview

- QestoChartSurface имел фиксированную тёмную instrument-поверхность независимо от темы.
- Подписи Y размещались в фиксированной ширине; последняя подпись X могла выйти за правый край и обрезаться внешним ClipRRect.
- Высота раскрытого графика вычислялась из глобальной MediaQuery с вычитанием константы, а не из доступной области инструмента.
- Добавление/удаление обёртки Expanded при раскрытии пересоздавало State графика.

Теперь поверхность, сетка, оси, линия и tooltip используют semantic theme. Поля plot вычисляются по измеренным подписям, шрифту и TextScaler; painter и hit-testing используют одну геометрию. Tooltip ограничен локальной шириной, крайние подписи остаются внутри viewport, одиночная точка отображается. Flexible сохраняет элемент графика при смене compact/expanded; размер поступает из локальных constraints. Финансовая агрегация и значения series не менялись.

### Тёмная тема

Вложенные Theme принудительно выбирали Light; виджеты и CustomPainter использовали статические светлые цвета. Теперь QestoSemanticColors — ThemeExtension с Light White Silver и Dark Graphite Silver. Компоненты, формы, таблицы и painters получают роли из контекста; painters учитывают палитру в shouldRepaint. Silver-кнопки сохраняют градиент/кант, финансовые роли сохраняют смысл. Нет инверсии/ColorFiltered. Собственные цвета категорий и логотипов не преобразуются.

## Проверки и воспроизведение

- Widget/golden: Overview Light/Dark на 1024/1280/1440 и телефоне; QestoWindow, кнопки, формы, sidebar, операции, бюджет, ликвидность, долги, инвестиции, цели, ИИ, выгода.
- Regression: Light → Dark → Light с сохранением текста/State; compact → expanded → compact с Escape; resize раскрытого графика; tooltip у правой границы; измеренные оси при TextScaler 1/1.5/2; контраст стандартных денежных/текстовых ролей не ниже 4.5:1 на поверхности.
- Холодный QestoApp и последовательный resize 1024 → 1440 → 1280 → 700 → 1024 при DPR 1/1.5/2, без навигации в банк. Проверяются фактические MediaQuery, View DPR и ширина Scaffold.
- Desktop-тесты переведены с одного `binding.setSurfaceSize` на согласованные physicalSize/DPR тестового View. Старый fixture задавал layout 1440 при MediaQuery 800/DPR3; после удаления синтетического MediaQuery он ошибочно проверял мобильную ветку уведомлений.
- `windows/test_bootstrap_manifest.ps1`: проверка на копии бинарника, без запуска банка. DPI EXE, сохранение деклараций bootstrap, идемпотентность.
- `windows/inspect_window_metrics.ps1`: read-only native DPI/window/manifest probe; не читает финансовые данные и не меняет состояние окна.

Банковские парсеры, sync, Synoball, импорт, расчёты и хранилище не изменялись. Существующие regression tests этих подсистем запускаются вместе с UI-тестами.

### Границы проверки

Автоматический resize-тест не заменяет физический multi-monitor тест. Hot restart, DevTools profiling, переход между мониторами с разным масштабом и полный live Sber sync не заявляются проверенными этим набором. Нативную проверку установленного EXE при холодном запуске нужно дополнить после обновления; без неё нельзя считать пользовательскую приёмку DPI завершённой.

## Результаты сборки и тестов

- `flutter analyze --no-pub`: No issues found.
- Полный `flutter test --no-pub`: **563 passed, 8 skipped**. Пропуски — существующие opt-in проверки с локальными fixtures/runtime; не засчитаны как успешные.
- Финальный Windows release build: **успешно**, `qesto.exe` имеет версию **1.0.47+48**, CompanyName `ru.qesto`, ProductName `Qesto`, манифест EXE содержит `PerMonitorV2`.
- Нативный regression manifest пройден и в PowerShell 7, и в Windows PowerShell 5.1, используемом CMake. Для .NET Framework явно добавлена ссылка `System.Xml.dll`.
- Визуально просмотрены сгенерированные Light/Dark Overview, тёмный бюджет и таблица операций; дополнительные основные экраны покрыты golden/widget проверками.
- Это локальная тестовая Windows-сборка, не подписанный публичный релиз. Android APK в этом проходе не пересобирался.
- 22.09.2026 обновлена существующая установка и прежние Desktop/Start Menu ярлыки. Резервная копия: `C:/Users/ARM/AppData/Local/Qesto/Backups/1.0.47+48-20260922-234029-978`. Финансовое хранилище, ключ и банковский профиль скопированы с проверкой SHA-256; исходные данные оставлены на месте. Приёмка холодного запуска пользователем пока ожидается.
