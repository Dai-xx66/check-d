import 'dart:convert';

import '../../../core/database/app_database.dart';

/// Local presentation deduplication; never records read/completed status.
class AgentReminderStore {
  AgentReminderStore(this.database);
  final AppDatabase database;
  Future<bool> claimDisplayed(
    String owner,
    String reminderKey,
    bool Function() isCurrentOwner,
  ) => database.transaction(() async {
    if (!isCurrentOwner()) return false;
    final key = 'agent.reminders.displayed.v1:$owner';
    final row = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    final displayed = row == null
        ? <String>[]
        : (jsonDecode(row.value) as List).cast<String>();
    if (displayed.contains(reminderKey) || !isCurrentOwner()) return false;
    displayed.add(reminderKey);
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: key,
            value: jsonEncode(
              displayed.length > 500
                  ? displayed.sublist(displayed.length - 500)
                  : displayed,
            ),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
    return isCurrentOwner();
  });
}
