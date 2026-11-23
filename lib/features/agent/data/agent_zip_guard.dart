import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Checks ZIP32 directory/local headers before ZipDecoder sees the package.
/// archive 3 decodes symbolic-link contents eagerly even when verify=false.
/// A 20MB OOXML input does not need ZIP64 or split/encrypted ZIP support.
void validateAgentOfficeZip(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  Never invalid() => throw const FormatException(
    '文档压缩结构不受支持、损坏或过大，请另存为标准DOCX/XLSX/PPTX或拆分文件。',
  );
  int u16(int offset) => data.getUint16(offset, Endian.little);
  int u32(int offset) => data.getUint32(offset, Endian.little);
  var eocd = -1;
  final earliest = bytes.length > 65557 ? bytes.length - 65557 : 0;
  for (var offset = bytes.length - 22; offset >= earliest; offset--) {
    if (u32(offset) == 0x06054b50 &&
        offset + 22 + u16(offset + 20) == bytes.length) {
      eocd = offset;
      break;
    }
  }
  if (eocd < 0) invalid();
  final count = u16(eocd + 10);
  final directorySize = u32(eocd + 12);
  final directoryStart = u32(eocd + 16);
  if (u16(eocd + 4) != 0 ||
      u16(eocd + 6) != 0 ||
      u16(eocd + 8) != count ||
      count > 2000 ||
      directorySize > 4 * 1024 * 1024 ||
      directoryStart + directorySize != eocd) {
    invalid();
  }
  var position = directoryStart, entries = 0, total = 0;
  final end = directoryStart + directorySize;
  while (position < end) {
    if (++entries > 2000 || position + 46 > end || u32(position) != 0x02014b50) {
      invalid();
    }
    final flags = u16(position + 8), method = u16(position + 10);
    final crc = u32(position + 16),
        compressed = u32(position + 20),
        size = u32(position + 24);
    final local = u32(position + 42);
    final mode = u32(position + 38) >> 16;
    total += size;
    if ((flags & 1) != 0 ||
        (method != 0 && method != 8) ||
        (mode & 0xf000) == 0xa000 ||
        size > 16 * 1024 * 1024 ||
        total > 64 * 1024 * 1024 ||
        u16(position + 34) != 0 ||
        local + 30 > directoryStart ||
        compressed > bytes.length ||
        u32(local) != 0x04034b50 ||
        u16(local + 6) != flags ||
        u16(local + 8) != method) {
      invalid();
    }
    final payload = local + 30 + u16(local + 26) + u16(local + 28);
    if (payload + compressed > directoryStart) invalid();
    if ((flags & 8) == 0) {
      if (u32(local + 14) != crc ||
          u32(local + 18) != compressed ||
          u32(local + 22) != size) {
        invalid();
      }
    } else {
      var descriptor = payload + compressed;
      if (descriptor + 4 > directoryStart) invalid();
      if (u32(descriptor) == 0x08074b50) descriptor += 4;
      if (descriptor + 12 > directoryStart ||
          u32(descriptor) != crc ||
          u32(descriptor + 4) != compressed ||
          u32(descriptor + 8) != size) {
        invalid();
      }
    }
    position +=
        46 + u16(position + 28) + u16(position + 30) + u16(position + 32);
    if (position > end) invalid();
  }
  if (entries != count || position != end) invalid();
}

/// Deflate output is bounded while it is produced, including when a malicious
/// ZIP lies about its uncompressed size. Native inflateBuffer is unbounded.
List<int> readAgentOfficeXml(ArchiveFile file) {
  final raw = file.rawContent;
  if (raw == null || file.size > 8 * 1024 * 1024) {
    throw const FormatException('文档单页内容过大或无法读取，请拆分。');
  }
  final output = _BoundedZipOutput(file.size);
  final input = InputStream(raw.toUint8List());
  if (file.compressionType == ArchiveFile.DEFLATE) {
    Inflate.stream(input, output);
  } else if (file.compressionType == ArchiveFile.STORE) {
    output.writeInputStream(input);
  } else {
    throw const FormatException('文档压缩方式不受支持，请另存为标准Office文件。');
  }
  final content = output.getBytes();
  if (content.length != file.size || getCrc32(content) != file.crc32) {
    throw const FormatException('文档内容与压缩目录不一致，请重新导出。');
  }
  return content;
}

class _BoundedZipOutput extends OutputStream {
  _BoundedZipOutput(this.limit) : super(size: limit < 1024 ? limit : 1024);
  final int limit;
  void _check(int addition) {
    if (addition < 0 || length + addition > limit) {
      throw const FormatException('文档解压超过声明大小，已停止读取，请重新导出或拆分。');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    _check(len ?? bytes.length);
    super.writeBytes(bytes, len);
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    _check(stream.length);
    super.writeInputStream(stream);
  }
}
