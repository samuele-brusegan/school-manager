import 'package:flutter/foundation.dart';

import '../model/contracts/classviva_data_gateway.dart';
import '../model/contracts/classviva_gateway.dart';
import '../model/contracts/school_data_repository.dart';
import '../model/entities/classviva_record.dart';
import '../model/entities/study_task.dart';

class SchoolDataController extends ChangeNotifier {
  SchoolDataController({
    required ClassVivaDataGateway dataGateway,
    required ClassVivaGateway sessionGateway,
    required SchoolDataRepository repository,
  })  : _dataGateway = dataGateway,
        _sessionGateway = sessionGateway,
        _repository = repository;

  final ClassVivaDataGateway _dataGateway;
  final ClassVivaGateway _sessionGateway;
  final SchoolDataRepository _repository;

  final Map<ClassVivaSection, List<ClassVivaRecord>> records = {};
  final Map<ClassVivaSection, String> errors = {};
  List<StudyTask> tasks = [];
  Map<String, bool> testFlags = {};
  bool isLoading = false;
  String? message;
  DateTime? lastUpdated;

  Future<void> loadLocal() async {
    for (final section in ClassVivaSection.values) {
      records[section] = await _repository.getRecords(section.name);
    }
    tasks = await _repository.getTasks();
    testFlags = await _repository.getTestFlags();
    lastUpdated = await _repository.getLastUpdated();
    notifyListeners();
  }

  /// Marca o smarca un evento come verifica/prova, sovrascrivendo il
  /// riconoscimento automatico da parole chiave.
  Future<void> setTestFlag(String recordId, bool value) async {
    await _repository.setTestFlag(recordId, value);
    testFlags = await _repository.getTestFlags();
    notifyListeners();
  }

  /// Vero se esiste una sessione ClasseViva salvata o attiva.
  Future<bool> hasSession() => _sessionGateway.hasSession();

  Future<void> signInAndRefresh({
    required String username,
    required String password,
  }) async {
    isLoading = true;
    message = null;
    notifyListeners();
    try {
      await _sessionGateway.signIn(username: username, password: password);
      await _refreshAll();
    } on Object catch (error) {
      message = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> useSavedSession() async {
    isLoading = true;
    message = null;
    notifyListeners();
    try {
      await _refreshAll();
    } on Object catch (error) {
      message = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _sessionGateway.signOut();
    message = 'Sessione ClasseViva eliminata.';
    notifyListeners();
  }

  Future<void> refresh() => useSavedSession();

  Future<void> refreshSection(ClassVivaSection section) async {
    errors.remove(section);
    try {
      final now = DateTime.now();
      final schoolYearEnd =
          DateTime(now.month >= 9 ? now.year + 1 : now.year, 8, 31);
      // Agenda e presenze si caricano dall'inizio dell'anno scolastico:
      // anche gli eventi/compiti dei giorni passati restano consultabili.
      final start = switch (section) {
        ClassVivaSection.agenda ||
        ClassVivaSection.attendance =>
          DateTime(schoolYearEnd.year - 1, 9, 1),
        _ => null,
      };
      final end = section == ClassVivaSection.agenda
          ? schoolYearEnd
          : section == ClassVivaSection.attendance
              ? now
              : null;
      final loaded = await _dataGateway.records(
        section,
        start: start,
        end: end,
      );
      await _repository.saveRecords(section.name, loaded);
      records[section] = loaded;
      lastUpdated = DateTime.now();
    } on Object catch (error) {
      errors[section] = error.toString();
    }
    notifyListeners();
  }

  Future<void> addTask({
    required String title,
    required DateTime dueDate,
    String subject = '',
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return;
    final task = StudyTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: cleanTitle,
      dueDate: dueDate,
      subject: subject.trim(),
    );
    await _repository.saveTask(task);
    tasks = await _repository.getTasks();
    notifyListeners();
  }

  Future<void> toggleTask(StudyTask task) async {
    final updated = StudyTask(
      id: task.id,
      title: task.title,
      dueDate: task.dueDate,
      subject: task.subject,
      isDone: !task.isDone,
    );
    await _repository.saveTask(updated);
    tasks = await _repository.getTasks();
    notifyListeners();
  }

  Future<void> deleteTask(String id) async {
    await _repository.deleteTask(id);
    tasks = await _repository.getTasks();
    notifyListeners();
  }

  Future<void> _refreshAll() async {
    for (final section in ClassVivaSection.values) {
      await refreshSection(section);
    }
    final failures = errors.length;
    if (failures == ClassVivaSection.values.length) {
      message = errors.values.first;
    } else if (failures > 0) {
      message =
          'Alcune sezioni non sono disponibili. I dati salvati restano visibili.';
    } else {
      message = 'Dati ClasseViva aggiornati.';
    }
  }
}
