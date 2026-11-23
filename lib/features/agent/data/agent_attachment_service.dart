import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:xml/xml.dart';

import '../domain/agent_models.dart';
import 'agent_pdf_renderer.dart';
import 'agent_zip_guard.dart';

/// Rasterization stays on the device. Page indexes are zero based, and the
/// returned PNG/JPEG bytes must follow that order. No source bytes are uploaded
/// by this service: the chat explicitly submits the resulting attachment later.
typedef AgentPdfPageRenderer =
    Future<List<Uint8List>> Function(Uint8List source, List<int> pageIndexes);

class AgentAttachmentService {
  AgentAttachmentService({AgentPdfPageRenderer? pdfPageRenderer})
    : pdfPageRenderer = pdfPageRenderer ?? renderAgentPdfPages;

  final AgentPdfPageRenderer pdfPageRenderer;
  static const maxFileBytes = 20 * 1024 * 1024;
  static const maxAttachments = 6;
  static const maxImages = 12;
  // Base64 plus its data-URL prefix must fit the gateway's 4MiB/image limit.
  static const maxImagePngBytes = 29 * 1024 * 1024 ~/ 10;
  static const maxTextCharacters = 60000;
  static const maxPdfPages = 16;
  static const maxScannedPages = 8;
  static const supportedExtensions = <String>[
    'png',
    'jpg',
    'jpeg',
    'webp',
    'pdf',
    'docx',
    'xlsx',
    'pptx',
    'txt',
    'md',
    'csv',
    'tsv',
    'json',
    'html',
    'htm',
    'ics',
  ];

  static void validateSelection(Iterable<AgentAttachment> attachments) {
    final selected = attachments.toList(growable: false);
    if (selected.length > maxAttachments) {
      throw const FormatException('一次最多添加6个附件，请分批发送。');
    }
    if (selected.fold<int>(0, (count, item) => count + item.images.length) >
        maxImages) {
      throw const FormatException('一次最多12张图片或PDF扫描页，请分批发送。');
    }
  }

  Future<AgentAttachment> read(String name, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > maxFileBytes) {
      throw const FormatException('附件须为非空文件，且单个文件不超过20MB。');
    }
    final extension = name.split('.').last.toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      throw const FormatException(
        '暂不支持此格式；旧DOC/XLS/PPT请另存为DOCX/XLSX/PPTX或PDF。',
      );
    }
    if (const ['png', 'jpg', 'jpeg', 'webp'].contains(extension)) {
      return AgentAttachment(
        name: name,
        kind: '图片',
        images: [await _image(bytes)],
        note: '图片已在本机处理；点击发送后才会提交，需图像识别能力。',
      );
    }
    if (extension == 'pdf') return _pdf(name, bytes);
    var text = '';
    final notes = <String>[];
    try {
      if (const ['docx', 'pptx', 'xlsx'].contains(extension)) {
        final archive = _officeArchive(bytes);
        if (extension == 'xlsx') {
          final extracted = _spreadsheet(archive);
          text = extracted.$1;
          notes.addAll(extracted.$2);
        } else {
          text = _officeText(archive, extension);
        }
      } else {
        text = _decodeText(bytes);
        if (extension == 'html' || extension == 'htm') {
          text = visibleHtmlText(text);
        }
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无法读取此文档，请检查文件是否损坏或加密，或另存为PDF/UTF-8文本。');
    }
    text = text.trim();
    if (text.isEmpty) {
      throw const FormatException('没有提取到正文；若内容是扫描图片，请发送截图或扫描PDF。');
    }
    if (text.length > maxTextCharacters) {
      text = text.substring(0, maxTextCharacters);
      notes.add('正文仅提取前60000字，其余内容未发送，请拆分文件。');
    }
    return AgentAttachment(
      name: name,
      kind: extension.toUpperCase(),
      text: text,
      note: ['正文在本机提取；添加附件不会自动上传。', ...notes].join('\n'),
    );
  }

  static String visibleHtmlText(String source) {
    final document = html.parse(source);
    document
        .querySelectorAll(
          'script,style,noscript,iframe,object,embed,form,input,textarea,select',
        )
        .forEach((element) => element.remove());
    final out = StringBuffer();
    void walk(dom.Node node) {
      if (node is dom.Text) {
        out.write(node.text);
      } else if (node is dom.Element) {
        if (node.attributes.containsKey('hidden') ||
            node.attributes['aria-hidden'] == 'true') {
          return;
        }
        for (final child in node.nodes) {
          walk(child);
        }
        if (const [
          'p',
          'div',
          'tr',
          'br',
          'li',
          'h1',
          'h2',
          'h3',
          'section',
          'article',
        ].contains(node.localName)) {
          out.writeln();
        }
        if (const ['td', 'th'].contains(node.localName)) out.write('\t');
      }
    }

    walk(document.body ?? document.documentElement!);
    return out
        .toString()
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Future<String> _image(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width * descriptor.height > 40 * 1000 * 1000) {
        throw const FormatException('图片像素过大，请缩小后发送。');
      }
      final longest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      for (final target in const [1800, 1200, 900]) {
        if (target != 1800 && target >= longest) continue;
        image?.dispose();
        image = null;
        codec?.dispose();
        codec = null;
        final scale = longest > target ? target / longest : 1.0;
        codec = await descriptor.instantiateCodec(
          targetWidth: (descriptor.width * scale).round().clamp(1, target),
          targetHeight: (descriptor.height * scale).round().clamp(1, target),
        );
        image = (await codec.getNextFrame()).image;
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw const FormatException('无法读取图片，请重新选择。');
        if (png.lengthInBytes <= maxImagePngBytes) {
          return 'data:image/png;base64,${base64Encode(png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes))}';
        }
      }
      throw const FormatException('图片处理后仍超过大小限制，请裁剪课表区域或缩小图片后添加。');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('图片无法解码，请选择有效的PNG、JPEG或WEBP。');
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Future<AgentAttachment> _pdf(String name, Uint8List bytes) async {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      if (document.pages.count > maxPdfPages) {
        throw const FormatException('PDF超过16页，请拆分后发送。');
      }
      final texts = <String>[];
      final scanned = <int>[];
      final extractor = PdfTextExtractor(document);
      for (var index = 0; index < document.pages.count; index++) {
        final text = extractor
            .extractText(
              startPageIndex: index,
              endPageIndex: index,
              layoutText: true,
            )
            .trim();
        texts.add('第${index + 1}页：\n$text');
        if (text.length < 40) scanned.add(index);
      }
      if (scanned.length > maxScannedPages) {
        throw const FormatException('PDF扫描页超过8页，请拆分后发送。');
      }
      final images = <String>[];
      if (scanned.isNotEmpty) {
        final pages = await pdfPageRenderer(bytes, scanned);
        if (pages.length != scanned.length) {
          throw const FormatException('PDF部分扫描页未能读取，未发送不完整材料，请重试或改发截图。');
        }
        for (final page in pages) {
          images.add(await _image(page));
        }
      }
      var text = texts.join('\n\n');
      final notes = <String>['PDF在本机提取；共${document.pages.count}页。'];
      if (scanned.isNotEmpty) {
        notes.add('第${scanned.map((i) => i + 1).join('、')}页已本地转为图片，需图像识别能力。');
      }
      if (text.length > maxTextCharacters) {
        text = text.substring(0, maxTextCharacters);
        notes.add('正文仅提取前60000字，其余未发送，请拆分。');
      }
      return AgentAttachment(
        name: name,
        kind: 'PDF',
        text: text,
        images: images,
        note: notes.join('\n'),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('PDF无法读取或受密码保护，请先解锁文件，或将课程页另存为截图。');
    } finally {
      document?.dispose();
    }
  }

  Archive _officeArchive(Uint8List bytes) {
    // This must precede ZipDecoder: Unix links are eagerly inflated there.
    validateAgentOfficeZip(bytes);
    final decoder = ZipDecoder();
    final archive = decoder.decodeBytes(bytes);
    var total = 0;
    if (archive.files.length > 2000) {
      throw const FormatException('文档内容过多，请拆分后发送。');
    }
    for (final file in archive.files) {
      total += file.size;
      if (file.size > 16 * 1024 * 1024 ||
          total > 64 * 1024 * 1024 ||
          file.isSymbolicLink) {
        throw const FormatException('文档解压内容过大或格式不受支持，请拆分后发送。');
      }
    }
    return archive;
  }

  XmlDocument? _xml(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null) return null;
    if (file.size > 8 * 1024 * 1024) {
      throw const FormatException('文档单页内容过大，请拆分。');
    }
    final content = readAgentOfficeXml(file);
    final text = utf8.decode(content);
    if (text.contains('<!DOCTYPE') || text.contains('<!ENTITY')) {
      throw const FormatException('文档含不支持的XML声明，请另存为PDF。');
    }
    return XmlDocument.parse(text);
  }

  String _officeText(Archive archive, String extension) {
    final names = archive.files
        .map((f) => f.name)
        .where(
          (name) => extension == 'docx'
              ? RegExp(
                  r'^word/(document|header\d+|footer\d+)\.xml$',
                ).hasMatch(name)
              : RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(name),
        )
        .toList();
    names.sort((a, b) {
      if (a == 'word/document.xml') return -1;
      if (b == 'word/document.xml') return 1;
      final ai =
          int.tryParse(RegExp(r'\d+').firstMatch(a)?.group(0) ?? '') ?? 0;
      final bi =
          int.tryParse(RegExp(r'\d+').firstMatch(b)?.group(0) ?? '') ?? 0;
      return ai == bi ? a.compareTo(b) : ai.compareTo(bi);
    });
    final out = StringBuffer();
    for (final name in names) {
      final doc = _xml(archive, name)!;
      if (extension == 'pptx') {
        out.writeln('[${name.split('/').last.replaceAll('.xml', '')}]');
      }
      for (final paragraph in doc.descendants.whereType<XmlElement>().where(
        (e) => e.name.local == 'p',
      )) {
        out.writeln(
          paragraph.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 't')
              .map((e) => e.innerText)
              .join(),
        );
      }
      if (out.length > maxTextCharacters) break;
    }
    return out.toString();
  }

  (String, List<String>) _spreadsheet(Archive archive) {
    final styles = _xml(archive, 'xl/styles.xml');
    final customFormats = <int, String>{
      for (final format in styles?.findAllElements('numFmt') ?? <XmlElement>[])
        if (int.tryParse(format.getAttribute('numFmtId') ?? '')
            case final int id)
          id: format.getAttribute('formatCode') ?? '',
    };
    final cellFormats =
        styles
            ?.getElement('styleSheet')
            ?.getElement('cellXfs')
            ?.findElements('xf')
            .map(
              (style) =>
                  int.tryParse(style.getAttribute('numFmtId') ?? '') ?? 0,
            )
            .toList() ??
        <int>[];
    final workbook = _xml(archive, 'xl/workbook.xml');
    final date1904 = const ['1', 'true'].contains(
      workbook
          ?.findAllElements('workbookPr')
          .firstOrNull
          ?.getAttribute('date1904'),
    );
    final strings =
        _xml(archive, 'xl/sharedStrings.xml')
            ?.findAllElements('si')
            .map((si) => si.findAllElements('t').map((t) => t.innerText).join())
            .toList() ??
        <String>[];
    final names =
        archive.files
            .map((f) => f.name)
            .where(
              (name) => RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(name),
            )
            .toList()
          ..sort(
            (a, b) => (int.parse(
              RegExp(r'\d+').firstMatch(a)!.group(0)!,
            )).compareTo(int.parse(RegExp(r'\d+').firstMatch(b)!.group(0)!)),
          );
    final notes = <String>[];
    if (names.length > 20) notes.add('仅提取前20个工作表。');
    final out = StringBuffer();
    for (final name in names.take(20)) {
      final sheet = _xml(archive, name)!;
      out.writeln('[$name]');
      var rowCount = 0;
      for (final row in sheet.findAllElements('row')) {
        if (++rowCount > 1000) {
          notes.add('工作表仅提取前1000个数据行。');
          break;
        }
        final cells = <String>[];
        for (final cell in row.findElements('c')) {
          final address = cell.getAttribute('r') ?? '';
          final letters = address.replaceAll(RegExp(r'\d'), '').toUpperCase();
          var column = 0;
          for (final letter in letters.codeUnits) {
            column = column * 26 + letter - 64;
          }
          if (column > 32) {
            if (!notes.contains('工作表仅提取前32列。')) notes.add('工作表仅提取前32列。');
            continue;
          }
          var value = cell.getElement('v')?.innerText ?? '';
          if (cell.getAttribute('t') == 's') {
            final index = int.tryParse(value);
            value = index != null && index >= 0 && index < strings.length
                ? strings[index]
                : '';
          } else if (cell.getAttribute('t') == 'inlineStr') {
            value = cell.findAllElements('t').map((t) => t.innerText).join();
          } else if (cell.getAttribute('t') == null ||
              cell.getAttribute('t') == 'n') {
            final style = int.tryParse(cell.getAttribute('s') ?? '');
            if (style != null && style >= 0 && style < cellFormats.length) {
              value = _spreadsheetNumber(
                value,
                cellFormats[style],
                customFormats,
                date1904,
              );
            }
          }
          if (value.isEmpty && cell.getElement('f') != null) {
            value = '[公式无缓存结果，请在表格软件重算并保存或另存为CSV]';
            if (!notes.contains('部分公式没有缓存结果，未执行公式或访问外部数据。')) {
              notes.add('部分公式没有缓存结果，未执行公式或访问外部数据。');
            }
          }
          if (value.trim().isNotEmpty) cells.add('$address=$value');
        }
        if (cells.isNotEmpty) out.writeln(cells.join(' | '));
        if (out.length > maxTextCharacters) return (out.toString(), notes);
      }
    }
    return (out.toString(), notes);
  }

  String _spreadsheetNumber(
    String raw,
    int formatId,
    Map<int, String> customFormats,
    bool date1904,
  ) {
    final number = double.tryParse(raw);
    if (number == null || !number.isFinite || number < 0 || number > 2958465) {
      return raw;
    }
    const builtinDates = {14, 15, 16, 17, 22};
    const builtinTimes = {18, 19, 20, 21, 22, 45, 46, 47};
    final format = (customFormats[formatId] ?? '')
        .replaceAll(RegExp(r'"[^\"]*"|\\.'), '')
        .toLowerCase()
        .replaceAllMapped(
          RegExp(r'\[[^\]]*\]'),
          (match) => match.group(0) == '[h]' ? '[h]' : '',
        );
    final hasDate =
        builtinDates.contains(formatId) || RegExp(r'[yd]').hasMatch(format);
    final hasTime =
        builtinTimes.contains(formatId) || RegExp(r'[hs]').hasMatch(format);
    final dateFormat = hasDate || (!hasTime && format.contains('m'));
    if (!dateFormat && !hasTime) return raw;
    String pad(int n) => n.toString().padLeft(2, '0');
    final seconds = (number * 24 * 60 * 60).round();
    final minutes = seconds ~/ 60;
    final showSeconds =
        const {19, 21, 45, 46, 47}.contains(formatId) || format.contains('s');
    final secondSuffix = showSeconds ? ':${pad(seconds % 60)}' : '';
    final time =
        '${pad((minutes ~/ 60) % 24)}:${pad(minutes % 60)}$secondSuffix';
    if (formatId == 46 || format.contains('[h]')) {
      return '${minutes ~/ 60}:${pad(minutes % 60)}';
    }
    if (!dateFormat) return time;
    final base = date1904
        ? DateTime.utc(1904)
        : (number < 60
              ? DateTime.utc(1899, 12, 31)
              : DateTime.utc(1899, 12, 30));
    final date = base.add(Duration(days: number.floor()));
    final day =
        '${date.year.toString().padLeft(4, '0')}-${pad(date.month)}-${pad(date.day)}';
    return hasTime ? '$day $time' : day;
  }

  String _decodeText(Uint8List bytes) {
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      if (bytes.length.isOdd) throw const FormatException('文本编码不完整，请另存为UTF-8。');
      final data = ByteData.sublistView(bytes);
      final endian = bytes[0] == 0xff ? Endian.little : Endian.big;
      return String.fromCharCodes([
        for (var i = 2; i < bytes.length; i += 2) data.getUint16(i, endian),
      ]);
    }
    try {
      return utf8.decode(bytes).replaceFirst('\ufeff', '');
    } on FormatException {
      throw const FormatException('文本不是有效UTF-8/UTF-16，请另存为UTF-8后导入。');
    }
  }
}
