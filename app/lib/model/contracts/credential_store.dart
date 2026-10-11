abstract interface class CredentialStore {
  Future<void> save({
    required String studentId,
    required String token,
    String? username,
    String? password,
    DateTime? expiresAt,
  });
  Future<(String, String)?> read();

  /// Credenziali per la riautenticazione automatica a token scaduto.
  Future<(String, String)?> readCredentials();

  /// Scadenza del token salvato, null se sconosciuta.
  Future<DateTime?> readExpiry();
  Future<void> clear();
}
