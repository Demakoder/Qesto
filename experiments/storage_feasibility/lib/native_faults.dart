/// Test-only Windows I/O interception, not imported by production or Android.
library;

import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/unstable/ffi_bindings.dart' as native;

class NativeFaults {
  NativeFaults(String path, {bool install = true})
    : dll = DynamicLibrary.open(path) {
    if (install) {
      // Initialize SQLite before resolving its underlying Windows VFS.
      sqlite3.version;
      final rc = dll
          .lookupFunction<
            Int Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('qesto_install')(native.addresses.sqlite3_close_v2.cast());
      if (rc != 0) throw StateError('Native shim install failed: $rc');
    }
  }
  final DynamicLibrary dll;
  void attach(Database db) {
    if (!Platform.isWindows) throw UnsupportedError('Windows test shim only');
    final attached = dll.lookupFunction<Int Function(Int), int Function(int)>(
      'qesto_attached',
    );
    for (final scope in [1, 2]) {
      if (attached(scope) == 0)
        throw StateError('No native file hooked for scope=$scope');
    }
  }

  // scope main=1 / WAL=2; op write=1 / sync=2 / truncate=3;
  // mode fail=0 / partialWrite=1 / exitBefore=2 / exitAfter=3 / errorAfter=4.
  void arm({
    required int scope,
    required int op,
    int nth = 1,
    int code = 10,
    int mode = 0,
  }) =>
      dll.lookupFunction<
        Void Function(Int, Int, Int, Int, Int),
        void Function(int, int, int, int, int)
      >('qesto_arm')(scope, op, nth, code, mode);
  void disarm() => arm(scope: 0, op: 0, nth: 0);
  int metric(int kind) =>
      dll.lookupFunction<Int64 Function(Int), int Function(int)>(
        'qesto_metric',
      )(kind);
  double get cpuMs => dll.lookupFunction<Double Function(), double Function()>(
    'qesto_cpu_ms',
  )();
}
