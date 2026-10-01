class RemoteLesson {
  const RemoteLesson({
    required this.date,
    required this.subjectName,
    required this.periodNumber,
    this.duration = 1,
  });

  final DateTime date;
  final String subjectName;
  final int periodNumber;
  final int duration;
}
