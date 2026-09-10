class OcrBoundingBox {
  const OcrBoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
}

class OcrToken {
  const OcrToken({
    required this.text,
    required this.boundingBox,
    this.confidence,
  });

  final String text;
  final OcrBoundingBox boundingBox;
  final double? confidence;
}

class OcrPageResult {
  const OcrPageResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.tokens,
  });

  final double imageWidth;
  final double imageHeight;
  final List<OcrToken> tokens;
}
