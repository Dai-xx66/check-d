import 'dart:js_interop';

@JS('checkdPdfReady')
external JSPromise<JSAny?>? get _pdfReady;

Future<void> ensureAgentPdfRuntime() async {
  final promise = _pdfReady;
  if (promise == null) {
    throw const FormatException('网页PDF组件没有加载，请刷新页面或改发课表截图。');
  }
  try {
    await promise.toDart.timeout(const Duration(seconds: 20));
  } catch (_) {
    throw const FormatException('网页PDF组件加载失败，请刷新页面或让管理员补全本地PDF资源。也可直接发送课表截图。');
  }
}
