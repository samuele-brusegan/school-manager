class StudyTask {
  const StudyTask({
    required this.id,
    required this.title,
    required this.dueDate,
    this.subject = '',
    this.isDone = false,
  });

  final String id;
  final String title;
  final DateTime dueDate;
  final String subject;
  final bool isDone;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'due_date': dueDate.toIso8601String(),
        'subject': subject,
        'is_done': isDone ? 1 : 0,
      };

  factory StudyTask.fromMap(Map<String, Object?> map) => StudyTask(
        id: map['id']! as String,
        title: map['title']! as String,
        dueDate: DateTime.parse(map['due_date']! as String),
        subject: map['subject'] as String? ?? '',
        isDone: map['is_done'] == 1,
      );
}
