import 'dart:io';

/// Keeps historical reports immutable while running the unchanged test bodies.
final class EvidenceRedirect extends IOOverrides {
  EvidenceRedirect(this.destination);
  final String destination;
  @override
  File createFile(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.startsWith('results/')) {
      return super.createFile('$destination/${normalized.substring(8)}');
    }
    if (normalized.startsWith('../results/')) {
      return super.createFile('$destination/${normalized.substring(11)}');
    }
    final binaries = Platform.environment['QESTO_4G_BINARIES'];
    if (binaries != null && normalized.startsWith('build/') &&
        ['receipt_probe', 'native_effects_probe', 'client_probe'].any((n) => normalized.startsWith('build/$n/'))) {
      return super.createFile('$binaries/${normalized.substring(6)}');
    }
    return super.createFile(path);
  }
}

void redirectEvidence() {
  final output = Platform.environment['QESTO_4G_EVIDENCE'];
  if (output == null || !output.replaceAll('\\', '/').contains('/owner_lifetime/results/')) {
    throw StateError('Stage 4g evidence directory required');
  }
  Directory(output).createSync(recursive: true);
  IOOverrides.global = EvidenceRedirect(output);
}
