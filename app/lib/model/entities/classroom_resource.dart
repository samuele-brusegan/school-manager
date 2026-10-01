enum ResourceCategory { room, teacher }

enum RoomType { classroom, laboratory }

enum TeacherType { teacher, itp }

class ClassroomResource {
  const ClassroomResource(
      {required this.id,
      required this.name,
      required this.category,
      required this.type});
  final String id;
  final String name;
  final ResourceCategory category;

  /// For rooms: classroom/laboratory. For teachers: teacher/itp.
  final String type;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'category': category.name,
        'type': type,
      };

  factory ClassroomResource.fromMap(Map<String, Object?> map) =>
      ClassroomResource(
        id: map['id']! as String,
        name: map['name']! as String,
        category: ResourceCategory.values.byName(map['category']! as String),
        type: map['type']! as String,
      );
}
