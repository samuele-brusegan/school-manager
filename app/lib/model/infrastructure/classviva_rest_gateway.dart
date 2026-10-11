import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../contracts/classviva_gateway.dart';
import '../contracts/classviva_data_gateway.dart';
import '../contracts/credential_store.dart';
import '../entities/classviva_record.dart';
import '../entities/remote_lesson.dart';

class ClassVivaRestGateway implements ClassVivaGateway, ClassVivaDataGateway {
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
    'User-Agent': 'CVVS/std/4.1.7 Android/10',
    'Z-Dev-ApiKey': 'Tg1NWEwNGIgIC0K',
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
    _debugResponse('login', response);
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
    if (response.body.trim().isEmpty) {
      throw ClassVivaException(
        'ClasseViva ha risposto al login con HTTP ${response.statusCode} senza un token o un corpo JSON.',
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
      username: username,
      password: password,
      expiresAt: DateTime.tryParse(body['expire']?.toString() ?? ''),
    );
  }

  /// Sessione valida (studente, token): rinnova il token se scaduto o
  /// prossimo alla scadenza, riautenticandosi con le credenziali salvate.
  Future<(String, String)> _session() async {
    final stored = await _credentialStore.read();
    _token ??= stored?.$2;
    _studentId ??= stored?.$1;
    if (_token != null && _studentId != null) {
      final expiry = await _credentialStore.readExpiry();
      final stale = expiry != null &&
          expiry.isBefore(DateTime.now().add(const Duration(minutes: 1)));
      if (!stale) return (_studentId!, _token!);
      _token = null;
      if (await _reauthenticate()) return (_studentId!, _token!);
    }
    throw const ClassVivaException(
      'Sessione ClasseViva non disponibile: effettua nuovamente l’accesso.',
    );
  }

  /// Riprova il login con le credenziali salvate. Falso se non ci sono
  /// credenziali o il server le rifiuta: l'utente dovrà rifare l'accesso.
  Future<bool> _reauthenticate() async {
    final credentials = await _credentialStore.readCredentials();
    if (credentials == null) return false;
    try {
      await signIn(username: credentials.$1, password: credentials.$2);
      return true;
    } on Object {
      _token = null;
      return false;
    }
  }

  @override
  Future<List<RemoteLesson>> lessonsBetween(
    DateTime start,
    DateTime end,
  ) async {
    var (student, token) = await _session();
    final startText = _datePath(start);
    final endText = _datePath(end);
    final uri = _baseUri.resolve(
      'v1/students/$student/lessons/$startText/$endText',
    );
    Future<http.Response> fetch() =>
        _client.get(uri, headers: {
          ..._headers,
          'Z-Auth-Token': token
        }).timeout(const Duration(seconds: 15));
    var response = await fetch();
    _debugResponse('lezioni', response);
    if (response.statusCode == 401 && await _reauthenticate()) {
      (student, token) = (_studentId!, _token!);
      response = await fetch();
      _debugResponse('lezioni (riautenticata)', response);
    }
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
  Future<List<ClassVivaRecord>> records(
    ClassVivaSection section, {
    DateTime? start,
    DateTime? end,
  }) async {
    var (student, token) = await _session();

    final rangePath = start != null && end != null
        ? '/${_datePath(start)}/${_datePath(end)}'
        : '';
    final path = switch (section) {
      ClassVivaSection.agenda => 'v1/students/$student/agenda/all$rangePath',
      ClassVivaSection.grades => 'v1/students/$student/grades',
      ClassVivaSection.attendance =>
        'v1/students/$student/absences/details$rangePath',
      ClassVivaSection.notes => 'v1/students/$student/notes/all',
      ClassVivaSection.noticeboard => 'v1/students/$student/noticeboard',
      ClassVivaSection.didactics => 'v1/students/$student/didactics',
      ClassVivaSection.documents => 'v1/students/$student/documents',
      ClassVivaSection.schoolbooks => 'v1/students/$student/schoolbooks',
    };
    final uri = _baseUri.resolve(path);
    Future<http.Response> fetch() {
      final headers = {..._headers, 'Z-Auth-Token': token};
      return section == ClassVivaSection.documents
          ? _client
              .post(uri, headers: headers, body: jsonEncode({}))
              .timeout(const Duration(seconds: 15))
          : _client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 15));
    }

    var response = await fetch();
    _debugResponse('registro ${section.name}', response);
    if (response.statusCode == 401 && await _reauthenticate()) {
      (student, token) = (_studentId!, _token!);
      response = await fetch();
      _debugResponse('registro ${section.name} (riautenticata)', response);
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const ClassVivaException(
        'ClasseViva non abilita questa sezione per l’account collegato.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ClassVivaException(
        'Impossibile recuperare ${_sectionLabel(section)} da ClasseViva (${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(response.body);
    final rows = _recordRows(decoded).expand(_flattenNestedRecord).toList();
    return [
      for (var index = 0; index < rows.length; index++)
        _recordFromMap(section, rows[index], index),
    ];
  }

  List<Map> _recordRows(Object? value) {
    if (value is List) return value.whereType<Map>().toList();
    if (value is! Map) return const [];
    const wrappers = {
      'agenda',
      'grades',
      'absences',
      'notes',
      'noticeboard',
      'didactics',
      'documents',
      'schoolbooks',
      'items',
      'data',
      'events',
      'lessons',
      'rows',
      'results',
      'subjects',
      'content',
      'didacticts',
    };
    for (final key in wrappers) {
      final child = value[key];
      if (child is List) return child.whereType<Map>().toList();
      if (child is Map) {
        final nestedRows = child.values
            .whereType<List>()
            .expand((rows) => rows.whereType<Map>())
            .toList();
        if (nestedRows.isNotEmpty) return nestedRows;
      }
    }
    final nestedRows = value.values
        .whereType<List>()
        .expand((rows) => rows.whereType<Map>())
        .toList();
    if (nestedRows.isNotEmpty) return nestedRows;
    return [value];
  }

  Iterable<Map> _flattenNestedRecord(Map row, [Map context = const {}]) {
    const childCollections = {'books', 'folders', 'contents'};
    for (final key in childCollections) {
      final children = row[key];
      if (children is! List || children.whereType<Map>().isEmpty) continue;
      final inherited = <String, Object?>{
        ...context,
        for (final field in const [
          'subjectDesc',
          'courseDesc',
          'teacherName',
          'folderName'
        ])
          if (row[field] != null) field: row[field],
      };
      return children
          .whereType<Map>()
          .expand((child) => _flattenNestedRecord(child, inherited));
    }
    return [
      {
        ...context,
        for (final entry in row.entries)
          if (!childCollections.contains(entry.key.toString()))
            entry.key.toString(): entry.value,
      }
    ];
  }

  ClassVivaRecord _recordFromMap(
    ClassVivaSection section,
    Map row,
    int index,
  ) {
    String? first(Iterable<String> keys) {
      for (final key in keys) {
        final value = row[key];
        if (value == null || value.toString().trim().isEmpty) continue;
        return value.toString().trim();
      }
      return null;
    }

    final codeTitle = switch (row['evtCode']?.toString()) {
      'ABA0' => 'Assenza',
      'ABU0' => 'Ritardo o uscita anticipata',
      'AGHW' => 'Compiti',
      'AGNT' => 'Agenda',
      _ => null,
    };
    final title = first(const [
          'evtTitle',
          'title',
          'cntTitle',
          'homeworkDesc',
          'contentName',
          'subjectDesc',
          'subjectName',
          'subject',
          'gradeDesc',
          'description',
          'text',
          'note',
          'notes',
          'folderName',
          'name',
          'documentName',
          'bookTitle',
          'materialName',
        ]) ??
        codeTitle ??
        _sectionLabel(section);
    final subtitle = first(const [
          'evtText',
          'description',
          'displayValue',
          'decimalValue',
          'gradeValue',
          'vote',
          'value',
          'evtValue',
          'teacherDesc',
          'authorName',
          'evtAuthor',
          'noteText',
          'comment',
          'justifReasonDesc',
          'periodDesc',
          'isbnCode',
          'author',
          'publisher',
          'fileName',
        ]) ??
        first(const [
          'subjectDesc',
          'subjectName',
          'teacher',
          'teacherName',
          'isJustified',
          'status'
        ]) ??
        '';
    // Per gli eventi con orario (agenda) il giorno corretto è quello
    // locale di evtDatetimeBegin: evtDate può riportare il giorno UTC,
    // spostando l'evento sul giorno precedente.
    final beginDate = _parseRecordDate(first(const ['evtDatetimeBegin']));
    final rawDate = first(const [
      'evtDate',
      'pubDT',
      'assignmentDate',
      'expiryDate',
      'shareDT',
      'date',
      'dateTime',
      'evtDatetime',
      'eventDate',
      'gradeDate',
      'insertDate',
    ]);
    final parsedDate = _parseRecordDate(rawDate);
    final date = beginDate != null
        ? DateTime(beginDate.year, beginDate.month, beginDate.day)
        : parsedDate;
    final values = <String, Object?>{
      for (final entry in row.entries)
        entry.key.toString(): _jsonSafe(entry.value),
    };
    return ClassVivaRecord(
      id: first(const ['evtId', 'id', 'pubId', 'gradeId', 'contentId']) ??
          '${section.name}-$index-${title.hashCode}',
      section: section.name,
      title: title,
      subtitle: subtitle,
      date: date,
      values: values,
    );
  }

  Object? _jsonSafe(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is List) return value.map(_jsonSafe).toList();
    if (value is Map) {
      return value
          .map((key, child) => MapEntry(key.toString(), _jsonSafe(child)));
    }
    return value.toString();
  }

  DateTime? _parseRecordDate(String? value) {
    if (value == null) return null;
    var parsed = DateTime.tryParse(value);
    if (parsed != null) {
      // Istanti senza fuso dichiarato: ClasseViva li esprime in UTC.
      if (!parsed.isUtc && _hasNoTimezone(value)) {
        parsed = DateTime.tryParse('${value}Z');
      }
      // Le date con fuso orario (es. evtDatetimeBegin) vanno convertite
      // all'ora locale: altrimenti un evento serale UTC cade sul giorno
      // precedente. Le date pure (yyyy-MM-dd) restano invariate.
      return parsed != null && parsed.isUtc ? parsed.toLocal() : parsed;
    }
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 8) {
      return DateTime.tryParse(
        '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6, 8)}',
      );
    }
    return null;
  }

  /// Vero se la stringa data/ora non dichiara alcun fuso orario.
  static bool _hasNoTimezone(String raw) {
    final time = raw.contains('T') ? raw.split('T').last : '';
    return time.isNotEmpty &&
        !time.contains('Z') &&
        !time.contains('+') &&
        !time.contains('-');
  }

  String _sectionLabel(ClassVivaSection section) => switch (section) {
        ClassVivaSection.agenda => 'Impegno',
        ClassVivaSection.grades => 'Valutazione',
        ClassVivaSection.attendance => 'Presenza',
        ClassVivaSection.notes => 'Nota',
        ClassVivaSection.noticeboard => 'Comunicazione',
        ClassVivaSection.didactics => 'Materiale didattico',
        ClassVivaSection.documents => 'Documento',
        ClassVivaSection.schoolbooks => 'Libro di testo',
      };

  @override
  Future<bool> hasSession() async =>
      _token != null || await _credentialStore.read() != null;

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
    final teacher = (row['authorName'] ??
            row['teacherName'] ??
            row['teacherDesc'] ??
            row['author'])
        ?.toString()
        .trim();
    return RemoteLesson(
      date: date,
      subjectName: subject,
      periodNumber: period,
      duration: duration,
      teacherName:
          teacher == null || teacher.isEmpty ? null : teacher,
      subjectId:
          (row['subjectId'] ?? row['subject_id'] ?? row['materiaId'])
              ?.toString(),
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

  void _debugResponse(String operation, http.Response response) {
    if (!kDebugMode) return;
    debugPrint(
      '[ClasseViva] $operation -> HTTP ${response.statusCode} '
      '(${response.bodyBytes.length} byte)',
    );
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
