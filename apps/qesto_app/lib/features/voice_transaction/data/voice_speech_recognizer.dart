import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/voice_transaction_models.dart';

abstract interface class VoiceSpeechRecognizer {
  bool get isSupported;

  Future<VoiceRecognitionResult?> recognize();
}

class AndroidVoiceSpeechRecognizer implements VoiceSpeechRecognizer {
  const AndroidVoiceSpeechRecognizer();

  static const _channel = MethodChannel('ru.qesto.qesto/voice');

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<VoiceRecognitionResult?> recognize() async {
    if (!isSupported) {
      throw const VoiceSpeechException(
        'Голосовое добавление пока доступно только на Android',
      );
    }

    try {
      final value = await _channel.invokeMapMethod<String, Object?>(
        'recognizeTransaction',
      );
      if (value == null) return null;
      final text = value['text'] as String?;
      if (text == null || text.trim().isEmpty) return null;
      return VoiceRecognitionResult(
        text: text.trim(),
        onDevice: value['onDevice'] == true,
      );
    } on PlatformException catch (error) {
      throw VoiceSpeechException(error.message ?? 'Не удалось распознать речь');
    }
  }
}

class VoiceSpeechException implements Exception {
  const VoiceSpeechException(this.message);

  final String message;

  @override
  String toString() => message;
}
