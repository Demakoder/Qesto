import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters/qesto_formatters.dart';
import '../../core/safety/financial_write_guard.dart';
import '../../core/platform/qesto_command_line.dart';
import '../../core/theme/qesto_theme.dart';
import '../../core/platform/external_url_launcher.dart';
import '../../data/models/qesto_models.dart';
import '../../features/bank_browser/config/bank_connector_registry.dart';
import '../../features/bank_browser/data/browser_profile_manager.dart';
import '../../features/bank_browser/domain/bank_browser_models.dart';
import '../../features/bank_browser/domain/bank_sync_models.dart';
import '../../features/bank_browser/runtime/browser_controller.dart';
import '../../features/bank_browser/dev/dev_browser_bridge.dart';
import '../../features/bank_browser/sber/sber_auth_manager.dart';
import '../../features/bank_browser/sber/sber_connector.dart';
import '../../features/bank_browser/sber/sber_connector_models.dart';
import '../../features/bank_browser/sber/sber_page_detector.dart';
import '../../features/bank_browser/sync/bank_sync_scheduler.dart';
import '../../features/budget/state/budget_controller.dart';
import '../../features/budget/services/cash_flow_calculation_service.dart';
import '../widgets/desktop_components.dart';

class DesktopBankConnectionsPage extends StatefulWidget {
  const DesktopBankConnectionsPage({
    super.key,
    this.profileManager,
    this.controller,
    this.bankSyncScheduler,
  });

  final BrowserProfileManager? profileManager;
  final BudgetController? controller;
  final BankSyncScheduler? bankSyncScheduler;

  @override
  State<DesktopBankConnectionsPage> createState() =>
      _DesktopBankConnectionsPageState();
}

class _DesktopBankConnectionsPageState
    extends State<DesktopBankConnectionsPage> {
  late final BrowserProfileManager _profiles =
      widget.profileManager ?? BrowserProfileManager();
  List<BankProfile> _items = const [];
  var _loading = true;
  var _busy = false;
  final _pinProfiles = <String>{};

  @override
  void initState() {
    super.initState();
    widget.bankSyncScheduler?.addListener(_onSchedulerChanged);
    unawaited(_initialize());
  }

  void _onSchedulerChanged() {
    if (mounted) unawaited(_reload());
  }

  Future<void> _initialize() async {
    await _reload();
    if (hasQestoCommandLineArgument('--qesto-bank-browser-open-sber')) {
      await _addSber();
    }
    if (hasQestoCommandLineArgument('--qesto-bank-browser-open-dev')) {
      for (final profile in _items) {
        if (profile.bankId == 'sber' && mounted) {
          await _openDev(profile, confirm: false);
          break;
        }
      }
    }
  }

  Future<void> _reload() async {
    final values = await _profiles.listProfiles();
    final pinProfiles = <String>{};
    try {
      for (final profile in values.where((p) => p.bankId == 'sber')) {
        final vault = SberPinVault(profileId: profile.id);
        await vault.migrateLegacy(_profiles);
        if ((await vault.read())?.isNotEmpty == true) {
          pinProfiles.add(profile.id);
        }
      }
    } on MissingPluginException {
      // Secure storage is provided by the Windows host; widget tests and
      // unsupported hosts simply render the PIN as not configured.
    }
    if (!mounted) return;
    setState(() {
      _items = values;
      _loading = false;
      _pinProfiles
        ..clear()
        ..addAll(pinProfiles);
    });
  }

  Future<void> _addSber() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final profile = await _profiles.createProfile(BankConnectorRegistry.sber);
      await widget.bankSyncScheduler?.refresh();
      if (!mounted) return;
      await _open(profile);
    } finally {
      if (mounted) setState(() => _busy = false);
      await _reload();
    }
  }

  Future<void> _open(BankProfile profile) async {
    final config = BankConnectorRegistry.byId(profile.bankId);
    if (config == null || !mounted) return;
    if (!_beginInteractive(profile)) return;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => BankBrowserPage(
            profile: profile,
            bank: config,
            profileManager: _profiles,
            budgetController: widget.controller,
            bankSyncScheduler: widget.bankSyncScheduler,
          ),
        ),
      );
    } finally {
      _endInteractive(profile);
      await _reload();
    }
  }

  Future<void> _syncProfile(BankProfile profile) async {
    final config = BankConnectorRegistry.byId(profile.bankId);
    if (config == null || !mounted || _busy) return;
    final latest = await _profiles.getProfile(profile.id);
    if (!mounted || latest == null) return;
    final range = profile.bankId == 'sber'
        ? await _showSberSyncRangeDialog(
            context,
            coveredThrough: latest.syncMetadata.lastHistorySyncThrough,
          )
        : null;
    if (profile.bankId == 'sber' && range == null) return;
    if (!mounted) return;
    final scheduler = widget.bankSyncScheduler;
    if (scheduler == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Фоновая синхронизация недоступна. Перезапустите Qesto.',
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final execution = await scheduler.refreshNow(profile.id, range: range);
      if (!mounted) return;
      final result = execution.result;
      final message = switch (execution.decision) {
        BankSyncStartDecision.busy =>
          'Браузер банка уже открыт или идёт синхронизация. Закройте страницу банка и повторите обновление.',
        BankSyncStartDecision.unavailable => 'Подключение больше недоступно.',
        BankSyncStartDecision.unsupported =>
          'Фоновое обновление этого банка недоступно.',
        _ => switch (result?.result) {
          BankSyncResult.cancelled => 'Синхронизация отменена',
          BankSyncResult.success => 'Сбер обновлён в фоне',
          BankSyncResult.partial =>
            'Данные сохранены частично — нужна проверка полноты или привязки счетов',
          BankSyncResult.authRequired =>
            'Сбер требует вход. Откройте банк кнопкой «Открыть», войдите и повторите обновление.',
          BankSyncResult.timeout =>
            'Истекло время ожидания банка. Повторите позже.',
          BankSyncResult.networkError => 'Нет соединения с банком.',
          _ =>
            'Синхронизация не завершена. ${result?.failureReason ?? "Попробуйте позже."}',
        },
      };
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(message),
          content: result == null
              ? null
              : Text(
                  'Новых операций: ${result.importedCount}\n'
                  'Обновлено операций и счетов: ${result.updatedCount}\n'
                  'Без изменений: ${result.deduplicatedCount}'
                  '${result.failureReason == null ? "" : "\nДиагностика: ${result.failureReason}"}',
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Готово'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      await _reload();
    }
  }

  Future<void> _openDev(BankProfile profile, {bool confirm = true}) async {
    final config = BankConnectorRegistry.byId(profile.bankId);
    if (config == null || !mounted || _busy) return;
    if (confirm) {
      final enabled = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Режим разработки'),
          content: const Text(
            'Локальные инструменты смогут читать содержимое открытого банковского профиля, DOM и отображаемые финансовые данные для разработки коннектора.\n\n'
            'Финансовые действия через Dev Inspector блокируются. Сессия работает только на этом компьютере и завершается при закрытии браузера.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Включить'),
            ),
          ],
        ),
      );
      if (enabled != true || !mounted) return;
    }
    if (!_beginInteractive(profile)) return;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => BankBrowserPage(
            profile: profile,
            bank: config,
            profileManager: _profiles,
            budgetController: widget.controller,
            bankSyncScheduler: widget.bankSyncScheduler,
            devMode: true,
          ),
        ),
      );
    } finally {
      _endInteractive(profile);
      await _reload();
    }
  }

  bool _beginInteractive(BankProfile profile) {
    final scheduler = widget.bankSyncScheduler;
    if (scheduler == null || scheduler.beginInteractiveSession(profile.id)) {
      return true;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Банк уже обновляется в фоне. Дождитесь завершения текущей синхронизации.',
        ),
      ),
    );
    return false;
  }

  void _endInteractive(BankProfile profile) {
    widget.bankSyncScheduler?.endInteractiveSession(profile.id);
  }

  Future<void> _saveSberPin(BankProfile profile) async {
    final vault = SberPinVault(profileId: profile.id);
    final input = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PIN быстрого входа Сбера'),
        content: TextField(
          controller: input,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(
            hintText: '4–8 цифр',
            helperText: 'Хранится только в защищённом хранилище Windows',
          ),
        ),
        actions: [
          if (_pinProfiles.contains(profile.id))
            TextButton(
              onPressed: () => Navigator.pop(context, '__delete__'),
              child: const Text('Удалить PIN'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    input.dispose();
    if (pin == null || pin.isEmpty) return;
    if (pin == '__delete__') {
      await vault.delete();
      if (mounted) {
        setState(() => _pinProfiles.remove(profile.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN удалён с этого компьютера.')),
        );
      }
      return;
    }
    try {
      await vault.write(pin);
      if (mounted) {
        setState(() => _pinProfiles.add(profile.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN сохранён на этом компьютере.')),
        );
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _delete(BankProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отключить банк?'),
        content: const Text(
          'Локальная сессия, cookie и все данные сайта в этом профиле будут полностью удалены. Финансовые данные Qesto не изменятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: QestoColors.negative,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить профиль'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!_beginInteractive(profile)) return;
    setState(() => _busy = true);
    try {
      await _profiles.deleteProfile(profile.id);
      if (profile.bankId == 'sber') {
        // The PIN belongs to this device connection, not to the financial
        // history. Remove it together with the CEF profile on disconnect.
        await SberPinVault(profileId: profile.id).delete();
        _pinProfiles.remove(profile.id);
      }
      await _reload();
      await widget.bankSyncScheduler?.refresh();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось удалить профиль. Закройте окно банка и попробуйте снова.',
            ),
          ),
        );
      }
    } finally {
      _endInteractive(profile);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    widget.bankSyncScheduler?.removeListener(_onSchedulerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 34),
      children: [
        DesktopSectionHeader(
          title: 'Подключения к банкам',
          subtitle:
              'Защищённый браузер хранит сессию только на этом компьютере. Qesto не видит логин, пароль или код подтверждения.',
          trailing: FilledButton.icon(
            key: const Key('bank-browser-add-sber'),
            onPressed: _busy ? null : _addSber,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Добавить банк'),
          ),
        ),
        const SizedBox(height: 18),
        DesktopCard(
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8EE),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.account_balance_rounded,
                  color: Color(0xFF16A05D),
                  size: 27,
                ),
              ),
              const SizedBox(width: 15),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'СберБанк Онлайн',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Официальный сайт · отдельный профиль CEF/Chromium · HTTPS',
                      style: TextStyle(
                        color: QestoColors.secondaryText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _addSber,
                icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                label: const Text('Подключить через веб-банк'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const DesktopSectionHeader(
          title: 'Локальные профили',
          subtitle:
              'Закрытие браузера не завершает банковскую сессию. Для полного выхода удалите профиль.',
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(34),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_items.isEmpty)
          const DesktopEmptyState(
            title: 'Банки пока не подключены',
            message:
                'Создайте локальный профиль и войдите на официальном сайте банка.',
            icon: Icons.lock_outline_rounded,
          )
        else
          for (final profile in _items) ...[
            _BankProfileCard(
              profile: profile,
              syncing:
                  widget.bankSyncScheduler?.manager.isSyncing(profile.id) ??
                  profile.syncMetadata.isSyncing,
              cancelling:
                  widget.bankSyncScheduler?.manager.isCancelling(profile.id) ??
                  false,
              onCancel: widget.bankSyncScheduler == null
                  ? null
                  : () =>
                        widget.bankSyncScheduler!.cancelCurrentSync(profile.id),
              onOpen: () => _open(profile),
              onSync: profile.bankId == 'sber'
                  ? () => _syncProfile(profile)
                  : null,
              onDev: profile.bankId == 'sber' ? () => _openDev(profile) : null,
              onSavePin: profile.bankId == 'sber'
                  ? () => _saveSberPin(profile)
                  : null,
              pinStored:
                  profile.bankId == 'sber' && _pinProfiles.contains(profile.id),
              onDelete: _busy ? null : () => _delete(profile),
              onBackgroundSyncChanged:
                  BankConnectorRegistry.byId(
                        profile.bankId,
                      )?.supportsBackgroundSync ==
                      true
                  ? (enabled) => widget.bankSyncScheduler
                        ?.setBackgroundSyncEnabled(profile.id, enabled)
                  : null,
              devDiagnostics: hasQestoCommandLineArgument(
                '--qesto-bank-browser-dev',
              ),
            ),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 18),
        DesktopCard(
          color: QestoColors.primarySoft,
          borderColor: QestoColors.primary.withValues(alpha: 0.18),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, color: QestoColors.primary),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Для СберБанка доступен локальный read-only коннектор: он читает только видимые страницы счетов и истории, не перехватывает запросы и не отправляет банковские данные в облако. Платежи, переводы и подтверждения операций заблокированы.',
                  style: TextStyle(fontSize: 11, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _SberPeriodChoice {
  sinceLastSync,
  currentMonth,
  last7Days,
  last30Days,
  last90Days,
  custom,
}

Future<SberSyncRange?> _showSberSyncRangeDialog(
  BuildContext context, {
  DateTime? coveredThrough,
}) async {
  var choice = coveredThrough == null
      ? _SberPeriodChoice.currentMonth
      : _SberPeriodChoice.sinceLastSync;
  DateTimeRange? custom;
  final now = DateTime.now();
  return showDialog<SberSyncRange>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Период синхронизации'),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Qesto загрузит операции только за выбранный период и остановит прокрутку, когда достигнет его начала.',
              ),
              const SizedBox(height: 14),
              for (final item in _SberPeriodChoice.values)
                ListTile(
                  enabled:
                      item != _SberPeriodChoice.sinceLastSync ||
                      coveredThrough != null,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    choice == item
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: choice == item
                        ? QestoColors.primary
                        : QestoColors.secondaryText,
                  ),
                  title: Text(_sberPeriodChoiceLabel(item)),
                  subtitle: item == _SberPeriodChoice.sinceLastSync
                      ? Text(
                          coveredThrough == null
                              ? 'Сначала нужна полная синхронизация периода'
                              : 'Проверено до ${_formatProfileDate(coveredThrough)}. Повторно проверим также предыдущий день.',
                        )
                      : item == _SberPeriodChoice.custom && custom != null
                      ? Text(
                          '${_sberShortDate(custom!.start)}—${_sberShortDate(custom!.end)}',
                        )
                      : null,
                  onTap: () async {
                    if (item != _SberPeriodChoice.custom) {
                      setDialogState(() => choice = item);
                      return;
                    }
                    final selected = await showDateRangePicker(
                      context: dialogContext,
                      firstDate: DateTime(now.year - 5),
                      lastDate: now,
                      initialDateRange:
                          custom ??
                          DateTimeRange(
                            start: DateTime(now.year, now.month),
                            end: now,
                          ),
                      helpText: 'Выберите период операций Сбера',
                      cancelText: 'Отмена',
                      confirmText: 'Выбрать',
                    );
                    if (selected != null) {
                      setDialogState(() {
                        choice = item;
                        custom = selected;
                      });
                    }
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: choice == _SberPeriodChoice.custom && custom == null
                ? null
                : () => Navigator.pop(
                    dialogContext,
                    _sberRangeFor(
                      choice,
                      now: now,
                      custom: custom,
                      coveredThrough: coveredThrough,
                    ),
                  ),
            child: const Text('Начать синхронизацию'),
          ),
        ],
      ),
    ),
  );
}

String _sberPeriodChoiceLabel(_SberPeriodChoice value) => switch (value) {
  _SberPeriodChoice.sinceLastSync => 'С последней успешной синхронизации',
  _SberPeriodChoice.currentMonth => 'Текущий месяц',
  _SberPeriodChoice.last7Days => 'Последние 7 дней',
  _SberPeriodChoice.last30Days => 'Последние 30 дней',
  _SberPeriodChoice.last90Days => 'Последние 90 дней',
  _SberPeriodChoice.custom => 'Выбрать даты',
};

SberSyncRange _sberRangeFor(
  _SberPeriodChoice value, {
  required DateTime now,
  DateTimeRange? custom,
  DateTime? coveredThrough,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final toExclusive = today.add(const Duration(days: 1));
  return switch (value) {
    _SberPeriodChoice.sinceLastSync => SberSyncRange.sinceLastSync(
      coveredThrough,
      now,
    ),
    _SberPeriodChoice.currentMonth => SberSyncRange(
      from: DateTime(now.year, now.month),
      toExclusive: toExclusive,
      label: 'Текущий месяц',
    ),
    _SberPeriodChoice.last7Days => SberSyncRange(
      from: today.subtract(const Duration(days: 6)),
      toExclusive: toExclusive,
      label: 'Последние 7 дней',
    ),
    _SberPeriodChoice.last30Days => SberSyncRange(
      from: today.subtract(const Duration(days: 29)),
      toExclusive: toExclusive,
      label: 'Последние 30 дней',
    ),
    _SberPeriodChoice.last90Days => SberSyncRange(
      from: today.subtract(const Duration(days: 89)),
      toExclusive: toExclusive,
      label: 'Последние 90 дней',
    ),
    _SberPeriodChoice.custom => SberSyncRange(
      from: DateTime(custom!.start.year, custom.start.month, custom.start.day),
      toExclusive: DateTime(
        custom.end.year,
        custom.end.month,
        custom.end.day + 1,
      ),
      label: 'Выбранные даты',
    ),
  };
}

String _formatProfileDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}, ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _sberShortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

class _BankProfileCard extends StatelessWidget {
  const _BankProfileCard({
    required this.profile,
    required this.onOpen,
    required this.onDelete,
    this.onSync,
    this.onSavePin,
    this.onDev,
    this.onBackgroundSyncChanged,
    this.onCancel,
    this.syncing = false,
    this.cancelling = false,
    this.pinStored = false,
    this.devDiagnostics = false,
  });

  final BankProfile profile;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onSync;
  final VoidCallback? onSavePin;
  final VoidCallback? onDev;
  final ValueChanged<bool>? onBackgroundSyncChanged;
  final VoidCallback? onCancel;
  final bool syncing;
  final bool cancelling;
  final bool pinStored;
  final bool devDiagnostics;

  @override
  Widget build(BuildContext context) {
    final date = profile.lastOpenedAt;
    final metadata = profile.syncMetadata;
    final opened =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    return DesktopCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_rounded,
                color: Color(0xFF16A05D),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.displayName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        _BankSyncStateBadge(metadata: metadata),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Последний вход: $opened · данные только на устройстве',
                      style: const TextStyle(
                        color: QestoColors.secondaryText,
                        fontSize: 10,
                      ),
                    ),
                    if (metadata.lastSuccessfulSyncAt case final syncedAt?)
                      Text(
                        'Обновлено: ${_formatProfileDate(syncedAt)}',
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 10,
                        ),
                      )
                    else if (profile.lastSyncAt case final syncedAt?)
                      Text(
                        'Последняя синхронизация: ${_formatProfileDate(syncedAt)}',
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 10,
                        ),
                      ),
                    if (profile.bankId == 'sber')
                      Text(
                        'PIN быстрого входа: ${pinStored ? 'сохранён' : 'не сохранён'}',
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.login_rounded, size: 17),
                label: Text(metadata.needsAuthentication ? 'Войти' : 'Открыть'),
              ),
              if (onSavePin != null)
                IconButton(
                  tooltip: 'Сохранить или изменить PIN Сбера',
                  onPressed: onSavePin,
                  icon: const Icon(Icons.password_rounded, size: 18),
                ),
              if (onSync != null)
                FilledButton.icon(
                  key: const Key('bank-sync-now'),
                  onPressed: syncing ? null : onSync,
                  icon: syncing
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded, size: 17),
                  label: Text(syncing ? 'Обновляется…' : 'Обновить сейчас'),
                ),
              if (syncing && onCancel != null)
                TextButton.icon(
                  key: const Key('bank-sync-cancel'),
                  onPressed: cancelling ? null : onCancel,
                  icon: const Icon(Icons.stop_circle_outlined, size: 17),
                  label: Text(cancelling ? 'Отменяется…' : 'Отменить'),
                ),
              if (onDev != null)
                IconButton(
                  tooltip: 'Открыть локальный DEV Inspector',
                  onPressed: onDev,
                  icon: const Icon(Icons.developer_mode_rounded, size: 18),
                ),
              IconButton(
                tooltip: 'Отключить и удалить локальную сессию',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
              ),
            ],
          ),
          if (onBackgroundSyncChanged != null) ...[
            const Divider(height: 24),
            Row(
              children: [
                const Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: QestoColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Автоматическая синхронизация',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        !metadata.backgroundSyncEnabled
                            ? 'Выключена'
                            : metadata.needsAuthentication
                            ? 'Приостановлена до повторного входа'
                            : metadata.nextScheduledSyncAt == null
                            ? 'Примерно каждый час'
                            : 'Следующее обновление: ${_formatProfileDate(metadata.nextScheduledSyncAt!)}',
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  key: const Key('bank-background-sync-toggle'),
                  value: metadata.backgroundSyncEnabled,
                  onChanged: onBackgroundSyncChanged,
                ),
              ],
            ),
          ],
          if (metadata.lastAttemptAt != null && !metadata.isSyncing) ...[
            const SizedBox(height: 10),
            Text(
              'Последняя попытка: новых ${metadata.importedCount}, '
              'обновлено ${metadata.updatedCount}, без изменений ${metadata.deduplicatedCount}',
              style: const TextStyle(
                fontSize: 11,
                color: QestoColors.secondaryText,
              ),
            ),
            if (metadata.lastResult == BankSyncResult.partial)
              const Text(
                'Получены частичные данные. Полная синхронизация ещё не подтверждена.',
                style: TextStyle(fontSize: 11, color: QestoColors.warning),
              ),
            if (metadata.lastFailureReason?.contains(
                  'ACCOUNT_MAPPING_UNRESOLVED',
                ) ==
                true)
              const Text(
                'Часть операций сохранена без привязки к конкретному счёту.',
                style: TextStyle(fontSize: 11, color: QestoColors.warning),
              ),
          ],
          if (devDiagnostics)
            ExpansionTile(
              key: const Key('bank-sync-dev-diagnostics'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                'DEV · фоновая синхронизация',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              children: [
                _diagnosticRow('Connection', profile.id),
                _diagnosticRow('State', metadata.state.name),
                _diagnosticRow(
                  'Last attempt',
                  _optionalDate(metadata.lastAttemptAt),
                ),
                _diagnosticRow(
                  'Last success',
                  _optionalDate(metadata.lastSuccessfulSyncAt),
                ),
                _diagnosticRow(
                  'Next scheduled',
                  _optionalDate(metadata.nextScheduledSyncAt),
                ),
                _diagnosticRow(
                  'Duration',
                  metadata.syncDurationMs == null
                      ? '—'
                      : '${metadata.syncDurationMs} ms',
                ),
                _diagnosticRow('Last result', metadata.lastResult?.name ?? '—'),
                _diagnosticRow(
                  'Failure reason',
                  metadata.lastFailureReason ?? '—',
                ),
                _diagnosticRow(
                  'History through',
                  _optionalDate(metadata.lastHistorySyncThrough),
                ),
                _diagnosticRow('Imported', '${metadata.importedCount}'),
                _diagnosticRow('Deduplicated', '${metadata.deduplicatedCount}'),
                _diagnosticRow(
                  'Browser mode',
                  metadata.lastBrowserMode?.name.toUpperCase() ?? '—',
                ),
                _diagnosticRow(
                  'Auth state',
                  metadata.needsAuthentication ? 'REQUIRED' : 'VALID',
                ),
                const _BankDiagnosticProfileRow(),
              ],
            ),
        ],
      ),
    );
  }

  static String _optionalDate(DateTime? value) =>
      value == null ? '—' : _formatProfileDate(value);

  static Widget _diagnosticRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: const TextStyle(
              color: QestoColors.secondaryText,
              fontSize: 10,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ],
    ),
  );
}

class _BankSyncStateBadge extends StatelessWidget {
  const _BankSyncStateBadge({required this.metadata});

  final BankSyncMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (metadata.state) {
      BankConnectionSyncState.connected => (
        'Подключён',
        const Color(0xFF16A05D),
      ),
      BankConnectionSyncState.syncing => ('Обновляется', QestoColors.primary),
      BankConnectionSyncState.authRequired => (
        'Требуется вход',
        QestoColors.warning,
      ),
      BankConnectionSyncState.temporaryError => (
        metadata.lastResult == BankSyncResult.partial
            ? 'Частичные данные'
            : 'Временная ошибка',
        QestoColors.warning,
      ),
      BankConnectionSyncState.failed => ('Ошибка', QestoColors.negative),
      BankConnectionSyncState.disconnected => (
        'Не подключён',
        QestoColors.secondaryText,
      ),
      BankConnectionSyncState.disabled => (
        'Автообновление выключено',
        QestoColors.secondaryText,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _BankDiagnosticProfileRow extends StatelessWidget {
  const _BankDiagnosticProfileRow();

  @override
  Widget build(BuildContext context) =>
      _BankProfileCard._diagnosticRow('Profile', 'existing persistent profile');
}

class BankBrowserPage extends StatefulWidget {
  const BankBrowserPage({
    required this.profile,
    required this.bank,
    required this.profileManager,
    this.budgetController,
    this.bankSyncScheduler,
    this.autoSyncOnOpen = false,
    this.devMode = false,
    this.initialSyncRange,
    super.key,
  });

  final BankProfile profile;
  final BankConnectorConfig bank;
  final BrowserProfileManager profileManager;
  final BudgetController? budgetController;
  final BankSyncScheduler? bankSyncScheduler;
  final bool autoSyncOnOpen;
  final bool devMode;
  final SberSyncRange? initialSyncRange;

  @override
  State<BankBrowserPage> createState() => _BankBrowserPageState();
}

class _BankBrowserPageState extends State<BankBrowserPage> {
  late final BrowserController _controller = BrowserController(
    profile: widget.profile,
    bank: widget.bank,
    profileManager: widget.profileManager,
    onNotice: _showNotice,
  );
  late final SberConnector? _sberConnector = widget.bank.bankId == 'sber'
      ? SberConnector(browser: _controller)
      : null;
  StreamSubscription<SberSyncReport>? _sberSubscription;
  SberSyncReport? _sberReport;
  var _syncing = false;
  var _cancellingSync = false;
  FinancialWriteGuard? _standaloneSyncGuard;

  Future<void> _cancelSync() async {
    if (!_syncing || _cancellingSync) return;
    setState(() => _cancellingSync = true);
    _standaloneSyncGuard?.cancel();
    final scheduler = widget.bankSyncScheduler;
    if (scheduler != null) {
      await scheduler.cancelCurrentSync(widget.profile.id);
    } else {
      await _controller.stop();
    }
  }

  var _closing = false;

  @override
  void initState() {
    super.initState();
    final connector = _sberConnector;
    if (connector != null) {
      _sberSubscription = connector.listen((report) {
        if (mounted) setState(() => _sberReport = report);
      });
    }
    unawaited(_openAndMaybeSync());
  }

  Future<void> _openAndMaybeSync() async {
    await _controller.open();
    if (widget.devMode && _controller.isRuntimeReady) {
      await DevBrowserBridge.instance.start(
        browser: _controller,
        bank: widget.bank,
      );
    }
    if (!widget.autoSyncOnOpen ||
        !mounted ||
        _closing ||
        !_controller.isRuntimeReady) {
      return;
    }
    try {
      await _controller
          .waitForLoadState(BankBrowserLoadState.finished)
          .timeout(const Duration(seconds: 20));
    } on Object {
      // Sync still produces an explicit auth/parser result if loading is
      // interrupted; it must never appear to do nothing.
    }
    if (mounted && !_closing) {
      await _syncSber(
        requestedRange: widget.initialSyncRange,
        askForPeriod: false,
      );
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _close() async {
    if (_closing) return;
    _standaloneSyncGuard?.cancel();
    setState(() => _closing = true);
    try {
      if (!_syncing && _sberConnector != null && _controller.isRuntimeReady) {
        try {
          const detector = SberPageDetector();
          final page = await detector
              .inspect(_controller)
              .timeout(const Duration(seconds: 3));
          if (page != null &&
              switch (detector.detect(page)) {
                SberPageType.dashboard ||
                SberPageType.accounts ||
                SberPageType.accountDetails ||
                SberPageType.transactions ||
                SberPageType.savings ||
                SberPageType.deposit ||
                SberPageType.investments => true,
                _ => false,
              }) {
            await widget.bankSyncScheduler?.resumeAfterAuthentication(
              widget.profile.id,
            );
          }
        } on Object {
          // Closing never requires a successful inspection or changes auth
          // state based merely on the URL of an unresponsive bank page.
        }
      }
      await widget.bankSyncScheduler?.manager.cancel(widget.profile.id);
      if (widget.devMode) await DevBrowserBridge.instance.stop();
      await _controller.disposeEnvironment().timeout(
        const Duration(seconds: 10),
      );
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) {
        setState(() => _closing = false);
        _showNotice(
          'Браузер ещё завершает работу. Подождите и нажмите «Закрыть» повторно.',
        );
      }
    }
  }

  Future<void> _syncSber({
    SberSyncRange? requestedRange,
    bool askForPeriod = true,
  }) async {
    final connector = _sberConnector;
    if (connector == null || _syncing || _closing) return;
    var range = requestedRange;
    if (range == null && askForPeriod) {
      final latest = await widget.profileManager.getProfile(widget.profile.id);
      if (!mounted || _closing) return;
      range = await _showSberSyncRangeDialog(
        context,
        coveredThrough: latest?.syncMetadata.lastHistorySyncThrough,
      );
      if (range == null) return;
    }
    range ??= SberSyncRange.currentMonth();
    if (!mounted) return;
    setState(() => _syncing = true);
    SberSyncReport? completedReport;
    SberImportSummary? imported;
    QestoCashFlowSummary? diagnostic;
    int? closingCashBalance;
    final generation = widget.budgetController?.dataGeneration;
    final startedAt = DateTime.now();
    Future<BankSyncRunResult> performSync() async {
      final report = await connector.sync(range: range);
      FinancialWriteGuard.check();
      completedReport = report;
      final snapshot = report.snapshot;
      if (report.state == SberConnectorState.pinRequired ||
          report.state == SberConnectorState.fullLoginRequired) {
        return const BankSyncRunResult(
          result: BankSyncResult.authRequired,
          failureReason: 'USER_AUTHENTICATION_REQUIRED',
        );
      }
      if (report.state == SberConnectorState.error) {
        return BankSyncRunResult(
          result: BankSyncResult.bankUnavailable,
          failureReason: report.failureCode ?? 'SBER_CONNECTOR_ERROR',
        );
      }
      if (snapshot == null ||
          (snapshot.accounts.isEmpty && snapshot.transactions.isEmpty) ||
          (snapshot.historyRowsSeen > 0 &&
              snapshot.transactions.isEmpty &&
              !snapshot.hasVerifiedEmptyHistory)) {
        return const BankSyncRunResult(
          result: BankSyncResult.parserError,
          failureReason: 'EMPTY_OR_INVALID_BANK_SNAPSHOT',
        );
      }
      if (widget.budgetController != null) {
        imported = await widget.budgetController!.importSberSnapshot(
          snapshot,
          expectedGeneration: generation,
        );
        diagnostic = widget.budgetController!.cashFlowForRange(
          from: range!.from,
          toExclusive: range.toExclusive,
          currency: 'RUB',
        );
        closingCashBalance = widget.budgetController!.accounts
            .where(
              (account) =>
                  account.currency == 'RUB' &&
                  account.type != AccountType.investment &&
                  account.type != AccountType.liability,
            )
            .fold<int>(0, (sum, account) => sum + account.balance);
      }
      final newest = snapshot.transactions.isEmpty
          ? null
          : snapshot.transactions
                .map((item) => item.date)
                .reduce((left, right) => left.isAfter(right) ? left : right);
      return BankSyncRunResult(
        result:
            report.state == SberConnectorState.syncPartial ||
                (imported?.unresolvedCount ?? 0) > 0 ||
                (imported?.unassignedAccountCount ?? 0) > 0
            ? BankSyncResult.partial
            : BankSyncResult.success,
        failureReason: report.importFailureReason(imported),
        importedCount: imported?.newCount ?? 0,
        updatedCount:
            (imported?.updatedCount ?? 0) + (imported?.accountsUpdated ?? 0),
        deduplicatedCount: imported?.unchangedCount ?? 0,
        lastImportedTransactionAt: newest,
        historySyncedThrough: range!.verifiedThrough(startedAt),
      );
    }

    try {
      final scheduler = widget.bankSyncScheduler;
      final standaloneGuard = scheduler == null ? FinancialWriteGuard() : null;
      _standaloneSyncGuard = standaloneGuard;
      final execution = scheduler == null
          ? BankSyncExecution(
              decision: BankSyncStartDecision.started,
              result: await standaloneGuard!.run(performSync),
            )
          : await scheduler.runManual(
              await widget.profileManager.getProfile(widget.profile.id) ??
                  _controller.profile,
              performSync,
              onCancel: _controller.stop,
            );
      if (execution.decision == BankSyncStartDecision.busy) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Синхронизация этого банка уже выполняется.'),
            ),
          );
        }
        return;
      }
      if (execution.decision == BankSyncStartDecision.unavailable) {
        _showNotice(
          'Сессия Qesto завершена. Закройте браузер банка и откройте его заново.',
        );
        return;
      }
      final report = completedReport;
      if (execution.result?.result == BankSyncResult.cancelled) {
        _showNotice('Синхронизация отменена');
        return;
      }
      final summary = imported;
      if (execution.result?.isSuccess == true && scheduler == null) {
        await widget.profileManager.updateLastSync(
          _controller.profile,
          DateTime.now(),
        );
      }
      if (mounted && !_closing && report != null && summary != null) {
        await _showSberResult(
          report,
          summary,
          period:
              '${_sberShortDate(range.from)}—${_sberShortDate(range.toExclusive.subtract(const Duration(days: 1)))}',
          diagnostic: diagnostic,
          closingCashBalance: closingCashBalance,
        );
      } else if (mounted && !_closing && report != null) {
        await _showSberFailure(report);
      } else if (mounted && !_closing && execution.result?.isSuccess != true) {
        await _showSberFailure(
          SberSyncReport(
            state: SberConnectorState.error,
            message: _manualSyncFailureMessage(execution.result),
          ),
        );
      }
    } on FinancialWriteCancelled {
      _showNotice('Синхронизация отменена');
    } finally {
      _standaloneSyncGuard = null;
      if (mounted) {
        setState(() {
          _syncing = false;
          _cancellingSync = false;
        });
      }
    }
  }

  String _manualSyncFailureMessage(BankSyncRunResult? result) =>
      switch (result?.result) {
        BankSyncResult.partial =>
          'История получена частично. Полнота периода не подтверждена.',
        BankSyncResult.authRequired =>
          'Сбер попросил повторно подтвердить вход.',
        BankSyncResult.timeout =>
          'Синхронизация превысила допустимое время. Попробуйте позже.',
        BankSyncResult.parserError =>
          'Страница загрузилась, но безопасный парсер не подтвердил данные.',
        BankSyncResult.networkError || BankSyncResult.bankUnavailable =>
          'Сбер временно недоступен или отсутствует подключение к сети.',
        _ => 'Синхронизация Сбера не завершена.',
      };

  Future<void> _showSberResult(
    SberSyncReport report,
    SberImportSummary summary, {
    required String period,
    QestoCashFlowSummary? diagnostic,
    int? closingCashBalance,
  }) async {
    final snapshot = report.snapshot;
    if (!mounted || snapshot == null) return;
    final partial =
        report.state == SberConnectorState.syncPartial ||
        summary.unresolvedCount > 0 ||
        summary.unassignedAccountCount > 0;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          partial ? 'Синхронизация завершена частично' : 'Сбер синхронизирован',
        ),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 620),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _syncMetric('Найдено операций', summary.found),
                  _syncMetric('Новых', summary.newCount),
                  _syncMetric('Обновлено', summary.updatedCount),
                  _syncMetric(
                    'Категорий пересчитано',
                    summary.recategorizedCount,
                  ),
                  _syncMetric('Без изменений', summary.unchangedCount),
                  if (summary.deletedCount > 0)
                    _syncMetric('Оставлено в корзине', summary.deletedCount),
                  if (summary.unresolvedCount > 0)
                    _syncMetric(
                      'Требуют проверки / не приняты',
                      summary.unresolvedCount,
                    ),
                  _syncMetric('Счетов найдено', summary.accountsFound),
                  _syncMetric('Балансов обновлено', summary.accountsUpdated),
                  if (summary.unassignedAccountCount > 0) ...[
                    _syncMetric(
                      'Сохранены, но счёт не определён',
                      summary.unassignedAccountCount,
                    ),
                    const Text(
                      'Эти операции учтены в денежном потоке, но не приписаны случайной карте. Сверка по счетам пока неполна.',
                      style: TextStyle(color: QestoColors.warning),
                    ),
                  ],
                  if (summary.accountsMerged > 0)
                    _syncMetric(
                      'Дубликатов счетов объединено',
                      summary.accountsMerged,
                    ),
                  _syncMetric('В обработке', snapshot.pendingCount),
                  const SizedBox(height: 8),
                  Text('Период: $period'),
                  if (snapshot.historyRowsSeen > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'История: ${snapshot.historyRowsAccepted} денежных операций из ${snapshot.historyRowsSeen} записей',
                      style: const TextStyle(color: QestoColors.secondaryText),
                    ),
                    if (snapshot.historyHasMoreRows &&
                        !snapshot.historyRangeBoundaryReached)
                      const Text(
                        'Полнота истории не подтверждена: остались страницы или не удалось проверить конец списка.',
                        style: TextStyle(color: QestoColors.warning),
                      ),
                    if (snapshot.historyRewardRows > 0)
                      Text(
                        'СберСпасибо: ${snapshot.historyRewardRows} неденежных операций',
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                        ),
                      ),
                    if (snapshot.historyRowsOutsidePeriod > 0)
                      Text(
                        'Вне выбранного периода: ${snapshot.historyRowsOutsidePeriod} '
                        '(не являются ошибками импорта)',
                      ),
                    if (snapshot.historyDiagnostics.any(
                      (d) => d.outcome.isError,
                    ))
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Почему часть строк не распознана'),
                        children: [
                          for (final row in snapshot.historyDiagnostics.where(
                            (d) => d.outcome.isError,
                          ))
                            ListTile(
                              dense: true,
                              title: Text(row.description),
                              subtitle: Text(
                                [
                                  if (row.date != null)
                                    formatDate(row.date!, includeYear: true),
                                  row.outcome.label,
                                ].join(' · '),
                              ),
                            ),
                        ],
                      ),
                    if (snapshot.historyRowsRejected > 0)
                      Text(
                        'Не распознано строк: ${snapshot.historyRowsRejected}. Результат нельзя считать полным.',
                        style: const TextStyle(color: QestoColors.warning),
                      ),
                    if (snapshot.historyLoyaltyRewards >
                        snapshot.historyRewardRows)
                      Text(
                        'Бонусных начислений в денежных операциях: ${snapshot.historyLoyaltyRewards - snapshot.historyRewardRows}',
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                        ),
                      ),
                    if (snapshot.historyServiceRows > 0)
                      Text(
                        'Служебные действия: ${snapshot.historyServiceRows} (не влияют на баланс)',
                        style: const TextStyle(
                          color: QestoColors.secondaryText,
                        ),
                      ),
                  ],
                  if (widget.devMode && diagnostic != null)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: const Text('DEV · Денежный поток всего профиля'),
                      subtitle: Text(
                        'Net: ${formatMoney(diagnostic.netCashFlow, 'RUB', showSign: true)}',
                      ),
                      children: [
                        _diagnosticMoneyRow(
                          'Внешние поступления',
                          diagnostic.externalInflows,
                        ),
                        _diagnosticMoneyRow(
                          'Внешние списания',
                          diagnostic.externalOutflows,
                        ),
                        _diagnosticMoneyRow(
                          'Внутренние переводы исключены',
                          diagnostic.internalTransfersExcluded,
                        ),
                        _syncMetric(
                          'Неденежных/неподтверждённых исключено',
                          diagnostic.ignoredTransactions,
                        ),
                        _syncMetric(
                          'СберСпасибо проигнорировано',
                          snapshot.historyLoyaltyRewards,
                        ),
                        if (closingCashBalance != null)
                          _diagnosticMoneyRow(
                            'Текущий баланс денежных счетов всего профиля',
                            closingCashBalance,
                          ),
                        const Padding(
                          padding: EdgeInsets.only(top: 6, bottom: 4),
                          child: Text(
                            'Сверка opening → closing недоступна: Сбер отдаёт текущий баланс, но не снимок баланса на начало выбранного периода.',
                            style: TextStyle(
                              color: QestoColors.secondaryText,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (summary.accounts.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text('Счета (${summary.accounts.length})'),
                      subtitle: Text(
                        '${summary.accountsUpdated} добавлено или обновлено',
                      ),
                      children: summary.accounts
                          .map(_sberAccountResultRow)
                          .toList(growable: false),
                    ),
                  if (summary.transactions.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text('Операции (${summary.transactions.length})'),
                      subtitle: Text(
                        '${summary.newCount} новых · ${summary.updatedCount} обновлено',
                      ),
                      children: summary.transactions
                          .map(_sberTransactionResultRow)
                          .toList(growable: false),
                    ),
                  if (report.message != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      report.message!,
                      style: const TextStyle(color: QestoColors.secondaryText),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
  }

  Future<void> _showSberFailure(SberSyncReport report) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Синхронизация Сбера не завершена'),
        content: Text(
          report.message ??
              'Сбер требует повторного входа или проверки страницы.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Widget _syncMetric(String label, int value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Widget _diagnosticMoneyRow(String label, int value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          formatMoney(value, 'RUB'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _sberAccountResultRow(SberAccountImportItem item) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(_sberChangeLabel(item.change)),
    trailing: Text(
      formatMoney(item.balance, item.currency),
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );

  Widget _sberTransactionResultRow(SberTransactionImportItem item) {
    final signedAmount = item.isIncome ? item.amount : -item.amount;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_sberShortDate(item.date)} · ${_sberChangeLabel(item.change)}',
      ),
      trailing: Text(
        formatMoney(signedAmount, item.currency, showSign: item.isIncome),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: item.isIncome ? const Color(0xFF16A05D) : null,
        ),
      ),
    );
  }

  String _sberChangeLabel(SberImportChange value) => switch (value) {
    SberImportChange.created => 'Добавлено',
    SberImportChange.updated => 'Обновлено',
    SberImportChange.unchanged => 'Без изменений',
    SberImportChange.needsReview => 'Требует проверки / не принято',
    SberImportChange.deleted => 'В корзине',
  };

  Future<void> _saveSberPin() async {
    final input = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PIN быстрого входа Сбера'),
        content: TextField(
          controller: input,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(
            hintText: '4–8 цифр',
            helperText: 'Хранится только в защищённом хранилище Windows',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    input.dispose();
    if (pin == null || pin.isEmpty) return;
    try {
      await SberPinVault(profileId: widget.profile.id).write(pin);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN сохранён только на этом компьютере.'),
          ),
        );
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  void dispose() {
    unawaited(_sberSubscription?.cancel());
    unawaited(_sberConnector?.dispose());
    if (widget.devMode) unawaited(DevBrowserBridge.instance.stop());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: QestoColors.background,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final state = _controller.state;
              return Column(
                children: [
                  _BankBrowserToolbar(
                    state: state,
                    devMode: widget.devMode,
                    onBack: state.canGoBack ? _controller.goBack : null,
                    onForward: state.canGoForward
                        ? _controller.goForward
                        : null,
                    onReload: state.lifecycle == BankBrowserLifecycle.loading
                        ? _controller.stop
                        : _controller.reload,
                    onHome: () => _controller.navigate(widget.bank.startUrl),
                    onClose: _close,
                    onCancelSync: _syncing && !_cancellingSync
                        ? _cancelSync
                        : null,
                    cancelling: _cancellingSync,
                    onSync: _sberConnector == null || _syncing
                        ? null
                        : () => _syncSber(),
                    onSavePin: _sberConnector == null ? null : _saveSberPin,
                    syncing: _syncing,
                    report: _sberReport,
                  ),
                  if (state.lifecycle == BankBrowserLifecycle.loading)
                    const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: _closing
                        ? const Center(child: CircularProgressIndicator())
                        : state.lifecycle == BankBrowserLifecycle.opening
                        ? const _BrowserStatus(
                            icon: Icons.shield_outlined,
                            title: 'Запускаем защищённый браузер',
                            message:
                                'Подготавливаем отдельный профиль CEF/Chromium…',
                            loading: true,
                          )
                        : state.lifecycle == BankBrowserLifecycle.error
                        ? _BrowserStatus(
                            icon: _controller.hasCertificateProblem
                                ? Icons.gpp_maybe_outlined
                                : Icons.error_outline_rounded,
                            title: _controller.hasCertificateProblem
                                ? 'Сертификат банка не доверен'
                                : 'Браузер не запустился',
                            message:
                                state.errorMessage ??
                                'Проверьте целостность компонентов CEF в папке Qesto.',
                            action: _controller.hasCertificateProblem
                                ? Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 10,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: () => unawaited(
                                          openExternalUrl(
                                            'https://www.gosuslugi.ru/crt',
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.open_in_new_rounded,
                                          size: 17,
                                        ),
                                        label: const Text(
                                          'Инструкция Госуслуг',
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            unawaited(_controller.reload()),
                                        icon: const Icon(
                                          Icons.refresh_rounded,
                                          size: 17,
                                        ),
                                        label: const Text('Проверить снова'),
                                      ),
                                    ],
                                  )
                                : null,
                          )
                        : _controller.isRuntimeReady
                        ? _controller.buildWebView(
                            key: ValueKey('bank-webview-${widget.profile.id}'),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BankBrowserToolbar extends StatelessWidget {
  const _BankBrowserToolbar({
    required this.state,
    required this.devMode,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onHome,
    required this.onClose,
    this.onSync,
    this.onSavePin,
    this.onCancelSync,
    this.cancelling = false,
    this.syncing = false,
    this.report,
  });

  final BankBrowserState state;
  final bool devMode;
  final Future<void> Function()? onBack;
  final Future<void> Function()? onForward;
  final Future<void> Function() onReload;
  final Future<void> Function() onHome;
  final Future<void> Function() onClose;
  final Future<void> Function()? onSync;
  final Future<void> Function()? onSavePin;
  final Future<void> Function()? onCancelSync;
  final bool cancelling;
  final bool syncing;
  final SberSyncReport? report;

  @override
  Widget build(BuildContext context) {
    final safeUrl = state.currentUrl == null
        ? state.bank.startUrl.toString()
        : Uri(
            scheme: state.currentUrl!.scheme,
            host: state.currentUrl!.host,
            path: state.currentUrl!.path,
          ).toString();
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: QestoColors.surface,
        border: Border(bottom: BorderSide(color: QestoColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Назад',
            onPressed: onBack == null ? null : () => unawaited(onBack!()),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          IconButton(
            tooltip: 'Вперёд',
            onPressed: onForward == null ? null : () => unawaited(onForward!()),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
          IconButton(
            tooltip: state.lifecycle == BankBrowserLifecycle.loading
                ? 'Остановить'
                : 'Обновить',
            onPressed: () => unawaited(onReload()),
            icon: Icon(
              state.lifecycle == BankBrowserLifecycle.loading
                  ? Icons.close_rounded
                  : Icons.refresh_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Начальная страница банка',
            onPressed: () => unawaited(onHome()),
            icon: const Icon(Icons.home_outlined),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: QestoColors.surfaceSecondary,
                border: Border.all(color: QestoColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_rounded,
                    color: Color(0xFF16A05D),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      safeUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    state.bank.displayName,
                    style: const TextStyle(
                      color: QestoColors.secondaryText,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (devMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.45),
                ),
              ),
              child: const Text(
                'DEV MODE',
                style: TextStyle(
                  color: Colors.deepOrange,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (onSavePin != null)
            IconButton(
              tooltip: 'Сохранить PIN быстрого входа локально',
              onPressed: () => unawaited(onSavePin!()),
              icon: const Icon(Icons.password_rounded, size: 19),
            ),
          if (syncing && report != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                _sberStageLabel(report!.state),
                style: const TextStyle(
                  color: QestoColors.secondaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (onSync != null)
            FilledButton.icon(
              onPressed: syncing ? null : () => unawaited(onSync!()),
              icon: syncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 17),
              label: Text(syncing ? 'Синхронизация…' : 'Синхронизировать'),
            ),
          if (syncing)
            TextButton.icon(
              key: const Key('bank-browser-cancel-sync'),
              onPressed: onCancelSync,
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: Text(cancelling ? 'Отменяется…' : 'Отменить'),
            ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            key: const Key('bank-browser-close'),
            onPressed: () => unawaited(onClose()),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  String _sberStageLabel(SberConnectorState state) => switch (state) {
    SberConnectorState.checkingAuth => 'Проверяем вход…',
    SberConnectorState.pinRequired => 'Нужен PIN…',
    SberConnectorState.fullLoginRequired => 'Нужен ручной вход…',
    SberConnectorState.syncingProducts => 'Читаем счета…',
    SberConnectorState.syncingTransactions => 'Читаем операции…',
    SberConnectorState.syncComplete => 'Готово',
    SberConnectorState.syncPartial => 'Частично',
    SberConnectorState.error => 'Ошибка',
    _ => 'Синхронизация…',
  };
}

class _BrowserStatus extends StatelessWidget {
  const _BrowserStatus({
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: QestoColors.primary, size: 40),
        const SizedBox(height: 14),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(message, style: const TextStyle(color: QestoColors.secondaryText)),
        if (loading) ...[
          const SizedBox(height: 18),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 18), action!],
      ],
    ),
  );
}
