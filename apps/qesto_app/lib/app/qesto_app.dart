import 'package:flutter/material.dart';

import '../core/theme/qesto_theme.dart';
import '../core/widgets/states.dart';
import '../data/models/qesto_models.dart';
import '../data/repositories/local_qesto_repository.dart';
import '../data/repositories/qesto_repository.dart';
import 'qesto_app_shell.dart';

class QestoApp extends StatelessWidget {
  QestoApp({super.key, QestoRepository? repository})
    : repository = repository ?? LocalQestoRepository();

  final QestoRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qesto',
      debugShowCheckedModeBanner: false,
      theme: buildQestoTheme(),
      builder: (context, child) {
        return ColoredBox(
          color: const Color(0xFFEFF2F7),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      home: _AppDataLoader(repository: repository),
    );
  }
}

class _AppDataLoader extends StatefulWidget {
  const _AppDataLoader({required this.repository});

  final QestoRepository repository;

  @override
  State<_AppDataLoader> createState() => _AppDataLoaderState();
}

class _AppDataLoaderState extends State<_AppDataLoader> {
  late Future<QestoAppData> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.loadAppData();
  }

  void _retry() {
    setState(() => _future = widget.repository.loadAppData());
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
          );
        },
      ),
    );
  }
}
