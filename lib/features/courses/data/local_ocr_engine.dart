import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/local_ocr_models.dart';

class LocalOcrUnavailable implements Exception {
  const LocalOcrUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class LocalOcrEngine {
  Future<OcrPageResult> recognize(Uint8List imageBytes);
}

/// Native OCR is intentionally isolated behind a platform channel. No image is
/// sent to Supabase, OpenAI, or any other remote service.
class PlatformLocalOcrEngine implements LocalOcrEngine {
  static const _channel = MethodChannel('check_d/local_ocr');

  @override
  Future<OcrPageResult> recognize(Uint8List imageBytes) async {
    if (kIsWeb) {
      throw const LocalOcrUnavailable('当前 Web 版暂不支持本地课程表识别，请使用桌面端或手机端。');
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('recognize', {
        'bytes': imageBytes,
      });
      if (raw == null) throw const LocalOcrUnavailable('本地 OCR 没有返回识别结果。');
      final width = _number(raw['imageWidth']);
      final height = _number(raw['imageHeight']);
      if (width == null || height == null || width <= 0 || height <= 0) {
        throw const LocalOcrUnavailable('本地 OCR 返回了无效的图片尺寸。');
      }
      return OcrPageResult(
        imageWidth: width,
        imageHeight: height,
        tokens: [
          for (final value in (raw['tokens'] as List? ?? const <dynamic>[]))
            if (value is Map) _token(Map<String, dynamic>.from(value)),
        ],
      );
    } on PlatformException catch (error) {
      throw LocalOcrUnavailable(error.message ?? '本地 OCR 运行失败。');
    } on MissingPluginException {
      throw const LocalOcrUnavailable('当前设备暂不支持本地课程表识别。');
    }
  }

  OcrToken _token(Map<String, dynamic> value) => OcrToken(
    text: value['text']?.toString() ?? '',
    boundingBox: OcrBoundingBox(
      left: _number(value['left']) ?? 0,
      top: _number(value['top']) ?? 0,
      right: _number(value['right']) ?? 0,
      bottom: _number(value['bottom']) ?? 0,
    ),
    confidence: _number(value['confidence']),
  );

  double? _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value');
}
