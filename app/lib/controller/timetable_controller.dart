import 'dart:convert';

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
      var subjects = await _repository.getSubjects();
      var lessons = await _repository.getLessons();
      // Versioni precedenti potevano creare materie duplicate con lo stesso
      // classviva_id: le unisco e ripunto le lezioni sulla voce principale.
      final merged = _mergeDuplicateSubjects(subjects, lessons);
      if (merged != null) {
        await _repository.replaceAll(
          subjects: merged.subjects,
          lessons: merged.lessons,
        );
        subjects = await _repository.getSubjects();
        lessons = await _repository.getLessons();
      }
      timetable = Timetable(subjects: subjects, lessons: lessons);
      periodTimes = await _repository.getPeriodTimes();
      // Migrazione: le vecchie configurazioni salvavano un orario per ogni
      // giorno. Le campanelle sono ora condivise (weekday 0): il giorno con
      // più ore fa da base e gli altri giorni diventano override sul solo
      // numero di ore.
      if (periodTimes.isNotEmpty &&
          periodTimes.every((period) => period.weekday != 0)) {
        final byDay = <int, List<PeriodTime>>{};
        for (final period in periodTimes) {
          byDay.putIfAbsent(period.weekday, () => []).add(period);
        }
        final base = byDay.values.reduce(
            (a, b) => a.length >= b.length ? a : b)
          ..sort((a, b) => a.number.compareTo(b.number));
        final shared = [
          for (final period in base)
            PeriodTime(
              number: period.number,
              weekday: 0,
              startMinute: period.startMinute,
              endMinute: period.endMinute,
            ),
        ];
        periodTimes = _propagateShared(
          shared,
          [...shared, ...periodTimes],
        );
        await _repository.savePeriodTimes(periodTimes);
      }
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

  /// Esporta la configurazione (materie, lezioni, campanelle, risorse,
  /// impostazioni) come stringa JSON. Credenziali e dati ClasseViva non
  /// vengono inclusi.
  Future<String> exportConfigJson() async =>
      jsonEncode(await _repository.exportConfig());

  /// Importa la configurazione da una stringa JSON prodotta da
  /// [exportConfigJson]. Solleva [FormatException] se non valida.
  Future<void> importConfigJson(String json) async {
    final decoded = jsonDecode(json);
    if (decoded is! Map || decoded['version'] == null) {
      throw const FormatException('File di configurazione non valido.');
    }
    await _repository.importConfig(decoded.cast<String, Object?>());
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

  Future<void> clearAllData() async {
    await _repository.clearAll();
    await load();
  }

  /// Campanelle condivise tra tutti i giorni (weekday 0): gli orari delle
  /// singole ore sono gli stessi ovunque, i giorni possono solo cambiare
  /// il numero di ore.
  List<PeriodTime> get sharedPeriods => periodTimes
      .where((period) => period.weekday == 0)
      .toList()
    ..sort((a, b) => a.number.compareTo(b.number));

  /// Cambia solo il numero di ore di un giorno: gli orari restano quelli
  /// delle campanelle condivise. Se il numero coincide con quello condiviso
  /// l'eventuale override viene rimosso, così il giorno segue sempre gli
  /// orari comuni.
  Future<void> setDayPeriodCount(int weekday, int count) async {
    if (weekday < 1 || weekday > 7) {
      throw ArgumentError('Giorno non valido.');
    }
    final shared = sharedPeriods;
    if (shared.isEmpty) {
      throw ArgumentError('Configura prima le campanelle condivise.');
    }
    final oldPeriods = await _repository.getPeriodTimes();
    if (count == shared.length) {
      await _commitPeriodTimes(
          oldPeriods.where((period) => period.weekday != weekday).toList());
      return;
    }
    final sharedByNumber = {for (final period in shared) period.number: period};
    final existing = {
      for (final period in oldPeriods.where((p) => p.weekday == weekday))
        period.number: period
    };
    var nextStart = shared.last.endMinute;
    final rows = <PeriodTime>[];
    for (var number = 1; number <= count; number++) {
      final start = sharedByNumber[number]?.startMinute ??
          existing[number]?.startMinute ??
          nextStart;
      final end = sharedByNumber[number]?.endMinute ??
          existing[number]?.endMinute ??
          start + 60;
      rows.add(PeriodTime(
        number: number,
        weekday: weekday,
        startMinute: start,
        endMinute: end > start ? end : start + 60,
      ));
      nextStart = rows.last.endMinute;
    }
    await savePeriodTimes(rows);
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
      if (configured[index].number != index + 1) {
        throw ArgumentError(
            'Le ore devono partire dalla 1ª ora ed essere consecutive.');
      }
      if (index > 0 &&
          configured[index - 1].endMinute > configured[index].startMinute) {
        throw ArgumentError('Le campanelle non possono sovrapporsi.');
      }
    }
    final oldPeriods = await _repository.getPeriodTimes();
    var allPeriods = [
      ...oldPeriods.where((period) => period.weekday != weekday),
      ...periods,
    ];
    if (weekday == 0) allPeriods = _propagateShared(configured, allPeriods);
    await _commitPeriodTimes(allPeriods);
  }

  /// Quando cambiano le campanelle condivise, gli override dei giorni
  /// conservano solo il numero di ore: gli orari vengono riallineati a
  /// quelli comuni (le ore oltre le condivise mantengono il loro orario).
  List<PeriodTime> _propagateShared(
      List<PeriodTime> shared, List<PeriodTime> all) {
    final sharedByNumber = {for (final period in shared) period.number: period};
    final lastSharedEnd =
        shared.isEmpty ? 8 * 60 : shared.last.endMinute;
    final result = [...shared];
    final overridenDays =
        all.where((p) => p.weekday != 0).map((p) => p.weekday).toSet();
    for (final weekday in overridenDays) {
      final dayRows = all.where((p) => p.weekday == weekday).toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      final oldByNumber = {for (final p in dayRows) p.number: p};
      var nextStart = lastSharedEnd;
      for (var number = 1; number <= dayRows.length; number++) {
        final common = sharedByNumber[number];
        final old = oldByNumber[number];
        final start =
            common?.startMinute ?? old?.startMinute ?? nextStart;
        final end = common?.endMinute ?? old?.endMinute ?? start + 60;
        result.add(PeriodTime(
          number: number,
          weekday: weekday,
          startMinute: start,
          endMinute: end > start ? end : start + 60,
        ));
        nextStart = result.last.endMinute;
      }
    }
    return result..sort((a, b) => a.weekday != b.weekday
        ? a.weekday.compareTo(b.weekday)
        : a.number.compareTo(b.number));
  }

  Future<void> _commitPeriodTimes(List<PeriodTime> allPeriods) async {
    allPeriods = [...allPeriods]..sort((a, b) => a.weekday != b.weekday
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

  /// Restituisce materie e lezioni con i duplicati (stesso classviva_id non
  /// vuoto) uniti in un'unica materia, oppure null se non c'è nulla da fare.
  ({List<Subject> subjects, List<Lesson> lessons})? _mergeDuplicateSubjects(
    List<Subject> subjects,
    List<Lesson> lessons,
  ) {
    final byRemoteId = <String, List<Subject>>{};
    for (final subject in subjects) {
      final remoteId = subject.classvivaId.trim();
      if (remoteId.isEmpty) continue;
      byRemoteId.putIfAbsent(remoteId, () => []).add(subject);
    }
    if (byRemoteId.values.every((group) => group.length == 1)) return null;

    final lessonCount = <String, int>{};
    for (final lesson in lessons) {
      lessonCount.update(lesson.subjectId, (count) => count + 1,
          ifAbsent: () => 1);
    }
    final remappedIds = <String, String>{};
    final kept = <Subject>[];
    final seen = <String>{};
    for (final subject in subjects) {
      final remoteId = subject.classvivaId.trim();
      final group = byRemoteId[remoteId];
      if (remoteId.isEmpty || group == null || group.length == 1) {
        kept.add(subject);
        continue;
      }
      if (!seen.add(remoteId)) continue;
      // Tiene la materia con più lezioni; a parità la più "corta" (di solito
      // il nome personalizzato come "GPOI" rispetto al nome ClasseViva).
      final canonical = [...group]..sort((a, b) {
          final byLessons = (lessonCount[b.id] ?? 0)
              .compareTo(lessonCount[a.id] ?? 0);
          return byLessons != 0
              ? byLessons
              : a.name.length.compareTo(b.name.length);
        });
      final primary = canonical.first;
      final others = canonical.skip(1).toList();
      for (final other in others) {
        remappedIds[other.id] = primary.id;
      }
      final color = primary.colorValue != 0xFF6750A4
          ? primary.colorValue
          : others
              .map((other) => other.colorValue)
              .firstWhere((value) => value != 0xFF6750A4,
                  orElse: () => primary.colorValue);
      kept.add(Subject(
        id: primary.id,
        name: primary.name,
        colorValue: color,
        classvivaId: primary.classvivaId,
        teachers: {primary.teachers, ...others.map((o) => o.teachers)}
            .expand((list) => list)
            .toList(),
        rooms: {primary.rooms, ...others.map((o) => o.rooms)}
            .expand((list) => list)
            .toList(),
      ));
    }
    final remappedLessons = [
      for (final lesson in lessons)
        remappedIds.containsKey(lesson.subjectId)
            ? Lesson(
                id: lesson.id,
                subjectId: remappedIds[lesson.subjectId]!,
                weekday: lesson.weekday,
                startMinute: lesson.startMinute,
                endMinute: lesson.endMinute,
                startPeriod: lesson.startPeriod,
                endPeriod: lesson.endPeriod,
                teachers: lesson.teachers,
                rooms: lesson.rooms,
              )
            : lesson,
    ];
    return (subjects: kept, lessons: remappedLessons);
  }

  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
  static int _counter = 0;
}
