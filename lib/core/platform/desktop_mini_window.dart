import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

bool get supportsDesktopMiniWindow =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows);

class DesktopWindowArguments {
  const DesktopWindowArguments._({this.ownerId});

  final String? ownerId;
  bool get isMiniWindow => ownerId != null;

  static DesktopWindowArguments parse(String raw) {
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      if (value['type'] == 'mini-window' && value['ownerId'] is String) {
        return DesktopWindowArguments._(ownerId: value['ownerId'] as String);
      }
    } on Object {
      // Main windows and older launchers have no structured arguments.
    }
    return const DesktopWindowArguments._();
  }
}

/// A paired channel is an invalidation signal only. Drift remains the source
/// of truth for courses and timers in both Flutter engines.
final miniWindowChannel = WindowMethodChannel(
  'check_d/mini_window',
  mode: ChannelMode.bidirectional,
);

class DesktopMiniWindowLauncher {
  static Future<void> open({required String ownerId}) async {
    if (!supportsDesktopMiniWindow) return;
    final windows = await WindowController.getAll();
    for (final candidate in windows) {
      final arguments = DesktopWindowArguments.parse(candidate.arguments);
      if (arguments.isMiniWindow && arguments.ownerId == ownerId) {
        await candidate.show();
        try {
          await candidate.invokeMethod<void>('focusMini');
        } on Object {
          // Showing an already active child remains a valid result.
        }
        return;
      }
    }
    final controller = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: jsonEncode({'type': 'mini-window', 'ownerId': ownerId}),
      ),
    );
    await controller.show();
  }
}

Future<DesktopWindowArguments> currentDesktopWindowArguments() async {
  if (!supportsDesktopMiniWindow) return const DesktopWindowArguments._();
  try {
    final controller = await WindowController.fromCurrentEngine();
    return DesktopWindowArguments.parse(controller.arguments);
  } on Object {
    return const DesktopWindowArguments._();
  }
}

class DesktopMainWindowSyncHost extends StatefulWidget {
  const DesktopMainWindowSyncHost({
    required this.child,
    required this.onRefresh,
    super.key,
  });

  final Widget child;
  final VoidCallback onRefresh;

  @override
  State<DesktopMainWindowSyncHost> createState() =>
      _DesktopMainWindowSyncHostState();
}

class _DesktopMainWindowSyncHostState extends State<DesktopMainWindowSyncHost>
    with WindowListener {
  var _floatingWidgetOpen = false;

  @override
  void initState() {
    super.initState();
    if (supportsDesktopMiniWindow) _register();
  }

  Future<void> _register() async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    await miniWindowChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'refreshMain':
          widget.onRefresh();
          return true;
        case 'openMain':
          await windowManager.show();
          await windowManager.focus();
          return true;
        case 'floatingWidgetOpened':
          _floatingWidgetOpen = true;
          await windowManager.setPreventClose(true);
          return true;
        case 'floatingWidgetClosed':
          _floatingWidgetOpen = false;
          await windowManager.setPreventClose(false);
          return true;
      }
      return null;
    });
  }

  @override
  void onWindowClose() {
    if (_floatingWidgetOpen) {
      windowManager.hide();
    }
  }

  @override
  void dispose() {
    if (supportsDesktopMiniWindow) {
      windowManager.removeListener(this);
      windowManager.setPreventClose(false);
      miniWindowChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
