import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../contracts/theme_preference_repository.dart';

class SqliteThemePreferenceRepository implements ThemePreferenceRepository {
  SqliteThemePreferenceRepository(this._database);

  final Database _database;

  @override
  Future<String> getThemeMode() async {
    final rows = await _database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['theme_mode'],
      limit: 1,
    );
    final value =
        rows.isEmpty ? '' : (rows.single['value'] as String? ?? '');
    if (value == 'light' || value == 'dark' || value == 'system') {
      return value;
    }
    // Migrazione dalla precedente preferenza booleana.
    final legacy = await _database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['dark_mode'],
      limit: 1,
    );
    if (legacy.isNotEmpty) {
      return legacy.single['value'] == 'true' ? 'dark' : 'light';
    }
    return 'system';
  }

  @override
  Future<void> saveThemeMode(String mode) async {
    await _database.insert(
      'app_settings',
      {'key': 'theme_mode', 'value': mode},
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

  @override
  Future<bool> getDebugMode() async {
    final rows = await _database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['debug_mode'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['value'] == 'true';
  }

  @override
  Future<void> saveDebugMode(bool enabled) async {
    await _database.insert(
      'app_settings',
      {'key': 'debug_mode', 'value': enabled.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<int> getAutoRefreshMinutes() async {
    final rows = await _database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['auto_refresh_minutes'],
      limit: 1,
    );
    return rows.isEmpty
        ? 5
        : int.tryParse('${rows.single['value']}') ?? 5;
  }

  @override
  Future<void> saveAutoRefreshMinutes(int minutes) async {
    await _database.insert(
      'app_settings',
      {'key': 'auto_refresh_minutes', 'value': minutes.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Map<String, double>> getGradeTargets() async {
    final rows = await _database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['grade_targets'],
      limit: 1,
    );
    if (rows.isEmpty) return const {};
    try {
      final decoded = jsonDecode(rows.single['value'] as String);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): (entry.value as num).toDouble(),
      };
    } on Object {
      return const {};
    }
  }

  @override
  Future<void> saveGradeTargets(Map<String, double> targets) async {
    await _database.insert(
      'app_settings',
      {'key': 'grade_targets', 'value': jsonEncode(targets)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<double?> getDefaultGradeTarget() async {
    final rows = await _database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['grade_target_default'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return double.tryParse('${rows.single['value']}');
  }

  @override
  Future<void> saveDefaultGradeTarget(double? target) async {
    await _database.insert(
      'app_settings',
      {
        'key': 'grade_target_default',
        'value': target?.toString() ?? '',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> getShowAttendanceRate() async {
    final rows = await _database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['show_attendance_rate'],
      limit: 1,
    );
    return rows.isEmpty || rows.single['value'] == 'true';
  }

  @override
  Future<void> saveShowAttendanceRate(bool enabled) async {
    await _database.insert(
      'app_settings',
      {'key': 'show_attendance_rate', 'value': enabled.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> getDebugUnlocked() async {
    final rows = await _database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['debug_unlocked'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['value'] == 'true';
  }

  @override
  Future<void> saveDebugUnlocked(bool unlocked) async {
    await _database.insert(
      'app_settings',
      {'key': 'debug_unlocked', 'value': unlocked.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> getHasSeenWelcome() async {
    final rows = await _database.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['welcome_seen'],
      limit: 1,
    );
    return rows.isNotEmpty && rows.single['value'] == 'true';
  }

  @override
  Future<void> saveHasSeenWelcome(bool seen) async {
    await _database.insert(
      'app_settings',
      {'key': 'welcome_seen', 'value': seen.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
