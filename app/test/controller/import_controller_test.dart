import 'package:flutter_test/flutter_test.dart';
import 'package:school_manager/controller/import_controller.dart';
import 'package:school_manager/model/contracts/classviva_gateway.dart';
import 'package:school_manager/model/contracts/timetable_repository.dart';
import 'package:school_manager/model/entities/classroom_resource.dart';
import 'package:school_manager/model/entities/lesson.dart';
import 'package:school_manager/model/entities/period_time.dart';
import 'package:school_manager/model/entities/remote_lesson.dart';
import 'package:school_manager/model/entities/subject.dart';
import 'package:school_manager/model/services/import_proposal_builder.dart';

void main() {
  test(
    'requests the previous Monday through Sunday and creates an import proposal',
    () async {
      final gateway = _FakeGateway();
      final controller = ImportController(
        gateway: gateway,
        repository: _FakeRepository(),
        builder: ImportProposalBuilder(),
      );
      await controller.signInAndBuildProposal(
        username: 'student',
        password: 'secret',
        referenceDay: DateTime(2026, 10, 1),
      );
      expect(gateway.start, DateTime(2026, 9, 21));
      // La finestra arriva fino al giorno di riferimento per coprire
      // anche le lezioni della settimana corrente.
      expect(gateway.end, DateTime(2026, 10, 1));
      expect(controller.proposal?.lessons, hasLength(1));
      expect(controller.error, isNull);
    },
  );

  test('turns gateway failures into a presentable error state', () async {
    final gateway = _FakeGateway()..failure = StateError('offline');
    final controller = ImportController(
      gateway: gateway,
      repository: _FakeRepository(),
      builder: ImportProposalBuilder(),
    );
    await controller.signInAndBuildProposal(
      username: 'student',
      password: 'secret',
      referenceDay: DateTime(2026, 10, 1),
    );
    expect(controller.error, contains('offline'));
    expect(controller.isLoading, isFalse);
  });
}

class _FakeGateway implements ClassVivaGateway {
  DateTime? start;
  DateTime? end;
  Object? failure;
  @override
  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    if (failure != null) throw failure!;
  }

  @override
  Future<List<RemoteLesson>> lessonsBetween(
    DateTime start,
    DateTime end,
  ) async {
    this.start = start;
    this.end = end;
    return [
      RemoteLesson(
        date: DateTime(2026, 9, 21),
        subjectName: 'Matematica',
        periodNumber: 1,
      ),
    ];
  }

  @override
  Future<bool> hasSession() async => true;

  @override
  Future<void> signOut() async {}
}

class _FakeRepository implements TimetableRepository {
  @override
  Future<void> deleteLesson(String id) async {}
  @override
  Future<void> deleteSubject(String id) async {}
  @override
  Future<List<Lesson>> getLessons() async => [];
  @override
  Future<List<PeriodTime>> getPeriodTimes() async => [
        PeriodTime(number: 1, startMinute: 480, endMinute: 530),
      ];
  @override
  Future<List<Subject>> getSubjects() async => [];
  @override
  Future<void> replaceAll({
    required List<Subject> subjects,
    required List<Lesson> lessons,
  }) async {}
  @override
  Future<void> saveLesson(Lesson lesson) async {}
  @override
  Future<void> savePeriodTimes(List<PeriodTime> periods) async {}
  @override
  Future<void> saveSubject(Subject subject) async {}
  @override
  Future<List<ClassroomResource>> getResources() async => [];
  @override
  Future<void> saveResource(ClassroomResource resource) async {}
  @override
  Future<void> deleteResource(String id) async {}
  @override
  Future<void> clearAll() async {}

  @override
  Future<Map<String, Object?>> exportConfig() async => {};

  @override
  Future<void> importConfig(Map<String, Object?> data) async {}
}
