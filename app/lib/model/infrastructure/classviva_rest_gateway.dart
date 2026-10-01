import 'dart:convert';

import 'package:http/http.dart' as http;

import '../contracts/classviva_gateway.dart';
import '../contracts/credential_store.dart';
import '../entities/remote_lesson.dart';

class ClassVivaRestGateway implements ClassVivaGateway {
  ClassVivaRestGateway({
    required http.Client client,
    required CredentialStore credentialStore,
    Uri? baseUri,
  })  : _client = client,
        _credentialStore = credentialStore,
        _baseUri = baseUri ?? Uri.https('web.spaggiari.eu', '/rest/');

  final http.Client _client;
  final CredentialStore _credentialStore;
  final Uri _baseUri;
  String? _studentId;
  String? _token;
  static const _headers = {
    'User-Agent': 'zorro/1.0',
    'Z-Dev-ApiKey': '+zorro+',
    'Content-Type': 'application/json',
  };

  @override
  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    final uri = _baseUri.resolve('v1/auth/login');
    final response = await _client
        .post(
          uri,
          headers: _headers,
          body: jsonEncode({'ident': null, 'uid': username, 'pass': password}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _responseMessage(response.body);
      final message = switch (response.statusCode) {
        401 => 'Credenziali ClasseViva non accettate.',
        403 => 'ClasseViva ha rifiutato l’accesso per questo account.',
        400 => 'ClasseViva non ha accettato la richiesta di accesso.',
        _ => 'Errore di accesso ClasseViva (${response.statusCode}).',
      };
      throw ClassVivaException(
        detail == null ? message : '$message\nDettaglio: $detail',
      );
    }
    final body = _decodeObject(response.body);
    final choices = body['choices'];
    if (choices is List && choices.isNotEmpty) {
      throw const ClassVivaException(
        'L’account ClasseViva richiede la scelta del profilo (studente o genitore), non ancora supportata. Usa il codice utente del profilo studente.',
      );
    }
    final token = body['token']?.toString();
    final ident = body['ident']?.toString();
    final student = ident?.replaceAll(RegExp('[^0-9]'), '');
    if (token == null || student == null || student.isEmpty) {
      throw const ClassVivaException(
        'Risposta di accesso ClasseViva non riconosciuta.',
      );
    }
    _token = token;
    _studentId = student;
    await _credentialStore.save(
      studentId: student,
      token: token,
    );
  }

  @override
  Future<List<RemoteLesson>> lessonsBetween(
    DateTime start,
    DateTime end,
  ) async {
    final session = await _credentialStore.read();
    final token = _token ?? session?.$2;
    final student = _studentId ?? session?.$1;
    _token = token;
    _studentId = student;
    if (token == null || student == null) {
      throw const ClassVivaException(
        'Sessione ClasseViva non disponibile: effettua nuovamente l’accesso.',
      );
    }
    final startText = _datePath(start);
    final endText = _datePath(end);
    final uri = _baseUri.resolve(
      'v1/students/$student/lessons/$startText/$endText',
    );
    final response = await _client.get(uri, headers: {
      ..._headers,
      'Z-Auth-Token': token
    }).timeout(const Duration(seconds: 15));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ClassVivaException(
        'ClasseViva ha rifiutato la sessione o non abilita questo account.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const ClassVivaException(
        'Impossibile recuperare le lezioni da ClasseViva.',
      );
    }
    final root = jsonDecode(response.body);
    final rows = root is List ? root : (root is Map ? root['lessons'] : null);
    if (rows is! List) {
      throw const ClassVivaException(
        'Formato delle lezioni ClasseViva non riconosciuto.',
      );
    }
    return rows
        .whereType<Map>()
        .map(_parseLesson)
        .whereType<RemoteLesson>()
        .toList();
  }

  @override
  Future<void> signOut() async {
    _studentId = null;
    _token = null;
    await _credentialStore.clear();
  }

  RemoteLesson? _parseLesson(Map row) {
    final date = DateTime.tryParse('${row['evtDate'] ?? row['date'] ?? ''}');
    final subject = (row['subjectDesc'] ?? row['subjectName'] ?? row['subject'])
        ?.toString();
    final eventCode = row['evtCode']?.toString();
    final period = int.tryParse('${row['evtHPos'] ?? ''}');
    final duration = int.tryParse('${row['evtDuration'] ?? 1}');
    if (date == null ||
        subject == null ||
        period == null ||
        duration == null ||
        eventCode != 'LSF0') {
      return null;
    }
    return RemoteLesson(
      date: date,
      subjectName: subject,
      periodNumber: period,
      duration: duration,
    );
  }

  Map _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const ClassVivaException(
        'Risposta di accesso ClasseViva non valida.',
      );
    }
    return decoded;
  }

  String? _responseMessage(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final value = decoded['error'] ?? decoded['message'] ?? decoded['msg'];
        if (value != null) return value.toString();
      }
    } on FormatException {
      // Avoid showing raw HTML or a complete server response in the UI.
    }
    return null;
  }

  String _datePath(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
}
