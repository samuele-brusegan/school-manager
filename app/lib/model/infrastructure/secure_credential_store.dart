import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../contracts/credential_store.dart';

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _studentIdKey = 'classeviva.student_id';
  static const _tokenKey = 'classeviva.token';
  static const _usernameKey = 'classeviva.username';
  static const _passwordKey = 'classeviva.password';
  static const _expiryKey = 'classeviva.token_expiry';

  @override
  Future<void> save({
    required String studentId,
    required String token,
    String? username,
    String? password,
    DateTime? expiresAt,
  }) async {
    await _storage.write(key: _studentIdKey, value: studentId);
    await _storage.write(key: _tokenKey, value: token);
    if (username != null) {
      await _storage.write(key: _usernameKey, value: username);
    }
    if (password != null) {
      await _storage.write(key: _passwordKey, value: password);
    }
    if (expiresAt != null) {
      await _storage.write(
          key: _expiryKey, value: expiresAt.toIso8601String());
    }
  }

  @override
  Future<(String, String)?> read() async {
    final studentId = await _storage.read(key: _studentIdKey);
    final token = await _storage.read(key: _tokenKey);
    if (studentId == null || token == null) return null;
    return (studentId, token);
  }

  @override
  Future<(String, String)?> readCredentials() async {
    final username = await _storage.read(key: _usernameKey);
    final password = await _storage.read(key: _passwordKey);
    if (username == null || password == null) return null;
    return (username, password);
  }

  @override
  Future<DateTime?> readExpiry() async {
    final raw = await _storage.read(key: _expiryKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _studentIdKey);
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _passwordKey);
    await _storage.delete(key: _expiryKey);
  }
}
