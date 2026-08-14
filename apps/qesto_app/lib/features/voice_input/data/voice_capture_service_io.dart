import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'voice_capture_models.dart';

final voiceCaptureSupported = Platform.isWindows;

const _modelFileName = 'ggml-small-q5_1.bin';

Future<VoiceCaptureResult> captureVoice() async {
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'Голосовой ввод сейчас поддерживается только в Windows',
    );
  }

  final runtime = _findWhisperRuntime();
  final wavePath = Platform.environment['QESTO_VOICE_WAVE_PATH']?.trim();
  if (wavePath != null && wavePath.isNotEmpty) {
    return _transcribeWave(runtime, File(wavePath));
  }
  return _captureMicrophone(runtime);
}

Directory _findWhisperRuntime() {
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  final candidates = <Directory>[
    Directory('${executableDirectory.path}${Platform.pathSeparator}whisper'),
    Directory(
      '${Directory.current.path}${Platform.pathSeparator}'
      'windows${Platform.pathSeparator}whisper${Platform.pathSeparator}runtime',
    ),
  ];
  for (final candidate in candidates) {
    final stream = File(
      '${candidate.path}${Platform.pathSeparator}whisper-stream.exe',
    );
    final cli = File(
      '${candidate.path}${Platform.pathSeparator}whisper-cli.exe',
    );
    final model = File(
      '${candidate.path}${Platform.pathSeparator}$_modelFileName',
    );
    if (stream.existsSync() && cli.existsSync() && model.existsSync()) {
      return candidate;
    }
  }
  throw StateError(
    'Не найден локальный модуль распознавания речи. Переустановите Qesto.',
  );
}

Future<VoiceCaptureResult> _transcribeWave(Directory runtime, File wave) async {
  if (!wave.existsSync()) {
    throw StateError('Аудиофайл для распознавания не найден');
  }
  final temporaryDirectory = await Directory.systemTemp.createTemp(
    'qesto-whisper-',
  );
  try {
    final outputBase =
        '${temporaryDirectory.path}${Platform.pathSeparator}transcript';
    final result = await Process.run(
      '${runtime.path}${Platform.pathSeparator}whisper-cli.exe',
      [
        '-m',
        '${runtime.path}${Platform.pathSeparator}$_modelFileName',
        '-l',
        'ru',
        '-nt',
        '-otxt',
        '-of',
        outputBase,
        '-f',
        wave.path,
      ],
      workingDirectory: runtime.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw StateError(
        _recognitionError(result.stderr.toString(), result.stdout.toString()),
      );
    }
    final transcriptFile = File('$outputBase.txt');
    final transcript = transcriptFile.existsSync()
        ? await transcriptFile.readAsString()
        : result.stdout.toString();
    return _validatedResult(transcript);
  } finally {
    await _deleteTemporaryDirectory(temporaryDirectory);
  }
}

Future<VoiceCaptureResult> _captureMicrophone(Directory runtime) async {
  final temporaryDirectory = await Directory.systemTemp.createTemp(
    'qesto-whisper-',
  );
  final outputFile = File(
    '${temporaryDirectory.path}${Platform.pathSeparator}transcript.txt',
  );
  Process? process;
  try {
    process = await Process.start(
      '${runtime.path}${Platform.pathSeparator}whisper-stream.exe',
      [
        '-m',
        '${runtime.path}${Platform.pathSeparator}$_modelFileName',
        '-l',
        'ru',
        '--step',
        '2000',
        '--length',
        '8000',
        '--keep',
        '200',
        '--max-tokens',
        '48',
        '--no-fallback',
        '-f',
        outputFile.path,
      ],
      workingDirectory: runtime.path,
      mode: ProcessStartMode.normal,
    );

    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    var exitedNaturally = false;
    var exitCode = -1;
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 12));
      exitedNaturally = true;
    } on TimeoutException {
      process.kill();
      exitCode = await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () => -1,
      );
    }

    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    if (exitedNaturally && exitCode != 0 && !await outputFile.exists()) {
      throw StateError(_recognitionError(stderr, stdout));
    }

    final transcript = await outputFile.exists()
        ? await outputFile.readAsString()
        : _extractTranscript(stdout);
    return _validatedResult(transcript);
  } on ProcessException catch (error) {
    throw StateError('Не удалось открыть микрофон: ${error.message}');
  } finally {
    process?.kill();
    await _deleteTemporaryDirectory(temporaryDirectory);
  }
}

VoiceCaptureResult _validatedResult(String rawTranscript) {
  final transcript = _cleanTranscript(rawTranscript);
  if (transcript.isEmpty) {
    throw StateError(
      'Речь не распознана. Проверьте микрофон и повторите фразу.',
    );
  }
  return VoiceCaptureResult(transcript: transcript, locale: 'ru-RU');
}

String _extractTranscript(String output) {
  final lines = output.split(RegExp(r'[\r\n]+'));
  return lines
      .where((line) {
        final value = line.trim();
        return value.isNotEmpty &&
            !value.startsWith('whisper_') &&
            !value.startsWith('main:') &&
            !value.startsWith('system_info:') &&
            !value.startsWith('init:') &&
            !value.startsWith('capture:') &&
            !value.startsWith('audio ') &&
            !value.startsWith('SDL');
      })
      .join(' ');
}

String _cleanTranscript(String value) => value
    .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
    .replaceAll(RegExp(r'\[[0-9:.\-\s>]+\]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _recognitionError(String stderr, String stdout) {
  final details = '$stderr\n$stdout'.trim();
  if (details.contains('capture device') ||
      details.contains('SDL_OpenAudioDevice') ||
      details.contains('audio device')) {
    return 'Windows не смог открыть микрофон. Проверьте доступ Qesto к микрофону.';
  }
  return details.isEmpty
      ? 'Не удалось запустить локальное распознавание речи'
      : 'Не удалось распознать речь локально';
}

Future<void> _deleteTemporaryDirectory(Directory directory) async {
  try {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  } on FileSystemException {
    // Windows can keep a just-terminated audio handle alive for a moment. The
    // operating system will clean the small temporary directory later.
  }
}
