abstract interface class CredentialStore {
  Future<void> save({
    required String studentId,
    required String token,
  });
  Future<(String, String)?> read();
  Future<void> clear();
}
