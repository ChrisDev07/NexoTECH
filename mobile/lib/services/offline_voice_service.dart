import 'package:flutter/services.dart';

/// Servicio de reconocimiento de voz 100% OFFLINE embebido en el APK (Vosk Español).
/// Funciona en Modo Avión real sin depender de Google ni conexión a internet.
class OfflineVoiceService {
  static const MethodChannel _channel = MethodChannel('co.nexotech.origo/offline_voice');

  void Function(String status)? onModelStatus;
  void Function()? onListeningStarted;
  void Function(String partial)? onPartial;
  void Function(String finalText)? onFinal;
  void Function(String error)? onError;

  bool _initialized = false;

  Future<bool> init() async {
    if (!_initialized) {
      _channel.setMethodCallHandler(_handleNativeCall);
      _initialized = true;
    }
    final ready = await _channel.invokeMethod<bool>('initModel');
    return ready ?? false;
  }

  Future<String> startListening() async {
    final res = await _channel.invokeMethod<String>('startListening');
    return res ?? 'error';
  }

  Future<void> stopListening() async {
    await _channel.invokeMethod('stopListening');
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onModelStatus':
        onModelStatus?.call(call.arguments?.toString() ?? '');
        break;
      case 'onListeningStarted':
        onListeningStarted?.call();
        break;
      case 'onPartial':
        onPartial?.call(call.arguments?.toString() ?? '');
        break;
      case 'onFinal':
        onFinal?.call(call.arguments?.toString() ?? '');
        break;
      case 'onError':
        onError?.call(call.arguments?.toString() ?? 'Error de micrófono');
        break;
    }
  }
}
