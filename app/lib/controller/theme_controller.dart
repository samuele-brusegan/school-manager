import 'package:flutter/foundation.dart';

import '../model/contracts/theme_preference_repository.dart';

class ThemeController extends ChangeNotifier {
  ThemeController(this._repository);

  final ThemePreferenceRepository _repository;
  bool isDarkMode = false;

  /// Giorni del weekend visibili in agenda: 'all', 'sunday' o 'none'.
  String weekendMode = 'all';

  Future<void> load() async {
    isDarkMode = await _repository.getDarkMode();
    weekendMode = await _repository.getWeekendMode();
    notifyListeners();
  }

  Future<void> setDarkMode(bool enabled) async {
    if (isDarkMode == enabled) return;
    await _repository.saveDarkMode(enabled);
    isDarkMode = enabled;
    notifyListeners();
  }

  Future<void> setWeekendMode(String mode) async {
    if (weekendMode == mode) return;
    await _repository.saveWeekendMode(mode);
    weekendMode = mode;
    notifyListeners();
  }
}
