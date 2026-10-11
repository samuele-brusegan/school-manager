class ClassVivaRecord {
  const ClassVivaRecord({
    required this.id,
    required this.section,
    required this.title,
    required this.subtitle,
    this.date,
    required this.values,
  });

  final String id;
  final String section;
  final String title;
  final String subtitle;
  final DateTime? date;
  final Map<String, Object?> values;

  String? get subjectName => _firstValue(const [
        'subjectDesc',
        'subjectName',
        'subject',
      ]);

  String? get teacherName => _firstValue(const [
        'teacherName',
        'teacherDesc',
        'authorName',
        'evtAuthor',
        'author',
      ]);

  /// Testo libero dell'evento (contenuto della verifica, dei compiti, ecc.).
  String? get content => _firstValue(const [
        'evtText',
        'notes',
        'noteText',
        'description',
        'homeworkDesc',
      ]);

  /// Tipo dell'evento di agenda derivato dal codice ClasseViva
  /// (AGHW = compiti, AGNT = note/annunci, AGCR = altri eventi).
  String? get typeLabel {
    final code = values['evtCode']?.toString().trim().toUpperCase();
    return switch (code) {
      'AGHW' => 'Compiti',
      'AGNT' => 'Note',
      'AGCR' => 'Altro evento',
      '' || null => null,
      _ => code,
    };
  }

  DateTime? get begin => _dateTimeValue('evtDatetimeBegin');
  DateTime? get end => _dateTimeValue('evtDatetimeEnd');

  String? _firstValue(List<String> keys) {
    for (final key in keys) {
      final value = values[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  DateTime? _dateTimeValue(String key) {
    final raw = values[key]?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    var parsed = DateTime.tryParse(raw);
    if (parsed != null && !parsed.isUtc && _hasNoTimezone(raw)) {
      // ClasseViva invia gli istanti in UTC; una stringa senza fuso va
      // interpretata come UTC, altrimenti un inizio serale (22:00/23:00)
      // slitta l'evento sul giorno precedente.
      parsed = DateTime.tryParse('${raw}Z');
    }
    return parsed?.toLocal();
  }

  /// Vero se la stringa data/ora non dichiara alcun fuso orario.
  static bool _hasNoTimezone(String raw) {
    final time = raw.contains('T') ? raw.split('T').last : '';
    return time.isNotEmpty &&
        !time.contains('Z') &&
        !time.contains('+') &&
        !time.contains('-');
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'section': section,
        'title': title,
        'subtitle': subtitle,
        'date': date?.toIso8601String(),
        'values': values,
      };

  factory ClassVivaRecord.fromMap(Map<String, Object?> map) => ClassVivaRecord(
        id: map['id']! as String,
        section: map['section']! as String,
        title: map['title']! as String,
        subtitle: map['subtitle']! as String,
        date: DateTime.tryParse(map['date']?.toString() ?? ''),
        values: (map['values'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value),
            ) ??
            const {},
      );
}
