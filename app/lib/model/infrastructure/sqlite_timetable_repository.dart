import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../contracts/timetable_repository.dart';
import '../contracts/school_data_repository.dart';
import '../entities/classviva_record.dart';
import '../entities/lesson.dart';
import '../entities/subject.dart';
import '../entities/period_time.dart';
import '../entities/classroom_resource.dart';
import '../entities/study_task.dart';

class SqliteTimetableRepository implements TimetableRepository {
  SqliteTimetableRepository(this._database);
  final Database _database;

  @override
  Future<List<Subject>> getSubjects() async => (await _database.query(
        'subjects',
        orderBy: 'name',
      ))
          .map(Subject.fromMap)
          .toList();

  @override
  Future<List<Lesson>> getLessons() async => (await _database.query(
        'lessons',
        orderBy: 'weekday, start_minute',
      ))
          .map(Lesson.fromMap)
          .toList();

  @override
  Future<void> saveSubject(Subject subject) async =>
      _database.transaction((txn) async {
        final values = subject.toMap();
        values.remove('id');
        final updated = await txn.update('subjects', values,
            where: 'id = ?', whereArgs: [subject.id]);
        if (updated == 0) {
          await txn.insert('subjects', subject.toMap());
        }
      });

  @override
  Future<void> saveLesson(Lesson lesson) async => _database.insert(
        'lessons',
        lesson.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<void> deleteLesson(String id) async =>
      _database.transaction((txn) async {
        await txn.delete('lessons', where: 'id = ?', whereArgs: [id]);
      });

  @override
  Future<void> deleteSubject(String id) async =>
      _database.transaction((txn) async {
        await txn.delete('lessons', where: 'subject_id = ?', whereArgs: [id]);
        await txn.delete('subjects', where: 'id = ?', whereArgs: [id]);
      });

  @override
  Future<void> replaceAll({
    required List<Subject> subjects,
    required List<Lesson> lessons,
  }) async =>
      _database.transaction((txn) async {
        await txn.delete('lessons');
        await txn.delete('subjects');
        for (final subject in subjects) {
          await txn.insert('subjects', subject.toMap());
        }
        for (final lesson in lessons) {
          await txn.insert('lessons', lesson.toMap());
        }
      });

  @override
  Future<List<PeriodTime>> getPeriodTimes() async => (await _database.query(
        'period_times',
        orderBy: 'weekday, number',
      ))
          .map(PeriodTime.fromMap)
          .toList();

  @override
  Future<void> savePeriodTimes(List<PeriodTime> periods) async =>
      _database.transaction((txn) async {
        await txn.delete('period_times');
        for (final period in periods) {
          await txn.insert(
            'period_times',
            period.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

  @override
  Future<List<ClassroomResource>> getResources() async =>
      (await _database.query('classroom_resources', orderBy: 'category, name'))
          .map(ClassroomResource.fromMap)
          .toList();

  @override
  Future<void> saveResource(ClassroomResource resource) async =>
      _database.transaction((txn) async {
        final existing = await txn.query('classroom_resources',
            columns: ['name', 'category'],
            where: 'id = ?',
            whereArgs: [resource.id],
            limit: 1);
        final oldName =
            existing.isEmpty ? null : existing.first['name']! as String;
        final oldCategory = existing.isEmpty
            ? resource.category.name
            : existing.first['category']! as String;
        await txn.insert('classroom_resources', resource.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
        if (oldName == null ||
            oldName == resource.name ||
            oldCategory != resource.category.name) {
          return;
        }
        final field = resource.category == ResourceCategory.teacher
            ? 'teachers_json'
            : 'rooms_json';
        for (final table in ['subjects', 'lessons']) {
          final rows = await txn.query(table, columns: ['id', field]);
          for (final row in rows) {
            final values = (jsonDecode(row[field]! as String) as List)
                .whereType<String>()
                .toList();
            if (!values.contains(oldName)) continue;
            final renamed = values
                .map((value) => value == oldName ? resource.name : value)
                .toSet()
                .toList();
            await txn.update(table, {field: jsonEncode(renamed)},
                where: 'id = ?', whereArgs: [row['id']]);
          }
        }
      });

  @override
  Future<void> deleteResource(String id) async =>
      _database.transaction((txn) async {
        final rows = await txn.query('classroom_resources',
            columns: ['name', 'category'],
            where: 'id = ?',
            whereArgs: [id],
            limit: 1);
        if (rows.isEmpty) return;
        final name = rows.first['name']! as String;
        final category = rows.first['category']! as String;
        final field = category == ResourceCategory.teacher.name
            ? 'teachers_json'
            : 'rooms_json';
        for (final table in ['subjects', 'lessons']) {
          final records = await txn.query(table, columns: ['id', field]);
          for (final record in records) {
            final names = (jsonDecode(record[field]! as String) as List)
                .whereType<String>()
                .where((value) => value != name)
                .toList();
            await txn.update(table, {field: jsonEncode(names)},
                where: 'id = ?', whereArgs: [record['id']]);
          }
        }
        await txn
            .delete('classroom_resources', where: 'id = ?', whereArgs: [id]);
      });

  @override
  Future<void> clearAll() => _database.transaction((txn) async {
        for (final table in const [
          'lessons',
          'subjects',
          'period_times',
          'classroom_resources',
          'classviva_cache',
          'study_tasks',
          'event_flags',
        ]) {
          await txn.delete(table);
        }
      });

  @override
  Future<Map<String, Object?>> exportConfig() async => {
        'version': 1,
        'subjects': await _database.query('subjects'),
        'lessons': await _database.query('lessons'),
        'period_times': await _database.query('period_times'),
        'classroom_resources': await _database.query('classroom_resources'),
        'app_settings': {
          for (final row in await _database.query('app_settings'))
            row['key']! as String: row['value'],
        },
      };

  @override
  Future<void> importConfig(Map<String, Object?> data) =>
      _database.transaction((txn) async {
        List<Map<String, Object?>> rowsOf(String key) => [
              for (final row in (data[key] as List?) ?? const [])
                (row as Map).cast<String, Object?>(),
            ];
        for (final table in const [
          'lessons',
          'subjects',
          'period_times',
          'classroom_resources',
        ]) {
          await txn.delete(table);
          for (final row in rowsOf(table)) {
            await txn.insert(table, row);
          }
        }
        final settings =
            (data['app_settings'] as Map?)?.cast<String, Object?>() ?? {};
        for (final entry in settings.entries) {
          await txn.insert(
            'app_settings',
            {'key': entry.key, 'value': '${entry.value}'},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
}

Future<Database> openTimetableDatabase(String path) => openDatabase(
      path,
      version: 10,
      onCreate: (database, version) async {
        await database.execute(
          "CREATE TABLE subjects(id TEXT PRIMARY KEY, name TEXT NOT NULL, color_value INTEGER NOT NULL, classviva_id TEXT NOT NULL DEFAULT '', teachers_json TEXT NOT NULL DEFAULT '[]', rooms_json TEXT NOT NULL DEFAULT '[]')",
        );
        await database.execute(
          "CREATE TABLE lessons(id TEXT PRIMARY KEY, subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE, weekday INTEGER NOT NULL CHECK(weekday BETWEEN 1 AND 7), start_minute INTEGER NOT NULL, end_minute INTEGER NOT NULL, start_period INTEGER, end_period INTEGER, teachers_json TEXT NOT NULL DEFAULT '[]', rooms_json TEXT NOT NULL DEFAULT '[]', CHECK(start_minute >= 0 AND end_minute <= 1440 AND start_minute < end_minute))",
        );
        await database.execute(
          'CREATE TABLE period_times(weekday INTEGER NOT NULL DEFAULT 0 CHECK(weekday BETWEEN 0 AND 7), number INTEGER NOT NULL CHECK(number BETWEEN 1 AND 20), start_minute INTEGER NOT NULL, end_minute INTEGER NOT NULL CHECK(start_minute >= 0 AND end_minute <= 1440 AND start_minute < end_minute), PRIMARY KEY(weekday, number))',
        );
        await database.execute(
            'CREATE TABLE classroom_resources(id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL CHECK(category IN (\'room\', \'teacher\')), type TEXT NOT NULL)');
        await database.execute(
            'CREATE TABLE classviva_cache(section TEXT PRIMARY KEY, records_json TEXT NOT NULL, fetched_at TEXT NOT NULL)');
        await database.execute(
            'CREATE TABLE study_tasks(id TEXT PRIMARY KEY, title TEXT NOT NULL, due_date TEXT NOT NULL, subject TEXT NOT NULL DEFAULT \'\', is_done INTEGER NOT NULL DEFAULT 0)');
        await database.execute(
            'CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await database.execute(
            'CREATE TABLE event_flags(record_id TEXT PRIMARY KEY, is_test INTEGER NOT NULL)');
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database
              .execute('ALTER TABLE lessons ADD COLUMN start_period INTEGER');
          await database
              .execute('ALTER TABLE lessons ADD COLUMN end_period INTEGER');
        }
        if (oldVersion < 3) {
          await database.execute(
              "ALTER TABLE subjects ADD COLUMN teachers_json TEXT NOT NULL DEFAULT '[]'");
          await database.execute(
              "ALTER TABLE subjects ADD COLUMN rooms_json TEXT NOT NULL DEFAULT '[]'");
          await database.execute(
              "ALTER TABLE lessons ADD COLUMN teachers_json TEXT NOT NULL DEFAULT '[]'");
          await database.execute(
              "ALTER TABLE lessons ADD COLUMN rooms_json TEXT NOT NULL DEFAULT '[]'");
        }
        if (oldVersion < 4) {
          await database
              .execute('ALTER TABLE period_times RENAME TO old_period_times');
          await database.execute(
              'CREATE TABLE period_times(weekday INTEGER NOT NULL DEFAULT 0 CHECK(weekday BETWEEN 0 AND 7), number INTEGER NOT NULL CHECK(number BETWEEN 1 AND 20), start_minute INTEGER NOT NULL, end_minute INTEGER NOT NULL CHECK(start_minute >= 0 AND end_minute <= 1440 AND start_minute < end_minute), PRIMARY KEY(weekday, number))');
          await database.execute(
              'INSERT INTO period_times(weekday, number, start_minute, end_minute) SELECT 0, number, start_minute, end_minute FROM old_period_times');
          await database.execute('DROP TABLE old_period_times');
        }
        if (oldVersion < 5) {
          await database.execute(
              'CREATE TABLE classroom_resources(id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL CHECK(category IN (\'room\', \'teacher\')), type TEXT NOT NULL)');
        }
        if (oldVersion < 6) {
          await database.execute(
              'CREATE TABLE classviva_cache(section TEXT PRIMARY KEY, records_json TEXT NOT NULL, fetched_at TEXT NOT NULL)');
          await database.execute(
              'CREATE TABLE study_tasks(id TEXT PRIMARY KEY, title TEXT NOT NULL, due_date TEXT NOT NULL, subject TEXT NOT NULL DEFAULT \'\', is_done INTEGER NOT NULL DEFAULT 0)');
        }
        if (oldVersion < 7) {
          await database.execute(
              'CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        }
        if (oldVersion < 10) {
          // Difensivo: aggiunge la colonna solo se manca, così anche un
          // database rimasto alla versione 8 senza la colonna si ripara.
          final columns =
              await database.rawQuery('PRAGMA table_info(subjects)');
          if (columns.every((column) => column['name'] != 'classviva_id')) {
            await database.execute(
                "ALTER TABLE subjects ADD COLUMN classviva_id TEXT NOT NULL DEFAULT ''");
          }
        }
        if (oldVersion < 10) {
          await database.execute(
              'CREATE TABLE IF NOT EXISTS event_flags(record_id TEXT PRIMARY KEY, is_test INTEGER NOT NULL)');
        }
      },
      onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
    );

class SqliteSchoolDataRepository implements SchoolDataRepository {
  SqliteSchoolDataRepository(this._database);
  final Database _database;

  @override
  Future<List<ClassVivaRecord>> getRecords(String section) async {
    final rows = await _database.query(
      'classviva_cache',
      columns: ['records_json'],
      where: 'section = ?',
      whereArgs: [section],
      limit: 1,
    );
    if (rows.isEmpty) return const [];
    final json = jsonDecode(rows.single['records_json']! as String) as List;
    return json
        .whereType<Map>()
        .map((row) => ClassVivaRecord.fromMap(
              row.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList();
  }

  @override
  Future<DateTime?> getLastUpdated() async {
    final rows = await _database.rawQuery(
      'SELECT MAX(fetched_at) AS fetched_at FROM classviva_cache',
    );
    return DateTime.tryParse(rows.single['fetched_at']?.toString() ?? '');
  }

  @override
  Future<void> saveRecords(
    String section,
    List<ClassVivaRecord> records,
  ) async {
    await _database.insert(
      'classviva_cache',
      {
        'section': section,
        'records_json':
            jsonEncode(records.map((record) => record.toMap()).toList()),
        'fetched_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<StudyTask>> getTasks() async => (await _database.query(
        'study_tasks',
        orderBy: 'is_done, due_date',
      ))
          .map(StudyTask.fromMap)
          .toList();

  @override
  Future<void> saveTask(StudyTask task) async => _database.insert(
        'study_tasks',
        task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<void> deleteTask(String id) async => _database.delete(
        'study_tasks',
        where: 'id = ?',
        whereArgs: [id],
      );

  @override
  Future<Map<String, bool>> getTestFlags() async => {
        for (final row in await _database.query('event_flags'))
          row['record_id']! as String: row['is_test'] == 1,
      };

  @override
  Future<void> setTestFlag(String recordId, bool value) async =>
      _database.insert(
        'event_flags',
        {'record_id': recordId, 'is_test': value ? 1 : 0},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
}
