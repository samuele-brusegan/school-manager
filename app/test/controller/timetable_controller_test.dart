import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/controller/timetable_controller.dart';
import 'package:school_manager/model/contracts/timetable_repository.dart';
import 'package:school_manager/model/entities/classroom_resource.dart';
import 'package:school_manager/model/entities/lesson.dart';
import 'package:school_manager/model/entities/period_time.dart';
import 'package:school_manager/model/entities/subject.dart';

void main() {
  test('adds, edits, and removes a weekly lesson', () async {
    final repository = _MemoryRepository();
    final controller = TimetableController(repository);
    await controller.load();
    await controller.addLesson(
        subjectName: 'Matematica',
        weekday: 1,
        startMinute: 480,
        endMinute: 530);
    expect(controller.timetable!.lessons, hasLength(1));
    final id = controller.timetable!.lessons.single.id;
    await controller.updateLesson(
        id: id,
        subjectName: 'Fisica',
        weekday: 2,
        startMinute: 540,
        endMinute: 590);
    expect(controller.timetable!.lessons.single.weekday, 2);
    expect(
      controller.timetable!.subjects.map((subject) => subject.name),
      contains('Fisica'),
    );
    await controller.deleteLesson(id);
    expect(controller.timetable!.lessons, isEmpty);
  });

  test('accepts overlapping lessons shown on parallel lanes', () async {
    final repository = _MemoryRepository();
    final controller = TimetableController(repository);
    await controller.load();
    await controller.addLesson(
        subjectName: 'Matematica',
        weekday: 1,
        startMinute: 480,
        endMinute: 540);
    await controller.addLesson(
        subjectName: 'Fisica', weekday: 1, startMinute: 530, endMinute: 590);
    expect(repository.lessons, hasLength(2));
  });
}

class _MemoryRepository implements TimetableRepository {
  List<Subject> subjects = [];
  List<Lesson> lessons = [];
  List<PeriodTime> periods = [];
  @override
  Future<void> deleteLesson(String id) async {
    lessons.removeWhere((lesson) => lesson.id == id);
    final used = lessons.map((lesson) => lesson.subjectId).toSet();
    subjects.removeWhere((subject) => !used.contains(subject.id));
  }

  @override
  Future<void> deleteSubject(String id) async {
    subjects.removeWhere((subject) => subject.id == id);
    lessons.removeWhere((lesson) => lesson.subjectId == id);
  }

  @override
  Future<List<Lesson>> getLessons() async => List.of(lessons);
  @override
  Future<List<PeriodTime>> getPeriodTimes() async => List.of(periods);
  @override
  Future<List<Subject>> getSubjects() async => List.of(subjects);
  @override
  Future<void> replaceAll(
      {required List<Subject> subjects, required List<Lesson> lessons}) async {
    this.subjects = List.of(subjects);
    this.lessons = List.of(lessons);
  }

  @override
  Future<void> saveLesson(Lesson lesson) async {
    lessons.removeWhere((existing) => existing.id == lesson.id);
    lessons.add(lesson);
  }

  @override
  Future<void> savePeriodTimes(List<PeriodTime> periods) async =>
      this.periods = List.of(periods);
  @override
  Future<void> saveSubject(Subject subject) async {
    subjects.removeWhere((existing) => existing.id == subject.id);
    subjects.add(subject);
  }

  List<ClassroomResource> resources = [];
  @override
  Future<List<ClassroomResource>> getResources() async => List.of(resources);
  @override
  Future<void> saveResource(ClassroomResource resource) async {
    resources.removeWhere((existing) => existing.id == resource.id);
    resources.add(resource);
  }

  @override
  Future<void> deleteResource(String id) async {
    resources.removeWhere((resource) => resource.id == id);
  }

  @override
  Future<void> clearAll() async {
    subjects = [];
    lessons = [];
    periods = [];
    resources = [];
  }

  @override
  Future<Map<String, Object?>> exportConfig() async => {};

  @override
  Future<void> importConfig(Map<String, Object?> data) async {}
}
