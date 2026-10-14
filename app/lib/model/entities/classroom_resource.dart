import 'dart:convert';

enum ResourceCategory { room, teacher }

enum RoomType { classroom, laboratory }

enum TeacherType { teacher, itp }

/// Chiavi riconosciute in [ClassroomResource.meta] per i docenti.
class TeacherMeta {
  TeacherMeta._();
  static const email = 'email';
  static const phone = 'phone';
  static const birthday = 'birthday'; // 'YYYY-MM-DD'
  static const notes = 'notes';
}

class ClassroomResource {
  const ClassroomResource(
      {required this.id,
      required this.name,
      required this.category,
      required this.type,
      this.meta = const {}});
  final String id;
  final String name;
  final ResourceCategory category;

  /// For rooms: classroom/laboratory. For teachers: teacher/itp.
  final String type;

  /// Metadati facoltativi (docenti: email, telefono, compleanno, note).
  final Map<String, String> meta;

  String? get email => meta[TeacherMeta.email];
  String? get phone => meta[TeacherMeta.phone];

  /// Compleanno del docente ('YYYY-MM-DD'), null se assente o invalido.
  DateTime? get birthday {
    final raw = meta[TeacherMeta.birthday];
    return raw == null ? null : DateTime.tryParse(raw);
  }

  String? get notes => meta[TeacherMeta.notes];

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'category': category.name,
        'type': type,
        'meta_json': jsonEncode(meta),
      };

  factory ClassroomResource.fromMap(Map<String, Object?> map) =>
      ClassroomResource(
        id: map['id']! as String,
        name: map['name']! as String,
        category: ResourceCategory.values.byName(map['category']! as String),
        type: map['type']! as String,
        meta: _metaFromJson(map['meta_json']),
      );

  static Map<String, String> _metaFromJson(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value.toString(),
      };
    } on Object {
      return const {};
    }
  }
}
