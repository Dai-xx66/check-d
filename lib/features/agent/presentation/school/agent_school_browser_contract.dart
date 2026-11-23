import 'dart:convert';

import 'package:flutter/widgets.dart';

/// The school page has no CheckD JavaScript channel and cannot call app tools.
/// Only a user-initiated, read-only extraction returns table text to the page.
abstract interface class AgentSchoolBrowser {
  bool get canExtract;
  String get capabilityNote;
  Future<void> open(Uri url);
  Widget buildView();
  Future<Object?> extract();
  void dispose();
}

typedef AgentSchoolBrowserFactory = AgentSchoolBrowser Function();

Uri validateSchoolUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  final host = uri?.host.toLowerCase() ?? '';
  if (uri == null ||
      uri.scheme != 'https' ||
      host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443) ||
      !host.contains('.') ||
      host.contains(':') ||
      RegExp(r'^[0-9.]+$').hasMatch(host) ||
      host.endsWith('.') ||
      const [
        '.localhost',
        '.local',
        '.internal',
        '.test',
        '.invalid',
      ].any(host.endsWith)) {
    throw const FormatException('请输入学校公开网站的HTTPS地址；不支持本机、内网IP或带账号密码的地址。');
  }
  return uri;
}

({String text, bool truncated}) decodeSchoolExtraction(Object? result) {
  Object? decoded = result;
  for (var i = 0; i < 3 && decoded is String; i++) {
    try {
      decoded = jsonDecode(decoded);
    } catch (_) {
      throw const FormatException('网页未返回可读课表。请进入课表页后重试，或使用截图/文件导入。');
    }
  }
  if (decoded is! Map || decoded['text'] is! String) {
    throw const FormatException('网页未返回可读课表。请使用截图、课表文件或粘贴文本。');
  }
  final text = (decoded['text'] as String).trim();
  if (text.isEmpty) {
    throw const FormatException('当前页没有可见的表格课表。Canvas、图片或跨域框架课表请截图或导出文件后添加。');
  }
  return (
    text: text.length > 60000 ? text.substring(0, 60000) : text,
    truncated: decoded['truncated'] == true || text.length > 60000,
  );
}

/// Runs only when the user presses “提取当前课表”. It does not read accounts,
/// password values, cookies, storage, hidden fields, iframe documents or the
/// page body. No script from the school page is executed inside CheckD.
const agentSchoolExtractionScript = r'''
(() => {
  if (location.protocol !== 'https:') return JSON.stringify({text: ''});
  const visible = e => {
    const s = getComputedStyle(e);
    return !e.hidden && e.getAttribute('aria-hidden') !== 'true' &&
      s.display !== 'none' && s.visibility !== 'hidden' && e.getClientRects().length > 0;
  };
  const controls = 'input,textarea,select,button,[contenteditable="true"]';
  const clean = element => {
    if (!visible(element) || element.matches(controls) || element.closest('form')) return '';
    const copy = element.cloneNode(true);
    const originalNodes = element.querySelectorAll('*');
    const copiedNodes = copy.querySelectorAll('*');
    for (let i = originalNodes.length - 1; i >= 0; i--) {
      const original = originalNodes[i];
      if (!visible(original) || original.matches(controls + ',script,style,noscript,iframe,object,embed')) {
        copiedNodes[i].remove();
      }
    }
    return (copy.textContent || '').replace(/\s+/g, ' ').trim();
  };
  const tables = [...document.querySelectorAll('table,[role="grid"],[role="table"]')]
    .filter(e => visible(e) && !e.closest('form') &&
      !e.parentElement?.closest('table,[role="grid"],[role="table"]'));
  const sections = [];
  let truncated = tables.length > 20;
  for (const table of tables.slice(0, 20)) {
    const rows = [...table.querySelectorAll('tr,[role="row"]')].filter(visible);
    if (rows.length > 400) truncated = true;
    const lines = [];
    for (const row of rows.slice(0, 400)) {
      if (row.querySelector(controls) || row.closest('form')) continue;
      const cells = [...row.querySelectorAll('th,td,[role="cell"],[role="gridcell"],[role="columnheader"],[role="rowheader"]')];
      if (cells.length > 32) truncated = true;
      const line = cells.slice(0, 32).map(clean).filter(Boolean).join('\t');
      if (line) lines.push(line);
    }
    if (lines.length) sections.push(lines.join('\n'));
  }
  const text = sections.join('\n\n');
  return JSON.stringify({text: text.slice(0, 60000), truncated: truncated || text.length > 60000});
})()
''';
