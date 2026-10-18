import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Current Windows process kernel+user CPU; includes its worker isolates only.
int cpuMicros() {
  if (!Platform.isWindows) throw UnsupportedError('Windows-only experiment');
  final kernel = DynamicLibrary.open('kernel32.dll');
  final process = kernel.lookupFunction<IntPtr Function(), int Function()>(
    'GetCurrentProcess',
  )();
  final getTimes = kernel
      .lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        ),
        int Function(
          int,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        )
      >('GetProcessTimes');
  final times = calloc<Uint64>(4);
  try {
    if (getTimes(process, times, times + 1, times + 2, times + 3) == 0) {
      throw StateError('GetProcessTimes failed');
    }
    return (times[2] + times[3]) ~/ 10;
  } finally {
    calloc.free(times);
  }
}

class Measurements {
  final Map<String, List<Map<String, int>>> values = {};
  T run<T>(String name, T Function() work, {int bytes = 0}) {
    final cpu = cpuMicros(), w = Stopwatch()..start();
    try {
      return work();
    } finally {
      values.putIfAbsent(name, () => []).add({
        'wall_us': w.elapsedMicroseconds,
        'cpu_us': cpuMicros() - cpu,
        'input_bytes': bytes,
        'rss': ProcessInfo.currentRss,
      });
    }
  }
}
