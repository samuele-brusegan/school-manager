import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/model/entities/period_time.dart';
import 'package:school_manager/model/entities/remote_lesson.dart';
import 'package:school_manager/model/services/import_proposal_builder.dart';

void main() {
  final builder = ImportProposalBuilder();
  final day = DateTime(2026, 9, 21);

  test('maps remote periods to local bell times and normalizes subjects', () {
    final proposal = builder.build(
      [
        RemoteLesson(date: day, subjectName: ' MATEMATICA ', periodNumber: 1),
        RemoteLesson(date: day, subjectName: 'matematica', periodNumber: 2),
      ],
      periods: [
        PeriodTime(number: 1, startMinute: 480, endMinute: 530),
        PeriodTime(number: 2, startMinute: 540, endMinute: 590),
      ],
    );
    expect(proposal.subjects, hasLength(1));
    // Le ore consecutive della stessa materia vengono unite in una lezione.
    expect(proposal.lessons, hasLength(1));
    expect(proposal.lessons.first.startMinute, 480);
    expect(proposal.lessons.first.endMinute, 590);
    expect(proposal.missingPeriods, isEmpty);
  });

  test('reports missing bell times without inventing lesson hours', () {
    final proposal = builder.build([
      RemoteLesson(date: day, subjectName: 'Fisica', periodNumber: 3),
    ]);
    expect(proposal.lessons, isEmpty);
    expect(proposal.missingPeriods, [3]);
  });

  test('uses the final configured bell time for multi-period lesson', () {
    final proposal = builder.build(
      [
        RemoteLesson(
          date: day,
          subjectName: 'Laboratorio',
          periodNumber: 1,
          duration: 2,
        ),
      ],
      periods: [
        PeriodTime(number: 1, startMinute: 480, endMinute: 530),
        PeriodTime(number: 2, startMinute: 540, endMinute: 600),
      ],
    );
    expect(proposal.lessons.single.endMinute, 600);
  });
}
