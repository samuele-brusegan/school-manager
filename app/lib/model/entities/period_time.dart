class PeriodTime {
  PeriodTime({
    required this.number,
    required this.startMinute,
    required this.endMinute,
    this.weekday = 0,
  }) {
    if (number < 1 || number > 20) {
      throw RangeError.range(number, 1, 20, 'number');
    }
    if (weekday < 0 || weekday > 7) {
      throw RangeError.range(weekday, 0, 7, 'weekday');
    }
    if (startMinute < 0 || endMinute > 1440 || startMinute >= endMinute) {
      throw ArgumentError('Intervallo orario non valido');
    }
  }

  final int number;

  /// Zero means the shared/default bell schedule; 1-7 overrides one weekday.
  final int weekday;
  final int startMinute;
  final int endMinute;

  Map<String, Object?> toMap() => {
        'number': number,
        'weekday': weekday,
        'start_minute': startMinute,
        'end_minute': endMinute,
      };
  factory PeriodTime.fromMap(Map<String, Object?> map) => PeriodTime(
        number: map['number']! as int,
        weekday: map['weekday'] as int? ?? 0,
        startMinute: map['start_minute']! as int,
        endMinute: map['end_minute']! as int,
      );
}
