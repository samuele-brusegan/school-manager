abstract interface class ThemePreferenceRepository {
  /// Tema dell'app: 'system' (predefinito), 'light' o 'dark'.
  Future<String> getThemeMode();
  Future<void> saveThemeMode(String mode);

  /// Giorni del weekend mostrati in agenda: 'all', 'sunday', 'none'.
  Future<String> getWeekendMode();
  Future<void> saveWeekendMode(String mode);

  /// Overlay di debug: mostra i metadati grezzi ovunque nell'app.
  Future<bool> getDebugMode();
  Future<void> saveDebugMode(bool enabled);

  /// Intervallo di aggiornamento automatico dei dati ClasseViva in minuti;
  /// 0 disattiva l'aggiornamento automatico.
  Future<int> getAutoRefreshMinutes();
  Future<void> saveAutoRefreshMinutes(int minutes);

  /// Obiettivi di media per materia (chiave = nome materia ClasseViva).
  Future<Map<String, double>> getGradeTargets();
  Future<void> saveGradeTargets(Map<String, double> targets);

  /// Obiettivo di media globale, usato per le materie senza override.
  Future<double?> getDefaultGradeTarget();
  Future<void> saveDefaultGradeTarget(double? target);

  /// Mostra la percentuale di assenze nella pagina Presenze.
  Future<bool> getShowAttendanceRate();
  Future<void> saveShowAttendanceRate(bool enabled);

  /// Pagina Debug sbloccata (7 tocchi sulla versione in Info).
  Future<bool> getDebugUnlocked();
  Future<void> saveDebugUnlocked(bool unlocked);

  /// Il tutorial di benvenuto è già stato mostrato al primo avvio.
  Future<bool> getHasSeenWelcome();
  Future<void> saveHasSeenWelcome(bool seen);
}
