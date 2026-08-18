import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_appearance_controller.dart';
import '../core/theme/qesto_theme.dart';
import '../core/widgets/states.dart';
import '../data/models/qesto_models.dart';
import '../data/persistence/local_key_value_store.dart';
import '../data/repositories/local_qesto_repository.dart';
import '../data/repositories/qesto_repository.dart';
import '../features/notification_import/data/notification_capture_service.dart';
import 'qesto_app_shell.dart';

class QestoApp extends StatefulWidget {
  QestoApp({super.key, QestoRepository? repository, this.preferenceStore})
    : repository = repository ?? LocalQestoRepository();

  final QestoRepository repository;
  final LocalKeyValueStore? preferenceStore;

  @override
  State<QestoApp> createState() => _QestoAppState();
}

class _QestoAppState extends State<QestoApp> {
  late final AppAppearanceController _appearanceController;

  @override
  void initState() {
    super.initState();
    _appearanceController = AppAppearanceController(
      store: widget.preferenceStore,
    );
    _appearanceController.load();
  }

  @override
  void dispose() {
    _appearanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _appearanceController,
      builder: (context, _) => MaterialApp(
        title: 'Qesto',
        debugShowCheckedModeBanner: false,
        theme: buildQestoTheme(),
        builder: (context, child) {
          final content = child ?? const SizedBox.shrink();
          final dark = _appearanceController.isDark(
            MediaQuery.platformBrightnessOf(context),
          );
          return AppAppearanceScope(
            controller: _appearanceController,
            child: QestoDarkSurface(
              enabled: dark,
              child: LayoutBuilder(
                builder: (context, constraints) => ColoredBox(
                  color: const Color(0xFFEFF2F7),
                  child: constraints.maxWidth >= 900
                      ? content
                      : Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: content,
                          ),
                        ),
                ),
              ),
            ),
          );
        },
        home: _AppDataLoader(repository: widget.repository),
      ),
    );
  }
}

class _AppDataLoader extends StatefulWidget {
  const _AppDataLoader({required this.repository});

  final QestoRepository repository;

  @override
  State<_AppDataLoader> createState() => _AppDataLoaderState();
}

class _AppDataLoaderState extends State<_AppDataLoader>
    with WidgetsBindingObserver {
  late Future<QestoAppData> _future;
  var _refreshOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = widget.repository.loadAppData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _refreshOnResume = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _refreshOnResume) {
      _refreshOnResume = false;
      widget.repository.resetPublicDeals();
      _retry();
    }
  }

  void _retry() {
    setState(() => _future = widget.repository.loadAppData());
  }

  Future<void> _deleteAllData() async {
    await widget.repository.deleteUserFinancialData();
    try {
      await const NotificationCaptureService().clearNotifications();
    } on MissingPluginException {
      // Notification capture exists only in the Android host application.
    }
    if (mounted) _retry();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<QestoAppData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SafeArea(child: LoadingSkeleton());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ErrorState(onRetry: _retry);
          }
          return QestoAppShell(
            data: snapshot.requireData,
            repository: widget.repository,
            onAllDataDeleted: _deleteAllData,
          );
        },
      ),
    );
  }
}
