import 'dart:async';

/// Marks database writes that originate from a cloud reconciliation.
///
/// Repositories normally enqueue every local business change. A download apply
/// must never re-enter that path and create an upload loop.
class SyncApplyScope {
  int _depth = 0;

  bool get isApplying => _depth > 0;

  Future<T> run<T>(Future<T> Function() action) async {
    _depth++;
    try {
      return await action();
    } finally {
      _depth--;
    }
  }
}
