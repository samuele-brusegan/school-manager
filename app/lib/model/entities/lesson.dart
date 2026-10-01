import 'dart:convert';

class Lesson {
  Lesson({
    required this.id,
    required this.subjectId,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    this.startPeriod,
    this.endPeriod,
    List<String> teachers = const [],
    List<String> rooms = const [],
  }) {
    if (weekday < 1 || weekday > 7) {
      throw RangeError.range(weekday, 1, 7, 'weekday');
    }
    if (startMinute < 0 || endMinute > 1440 || startMinute >= endMinute) {
      throw ArgumentError('Intervallo orario non valido');
    }
    if ((startPeriod == null) != (endPeriod == null) ||
        (startPeriod != null &&
            (startPeriod! < 1 || endPeriod! <= startPeriod!))) {
      throw ArgumentError('Numero delle ore scolastiche non valido');
    }
    this.teachers = List.unmodifiable(_clean(teachers));
    this.rooms = List.unmodifiable(_clean(rooms));
  }

  final String id;
  final String subjectId;
  final int weekday;
  final int startMinute;
  final int endMinute;
  final int? startPeriod;
  final int? endPeriod;
  late final List<String> teachers;
  late final List<String> rooms;

  bool overlaps(Lesson other) =>
      weekday == other.weekday &&
      startMinute < other.endMinute &&
      other.startMinute < endMinute;

  Map<String, Object?> toMap() => {
        'id': id,
        'subject_id': subjectId,
        'weekday': weekday,
        'start_minute': startMinute,
        'end_minute': endMinute,
        'start_period': startPeriod,
        'end_period': endPeriod,
        'teachers_json': jsonEncode(teachers),
        'rooms_json': jsonEncode(rooms),
      };

  factory Lesson.fromMap(Map<String, Object?> map) => Lesson(
        id: map['id']! as String,
        subjectId: map['subject_id']! as String,
        weekday: map['weekday']! as int,
        startMinute: map['start_minute']! as int,
        endMinute: map['end_minute']! as int,
        startPeriod: map['start_period'] as int?,
        endPeriod: map['end_period'] as int?,
        teachers: _decodeNames(map['teachers_json']),
        rooms: _decodeNames(map['rooms_json']),
      );

  static List<String> _clean(List<String> values) => values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  static List<String> _decodeNames(Object? value) {
    if (value == null) return const [];
    try {
      final decoded = jsonDecode(value as String);
      return decoded is List ? decoded.whereType<String>().toList() : const [];
    } on FormatException {
      return const [];
    }
  }
}
