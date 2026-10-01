import 'lesson.dart';
import 'subject.dart';

class Timetable {
  Timetable({required List<Subject> subjects, required List<Lesson> lessons})
      : subjects = List.unmodifiable(subjects),
        lessons = List.unmodifiable(lessons) {
    final subjectIds = this.subjects.map((subject) => subject.id).toSet();
    if (subjectIds.length != this.subjects.length) {
      throw ArgumentError('Identificatore materia duplicato');
    }
    final lessonIds = this.lessons.map((lesson) => lesson.id).toSet();
    if (lessonIds.length != this.lessons.length) {
      throw ArgumentError('Identificatore lezione duplicato');
    }
    if (this.lessons.any((lesson) => !subjectIds.contains(lesson.subjectId))) {
      throw ArgumentError('Lezione senza materia');
    }
  }

  final List<Subject> subjects;
  final List<Lesson> lessons;
}
