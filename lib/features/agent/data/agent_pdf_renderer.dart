import 'dart:typed_data';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'agent_pdf_runtime_stub.dart'
    if (dart.library.js_interop) 'agent_pdf_runtime_web.dart';

/// Renders only the requested pages on the device. Opening data never fetches
/// a document URL or grants the PDF access to CheckD. Web uses the pinned,
/// locally served PDF.js assets; PDF bytes stay in the browser worker.
Future<List<Uint8List>> renderAgentPdfPages(
  Uint8List source,
  List<int> pageIndexes,
) async {
  pdfx.PdfDocument? document;
  try {
    await ensureAgentPdfRuntime();
    document = await pdfx.PdfDocument.openData(source);
    final result = <Uint8List>[];
    for (final index in pageIndexes) {
      if (index < 0 || index >= document.pagesCount) {
        throw const FormatException('PDF页码不正确，请重新选择文件。');
      }
      final page = await document.getPage(index + 1);
      try {
        if (page.width <= 0 || page.height <= 0) {
          throw const FormatException('PDF页面尺寸不正确，请改发截图。');
        }
        final longest = page.width > page.height ? page.width : page.height;
        final scale = 1800 / longest;
        final raster = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: pdfx.PdfPageImageFormat.png,
          backgroundColor: '#FFFFFF',
        );
        if (raster == null) {
          throw const FormatException('PDF页面未能转图，请重试或改发截图。');
        }
        result.add(raster.bytes);
      } finally {
        await page.close();
      }
    }
    return result;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
      '本机PDF转图组件尚未加载或文件受密码保护。网页版请刷新以加载本地PDF组件；也可改发课表截图或解锁后的PDF。',
    );
  } finally {
    await document?.close();
  }
}
