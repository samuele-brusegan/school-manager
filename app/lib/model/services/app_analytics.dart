/// Stub senza tracciamento: l'app non raccoglie analytics.
/// Mantiene l'API precedente per non dover toccare i call site.
class AppAnalytics {
  const AppAnalytics._();

  bool get enabled => false;

  static Future<AppAnalytics> init() async => const AppAnalytics._();

  Future<void> screenView(String name) async {}

  Future<void> event(String name, [Map<String, Object>? params]) async {}
}
