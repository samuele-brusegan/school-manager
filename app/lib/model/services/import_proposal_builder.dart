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
    final lessons = <Lesson>[];
    final warnings = <String>[];
    final missingPeriods = <int>{};
    for (final item in remoteLessons) {
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
      final subject = subjects.putIfAbsent(
        key,
        () => Subject(id: 'cv-${Uri.encodeComponent(key)}', name: name),
      );
      final candidate = Lesson(
        id: 'import-${item.date.toIso8601String()}-${item.periodNumber}-${subject.id}',
        subjectId: subject.id,
        weekday: item.date.weekday,
        startMinute: firstPeriod.startMinute,
        endMinute: lastPeriod.endMinute,
        startPeriod: item.periodNumber,
        endPeriod: item.periodNumber + item.duration,
      );
      if (lessons.any((lesson) => lesson.overlaps(candidate))) {
        warnings.add(
          'Lezioni sovrapposte il ${item.date.day}/${item.date.month}: verifica la bozza.',
        );
        continue;
      }
      lessons.add(candidate);
    }
    return ImportProposal(
      subjects: subjects.values.toList(),
      lessons: lessons,
      warnings: warnings.toSet().toList(),
      missingPeriods: missingPeriods.toList()..sort(),
    );
  }
}
