import 'dart:convert';

class Subject {
  Subject({
    required this.id,
    required String name,
    this.colorValue = 0xFF6750A4,
    this.classvivaId = '',
    List<String> teachers = const [],
    List<String> rooms = const [],
  }) : name = name.trim() {
    if (this.name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Materia vuota');
    }
    this.teachers = List.unmodifiable(_clean(teachers));
    this.rooms = List.unmodifiable(_clean(rooms));
  }

  final String id;
  final String name;
  final int colorValue;
  final String classvivaId;
  late final List<String> teachers;
  late final List<String> rooms;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'color_value': colorValue,
        'classviva_id': classvivaId,
        'teachers_json': jsonEncode(teachers),
        'rooms_json': jsonEncode(rooms),
      };

  factory Subject.fromMap(Map<String, Object?> map) => Subject(
        id: map['id']! as String,
        name: map['name']! as String,
        colorValue: map['color_value']! as int,
        classvivaId: map['classviva_id'] as String? ?? '',
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
