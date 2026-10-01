import 'package:flutter/foundation.dart';

import '../model/contracts/classviva_gateway.dart';
import '../model/contracts/timetable_repository.dart';
import '../model/entities/import_proposal.dart';
import '../model/entities/remote_lesson.dart';
import '../model/entities/period_time.dart';
import '../model/services/import_proposal_builder.dart';

class ImportController extends ChangeNotifier {
  ImportController({
    required ClassVivaGateway gateway,
    required TimetableRepository repository,
    required ImportProposalBuilder builder,
  })  : _gateway = gateway,
        _repository = repository,
        _builder = builder;

  final ClassVivaGateway _gateway;
  final TimetableRepository _repository;
  final ImportProposalBuilder _builder;
  bool isLoading = false;
  String? error;
  ImportProposal? proposal;
  List<RemoteLesson> _remoteLessons = [];

  Future<void> signInAndBuildProposal({
    required String username,
    required String password,
    DateTime? referenceDay,
  }) async {
    isLoading = true;
    error = null;
    proposal = null;
    notifyListeners();
    try {
      await _gateway.signIn(username: username, password: password);
      await _buildProposal(referenceDay);
    } catch (exception) {
      error = exception.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> useSavedSession({DateTime? referenceDay}) async {
    isLoading = true;
    error = null;
    proposal = null;
    notifyListeners();
    try {
      await _buildProposal(referenceDay);
    } catch (exception) {
      error = exception.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _gateway.signOut();
    _remoteLessons = [];
    proposal = null;
    error = null;
    notifyListeners();
  }

  Future<void> _buildProposal(DateTime? referenceDay) async {
    final today = referenceDay ?? DateTime.now();
    final currentMonday = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - 1));
    final previousMonday = currentMonday.subtract(const Duration(days: 7));
    final previousSunday = currentMonday.subtract(const Duration(days: 1));
    _remoteLessons =
        await _gateway.lessonsBetween(previousMonday, previousSunday);
    proposal = _builder.build(
      _remoteLessons,
      existing: await _repository.getSubjects(),
      periods: await _repository.getPeriodTimes(),
    );
    if (proposal!.lessons.isEmpty && proposal!.missingPeriods.isEmpty) {
      error = 'Nessuna lezione importabile trovata nella settimana precedente.';
    }
  }

  Future<void> savePeriodTimes(List<PeriodTime> periods) async {
    final saved = await _repository.getPeriodTimes();
    final allPeriods = [
      ...saved.where(
        (old) => periods.every((value) =>
            value.weekday != old.weekday || value.number != old.number),
      ),
      ...periods,
    ]..sort((a, b) => a.weekday != b.weekday
        ? a.weekday.compareTo(b.weekday)
        : a.number.compareTo(b.number));
    for (final weekday in allPeriods.map((period) => period.weekday).toSet()) {
      final dayPeriods =
          allPeriods.where((period) => period.weekday == weekday).toList();
      for (var index = 1; index < dayPeriods.length; index++) {
        if (dayPeriods[index - 1].endMinute > dayPeriods[index].startMinute) {
          throw const ClassVivaException(
            'Gli orari delle ore non possono sovrapporsi.',
          );
        }
      }
    }
    await _repository.savePeriodTimes(allPeriods);
    proposal = _builder.build(
      _remoteLessons,
      existing: await _repository.getSubjects(),
      periods: await _repository.getPeriodTimes(),
    );
    notifyListeners();
  }

  void discard() {
    proposal = null;
    notifyListeners();
  }
}
