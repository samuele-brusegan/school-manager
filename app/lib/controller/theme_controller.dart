import 'package:flutter/foundation.dart';

import '../model/contracts/theme_preference_repository.dart';

class ThemeController extends ChangeNotifier {
  ThemeController(this._repository);

  final ThemePreferenceRepository _repository;

  /// 'system' (predefinito), 'light' o 'dark'.
  String themeMode = 'system';

  /// Giorni del weekend visibili in agenda: 'all', 'sunday' o 'none'.
  String weekendMode = 'all';

  /// Overlay di debug: mostra i metadati grezzi ovunque nell'app.
  bool debugMode = false;

  /// Intervallo di aggiornamento automatico ClasseViva in minuti (0 = mai).
  int autoRefreshMinutes = 5;

  /// Obiettivi di media per materia (chiave = nome materia ClasseViva).
  Map<String, double> gradeTargets = {};

  /// Obiettivo globale, usato dalle materie senza override specifico.
  double? defaultGradeTarget;

  /// Target effettivo di una materia: override specifico o globale.
  double? targetFor(String subject) =>
      gradeTargets[subject] ?? defaultGradeTarget;

  /// Mostra la percentuale di assenze nella pagina Presenze.
  bool showAttendanceRate = true;

  /// Pagina Debug visibile nelle impostazioni (sblocco: 7 tocchi sulla versione).
  bool debugUnlocked = false;

  /// Tutorial di benvenuto già mostrato al primo avvio.
  bool hasSeenWelcome = false;

  Future<void> load() async {
    themeMode = await _repository.getThemeMode();
    weekendMode = await _repository.getWeekendMode();
    debugMode = await _repository.getDebugMode();
    autoRefreshMinutes = await _repository.getAutoRefreshMinutes();
    gradeTargets = await _repository.getGradeTargets();
    defaultGradeTarget = await _repository.getDefaultGradeTarget();
    showAttendanceRate = await _repository.getShowAttendanceRate();
    debugUnlocked = await _repository.getDebugUnlocked();
    hasSeenWelcome = await _repository.getHasSeenWelcome();
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    if (themeMode == mode) return;
    await _repository.saveThemeMode(mode);
    themeMode = mode;
    notifyListeners();
  }

  Future<void> setWeekendMode(String mode) async {
    if (weekendMode == mode) return;
    await _repository.saveWeekendMode(mode);
    weekendMode = mode;
    notifyListeners();
  }

  Future<void> setDebugMode(bool enabled) async {
    if (debugMode == enabled) return;
    await _repository.saveDebugMode(enabled);
    debugMode = enabled;
    notifyListeners();
  }

  Future<void> setAutoRefreshMinutes(int minutes) async {
    if (autoRefreshMinutes == minutes) return;
    await _repository.saveAutoRefreshMinutes(minutes);
    autoRefreshMinutes = minutes;
    notifyListeners();
  }

  /// Imposta o rimuove (null) il target di media di una materia.
  Future<void> setGradeTarget(String subject, double? target) async {
    final updated = Map<String, double>.of(gradeTargets);
    if (target == null) {
      updated.remove(subject);
    } else {
      updated[subject] = target;
    }
    await _repository.saveGradeTargets(updated);
    gradeTargets = updated;
    notifyListeners();
  }

  /// Imposta o rimuove (null) il target globale di media.
  Future<void> setDefaultGradeTarget(double? target) async {
    if (defaultGradeTarget == target) return;
    await _repository.saveDefaultGradeTarget(target);
    defaultGradeTarget = target;
    notifyListeners();
  }

  Future<void> setShowAttendanceRate(bool enabled) async {
    if (showAttendanceRate == enabled) return;
    await _repository.saveShowAttendanceRate(enabled);
    showAttendanceRate = enabled;
    notifyListeners();
  }

  Future<void> unlockDebug() async {
    if (debugUnlocked) return;
    await _repository.saveDebugUnlocked(true);
    debugUnlocked = true;
    notifyListeners();
  }

  Future<void> markWelcomeSeen() async {
    if (hasSeenWelcome) return;
    await _repository.saveHasSeenWelcome(true);
    hasSeenWelcome = true;
    notifyListeners();
  }
}
