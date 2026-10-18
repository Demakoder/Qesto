import 'package:flutter/material.dart';

import '../core/theme/qesto_theme.dart';
import '../data/models/qesto_models.dart';
import '../desktop/desktop_destination.dart';
import '../features/budget/transaction_route_scope.dart';
import '../features/statistics/presentation/state/statistics_controller.dart';
import '../features/notification_import/data/notification_capture_service.dart';
import 'adapters/mobile_page_adapters.dart';
import 'navigation/mobile_root.dart';
import 'sources/mobile_source_attention_controller.dart';
import 'sources/mobile_source_status_page.dart';
import 'transactions/mobile_attention_queue.dart';
import 'capital/mobile_capital_common.dart';
import 'capital/mobile_capital_pages.dart';

/// Four independent, lazy, retained navigation stacks. UI state lives only for
/// this shell's lifetime; no new storage schema or financial state is involved.
class MobileAppShell extends StatefulWidget {
  const MobileAppShell({
    required this.adapters,
    required this.overviewPeriod,
    required this.overviewPeriodLabel,
    required this.onChooseOverviewPeriod,
    required this.onAddData,
    required this.onSearch,
    required this.onNotifications,
    required this.onOpenInbox,
    this.transactionAttention,
    this.transactionAttentionCount,
    this.sourceAttention,
    this.bankConnectionsAvailable = false,
    super.key,
  });

  final MobilePageAdapters adapters;
  final BudgetPeriod overviewPeriod;
  final String overviewPeriodLabel;
  final VoidCallback onChooseOverviewPeriod;
  final VoidCallback onAddData;
  final VoidCallback onSearch;
  final VoidCallback onNotifications;
  final VoidCallback onOpenInbox;
  final Listenable? transactionAttention;
  final int Function()? transactionAttentionCount;
  final MobileSourceAttentionController? sourceAttention;
  final bool bankConnectionsAvailable;

  @override
  State<MobileAppShell> createState() => MobileAppShellState();
}

class MobileAppShellState extends State<MobileAppShell> {
  final _navigators = {
    for (final root in MobileRoot.values) root: GlobalKey<NavigatorState>(),
  };
  final _buckets = {
    for (final root in MobileRoot.values) root: PageStorageBucket(),
  };
  final _visited = <MobileRoot>{MobileRoot.dashboard};
  var _selected = MobileRoot.dashboard;
  var _revision = 0;
  MobileSourceAttentionController? _unsupportedSources;

  MobileSourceAttentionController get _sources =>
      widget.sourceAttention ??
      (_unsupportedSources ??= MobileSourceAttentionController(
        gateway: const NotificationCaptureService(),
        supported: false,
      ));

  @override
  void dispose() {
    _unsupportedSources?.dispose();
    super.dispose();
  }

  void selectRoot(MobileRoot root) {
    if (root == _selected) return; // Reselect never resets filters or routes.
    setState(() {
      _selected = root;
      _visited.add(root);
    });
  }

  Future<void> createAccount() async {
    final navigator = _navigators[_selected]!.currentState!;
    final origin = navigator.overlay!.context;
    final id = await openMobileAccountCreate(
      origin,
      widget.adapters.controller,
    );
    if (!mounted || !origin.mounted || id == null) return;
    capitalPush(
      origin,
      '/capital/account/$id',
      MobileAccountDetail(
        controller: widget.adapters.controller,
        accountId: id,
        onOpenFilteredTransactions: openFilteredTransactions,
      ),
    );
  }

  void openDestination(DesktopDestination destination) {
    final root = switch (destination) {
      DesktopDestination.dashboard => MobileRoot.dashboard,
      DesktopDestination.transactions => MobileRoot.transactions,
      DesktopDestination.budget => MobileRoot.budget,
      _ => null,
    };
    if (root != null) {
      selectRoot(root);
      return;
    }
    if (destination == DesktopDestination.connections &&
        !widget.bankConnectionsAvailable) {
      openSources();
      return;
    }
    _push(
      '/${destination.name}',
      () => switch (destination) {
        DesktopDestination.expenses ||
        DesktopDestination.cashFlow ||
        DesktopDestination.rhythm ||
        DesktopDestination.recurring ||
        DesktopDestination.accounts ||
        DesktopDestination.liquidity ||
        DesktopDestination.investments ||
        DesktopDestination.debts ||
        DesktopDestination.goals => widget.adapters.secondary(
          destination,
          onOpenFilteredTransactions: openFilteredTransactions,
        ),
        _ => Scaffold(
          appBar: AppBar(title: Text(destination.label)),
          body: SafeArea(
            top: false,
            child: widget.adapters.secondary(destination),
          ),
        ),
      },
    );
  }

  void openTransaction(String id) {
    // Validate without creating a period or changing a transaction.
    if (widget.adapters.transaction(id) == null) return;
    _push(
      '/transaction/$id',
      () =>
          widget.adapters.transaction(id) ??
          Scaffold(
            appBar: AppBar(title: const Text('Операция')),
            body: const Center(child: Text('Операция больше не доступна')),
          ),
    );
  }

  void openFilteredTransactions(List<String> ids) {
    final scope = List<String>.unmodifiable(ids);
    _push(
      '/operations/selection',
      () => Scaffold(
        appBar: AppBar(title: const Text('Выбранные операции')),
        body: SafeArea(
          top: false,
          child: widget.adapters.transactions(
            ids: scope,
            onOpenTransaction: openTransaction,
          ),
        ),
      ),
    );
  }

  void openAttention([StatisticsController? origin]) => _push(
    '/operations/attention',
    () => MobileAttentionQueue(
      controller: widget.adapters.controller,
      statistics: origin,
      onOpenTransaction: openTransaction,
    ),
  );

  void openSources() => _push(
    '/sources',
    () => MobileSourceStatusPage(
      controller: _sources,
      onOpenInbox: widget.onOpenInbox,
      onOpenBankConnections: widget.bankConnectionsAvailable
          ? () => openDestination(DesktopDestination.connections)
          : null,
    ),
  );

  void _push(String name, Widget Function() builder) {
    _navigators[_selected]!.currentState!.push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: name),
        builder: (context) {
          _MobilePresentationScope.of(context);
          return builder();
        },
      ),
    );
  }

  void _openMore() => _push(
    '/more',
    () => Scaffold(
      appBar: AppBar(title: const Text('Ещё')),
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            _moreItem(
              'sources',
              'Источники',
              Icons.sensors_outlined,
              openSources,
            ),
            _moreItem(
              'benefits',
              'Выгода',
              Icons.local_offer_outlined,
              () => openDestination(DesktopDestination.benefits),
            ),
            _moreItem(
              'insights',
              'ИИ-экспорт',
              Icons.auto_awesome_outlined,
              () => openDestination(DesktopDestination.insights),
            ),
            _moreItem(
              'history',
              'История действий',
              Icons.history,
              () => _push('/history', widget.adapters.history),
            ),
            _moreItem(
              'trash',
              'Корзина',
              Icons.delete_outline,
              () => _push('/trash', widget.adapters.trash),
            ),
            _moreItem(
              'categories',
              'Категории и правила',
              Icons.category_outlined,
              () => _push('/categories', widget.adapters.categories),
            ),
            _moreItem(
              'settings',
              'Настройки',
              Icons.settings_outlined,
              () => openDestination(DesktopDestination.settings),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _moreItem(
    String id,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) => ListTile(
    key: Key('mobile-more-$id'),
    leading: Icon(icon),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );

  Widget _rootPage(MobileRoot root) {
    final page = widget.adapters.root(
      destination: root,
      overviewPeriod: widget.overviewPeriod,
      onOpenDestination: openDestination,
      onOpenTransaction: openTransaction,
      onOpenFilteredTransactions: openFilteredTransactions,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(root.label),
        actions: [
          IconButton(
            tooltip: 'Поиск',
            onPressed: widget.onSearch,
            icon: const Icon(Icons.search),
          ),
          ListenableBuilder(
            listenable: widget.transactionAttention ?? _sources,
            builder: (context, _) => Badge(
              isLabelVisible:
                  (widget.transactionAttentionCount?.call() ?? 0) > 0,
              label: Text('${widget.transactionAttentionCount?.call() ?? 0}'),
              child: IconButton(
                tooltip: 'Уведомления',
                onPressed: widget.onNotifications,
                icon: const Icon(Icons.notifications_none),
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _sources,
            builder: (context, _) => Badge(
              key: const Key('mobile-source-attention-badge'),
              isLabelVisible: _sources.needsAttention,
              child: IconButton(
                key: const Key('mobile-more'),
                tooltip: 'Ещё',
                onPressed: _openMore,
                icon: const Icon(Icons.more_horiz),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            MobileSourceAttentionBanner(
              controller: _sources,
              onTap: openSources,
            ),
            if (root == MobileRoot.dashboard)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('mobile-overview-period'),
                  onPressed: widget.onChooseOverviewPeriod,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(widget.overviewPeriodLabel),
                ),
              ),
            Expanded(child: page),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const Key('mobile-app-shell'),
    backgroundColor: context.qestoColors.background,
    // Reserve an action lane so the global + never covers a legacy page's
    // final row/editor button. This is shell layout, not a screen redesign.
    body: Padding(
      padding: const EdgeInsets.only(bottom: 64),
      child: TransactionRouteScope(
        openTransaction: openTransaction,
        openAttention: openAttention,
        child: _MobilePresentationScope(
          revision: ++_revision,
          child: IndexedStack(
            index: _selected.index,
            children: [
              for (final root in MobileRoot.values)
                if (!_visited.contains(root))
                  const SizedBox.shrink()
                else
                  TickerMode(
                    enabled: root == _selected,
                    child: FocusScope(
                      canRequestFocus: root == _selected,
                      child: PageStorage(
                        bucket: _buckets[root]!,
                        child: NavigatorPopHandler<Object?>(
                          enabled: root == _selected,
                          onPopWithResult: (result) {
                            if (root == _selected) {
                              _navigators[root]!.currentState!.maybePop(result);
                            }
                          },
                          child: Navigator(
                            key: _navigators[root],
                            onGenerateRoute: (_) => MaterialPageRoute<void>(
                              settings: RouteSettings(name: '/${root.name}'),
                              builder: (context) {
                                _MobilePresentationScope.of(context);
                                return _rootPage(root);
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton.small(
      key: const Key('mobile-add-data'),
      tooltip: 'Добавить данные',
      onPressed: widget.onAddData,
      child: const Icon(Icons.add),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selected.index,
      onDestinationSelected: (index) => selectRoot(MobileRoot.values[index]),
      destinations: [
        for (final root in MobileRoot.values)
          NavigationDestination(
            key: Key('mobile-root-${root.name}'),
            icon: Icon(root.icon),
            label: root.label,
          ),
      ],
    ),
  );
}

/// Retained route builders subscribe to presentation updates (e.g. Overview
/// period selection), without replacing their state or Navigator history.
class _MobilePresentationScope extends InheritedWidget {
  const _MobilePresentationScope({
    required this.revision,
    required super.child,
  });
  final int revision;
  static void of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MobilePresentationScope>();
  @override
  bool updateShouldNotify(_MobilePresentationScope oldWidget) =>
      revision != oldWidget.revision;
}
