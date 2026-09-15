import 'package:check_d/features/courses/data/local_ocr_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('check_d/test_local_ocr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  for (final fixture in <String, Uint8List>{
    'PNG': Uint8List.fromList(const [0x89, 0x50, 0x4e, 0x47]),
    'JPEG': Uint8List.fromList(const [0xff, 0xd8, 0xff, 0xe0]),
  }.entries) {
    test('${fixture.key} bytes are passed to native OCR', () async {
      Uint8List? receivedBytes;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'recognize');
        receivedBytes =
            (call.arguments as Map<Object?, Object?>)['bytes'] as Uint8List;
        return <String, Object>{
          'imageWidth': 1200.0,
          'imageHeight': 800.0,
          'tokens': <Map<String, Object>>[
            <String, Object>{
              'text': '高等数学',
              'left': 10.0,
              'top': 20.0,
              'right': 110.0,
              'bottom': 50.0,
            },
          ],
        };
      });

      final result = await PlatformLocalOcrEngine(
        channel: channel,
      ).recognize(fixture.value);

      expect(receivedBytes, fixture.value);
      expect(result.imageWidth, 1200);
      expect(result.tokens.single.text, '高等数学');
    });
  }

  test('native image decode failure has a readable error', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'image_decode_failed', message: '无法读取图片');
    });

    expect(
      () => PlatformLocalOcrEngine(channel: channel).recognize(Uint8List(0)),
      throwsA(
        isA<LocalOcrUnavailable>().having(
          (error) => error.message,
          'message',
          contains('无法读取所选图片'),
        ),
      ),
    );
  });

  test('empty native OCR result remains a valid no-text result', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      return <String, Object>{
        'imageWidth': 1200.0,
        'imageHeight': 800.0,
        'tokens': <Object>[],
      };
    });

    final result = await PlatformLocalOcrEngine(
      channel: channel,
    ).recognize(Uint8List.fromList(const [1]));

    expect(result.tokens, isEmpty);
  });

  test('Chinese multiline tokens preserve native reading order', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      return <String, Object>{
        'imageWidth': 1200.0,
        'imageHeight': 800.0,
        'tokens': <Map<String, Object>>[
          <String, Object>{
            'text': '星期一',
            'left': 10.0,
            'top': 20.0,
            'right': 110.0,
            'bottom': 50.0,
            'confidence': 0.98,
          },
          <String, Object>{
            'text': '高等数学',
            'left': 10.0,
            'top': 80.0,
            'right': 160.0,
            'bottom': 110.0,
            'confidence': 0.95,
          },
        ],
      };
    });

    final result = await PlatformLocalOcrEngine(
      channel: channel,
    ).recognize(Uint8List.fromList(const [1]));

    expect(result.tokens.map((token) => token.text), ['星期一', '高等数学']);
    expect(result.tokens.last.confidence, 0.95);
  });

  test('native recognizer initialization failure is distinguished', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'ocr_initialization_failed',
        message: 'native detail',
      );
    });

    expect(
      () => PlatformLocalOcrEngine(
        channel: channel,
      ).recognize(Uint8List.fromList(const [1])),
      throwsA(
        isA<LocalOcrUnavailable>().having(
          (error) => error.message,
          'message',
          contains('OCR 初始化失败'),
        ),
      ),
    );
  });

  test('native recognition failure has a stable user-facing error', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'ocr_recognition_failed',
        message: 'Vision internal detail',
      );
    });

    expect(
      () => PlatformLocalOcrEngine(
        channel: channel,
      ).recognize(Uint8List.fromList(const [1])),
      throwsA(
        isA<LocalOcrUnavailable>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('OCR 识别失败'),
            isNot(contains('Vision internal detail')),
          ),
        ),
      ),
    );
  });

  test('unsupported native platform has a stable user-facing error', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unsupported_platform');
    });

    expect(
      () => PlatformLocalOcrEngine(
        channel: channel,
      ).recognize(Uint8List.fromList(const [1])),
      throwsA(
        isA<LocalOcrUnavailable>().having(
          (error) => error.message,
          'message',
          contains('当前设备暂不支持'),
        ),
      ),
    );
  });

  test('null native result is not treated as an empty draft', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    expect(
      () => PlatformLocalOcrEngine(
        channel: channel,
      ).recognize(Uint8List.fromList(const [1])),
      throwsA(isA<LocalOcrUnavailable>()),
    );
  });
}
