import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'agent_school_browser_contract.dart';

AgentSchoolBrowser createSchoolBrowser() => _WebSchoolBrowser();

class _WebSchoolBrowser implements AgentSchoolBrowser {
  @override
  bool get canExtract => false;
  @override
  String get capabilityNote =>
      '网页版会在独立标签页打开教务网站。浏览器的跨域隔离不允许CheckD读取登录页，请复制课表文本到下方，或返回对话添加截图/HTML文件。';
  @override
  Future<void> open(Uri url) async {
    validateSchoolUrl(url.toString());
    web.window.open(url.toString(), '_blank', 'noopener,noreferrer');
  }

  @override
  Widget buildView() => const SizedBox.shrink();
  @override
  Future<Object?> extract() async => null;
  @override
  void dispose() {}
}
