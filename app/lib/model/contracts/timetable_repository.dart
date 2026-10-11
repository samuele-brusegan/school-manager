import '../entities/lesson.dart';
import '../entities/subject.dart';
import '../entities/period_time.dart';
import '../entities/classroom_resource.dart';

abstract interface class TimetableRepository {
  Future<List<Subject>> getSubjects();
  Future<List<Lesson>> getLessons();
  Future<void> saveSubject(Subject subject);
  Future<void> saveLesson(Lesson lesson);
  Future<void> deleteLesson(String id);
  Future<void> deleteSubject(String id);
  Future<void> replaceAll({
    required List<Subject> subjects,
    required List<Lesson> lessons,
  });
  Future<List<PeriodTime>> getPeriodTimes();
  Future<void> savePeriodTimes(List<PeriodTime> periods);
  Future<List<ClassroomResource>> getResources();
  Future<void> saveResource(ClassroomResource resource);
  Future<void> deleteResource(String id);
  Future<void> clearAll();

  /// Serializza la configurazione (materie, lezioni, campanelle,
  /// risorse, impostazioni) in una mappa JSON-esportabile.
  Future<Map<String, Object?>> exportConfig();

  /// Ripristina la configurazione da [exportConfig]; compiti, cache
  /// ClasseViva e flag verifiche non vengono toccati.
  Future<void> importConfig(Map<String, Object?> data);
}
