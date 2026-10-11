import '../entities/classviva_record.dart';

enum ClassVivaSection {
  agenda,
  grades,
  attendance,
  notes,
  noticeboard,
  didactics,
  documents,
  schoolbooks,
}

abstract interface class ClassVivaDataGateway {
  Future<List<ClassVivaRecord>> records(
    ClassVivaSection section, {
    DateTime? start,
    DateTime? end,
  });
}
