import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_windows/webview_windows.dart' as windows;

import 'agent_school_browser_contract.dart';
import 'agent_school_browser_fallback.dart';

AgentSchoolBrowser createSchoolBrowser() => switch (defaultTargetPlatform) {
  TargetPlatform.windows => _WindowsSchoolBrowser(),
  TargetPlatform.android || TargetPlatform.iOS => _MobileSchoolBrowser(),
  _ => FallbackSchoolBrowser(),
};

class _MobileSchoolBrowser implements AgentSchoolBrowser {
  mobile.WebViewController? _controller;
  bool _disposed = false;
  @override
  bool get canExtract => true;
  @override
  String get capabilityNote =>
      '在下方教务网页自行登录并打开课表，再点击提取。仅提取可见表格；图片、Canvas和跨域框架请改发截图。';
  @override
  Future<void> open(Uri url) async {
    validateSchoolUrl(url.toString());
    if (_disposed) return;
    final controller = _controller ??= mobile.WebViewController();
    await controller.setJavaScriptMode(mobile.JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      mobile.NavigationDelegate(
        onNavigationRequest: (request) {
          if (!request.isMainFrame) return mobile.NavigationDecision.navigate;
          try {
            validateSchoolUrl(request.url);
            return mobile.NavigationDecision.navigate;
          } catch (_) {
            return mobile.NavigationDecision.prevent;
          }
        },
      ),
    );
    if (!_disposed) await controller.loadRequest(url);
  }

  @override
  Widget buildView() => _controller == null
      ? const SizedBox.shrink()
      : mobile.WebViewWidget(controller: _controller!);
  @override
  Future<Object?> extract() async {
    final controller = _controller;
    if (controller == null || _disposed) {
      throw const FormatException('请先打开课表网页。');
    }
    validateSchoolUrl(await controller.currentUrl() ?? '');
    return controller.runJavaScriptReturningResult(agentSchoolExtractionScript);
  }

  @override
  void dispose() {
    _disposed = true;
    final controller = _controller;
    if (controller != null) {
      unawaited(controller.loadHtmlString('').catchError((_) {}));
    }
  }
}

class _WindowsSchoolBrowser implements AgentSchoolBrowser {
  windows.WebviewController? _controller;
  StreamSubscription<String>? _navigation;
  bool _disposed = false;
  String? _currentUrl;
  @override
  bool get canExtract => true;
  @override
  String get capabilityNote =>
      'Windows需要WebView2运行库。请在内嵌网页自行登录并打开课表，再点击提取；若学校要求弹窗或不显示表格，请改用导出文件/截图。';
  @override
  Future<void> open(Uri url) async {
    validateSchoolUrl(url.toString());
    if (_disposed) return;
    if (_controller == null) {
      if (await windows.WebviewController.getWebViewVersion() == null) {
        throw const FormatException(
          '未检测到WebView2运行库。请在浏览器打开教务网站，复制课表到下方或导出文件。',
        );
      }
      if (_disposed) return;
      final controller = windows.WebviewController();
      _controller = controller;
      await controller.initialize();
      if (_disposed) return;
      await controller.setPopupWindowPolicy(
        windows.WebviewPopupWindowPolicy.deny,
      );
      _navigation = controller.url.listen((value) {
        _currentUrl = value;
        if (value == 'about:blank') return;
        try {
          validateSchoolUrl(value);
        } catch (_) {
          // This plugin exposes URL-change events rather than a pre-navigation
          // delegate. Stop unsafe redirects; extraction also rechecks location.
          unawaited(
            controller
                .stop()
                .then((_) => controller.loadUrl('about:blank'))
                .catchError((_) {}),
          );
        }
      });
    }
    if (!_disposed) {
      _currentUrl = url.toString();
      await _controller!.loadUrl(url.toString());
    }
  }

  @override
  Widget buildView() => _controller?.value.isInitialized != true
      ? const SizedBox.shrink()
      : windows.Webview(
          _controller!,
          permissionRequested: (_, _, _) =>
              windows.WebviewPermissionDecision.deny,
        );
  @override
  Future<Object?> extract() async {
    final controller = _controller;
    if (controller?.value.isInitialized != true || _disposed) {
      throw const FormatException('请先打开课表网页。');
    }
    validateSchoolUrl(_currentUrl ?? '');
    return controller!.executeScript(agentSchoolExtractionScript);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_navigation?.cancel());
    final controller = _controller;
    if (controller != null) unawaited(controller.dispose().catchError((_) {}));
  }
}
