import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/app_database.dart';
import 'holiday_calendar.dart';

class ChinaHolidayService implements HolidayCalendar {
  ChinaHolidayService(this._database, {http.Client? client})
    : _client = client ?? http.Client();

  final AppDatabase _database;
  final http.Client _client;

  @override
  Future<ChinaDayKind> kindFor(DateTime date) async {
    final year = date.year;
    final key = 'china-holidays:$year';
    var raw = await _read(key);
    raw ??= await _fetchYear(year, key);
    if (raw == null) return ChinaDayKind.unknown;
    final item = raw[_dateKey(date)];
    if (item is! Map<String, dynamic>) return ChinaDayKind.unknown;
    final type = item['type'] as int?;
    return switch (type) {
      0 => ChinaDayKind.workday,
      1 => ChinaDayKind.weekend,
      2 => ChinaDayKind.holiday,
      3 => ChinaDayKind.adjustedWorkday,
      _ => ChinaDayKind.unknown,
    };
  }

  Future<Map<String, dynamic>?> _read(String key) async {
    final record = await (_database.select(
      _database.appSettings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    if (record == null) return null;
    try {
      return jsonDecode(record.value) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchYear(int year, String key) async {
    try {
      final response = await _client
          .get(Uri.parse('https://timor.tech/api/holiday/year/$year/'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['code'] != 0 || body['holiday'] is! Map<String, dynamic>) {
        return null;
      }
      final data = body['holiday'] as Map<String, dynamic>;
      await _database
          .into(_database.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: key,
              value: jsonEncode(data),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      return data;
    } on Object {
      return null;
    }
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
