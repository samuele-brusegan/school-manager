import 'package:flutter/foundation.dart';

import '../model/contracts/timetable_repository.dart';
import '../model/entities/lesson.dart';
import '../model/entities/subject.dart';
import '../model/entities/timetable.dart';
import '../model/entities/period_time.dart';
import '../model/entities/classroom_resource.dart';

class TimetableController extends ChangeNotifier {
  TimetableController(this._repository);
  final TimetableRepository _repository;
  Timetable? timetable;
  List<PeriodTime> periodTimes = [];
  List<ClassroomResource> resources = [];
  bool isLoading = false;
  String? error;

  List<PeriodTime> periodsForWeekday(int weekday) {
    final specific = periodTimes
        .where((period) => period.weekday == weekday)
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    if (specific.isNotEmpty) return specific;
    return periodTimes.where((period) => period.weekday == 0).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
  }

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final subjects = await _repository.getSubjects();
      final lessons = await _repository.getLessons();
      timetable = Timetable(subjects: subjects, lessons: lessons);
      periodTimes = await _repository.getPeriodTimes();
      resources = await _repository.getResources();
      await _ensureCatalogValues(subjects, lessons);
      resources = await _repository.getResources();
    } catch (_) {
      error = 'Non è stato possibile caricare l’orario.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addLesson({
    required String subjectName,
    required int weekday,
    required int startMinute,
    required int endMinute,
    int? startPeriod,
    int? endPeriod,
    String? subjectId,
    List<String> teachers = const [],
    List<String> rooms = const [],
  }) async {
    final name = subjectName.trim();
    final current = timetable ?? Timetable(subjects: [], lessons: []);
    Subject? subject;
    for (final item in current.subjects) {
      if (subjectId != null && item.id == subjectId) {
        subject = item;
        break;
      }
    }
    for (final item in current.subjects) {
      if (subject != null) break;
      if (item.name.toLowerCase() == name.toLowerCase()) {
        subject = item;
        break;
      }
    }
    subject ??= Subject(id: _id(), name: name);
    final lesson = Lesson(
      id: _id(),
      subjectId: subject.id,
      weekday: weekday,
      startMinute: startMinute,
      endMinute: endMinute,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      teachers: teachers,
      rooms: rooms,
    );
    final updatedSubjects = [
      ...current.subjects,
      if (!current.subjects.any((item) => item.id == subject!.id)) subject,
    ];
    final updatedLessons = [...current.lessons, lesson];
    Timetable(subjects: updatedSubjects, lessons: updatedLessons);
    await _ensureCatalogValues(updatedSubjects, updatedLessons);
    await _repository.replaceAll(
      subjects: updatedSubjects,
      lessons: updatedLessons,
    );
    timetable = Timetable(
      subjects: await _repository.getSubjects(),
      lessons: await _repository.getLessons(),
    );
    notifyListeners();
  }

  Future<void> deleteLesson(String id) async {
    await _repository.deleteLesson(id);
    await load();
  }

  Future<void> updateLesson({
    required String id,
    required String subjectName,
    required int weekday,
    required int startMinute,
    required int endMinute,
    int? startPeriod,
    int? endPeriod,
    String? subjectId,
    List<String> teachers = const [],
    List<String> rooms = const [],
  }) async {
    final current = timetable ?? Timetable(subjects: [], lessons: []);
    Subject? subject;
    for (final item in current.subjects) {
      if (subjectId != null && item.id == subjectId) {
        subject = item;
        break;
      }
    }
    for (final item in current.subjects) {
      if (subject != null) break;
      if (item.name.toLowerCase() == subjectName.trim().toLowerCase()) {
        subject = item;
        break;
      }
    }
    subject ??= Subject(id: _id(), name: subjectName);
    final updatedLessons = [
      for (final lesson in current.lessons)
        if (lesson.id == id)
          Lesson(
            id: id,
            subjectId: subject.id,
            weekday: weekday,
            startMinute: startMinute,
            endMinute: endMinute,
            startPeriod: startPeriod,
            endPeriod: endPeriod,
            teachers: teachers,
            rooms: rooms,
          )
        else
          lesson,
    ];
    final updatedSubjects = [
      ...current.subjects,
      if (!current.subjects.any((item) => item.id == subject!.id)) subject,
    ];
    Timetable(subjects: updatedSubjects, lessons: updatedLessons);
    await _ensureCatalogValues(updatedSubjects, updatedLessons);
    await _repository.replaceAll(
      subjects: updatedSubjects,
      lessons: updatedLessons,
    );
    timetable = Timetable(
      subjects: await _repository.getSubjects(),
      lessons: await _repository.getLessons(),
    );
    notifyListeners();
  }

  Future<void> applyImport({
    required List<Subject> subjects,
    required List<Lesson> lessons,
  }) async {
    Timetable(subjects: subjects, lessons: lessons);
    await _ensureCatalogValues(subjects, lessons);
    await _repository.replaceAll(subjects: subjects, lessons: lessons);
    await load();
  }

  Future<void> saveSubject(Subject subject) async {
    await _ensureResourceNames(ResourceCategory.teacher, subject.teachers);
    await _ensureResourceNames(ResourceCategory.room, subject.rooms);
    await _repository.saveSubject(subject);
    await load();
  }

  Future<void> saveResource(ClassroomResource resource) async {
    final duplicate = resources.any((item) =>
        item.id != resource.id &&
        item.category == resource.category &&
        item.name.trim().toLowerCase() == resource.name.trim().toLowerCase());
    if (duplicate) {
      throw ArgumentError('Esiste già una voce con questo nome nella sezione.');
    }
    await _repository.saveResource(resource);
    await load();
  }

  Future<void> deleteResource(String id) async {
    await _repository.deleteResource(id);
    await load();
  }

  Future<void> _ensureCatalogValues(
      List<Subject> subjects, List<Lesson> lessons) async {
    await _ensureResourceNames(ResourceCategory.teacher, [
      ...subjects.expand((subject) => subject.teachers),
      ...lessons.expand((lesson) => lesson.teachers),
    ]);
    await _ensureResourceNames(ResourceCategory.room, [
      ...subjects.expand((subject) => subject.rooms),
      ...lessons.expand((lesson) => lesson.rooms),
    ]);
  }

  Future<void> _ensureResourceNames(
      ResourceCategory category, Iterable<String> names) async {
    final known = (await _repository.getResources())
        .where((item) => item.category == category)
        .map((item) => item.name.trim().toLowerCase())
        .toSet();
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty || !known.add(name.toLowerCase())) continue;
      final isRoom = category == ResourceCategory.room;
      await _repository.saveResource(ClassroomResource(
        id: _id(),
        name: name,
        category: category,
        type: isRoom ? RoomType.classroom.name : TeacherType.teacher.name,
      ));
    }
  }

  Future<void> deleteSubject(String id) async {
    await _repository.deleteSubject(id);
    await load();
  }

  Future<void> savePeriodTimes(List<PeriodTime> periods) async {
    if (periods.isEmpty) {
      throw ArgumentError('Configura almeno una campanella.');
    }
    final weekday = periods.first.weekday;
    if (periods.any((period) => period.weekday != weekday)) {
      throw ArgumentError('Un salvataggio deve riguardare un solo giorno.');
    }
    final configured = [...periods]
      ..sort((a, b) => a.number.compareTo(b.number));
    for (var index = 0; index < configured.length; index++) {
      if (weekday != 0 && configured[index].number != index + 1) {
        throw ArgumentError(
            'Le ore devono partire dalla 1ª ora ed essere consecutive.');
      }
      if (index > 0 &&
          configured[index - 1].endMinute > configured[index].startMinute) {
        throw ArgumentError('Le campanelle non possono sovrapporsi.');
      }
    }
    final oldPeriods = await _repository.getPeriodTimes();
    final allPeriods = [
      ...oldPeriods.where((period) => period.weekday != weekday),
      ...periods,
    ]..sort((a, b) => a.weekday != b.weekday
        ? a.weekday.compareTo(b.weekday)
        : a.number.compareTo(b.number));
    final current = timetable ?? Timetable(subjects: [], lessons: []);
    for (final lesson in current.lessons) {
      final schedule = _periodsFor(lesson.weekday, allPeriods);
      final lastConfiguredPeriod = schedule.isEmpty ? 0 : schedule.last.number;
      if (lesson.endPeriod != null &&
          lesson.endPeriod! > lastConfiguredPeriod + 1) {
        throw ArgumentError('Non puoi rimuovere ore già usate nell’orario.');
      }
    }
    final updatedLessons = current.lessons.map((lesson) {
      if (lesson.startPeriod == null || lesson.endPeriod == null) return lesson;
      final schedule = _periodsFor(lesson.weekday, allPeriods);
      final byNumber = {for (final period in schedule) period.number: period};
      final first = byNumber[lesson.startPeriod];
      final last = byNumber[lesson.endPeriod! - 1];
      if (first == null || last == null) return lesson;
      return Lesson(
        id: lesson.id,
        subjectId: lesson.subjectId,
        weekday: lesson.weekday,
        startMinute: first.startMinute,
        endMinute: last.endMinute,
        startPeriod: lesson.startPeriod,
        endPeriod: lesson.endPeriod,
        teachers: lesson.teachers,
        rooms: lesson.rooms,
      );
    }).toList();
    Timetable(subjects: current.subjects, lessons: updatedLessons);
    await _repository.savePeriodTimes(allPeriods);
    await _repository.replaceAll(
        subjects: current.subjects, lessons: updatedLessons);
    periodTimes = allPeriods;
    timetable = Timetable(subjects: current.subjects, lessons: updatedLessons);
    notifyListeners();
  }

  List<PeriodTime> _periodsFor(int weekday, List<PeriodTime> source) {
    final specific = source
        .where((period) => period.weekday == weekday)
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    if (specific.isNotEmpty) return specific;
    return source.where((period) => period.weekday == 0).toList()
      ..sort((a, b) => a.number.compareTo(b.number));
  }

  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
  static int _counter = 0;
}
