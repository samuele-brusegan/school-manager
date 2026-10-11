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

  Future<List<PeriodTime>> guessPeriodTimes() async {
    if (_remoteLessons.isEmpty) return const [];
    final counts = <int, int>{};
    for (final lesson in _remoteLessons) {
      final lastPeriod = (lesson.periodNumber + lesson.duration - 1).clamp(1, 20);
      final weekday = lesson.date.weekday;
      if (weekday < 1 || weekday > 7) continue;
      if (lastPeriod > (counts[weekday] ?? 0)) counts[weekday] = lastPeriod;
    }

    final configured = await _repository.getPeriodTimes();
    final durations = configured
        .map((period) => period.endMinute - period.startMinute)
        .where((minutes) => minutes > 0)
        .toList();
    final gaps = <int>[];
    final schedules = <int, List<PeriodTime>>{};
    for (final period in configured) {
      schedules.putIfAbsent(period.weekday, () => []).add(period);
    }
    for (final schedule in schedules.values) {
      schedule.sort((a, b) => a.number.compareTo(b.number));
      for (var index = 1; index < schedule.length; index++) {
        final gap = schedule[index].startMinute - schedule[index - 1].endMinute;
        if (gap >= 0 && schedule[index].number == schedule[index - 1].number + 1) {
          gaps.add(gap);
        }
      }
    }
    final lessonMinutes = _median(durations) ?? 60;
    final breakMinutes = _median(gaps) ?? 10;
    final guesses = <PeriodTime>[];

    for (final entry in counts.entries) {
      final weekday = entry.key;
      final daySpecific = schedules[weekday] ?? const <PeriodTime>[];
      final existing = daySpecific.isNotEmpty
          ? daySpecific
          : schedules[0] ?? const <PeriodTime>[];
      final byNumber = {for (final period in existing) period.number: period};
      var nextStart = byNumber[1]?.startMinute ?? 8 * 60;
      for (var number = 1; number <= entry.value; number++) {
        final known = byNumber[number];
        final start = known?.startMinute ?? nextStart;
        final end = known?.endMinute ?? start + lessonMinutes;
        if (start >= 1440 || end > 1440) break;
        guesses.add(PeriodTime(
          number: number,
          weekday: weekday,
          startMinute: start,
          endMinute: end,
        ));
        nextStart = end + breakMinutes;
      }
    }
    return guesses;
  }

  int? _median(List<int> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Vero se esiste una sessione ClasseViva salvata o attiva.
  Future<bool> hasSession() => _gateway.hasSession();

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
    // Si prendono le lezioni dalla settimana precedente fino a oggi:
    // nel fine settimana i giorni lun-ven della settimana corrente
    // contengono già le lezioni appena svolte.
    final previousMonday = currentMonday.subtract(const Duration(days: 7));
    _remoteLessons = await _gateway.lessonsBetween(previousMonday, today);
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
