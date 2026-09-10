import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/course_schedule_import_models.dart';
import '../domain/local_ocr_models.dart';

/// Development-only aid for inspecting native OCR geometry against an image.
/// It is deliberately opt-in and is not placed in the normal import flow.
class OcrDebugOverlay extends StatelessWidget {
  const OcrDebugOverlay({
    super.key,
    required this.child,
    required this.page,
    this.parseDebug,
  });

  final Widget child;
  final OcrPageResult page;
  final CourseScheduleParseDebug? parseDebug;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: CustomPaint(painter: _OcrDebugPainter(page, parseDebug)),
        ),
      ],
    );
  }
}

class _OcrDebugPainter extends CustomPainter {
  const _OcrDebugPainter(this.page, this.parseDebug);

  final OcrPageResult page;
  final CourseScheduleParseDebug? parseDebug;

  @override
  void paint(Canvas canvas, Size size) {
    if (page.imageWidth <= 0 || page.imageHeight <= 0) return;
    final scaleX = size.width / page.imageWidth;
    final scaleY = size.height / page.imageHeight;
    final border = Paint()
      ..color = Colors.deepOrangeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final token in page.tokens) {
      final box = token.boundingBox;
      final rect = Rect.fromLTRB(
        box.left * scaleX,
        box.top * scaleY,
        box.right * scaleX,
        box.bottom * scaleY,
      );
      canvas.drawRect(rect, border);
      final painter = TextPainter(
        text: TextSpan(
          text: token.text,
          style: const TextStyle(
            color: Colors.deepOrange,
            fontSize: 9,
            backgroundColor: Colors.white70,
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - rect.left);
      painter.paint(canvas, Offset(rect.left, rect.top));
    }
    _paintBoxes(
      canvas,
      size,
      parseDebug?.weekdayColumns ?? const [],
      Colors.blue,
    );
    _paintBoxes(
      canvas,
      size,
      parseDebug?.sectionRows ?? const [],
      Colors.purple,
    );
    _paintBoxes(
      canvas,
      size,
      parseDebug?.acceptedCells ?? const [],
      Colors.green,
      width: 2,
    );
    _paintBoxes(
      canvas,
      size,
      parseDebug?.rejectedTokens ?? const [],
      Colors.red,
    );
  }

  void _paintBoxes(
    Canvas canvas,
    Size size,
    List<OcrBoundingBox> boxes,
    Color color, {
    double width = 1,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final box in boxes) {
      canvas.drawRect(
        Rect.fromLTRB(
          box.left * size.width / page.imageWidth,
          box.top * size.height / page.imageHeight,
          box.right * size.width / page.imageWidth,
          box.bottom * size.height / page.imageHeight,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OcrDebugPainter oldDelegate) =>
      oldDelegate.page != page || oldDelegate.parseDebug != parseDebug;
}
