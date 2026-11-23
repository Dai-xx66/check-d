import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/agent_attachment_service.dart';
import '../domain/agent_models.dart';
import 'school/agent_school_browser.dart';

/// A local-only import surface. It returns a reviewed attachment to the chat;
/// opening a site or extracting a table never calls the cloud/model gateway.
class AgentSchoolPage extends StatefulWidget {
  const AgentSchoolPage({super.key, this.initialUrl, this.browserFactory});

  final String? initialUrl;
  final AgentSchoolBrowserFactory? browserFactory;

  @override
  State<AgentSchoolPage> createState() => _AgentSchoolPageState();
}

class _AgentSchoolPageState extends State<AgentSchoolPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _url;
  final _preview = TextEditingController();
  late final AgentSchoolBrowser _browser;
  bool _busy = false;
  bool _opened = false;
  bool _truncated = false;
  String? _schoolHost;
  String? _error;

  bool get _isHtml => RegExp(
    r'<(?:html|body|table|tr|td|div|p)\b',
    caseSensitive: false,
  ).hasMatch(_preview.text);

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.initialUrl ?? '');
    _browser = (widget.browserFactory ?? createAgentSchoolBrowser)();
  }

  @override
  void dispose() {
    _browser.dispose();
    _url.dispose();
    _preview.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uri = validateSchoolUrl(_url.text);
      await _browser.open(uri);
      if (!mounted) return;
      setState(() {
        _opened = true;
        _schoolHost = uri.host;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : '教务网页暂时无法打开，请使用粘贴文本或导入截图/文件。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extract() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final extraction = decodeSchoolExtraction(await _browser.extract());
      if (!mounted) return;
      setState(() {
        _preview.text = extraction.text;
        _truncated = extraction.truncated;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message.toString()
              : '未能提取课表。请确认已进入课表页，或使用截图/导出文件。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _finish() {
    var text = _preview.text.trim();
    if (_isHtml) {
      text = AgentAttachmentService.visibleHtmlText(text);
      setState(() {
        _preview.text = text;
        _error = text.isEmpty ? '粘贴的HTML中没有课表正文，请改用截图或课表文件。' : null;
      });
      return;
    }
    if (text.isEmpty) return;
    Navigator.pop<AgentAttachment>(
      context,
      AgentAttachment(
        name: '教务课表${_schoolHost == null ? '' : '（$_schoolHost）'}.txt',
        kind: '教务课表',
        text: text,
        note:
            '由用户在本机提取、检查并编辑；添加附件不会自动上传。课表的有效起止日期、周次和作息仍需确认。${_truncated ? '原课表超过提取上限，仅保留前20张表、每表400行、32列与60000字，请拆分补充其余内容。' : ''}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('导入教务课表')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            return SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 16 : 24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1050),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.school_outlined,
                                  color: AppColors.primaryStrong,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '登录、提取、检查，再添加',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '你直接在学校网页登录，CheckD不收集账号密码。提取只读取可见表格，不读取登录表单、Cookie或浏览器存储。检查后添加到对话，点击发送才会提交。',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _browser.capabilityNote,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _panel(
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _url,
                                keyboardType: TextInputType.url,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: '学校教务网站地址',
                                  hintText: 'https://jw.example.edu.cn',
                                  prefixIcon: Icon(Icons.link),
                                ),
                                validator: (value) {
                                  try {
                                    validateSchoolUrl(value ?? '');
                                    return null;
                                  } on FormatException catch (error) {
                                    return error.message.toString();
                                  }
                                },
                                onFieldSubmitted: (_) {
                                  if (!_busy) _open();
                                },
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  FilledButton.tonalIcon(
                                    onPressed: _busy ? null : _open,
                                    icon: const Icon(Icons.open_in_browser),
                                    label: Text(
                                      _browser.canExtract
                                          ? '打开并自行登录'
                                          : '在浏览器打开',
                                    ),
                                  ),
                                  if (_browser.canExtract)
                                    OutlinedButton.icon(
                                      onPressed: _busy || !_opened
                                          ? null
                                          : _extract,
                                      icon: const Icon(
                                        Icons.table_view_outlined,
                                      ),
                                      label: const Text('提取当前课表'),
                                    ),
                                ],
                              ),
                              if (_busy)
                                const Padding(
                                  padding: EdgeInsets.only(top: 16),
                                  child: LinearProgressIndicator(),
                                ),
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      _error!,
                                      style: TextStyle(
                                        color: theme.colorScheme.error,
                                      ),
                                    ),
                                  ),
                                ),
                              if (_opened && _browser.canExtract)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: SizedBox(
                                      height: compact ? 400 : 480,
                                      child: _browser.buildView(),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('检查课表内容', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            const Text(
                              '也可以直接粘贴课表文本或HTML。请删除姓名、学号等无关信息，保留日期范围、周次、课程名、星期和起止时间。',
                            ),
                            if (_truncated)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  '课表超过提取上限，当前预览只保留部分内容。请拆分并补充其余课表。',
                                  style: TextStyle(color: AppColors.orange),
                                ),
                              ),
                            const SizedBox(height: 16),
                            TextField(
                              key: const ValueKey('school-preview'),
                              controller: _preview,
                              minLines: 6,
                              maxLines: 16,
                              maxLength:
                                  AgentAttachmentService.maxTextCharacters,
                              decoration: const InputDecoration(
                                labelText: '课表预览（可修改）',
                                alignLabelWithHint: true,
                                hintText: '粘贴或提取课表后在这里检查',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _busy || _preview.text.trim().isEmpty
                                    ? null
                                    : _finish,
                                icon: Icon(
                                  _isHtml
                                      ? Icons.cleaning_services_outlined
                                      : Icons.attach_file,
                                ),
                                label: Text(_isHtml ? '整理HTML并预览' : '添加到本次对话'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.glassStrong,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(24),
    ),
    child: child,
  );
}
