import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../contracts/timetable_repository.dart';
import '../entities/lesson.dart';
import '../entities/subject.dart';
import '../entities/period_time.dart';
import '../entities/classroom_resource.dart';

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
  Future<void> saveSubject(Subject subject) async => _database.insert(
        'subjects',
        subject.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

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
}

Future<Database> openTimetableDatabase(String path) => openDatabase(
      path,
      version: 5,
      onCreate: (database, version) async {
        await database.execute(
          "CREATE TABLE subjects(id TEXT PRIMARY KEY, name TEXT NOT NULL, color_value INTEGER NOT NULL, teachers_json TEXT NOT NULL DEFAULT '[]', rooms_json TEXT NOT NULL DEFAULT '[]')",
        );
        await database.execute(
          "CREATE TABLE lessons(id TEXT PRIMARY KEY, subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE, weekday INTEGER NOT NULL CHECK(weekday BETWEEN 1 AND 7), start_minute INTEGER NOT NULL, end_minute INTEGER NOT NULL, start_period INTEGER, end_period INTEGER, teachers_json TEXT NOT NULL DEFAULT '[]', rooms_json TEXT NOT NULL DEFAULT '[]', CHECK(start_minute >= 0 AND end_minute <= 1440 AND start_minute < end_minute))",
        );
        await database.execute(
          'CREATE TABLE period_times(weekday INTEGER NOT NULL DEFAULT 0 CHECK(weekday BETWEEN 0 AND 7), number INTEGER NOT NULL CHECK(number BETWEEN 1 AND 20), start_minute INTEGER NOT NULL, end_minute INTEGER NOT NULL CHECK(start_minute >= 0 AND end_minute <= 1440 AND start_minute < end_minute), PRIMARY KEY(weekday, number))',
        );
        await database.execute(
            'CREATE TABLE classroom_resources(id TEXT PRIMARY KEY, name TEXT NOT NULL, category TEXT NOT NULL CHECK(category IN (\'room\', \'teacher\')), type TEXT NOT NULL)');
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
      },
      onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
    );
