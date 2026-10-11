abstract interface class ThemePreferenceRepository {
  Future<bool> getDarkMode();
  Future<void> saveDarkMode(bool enabled);

  /// Giorni del weekend mostrati in agenda: 'all', 'sunday', 'none'.
  Future<String> getWeekendMode();
  Future<void> saveWeekendMode(String mode);
}
