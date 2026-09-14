import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../domain/course_share_models.dart';

class CourseShareScannerPage extends StatefulWidget {
  const CourseShareScannerPage({super.key});

  @override
  State<CourseShareScannerPage> createState() => _CourseShareScannerPageState();
}

class _CourseShareScannerPageState extends State<CourseShareScannerPage> {
  bool _handled = false;
  String? _error;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫描课程分享二维码')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(onDetect: _onDetect),
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
        if (_error != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.all(20),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (value == null) return;
    try {
      final code = CourseShareCode.fromQrValue(value);
      _handled = true;
      Navigator.of(context).pop(code);
    } on CourseShareException catch (error) {
      setState(() => _error = error.message);
    }
  }
}
