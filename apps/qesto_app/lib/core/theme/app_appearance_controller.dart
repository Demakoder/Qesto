import 'package:flutter/material.dart';

import '../../data/persistence/local_key_value_store.dart';

enum QestoThemePreference { system, light, dark }

class AppAppearanceController extends ChangeNotifier {
  AppAppearanceController({LocalKeyValueStore? store})
    : _store = store ?? const LocalKeyValueStore();

  static const storageKey = 'qesto.themeMode';

  final LocalKeyValueStore _store;
  QestoThemePreference _preference = QestoThemePreference.system;

  QestoThemePreference get preference => _preference;

  Future<void> load() async {
    final value = await _store.readString(storageKey);
    _preference = QestoThemePreference.values.firstWhere(
      (item) => item.name == value,
      orElse: () => QestoThemePreference.system,
    );
    notifyListeners();
  }

  Future<void> select(QestoThemePreference value) async {
    if (_preference == value) return;
    _preference = value;
    notifyListeners();
    if (value == QestoThemePreference.system) {
      await _store.remove(storageKey);
    } else {
      await _store.writeString(storageKey, value.name);
    }
  }

  bool isDark(Brightness platformBrightness) => switch (_preference) {
    QestoThemePreference.system => platformBrightness == Brightness.dark,
    QestoThemePreference.light => false,
    QestoThemePreference.dark => true,
  };
}

class AppAppearanceScope extends InheritedNotifier<AppAppearanceController> {
  const AppAppearanceScope({
    required AppAppearanceController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static AppAppearanceController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppAppearanceScope>();
    assert(scope != null, 'AppAppearanceScope is missing above this context.');
    return scope!.notifier!;
  }
}

/// The desktop UI still contains legacy light palette constants. This filter
/// supplies one coherent dark surface while those widgets migrate to semantic
/// color tokens. Its hue-preserving inversion keeps Qesto's blue/orange/purple
/// accents recognizable and maps pure white/black to softer dark/light values.
class QestoDarkSurface extends StatelessWidget {
  const QestoDarkSurface({
    required this.enabled,
    required this.child,
    super.key,
  });

  final bool enabled;
  final Widget child;

  static const _matrix = <double>[
    0.49364,
    -1.2298,
    -0.12384,
    0,
    237.3,
    -0.36636,
    -0.3698,
    -0.12384,
    0,
    237.3,
    -0.36636,
    -1.2298,
    0.73616,
    0,
    237.3,
    0,
    0,
    0,
    1,
    0,
  ];

  @override
  Widget build(BuildContext context) => enabled
      ? ColorFiltered(
          key: const Key('qesto-dark-surface'),
          colorFilter: const ColorFilter.matrix(_matrix),
          child: child,
        )
      : child;
}
