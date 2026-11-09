class StudyTask {
  const StudyTask({
    required this.id,
    required this.title,
    required this.dueDate,
    this.subject = '',
    this.startMinute,
    this.endMinute,
    this.isDone = false,
  });

  final String id;
  final String title;
  final DateTime dueDate;
  final String subject;

  /// Minuti del giorno (0-1439) in cui si svolge il compito; null se
  /// è un compito "di giornata" senza orario.
  final int? startMinute;
  final int? endMinute;
  final bool isDone;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'due_date': dueDate.toIso8601String(),
        'subject': subject,
        'start_minute': startMinute,
        'end_minute': endMinute,
        'is_done': isDone ? 1 : 0,
      };

  factory StudyTask.fromMap(Map<String, Object?> map) => StudyTask(
        id: map['id']! as String,
        title: map['title']! as String,
        dueDate: DateTime.parse(map['due_date']! as String),
        subject: map['subject'] as String? ?? '',
        startMinute: map['start_minute'] as int?,
        endMinute: map['end_minute'] as int?,
        isDone: map['is_done'] == 1,
      );
}
