import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:school_manager/model/contracts/classviva_gateway.dart';
import 'package:school_manager/model/contracts/credential_store.dart';
import 'package:school_manager/model/infrastructure/classviva_rest_gateway.dart';

void main() {
  test(
    'authenticates, derives student id, and parses lesson period fields',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/v1/auth/login')) {
          return http.Response(
            jsonEncode({'ident': 'S123456X', 'token': 'test-token'}),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'lessons': [
              {
                'evtDate': '2026-09-21',
                'evtCode': 'LSF0',
                'evtHPos': 2,
                'evtDuration': 1,
                'subjectDesc': 'MATEMATICA',
              },
              {
                'evtDate': '2026-09-21',
                'evtCode': 'LSS0',
                'evtHPos': 2,
                'evtDuration': 1,
                'subjectDesc': 'SOSTEGNO',
              },
            ],
          }),
          200,
        );
      });
      final store = _MemoryCredentialStore();
      final gateway = ClassVivaRestGateway(
        client: client,
        credentialStore: store,
      );
      await gateway.signIn(username: 'S123456X', password: 'secret');
      final lessons = await gateway.lessonsBetween(
        DateTime(2026, 9, 21),
        DateTime(2026, 9, 27),
      );

      expect(jsonDecode(requests.first.body), {
        'ident': null,
        'uid': 'S123456X',
        'pass': 'secret',
      });
      expect(requests.first.headers['Z-Dev-ApiKey'], 'Tg1NWEwNGIgIC0K');
      expect(
        requests[1].url.path,
        '/rest/v1/students/123456/lessons/20260921/20260927',
      );
      expect(requests[1].headers['Z-Auth-Token'], 'test-token');
      expect(lessons, hasLength(1));
      expect(lessons.single.periodNumber, 2);
      expect(lessons.single.subjectName, 'MATEMATICA');
      final restoredGateway = ClassVivaRestGateway(
        client: client,
        credentialStore: store,
      );
      final restoredLessons = await restoredGateway.lessonsBetween(
        DateTime(2026, 9, 21),
        DateTime(2026, 9, 27),
      );
      expect(restoredLessons, hasLength(1));
      expect(requests.last.headers['Z-Auth-Token'], 'test-token');
    },
  );

  test('reports an expired or unsupported session', () async {
    final client = MockClient((_) async => http.Response('denied', 401));
    final store = _MemoryCredentialStore()
      ..studentId = '123456'
      ..token = 'expired';
    final gateway = ClassVivaRestGateway(
      client: client,
      credentialStore: store,
    );
    await expectLater(
      gateway.lessonsBetween(DateTime(2026, 9, 21), DateTime(2026, 9, 27)),
      throwsA(isA<ClassVivaException>()),
    );
  });
}

class _MemoryCredentialStore implements CredentialStore {
  String? studentId;
  String? token;
  @override
  Future<void> clear() async {
    studentId = null;
    token = null;
  }

  @override
  Future<(String, String)?> read() async =>
      token == null || studentId == null ? null : (studentId!, token!);
  @override
  Future<void> save({
    required String studentId,
    required String token,
  }) async {
    this.studentId = studentId;
    this.token = token;
  }
}
