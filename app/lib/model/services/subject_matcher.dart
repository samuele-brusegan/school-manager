import '../entities/subject.dart';

/// Collega un nome di materia remoto (ClasseViva) a una [Subject] locale.
/// Prima controlla il `classvivaId` configurato, poi il nome normalizzato,
/// infine la corrispondenza parziale.
class SubjectMatcher {
  SubjectMatcher(List<Subject> subjects)
      : _subjects = List.unmodifiable(subjects);

  final List<Subject> _subjects;

  Subject? match(String remoteName) {
    final normalized = _normalize(remoteName);
    if (normalized.isEmpty) return null;
    for (final subject in _subjects) {
      if (subject.classvivaId.isNotEmpty &&
          _normalize(subject.classvivaId) == normalized) {
        return subject;
      }
    }
    for (final subject in _subjects) {
      if (_normalize(subject.name) == normalized) return subject;
    }
    for (final subject in _subjects) {
      final local = _normalize(subject.name);
      if (normalized.contains(local) || local.contains(normalized)) {
        return subject;
      }
    }
    return null;
  }

  /// Cerca una materia per identificativo remoto (classvivaId o id locale).
  Subject? matchId(String remoteId) {
    final normalized = _normalize(remoteId);
    if (normalized.isEmpty) return null;
    for (final subject in _subjects) {
      if (subject.classvivaId.isNotEmpty &&
          _normalize(subject.classvivaId) == normalized) {
        return subject;
      }
      if (subject.id == remoteId) return subject;
    }
    return null;
  }

  static String _normalize(String value) => value
      .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9àèéìòù]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
