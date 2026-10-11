import '../entities/classviva_record.dart';
import '../entities/study_task.dart';

abstract interface class SchoolDataRepository {
  Future<List<ClassVivaRecord>> getRecords(String section);
  Future<DateTime?> getLastUpdated();
  Future<void> saveRecords(String section, List<ClassVivaRecord> records);
  Future<List<StudyTask>> getTasks();
  Future<void> saveTask(StudyTask task);
  Future<void> deleteTask(String id);
  Future<Map<String, bool>> getTestFlags();
  Future<void> setTestFlag(String recordId, bool value);
}
