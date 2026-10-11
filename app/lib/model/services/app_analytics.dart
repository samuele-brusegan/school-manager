import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Wrapper opzionale su Firebase Analytics: senza `google-services.json`
/// l'inizializzazione fallisce e l'app continua senza tracciare nulla.
class AppAnalytics {
  AppAnalytics._(this._analytics);

  final FirebaseAnalytics? _analytics;

  bool get enabled => _analytics != null;

  /// Prova ad attivare Firebase; in assenza di configurazione nativa
  /// (google-services.json / GoogleService-Info.plist) resta disattivo.
  static Future<AppAnalytics> init() async {
    try {
      await Firebase.initializeApp();
      return AppAnalytics._(FirebaseAnalytics.instance);
    } on Object catch (error) {
      debugPrint('[Analytics] Firebase non disponibile: $error');
      return AppAnalytics._(null);
    }
  }

  Future<void> screenView(String name) async {
    if (_analytics == null) return;
    try {
      await _analytics.logScreenView(screenName: name);
    } on Object {
      // Analytics non deve mai bloccare l'app.
    }
  }

  Future<void> event(String name, [Map<String, Object>? params]) async {
    if (_analytics == null) return;
    try {
      await _analytics.logEvent(name: name, parameters: params);
    } on Object {
      // Analytics non deve mai bloccare l'app.
    }
  }
}
