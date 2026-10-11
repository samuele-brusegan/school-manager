import '../entities/import_proposal.dart';
import '../entities/lesson.dart';
import '../entities/remote_lesson.dart';
import '../entities/subject.dart';
import '../entities/period_time.dart';

class ImportProposalBuilder {
  ImportProposal build(
    List<RemoteLesson> remoteLessons, {
    List<Subject> existing = const [],
    List<PeriodTime> periods = const [],
  }) {
    final subjects = <String, Subject>{
      for (final subject in existing) subject.name.toLowerCase(): subject,
    };
    // Il match principale avviene sull'ID numerico di ClasseViva: il nome
    // remoto cambia facilmente (es. materia rinominata "GPOI"), l'ID no.
    final remoteSubjects = <String, Subject>{
      for (final subject in existing)
        if (subject.classvivaId.trim().isNotEmpty)
          subject.classvivaId.trim(): subject,
    };
    final usedIds = existing.map((subject) => subject.id).toSet();
    final lessons = <Lesson>[];
    final warnings = <String>[];
    final missingPeriods = <int>{};
    final seenSlots = <String>{};
    final subjectTeachers = <String, Set<String>>{};
    final subjectIds = <String, String>{};

    // ClasseViva restituisce un evento per ogni ora: le ore consecutive
    // della stessa materia nello stesso giorno vengono unite in una
    // sola lezione. In parallelo si raccolgono i docenti di ogni ora.
    final sorted = [...remoteLessons]
      ..sort((a, b) {
        final byDate = DateTime(a.date.year, a.date.month, a.date.day)
            .compareTo(DateTime(b.date.year, b.date.month, b.date.day));
        return byDate != 0
            ? byDate
            : a.periodNumber.compareTo(b.periodNumber);
      });
    final merged = <RemoteLesson>[];
    final mergedTeachers = <Set<String>>[];
    for (final item in sorted) {
      final names = {
        if (item.teacherName != null && item.teacherName!.trim().isNotEmpty)
          item.teacherName!.trim(),
      };
      subjectTeachers
          .putIfAbsent(item.subjectName.trim().toLowerCase(), () => {})
          .addAll(names);
      final remoteId = item.subjectId?.trim();
      if (remoteId != null && remoteId.isNotEmpty) {
        subjectIds[item.subjectName.trim().toLowerCase()] = remoteId;
      }
      if (merged.isNotEmpty) {
        final last = merged.last;
        final sameDay = last.date.year == item.date.year &&
            last.date.month == item.date.month &&
            last.date.day == item.date.day;
        if (sameDay &&
            last.subjectName.trim().toLowerCase() ==
                item.subjectName.trim().toLowerCase() &&
            last.periodNumber + last.duration == item.periodNumber) {
          merged[merged.length - 1] = RemoteLesson(
            date: last.date,
            subjectName: last.subjectName,
            periodNumber: last.periodNumber,
            duration: last.duration + item.duration,
            teacherName: last.teacherName ?? item.teacherName,
            subjectId: last.subjectId ?? item.subjectId,
          );
          mergedTeachers.last.addAll(names);
          continue;
        }
      }
      merged.add(item);
      mergedTeachers.add(names);
    }

    for (var index = 0; index < merged.length; index++) {
      final item = merged[index];
      final lessonTeachers = mergedTeachers[index].toList()..sort();
      final dayPeriods = periods
              .where((period) => period.weekday == item.date.weekday)
              .isNotEmpty
          ? periods.where((period) => period.weekday == item.date.weekday)
          : periods.where((period) => period.weekday == 0);
      final times = {for (final period in dayPeriods) period.number: period};
      final name = item.subjectName.trim();
      if (name.isEmpty || item.periodNumber < 1 || item.duration < 1) {
        warnings.add('Una lezione con dati incompleti è stata ignorata.');
        continue;
      }
      final firstPeriod = times[item.periodNumber];
      final lastPeriod = times[item.periodNumber + item.duration - 1];
      if (firstPeriod == null || lastPeriod == null) {
        for (var slot = item.periodNumber;
            slot < item.periodNumber + item.duration;
            slot++) {
          if (!times.containsKey(slot)) missingPeriods.add(slot);
        }
        continue;
      }
      final key = name.toLowerCase();
      final remoteId = item.subjectId?.trim();
      var subject = remoteId != null && remoteId.isNotEmpty
          ? remoteSubjects[remoteId]
          : null;
      subject ??= subjects.putIfAbsent(
        key,
        () {
          var id = 'cv-${Uri.encodeComponent(key)}';
          var suffix = 0;
          while (usedIds.contains(id)) {
            id = 'cv-${Uri.encodeComponent(key)}-${++suffix}';
          }
          usedIds.add(id);
          return Subject(
            id: id,
            name: name,
            classvivaId:
                remoteId != null && remoteId.isNotEmpty ? remoteId : name,
          );
        },
      );
      // La materia riconosciuta via classviva_id deve comparire nella bozza
      // anche se il nome remoto non coincide con quello salvato.
      subjects.putIfAbsent(subject.name.toLowerCase(), () => subject!);
      if (remoteId != null && remoteId.isNotEmpty) {
        remoteSubjects[remoteId] = subject;
      }
      final candidate = Lesson(
        id: 'import-${item.date.toIso8601String()}-${item.periodNumber}-${subject.id}',
        subjectId: subject.id,
        weekday: item.date.weekday,
        startMinute: firstPeriod.startMinute,
        endMinute: lastPeriod.endMinute,
        startPeriod: item.periodNumber,
        endPeriod: item.periodNumber + item.duration,
        teachers: lessonTeachers,
      );
      // La finestra può coprire più settimane: la stessa lezione
      // (giorno/ora/materia) viene importata una sola volta.
      final slotKey =
          '${item.date.weekday}-${candidate.startMinute}-${candidate.endMinute}-${subject.id}';
      if (!seenSlots.add(slotKey)) continue;
      if (lessons.any((lesson) => lesson.overlaps(candidate))) {
        warnings.add(
          'Lezioni sovrapposte il ${item.date.day}/${item.date.month}: verifica la bozza.',
        );
        continue;
      }
      lessons.add(candidate);
    }
    return ImportProposal(
      subjects: [
        for (final subject in subjects.values)
          Subject(
            id: subject.id,
            name: subject.name,
            colorValue: subject.colorValue,
            // Si memorizza l'ID numerico di ClasseViva (più stabile del
            // nome) quando la materia non ha un mapping manuale diverso.
            classvivaId: _resolvedClassVivaId(subject, subjectIds),
            teachers: {
              ...subject.teachers,
              ...?subjectTeachers[subject.name.toLowerCase()],
            }.toList()
              ..sort(),
            rooms: subject.rooms,
          ),
      ],
      lessons: lessons,
      warnings: warnings.toSet().toList(),
      missingPeriods: missingPeriods.toList()..sort(),
    );
  }

  /// Usa l'ID remoto se la materia non ha mapping o se il mapping era il
  /// nome remoto (import precedente); non sovrascrive mapping manuali.
  static String _resolvedClassVivaId(
      Subject subject, Map<String, String> subjectIds) {
    final remoteId = subjectIds[subject.name.toLowerCase()];
    if (remoteId == null) return subject.classvivaId;
    final current = subject.classvivaId.trim();
    if (current.isEmpty ||
        current.toLowerCase() == subject.name.toLowerCase() ||
        current == remoteId) {
      return remoteId;
    }
    return subject.classvivaId;
  }
}
