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
