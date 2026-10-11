import '../entities/remote_lesson.dart';

class ClassVivaException implements Exception {
  const ClassVivaException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class ClassVivaGateway {
  Future<void> signIn({required String username, required String password});
  Future<List<RemoteLesson>> lessonsBetween(DateTime start, DateTime end);
  Future<bool> hasSession();
  Future<void> signOut();
}
