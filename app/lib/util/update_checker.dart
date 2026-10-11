import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Esito del controllo aggiornamenti su GitHub Releases.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.url});
  final String version;
  final Uri url;
}

/// Controlla l'ultima release pubblicata su GitHub e la confronta con la
/// versione installata. Restituisce null se non ci sono aggiornamenti o
/// in caso di errore di rete (il controllo non deve mai bloccare l'app).
class UpdateChecker {
  UpdateChecker({required this.repo, http.Client? client})
      : _client = client ?? http.Client();
  final String repo;
  final http.Client _client;

  Future<UpdateInfo?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final response = await _client
          .get(Uri.https('api.github.com', '/repos/$repo/releases/latest'),
              headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      if (body is! Map) return null;
      final tag = body['tag_name']?.toString() ?? '';
      final latest = _normalize(tag);
      final url = body['html_url']?.toString() ??
          'https://github.com/$repo/releases/latest';
      if (latest == null || !_isNewer(latest, _normalize(info.version) ?? info.version)) {
        return null;
      }
      return UpdateInfo(version: tag.isEmpty ? latest : tag, url: Uri.parse(url));
    } on Object {
      return null;
    }
  }

  static String? _normalize(String value) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(value);
    return match?.group(0);
  }

  static bool _isNewer(String latest, String current) {
    final a = latest.split('.').map(int.tryParse).toList();
    final b = current.split('.').map(int.tryParse).toList();
    for (var index = 0; index < 3; index++) {
      final va = index < a.length ? a[index] ?? 0 : 0;
      final vb = index < b.length ? b[index] ?? 0 : 0;
      if (va != vb) return va > vb;
    }
    return false;
  }
}
