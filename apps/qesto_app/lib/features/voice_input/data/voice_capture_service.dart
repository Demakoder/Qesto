import 'voice_capture_service_stub.dart'
    if (dart.library.io) 'voice_capture_service_io.dart'
    as platform;
import 'voice_capture_models.dart';

export 'voice_capture_models.dart';

class VoiceCaptureService {
  const VoiceCaptureService();

  bool get isSupported => platform.voiceCaptureSupported;

  Future<VoiceCaptureResult> capture() => platform.captureVoice();
}
