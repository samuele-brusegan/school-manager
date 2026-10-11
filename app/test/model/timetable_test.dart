import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/model/entities/lesson.dart';
import 'package:school_manager/model/entities/subject.dart';
import 'package:school_manager/model/entities/timetable.dart';

void main() {
  group('Timetable', () {
    final subject = Subject(id: 'math', name: ' Matematica ');

    test('trims subject names and accepts adjacent lessons', () {
      final timetable = Timetable(
        subjects: [subject],
        lessons: [
          Lesson(
            id: 'a',
            subjectId: 'math',
            weekday: 1,
            startMinute: 480,
            endMinute: 530,
          ),
          Lesson(
            id: 'b',
            subjectId: 'math',
            weekday: 1,
            startMinute: 530,
            endMinute: 580,
          ),
        ],
      );
      expect(subject.name, 'Matematica');
      expect(timetable.lessons, hasLength(2));
    });

    test('accepts overlapping lessons rendered on parallel lanes', () {
      final timetable = Timetable(
        subjects: [subject],
        lessons: [
          Lesson(
            id: 'a',
            subjectId: 'math',
            weekday: 1,
            startMinute: 480,
            endMinute: 540,
          ),
          Lesson(
            id: 'b',
            subjectId: 'math',
            weekday: 1,
            startMinute: 530,
            endMinute: 580,
          ),
        ],
      );
      expect(timetable.lessons, hasLength(2));
    });

    test('rejects missing subject references', () {
      expect(
        () => Timetable(
          subjects: const [],
          lessons: [
            Lesson(
              id: 'a',
              subjectId: 'missing',
              weekday: 1,
              startMinute: 480,
              endMinute: 540,
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects invalid day, range, and empty subject', () {
      expect(
        () => Lesson(
          id: 'x',
          subjectId: 'math',
          weekday: 0,
          startMinute: 1,
          endMinute: 2,
        ),
        throwsRangeError,
      );
      expect(
        () => Lesson(
          id: 'x',
          subjectId: 'math',
          weekday: 1,
          startMinute: 600,
          endMinute: 600,
        ),
        throwsArgumentError,
      );
      expect(() => Subject(id: 'x', name: '  '), throwsArgumentError);
    });
  });
}
