import 'package:sqflite/sqflite.dart';

import '../contracts/theme_preference_repository.dart';

class SqliteThemePreferenceRepository implements ThemePreferenceRepository {
  SqliteThemePreferenceRepository(this._database);

  final Database _database;

  @override
  Future<bool> getDarkMode() async {
    final rows = await _database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['dark_mode'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['value'] == 'true';
  }

  @override
  Future<void> saveDarkMode(bool enabled) async {
    await _database.insert(
      'app_settings',
      {'key': 'dark_mode', 'value': enabled.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<String> getWeekendMode() async {
    final rows = await _database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['agenda_weekend_mode'],
      limit: 1,
    );
    return rows.isEmpty ? 'all' : rows.single['value']! as String;
  }

  @override
  Future<void> saveWeekendMode(String mode) async {
    await _database.insert(
      'app_settings',
      {'key': 'agenda_weekend_mode', 'value': mode},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
