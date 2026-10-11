class RemoteLesson {
  const RemoteLesson({
    required this.date,
    required this.subjectName,
    required this.periodNumber,
    this.duration = 1,
    this.teacherName,
    this.subjectId,
  });

  final DateTime date;
  final String subjectName;
  final int periodNumber;
  final int duration;
  final String? teacherName;

  /// ID numerico della materia su ClasseViva (mapping stabile).
  final String? subjectId;
}
