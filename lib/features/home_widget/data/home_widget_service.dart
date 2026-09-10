import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../mini_window/data/mini_window_repository.dart';
import '../domain/home_widget_snapshot.dart';

class HomeWidgetService {
  HomeWidgetService({required MiniWindowRepository repository})
    : _repository = repository;

  static const _channel = MethodChannel('check_d/home_widget');
  final MiniWindowRepository _repository;

  Future<HomeWidgetSnapshot?> refresh({DateTime? now}) async {
    if (kIsWeb) return null;
    try {
      final snapshot = HomeWidgetSnapshot.fromMiniWindow(
        await _repository.load(now: now),
      );
      await _channel.invokeMethod<void>('saveSnapshot', {
        'json': jsonEncode(snapshot.toJson()),
      });
      return snapshot;
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      debugPrint('[HomeWidget] refresh failed: ${error.code} ${error.message}');
      return null;
    } on Object catch (error) {
      debugPrint('[HomeWidget] refresh failed: $error');
      return null;
    }
  }
}
