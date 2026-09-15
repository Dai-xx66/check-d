import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../domain/course_share_models.dart';

class CourseShareScannerPage extends StatefulWidget {
  const CourseShareScannerPage({super.key});

  @override
  State<CourseShareScannerPage> createState() => _CourseShareScannerPageState();
}

class _CourseShareScannerPageState extends State<CourseShareScannerPage> {
  final _controller = MobileScannerController();
  bool _handled = false;
  bool _pickingImage = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫描课程分享二维码')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            minimum: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ScannerMessage(text: _error ?? '将 Check D 课程分享二维码放入框内'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _pickingImage ? null : _pickFromGallery,
                  icon: _pickingImage
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_library_outlined),
                  label: Text(_pickingImage ? '正在识别图片…' : '从相册选择'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  void _onDetect(BarcodeCapture capture) {
    if (_handled || _pickingImage) return;
    _handleValues(capture.barcodes.map((barcode) => barcode.rawValue));
  }

  Future<void> _pickFromGallery() async {
    setState(() {
      _pickingImage = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final file = result?.files.singleOrNull;
      if (file == null) return;
      final path = file.path;
      if (path == null || path.isEmpty) {
        throw const _QrImageReadException('无法读取所选图片，请重新选择。');
      }
      final capture = await _controller.analyzeImage(
        path,
        formats: const [BarcodeFormat.qrCode],
      );
      if (!mounted || capture == null || capture.barcodes.isEmpty) {
        if (mounted) setState(() => _error = '这张图片中没有识别到二维码。');
        return;
      }
      _handleValues(capture.barcodes.map((barcode) => barcode.rawValue));
    } on _QrImageReadException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on UnsupportedError {
      if (mounted) setState(() => _error = '当前设备暂不支持从相册识别二维码，请使用摄像头扫描。');
    } on MobileScannerBarcodeException {
      if (mounted) setState(() => _error = '无法读取这张二维码图片，请重新选择清晰的图片。');
    } catch (_) {
      if (mounted) setState(() => _error = '读取二维码图片失败，请检查图片权限后重试。');
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  void _handleValues(Iterable<String?> values) {
    if (_handled) return;
    final value = values.whereType<String>().firstOrNull;
    if (value == null) {
      setState(() => _error = '没有读取到二维码内容。');
      return;
    }
    try {
      final code = CourseShareQrDecoder.decode(value);
      _handled = true;
      Navigator.of(context).pop(code);
    } on CourseShareException catch (error) {
      setState(() => _error = error.message);
    }
  }
}

abstract final class CourseShareQrDecoder {
  static String decode(String value) => CourseShareCode.fromQrValue(value);
}

class _QrImageReadException implements Exception {
  const _QrImageReadException(this.message);
  final String message;
}

class _ScannerMessage extends StatelessWidget {
  const _ScannerMessage({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
