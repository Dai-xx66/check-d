import 'dart:convert';

import 'package:check_d/features/agent/domain/agent_models.dart';
import 'package:check_d/features/agent/presentation/agent_school_page.dart';
import 'package:check_d/features/agent/presentation/school/agent_school_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _SchoolBrowser implements AgentSchoolBrowser {
  _SchoolBrowser({this.canExtract = true});
  @override
  final bool canExtract;
  int opens = 0;
  int extractions = 0;
  bool disposed = false;
  @override
  String get capabilityNote => canExtract ? '本机主动提取' : '跨域隔离，请粘贴文本';
  @override
  Widget buildView() => const Center(child: Text('本机教务网页'));
  @override
  Future<void> open(Uri url) async => opens++;
  @override
  Future<Object?> extract() async {
    extractions++;
    return jsonEncode({
      'text': '2026-11-23至2026-11-29\n周一\tEnglish\t09:00-10:00',
      'truncated': false,
    });
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  test(
    'school address allows public HTTPS and excludes local or credential URLs',
    () {
      expect(
        validateSchoolUrl('https://jw.example.edu.cn/course?term=2026').host,
        'jw.example.edu.cn',
      );
      for (final value in [
        'http://jw.example.edu.cn',
        'https://user:pass@school.edu.cn',
        'https://127.0.0.1',
        'https://192.168.1.1',
        'https://[::1]',
        'https://school.local',
        'https://school.internal',
        'https://localhost',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'https://school.edu.cn:9443',
      ]) {
        expect(
          () => validateSchoolUrl(value),
          throwsFormatException,
          reason: value,
        );
      }
    },
  );

  test(
    'table extraction handles platform JSON escaping, empty grids and truncation',
    () {
      final response = jsonEncode({
        'text': '周一\t09:00\tEnglish',
        'truncated': true,
      });
      final decoded = decodeSchoolExtraction(jsonEncode(response));
      expect(decoded.text, contains('English'));
      expect(decoded.truncated, isTrue);
      expect(
        () => decodeSchoolExtraction('{"text":""}'),
        throwsFormatException,
      );
      expect(() => decodeSchoolExtraction('not JSON'), throwsFormatException);
      expect(
        decodeSchoolExtraction({
          'text': List.filled(60001, '字').join(),
        }).text.length,
        60000,
      );
    },
  );

  testWidgets(
    'school import stays local until reviewed attachment is explicitly returned on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final browser = _SchoolBrowser();
      AgentAttachment? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<AgentAttachment>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AgentSchoolPage(
                        initialUrl: 'https://jw.example.edu.cn',
                        browserFactory: () => browser,
                      ),
                    ),
                  );
                },
                child: const Text('导入'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('导入'));
      await tester.pumpAndSettle();
      expect(browser.opens, 0);
      expect(browser.extractions, 0);
      await tester.tap(find.text('打开并自行登录'));
      await tester.pumpAndSettle();
      expect(browser.opens, 1);
      expect(browser.extractions, 0);
      expect(result, isNull);
      await tester.tap(find.text('提取当前课表'));
      await tester.pumpAndSettle();
      expect(browser.extractions, 1);
      expect(result, isNull);
      await tester.ensureVisible(find.text('添加到本次对话'));
      await tester.tap(find.text('添加到本次对话'));
      await tester.pumpAndSettle();
      expect(result?.text, contains('English'));
      expect(result?.note, contains('有效起止日期'));
      expect(result?.name, contains('jw.example.edu.cn'));
      expect(browser.disposed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fallback shows honest platform capability and sanitizes pasted HTML before adding',
    (tester) async {
      final browser = _SchoolBrowser(canExtract: false);
      await tester.pumpWidget(
        MaterialApp(home: AgentSchoolPage(browserFactory: () => browser)),
      );
      expect(find.text('提取当前课表'), findsNothing);
      expect(find.text('跨域隔离，请粘贴文本'), findsOneWidget);
      final preview = find.byKey(const ValueKey('school-preview'));
      await tester.ensureVisible(preview);
      await tester.enterText(
        preview,
        '<table><tr><td>English</td><td>09:00</td></tr></table><form><input value="SECRET">ACCOUNT</form><script>evil()</script>',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('整理HTML并预览'));
      await tester.tap(find.text('整理HTML并预览'));
      await tester.pumpAndSettle();
      final text = tester.widget<TextField>(preview).controller!.text;
      expect(text, contains('English'));
      expect(text, isNot(contains('SECRET')));
      expect(text, isNot(contains('ACCOUNT')));
      expect(text, isNot(contains('evil')));
      expect(find.text('添加到本次对话'), findsOneWidget);
      expect(browser.opens, 0);
    },
  );
}
