import 'package:flutter/widgets.dart';

import 'agent_school_browser_contract.dart';

AgentSchoolBrowser createSchoolBrowser() => FallbackSchoolBrowser();

class FallbackSchoolBrowser implements AgentSchoolBrowser {
  @override
  bool get canExtract => false;
  @override
  String get capabilityNote => '当前平台请在浏览器自行打开教务网站，复制课表文本到下方，或返回对话添加截图/HTML文件。';
  @override
  Future<void> open(Uri url) async {
    throw const FormatException('当前平台不支持内嵌教务浏览器，请自行打开网站后粘贴课表，或导入截图/文件。');
  }

  @override
  Widget buildView() => const SizedBox.shrink();
  @override
  Future<Object?> extract() async => null;
  @override
  void dispose() {}
}
