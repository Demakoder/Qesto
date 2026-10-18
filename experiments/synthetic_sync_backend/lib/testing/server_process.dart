// Shared synthetic-process harness; never used by production application code.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ServerProcess {
  ServerProcess(this.process, this.base, this.control, this.errors);
  final Process process;
  final Uri base;
  final File control;
  final StringBuffer errors;
  void fault(String id, String stage, String action) {
    for (final suffix in ['.hit', '.release']) {
      final f = File('${control.path}$suffix');
      if (f.existsSync()) f.deleteSync();
    }
    control.writeAsStringSync(
      jsonEncode({'change_id': id, 'stage': stage, 'action': action}),
      flush: true,
    );
  }

  void clearFault() {
    if (control.existsSync()) control.deleteSync();
  }

  Future<void> hit() async {
    for (var i = 0; i < 1000; i++) {
      if (File('${control.path}.hit').existsSync()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('Fault hook not reached: $errors');
  }

  void release() =>
      File('${control.path}.release').writeAsStringSync('release', flush: true);
  Future<void> kill() async {
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 5));
  }

  Future<void> close() async {
    try {
      await process.stdin.close();
    } catch (_) {
      // A fault-injection test may already have killed this process.
    }
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      await kill();
    }
  }
}
