import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_queue_service.dart';

class ReminderDefaults {
  const ReminderDefaults({
    this.advanceEnabled = false,
    this.advanceMinutes = 10,
    this.atTimeEnabled = false,
  });

  final bool advanceEnabled;
  final int advanceMinutes;
  final bool atTimeEnabled;

  ReminderDefaults copyWith({
    bool? advanceEnabled,
    int? advanceMinutes,
    bool? atTimeEnabled,
  }) => ReminderDefaults(
    advanceEnabled: advanceEnabled ?? this.advanceEnabled,
    advanceMinutes: advanceMinutes ?? this.advanceMinutes,
    atTimeEnabled: atTimeEnabled ?? this.atTimeEnabled,
  );
}

class ReminderDefaultsRepository {
  ReminderDefaultsRepository({
    required this.database,
    required this.userId,
    required this.syncQueue,
  });

  final AppDatabase database;
  final String userId;
  final SyncQueueService syncQueue;

  String get _key => 'reminder-defaults:$userId';

  Future<ReminderDefaults> load() async {
    final record = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(_key))).getSingleOrNull();
    if (record == null) return const ReminderDefaults();
    try {
      final value = jsonDecode(record.value) as Map<String, Object?>;
      final minutes = value['advanceMinutes'];
      return ReminderDefaults(
        advanceEnabled: value['advanceEnabled'] == true,
        advanceMinutes: minutes is int && minutes >= 0 ? minutes : 10,
        atTimeEnabled: value['atTimeEnabled'] == true,
      );
    } on Object {
      return const ReminderDefaults();
    }
  }

  Future<void> save(ReminderDefaults value) async {
    if (value.advanceMinutes < 0) {
      throw ArgumentError.value(value.advanceMinutes, 'advanceMinutes');
    }
    final now = DateTime.now().toUtc();
    final encoded = {
      'advanceEnabled': value.advanceEnabled,
      'advanceMinutes': value.advanceMinutes,
      'atTimeEnabled': value.atTimeEnabled,
    };
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _key,
            value: jsonEncode(encoded),
            updatedAt: now,
          ),
        );
    await syncQueue.enqueue(
      entityType: 'user_preferences',
      entityId: userId,
      operation: SyncOperationType.upsert,
      payload: {
        'id': userId,
        'preference_key': 'reminder_defaults',
        'value': encoded,
        'updated_at': now.toIso8601String(),
      },
      userId: userId,
    );
  }
}
