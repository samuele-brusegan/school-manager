import 'lesson.dart';
import 'subject.dart';

class ImportProposal {
  const ImportProposal({
    required this.subjects,
    required this.lessons,
    required this.warnings,
    this.missingPeriods = const [],
  });

  final List<Subject> subjects;
  final List<Lesson> lessons;
  final List<String> warnings;
  final List<int> missingPeriods;
}
