import 'voice_capture_models.dart';

const voiceCaptureSupported = false;

Future<VoiceCaptureResult> captureVoice() =>
    throw UnsupportedError('Голосовой ввод недоступен на этой платформе');
