import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../contracts/credential_store.dart';

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _studentIdKey = 'classeviva.student_id';
  static const _tokenKey = 'classeviva.token';

  @override
  Future<void> save({
    required String studentId,
    required String token,
  }) async {
    await _storage.write(key: _studentIdKey, value: studentId);
    await _storage.write(key: _tokenKey, value: token);
  }

  @override
  Future<(String, String)?> read() async {
    final studentId = await _storage.read(key: _studentIdKey);
    final token = await _storage.read(key: _tokenKey);
    if (studentId == null || token == null) return null;
    return (studentId, token);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _studentIdKey);
    await _storage.delete(key: _tokenKey);
  }
}
