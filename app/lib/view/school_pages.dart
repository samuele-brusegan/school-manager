import 'package:flutter/material.dart';

import '../controller/school_data_controller.dart';
import '../controller/timetable_controller.dart';
import '../model/contracts/classviva_data_gateway.dart';
import '../model/entities/classviva_record.dart';
import '../model/entities/lesson.dart';
import '../model/entities/subject.dart';
import '../model/services/subject_matcher.dart';
import 'app_palette.dart';
import 'agenda_view.dart';
import 'classviva_login_view.dart';
export 'agenda_view.dart';

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.timetableController,
    required this.schoolDataController,
  });

  final TimetableController timetableController;
  final SchoolDataController schoolDataController;

  /// Primo giorno successivo a oggi con lezioni in orario
  /// (sabato/dom → lunedì, venerdì → lunedì, ecc.).
  (DateTime, List<Lesson>) _nextSchoolDay(DateTime now) {
    final lessons = timetableController.timetable?.lessons ?? const <Lesson>[];
    for (var offset = 1; offset <= 7; offset++) {
      final day = now.add(Duration(days: offset));
      final dayLessons = lessons
          .where((lesson) => lesson.weekday == day.weekday)
          .toList()
        ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
      if (dayLessons.isNotEmpty) {
        return (DateTime(day.year, day.month, day.day), dayLessons);
      }
    }
    return (now.add(const Duration(days: 1)), const <Lesson>[]);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge(
            [timetableController, schoolDataController]),
        builder: (context, _) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final timetable = timetableController.timetable;
          final subjects = {
            for (final subject in timetable?.subjects ?? const <Subject>[])
              subject.id: subject,
          };
          final matcher = SubjectMatcher(
              timetable?.subjects ?? const <Subject>[]);
          final (nextDay, nextLessons) = _nextSchoolDay(today);
          final weekAhead = today.add(const Duration(days: 7));
          final records =
              schoolDataController.records[ClassVivaSection.agenda] ??
                  const <ClassVivaRecord>[];
          // Verifiche e prove dei prossimi 7 giorni: il tag manuale ha
          // precedenza sul riconoscimento da parole chiave. Tutto il
          // resto dell'agenda finisce tra i compiti/impegni.
          bool isTest(ClassVivaRecord record) =>
              schoolDataController.testFlags[record.id] ??
              hasSchoolKeywordText(
                  '${record.title} ${record.subtitle} ${record.content ?? ''}');
          final inWeek = records
              .where((record) =>
                  record.date != null &&
                  !record.date!.isBefore(today) &&
                  !record.date!.isAfter(weekAhead))
              .toList();
          final tests = inWeek.where(isTest).toList()
            ..sort((a, b) => (a.date ?? DateTime(9999))
                .compareTo(b.date ?? DateTime(9999)));
          // Compiti/impegni: eventi di agenda che non sono verifiche,
          // più i compiti personali, ordinati per data.
          final commitments = <({DateTime? date, String title, String? subtitle})>[
            for (final record in inWeek.where((r) => !isTest(r)))
              (
                date: record.date,
                title: record.title,
                subtitle: [
                  if (record.subjectName != null) record.subjectName!,
                  if (record.content != null &&
                      record.content != record.title)
                    record.content!,
                ].join(' • '),
              ),
            for (final task in schoolDataController.tasks
                .where((task) => !task.isDone))
              (
                date: task.dueDate,
                title: task.title,
                subtitle: task.subject,
              ),
          ]..sort((a, b) => (a.date ?? DateTime(9999))
              .compareTo(b.date ?? DateTime(9999)));
          final isTomorrow =
              _sameDate(nextDay, today.add(const Duration(days: 1)));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(_longDate(now),
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              _SectionTitle(
                  title:
                      'Prossimo giorno di scuola (${isTomorrow ? 'domani' : _weekday(nextDay.weekday)})'),
              if (nextLessons.isEmpty)
                const _EmptyText('Nessuna lezione in orario.')
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final lesson in nextLessons)
                      ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: Color(
                              subjects[lesson.subjectId]?.colorValue ??
                                  0xFF9E9E9E),
                        ),
                        title: Text(
                            subjects[lesson.subjectId]?.name ?? 'Materia',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${_clock(lesson.startMinute)}–${_clock(lesson.endMinute)}'),
                      ),
                  ]),
                ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Verifiche della settimana'),
              if (tests.isEmpty)
                const _EmptyText('Nessuna verifica nei prossimi 7 giorni.')
              else
                ...tests.map((record) {
                  final subject =
                      matchRecordSubject(record, matcher, timetable);
                  final color = subject != null
                      ? Color(subject.colorValue)
                      : Theme.of(context).colorScheme.secondaryContainer;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: BoxDecoration(
                        // Colore della materia dall'angolo in basso a
                        // destra, sfumato verso trasparente (leggibilità).
                        gradient: RadialGradient(
                          center: Alignment.bottomRight,
                          radius: 1.6,
                          colors: [
                            color.withValues(alpha: .55),
                            color.withValues(alpha: 0),
                          ],
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        title: Text(record.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text([
                          if (subject != null)
                            subject.name
                          else if (record.subjectName != null)
                            record.subjectName!,
                          if (record.date != null)
                            '${_weekday(record.date!.weekday)} ${_shortDate(record.date!)}',
                        ].join(' • ')),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Compiti e impegni'),
              if (commitments.isEmpty)
                const _EmptyText('Nessun compito o impegno in vista.')
              else
                ...commitments.take(6).map((item) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.task_alt_outlined),
                      title: Text(item.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        if (item.subtitle != null && item.subtitle!.isNotEmpty)
                          item.subtitle!,
                        if (item.date != null)
                          '${_weekday(item.date!.weekday)} ${_shortDate(item.date!)}',
                      ].join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    )),
            ],
          );
        },
      );
}

class PerformanceView extends StatefulWidget {
  const PerformanceView({super.key, required this.controller});
  final SchoolDataController controller;

  @override
  State<PerformanceView> createState() => _PerformanceViewState();
}

class _PerformanceViewState extends State<PerformanceView> {
  static const _allSubjects = '\u0000all-subjects';
  static const _allPeriods = '\u0000all-periods';
  String? _subject;
  String? _period;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final allGrades =
              widget.controller.records[ClassVivaSection.grades] ?? const [];
          final subjects = allGrades
              .map((record) => _firstRecordValue(
                  record, const ['subjectDesc', 'subjectName', 'subject']))
              .whereType<String>()
              .toSet()
              .toList()
            ..sort();
          final periods = allGrades
              .map((record) => _firstRecordValue(
                  record, const ['periodDesc', 'periodLabel']))
              .whereType<String>()
              .toSet()
              .toList()
            ..sort();
          if (_subject != null && !subjects.contains(_subject)) _subject = null;
          if (_period != null && !periods.contains(_period)) _period = null;
          final grades = allGrades.where((record) {
            final subject = _firstRecordValue(
                record, const ['subjectDesc', 'subjectName', 'subject']);
            final period =
                _firstRecordValue(record, const ['periodDesc', 'periodLabel']);
            return (_subject == null || subject == _subject) &&
                (_period == null || period == _period);
          }).toList()
            ..sort((a, b) =>
                (a.date ?? DateTime(1)).compareTo(b.date ?? DateTime(1)));
          final numericGrades = grades
              .where((record) =>
                  record.values['canceled'] != true &&
                  record.values['noAverage'] != true)
              .map((record) => _gradeValue(record))
              .whereType<double>()
              .toList();
          final values = grades
              .where((record) =>
                  record.date != null &&
                  record.values['canceled'] != true &&
                  record.values['noAverage'] != true &&
                  _gradeValue(record) != null)
              .map((record) => (record.date!, _gradeValue(record)!))
              .toList();
          final average = numericGrades.isEmpty
              ? null
              : numericGrades.reduce((a, b) => a + b) / numericGrades.length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text('Voti',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                  'Filtra lo storico per materia e periodo. La media semplice usa solo i valori numerici ricevuti.'),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: _subject ?? _allSubjects,
                decoration: const InputDecoration(
                  labelText: 'Materia',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                      value: _allSubjects, child: Text('Tutte')),
                  for (final subject in subjects)
                    DropdownMenuItem(value: subject, child: Text(subject)),
                ],
                onChanged: (value) => setState(
                    () => _subject = value == _allSubjects ? null : value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _period ?? _allPeriods,
                decoration: const InputDecoration(
                  labelText: 'Periodo',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                      value: _allPeriods, child: Text('Tutti')),
                  for (final period in periods)
                    DropdownMenuItem(value: period, child: Text(period)),
                ],
                onChanged: (value) => setState(
                    () => _period = value == _allPeriods ? null : value),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.trending_up),
                  title: Text(average == null
                      ? 'Media non disponibile'
                      : 'Media semplice: ${average.toStringAsFixed(2)}'),
                  subtitle:
                      Text('${numericGrades.length} valutazioni numeriche'),
                ),
              ),
              if (values.length > 1) ...[
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Andamento nel tempo'),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 150,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _GradeTrendPainter(
                              values: values,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _SectionTitle(title: 'Valutazioni'),
              if (grades.isEmpty)
                _EmptyText(widget.controller.errors[ClassVivaSection.grades] ??
                    'Nessun voto caricato. Collega o aggiorna ClasseViva dal Registro.')
              else
                ...grades.map((record) => _RecordTile(record: record)),
            ],
          );
        },
      );
}

class RegisterView extends StatefulWidget {
  const RegisterView({super.key, required this.controller});
  final SchoolDataController controller;

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openLogin() {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Accedi a ClasseViva')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ClassVivaLoginView(
              controller: widget.controller,
              onSignedIn: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                Expanded(
                    child: Text('Altro',
                        style: Theme.of(context).textTheme.headlineSmall)),
                IconButton(
                  tooltip: 'Aggiorna dati',
                  onPressed: widget.controller.isLoading
                      ? null
                      : widget.controller.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _ConnectionPanel(
                controller: widget.controller,
                onLogin: _openLogin,
              ),
            ),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Presenze'),
                Tab(text: 'Comunicazioni'),
                Tab(text: 'Materiali'),
                Tab(text: 'Libri'),
              ],
            ),
            Expanded(
              child: TabBarView(controller: _tabs, children: [
                _RecordSection(
                  controller: widget.controller,
                  sections: const [
                    ClassVivaSection.attendance,
                    ClassVivaSection.notes
                  ],
                ),
                _RecordSection(
                  controller: widget.controller,
                  sections: const [ClassVivaSection.noticeboard],
                ),
                _RecordSection(
                  controller: widget.controller,
                  sections: const [
                    ClassVivaSection.didactics,
                    ClassVivaSection.documents
                  ],
                ),
                _RecordSection(
                  controller: widget.controller,
                  sections: const [ClassVivaSection.schoolbooks],
                ),
              ]),
            ),
          ],
        ),
      );
}

/// Stato della connessione: l'accesso vero e proprio è centralizzato
/// nelle Impostazioni (stesso widget di login).
class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.controller,
    required this.onLogin,
  });

  final SchoolDataController controller;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Account ClasseViva'),
          subtitle: Text(controller.message ??
              (controller.lastUpdated == null
                  ? 'I dati già caricati sono consultabili offline.'
                  : 'Ultimo aggiornamento: ${_shortDateTime(controller.lastUpdated!)}')),
          trailing: FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.classeViva.withValues(alpha: .15),
              foregroundColor: AppPalette.classeViva,
            ),
            onPressed: onLogin,
            icon: const Icon(Icons.login, size: 18),
            label: const Text('Accedi'),
          ),
        ),
      );
}

class _RecordSection extends StatelessWidget {
  const _RecordSection({required this.controller, required this.sections});
  final SchoolDataController controller;
  final List<ClassVivaSection> sections;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          for (final section in sections) ...[
            Row(children: [
              Expanded(
                child: _SectionTitle(title: _sectionTitle(section)),
              ),
              IconButton(
                tooltip: 'Aggiorna ${_sectionTitle(section).toLowerCase()}',
                onPressed: controller.isLoading
                    ? null
                    : () => controller.refreshSection(section),
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ]),
            if ((controller.records[section] ?? const []).isEmpty)
              _EmptyText(controller.errors[section] ?? 'Nessun dato caricato.')
            else
              ...(controller.records[section] ?? const [])
                  .map((record) => _RecordTile(record: record)),
            const SizedBox(height: 12),
          ],
        ],
      );
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});
  final ClassVivaRecord record;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: record.date == null
              ? const Icon(Icons.article_outlined)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${record.date!.day}',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(_monthShort(record.date!.month),
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
          title:
              Text(record.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: record.subtitle.isEmpty ? null : Text(record.subtitle),
          trailing: _trailingValue(record),
        ),
      );
}

class _GradeTrendPainter extends CustomPainter {
  const _GradeTrendPainter({required this.values, required this.color});
  final List<(DateTime, double)> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final numbers = values.map((entry) => entry.$2).toList();
    var low = numbers.reduce((a, b) => a < b ? a : b);
    var high = numbers.reduce((a, b) => a > b ? a : b);
    if (low == high) {
      low -= 1;
      high += 1;
    }
    const inset = 12.0;
    final plotWidth = size.width - inset * 2;
    final plotHeight = size.height - inset * 2;
    final points = [
      for (var index = 0; index < values.length; index++)
        Offset(
          inset + plotWidth * index / (values.length - 1),
          inset + plotHeight * (high - values[index].$2) / (high - low),
        ),
    ];
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = color;
    for (final point in points) {
      canvas.drawCircle(point, 4, dot);
    }
    final axis = Paint()
      ..color = color.withValues(alpha: .18)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(inset, size.height - inset),
      Offset(size.width - inset, size.height - inset),
      axis,
    );
  }

  @override
  bool shouldRepaint(covariant _GradeTrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

Widget? _trailingValue(ClassVivaRecord record) {
  const keys = [
    'displayValue',
    'decimalValue',
    'gradeValue',
    'vote',
    'value',
    'evtValue'
  ];
  for (final key in keys) {
    final value = record.values[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return Text(value.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold));
    }
  }
  return null;
}

String? _firstRecordValue(ClassVivaRecord record, List<String> keys) {
  for (final key in keys) {
    final value = record.values[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

double? _gradeValue(ClassVivaRecord record) {
  for (final key in const [
    'decimalValue',
    'gradeValue',
    'vote',
    'value',
    'evtValue'
  ]) {
    final value = record.values[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value.replaceAll(',', '.');
      final parsed = double.tryParse(normalized);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

String _sectionTitle(ClassVivaSection section) => switch (section) {
      ClassVivaSection.agenda => 'Agenda',
      ClassVivaSection.grades => 'Voti',
      ClassVivaSection.attendance => 'Assenze, ritardi e uscite',
      ClassVivaSection.notes => 'Note',
      ClassVivaSection.noticeboard => 'Bacheca',
      ClassVivaSection.didactics => 'Didattica',
      ClassVivaSection.documents => 'Documenti',
      ClassVivaSection.schoolbooks => 'Libri di testo',
    };

String _clock(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

bool _sameDate(DateTime? a, DateTime b) =>
    a != null && a.year == b.year && a.month == b.month && a.day == b.day;

String _longDate(DateTime date) =>
    '${_weekday(date.weekday)}, ${date.day} ${_month(date.month)}';

String _shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

String _shortDateTime(DateTime date) =>
    '${_shortDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _weekday(int value) => const [
      'Lunedì',
      'Martedì',
      'Mercoledì',
      'Giovedì',
      'Venerdì',
      'Sabato',
      'Domenica'
    ][value - 1];

String _month(int value) => const [
      'gennaio',
      'febbraio',
      'marzo',
      'aprile',
      'maggio',
      'giugno',
      'luglio',
      'agosto',
      'settembre',
      'ottobre',
      'novembre',
      'dicembre'
    ][value - 1];

String _monthShort(int value) => const [
      'GEN',
      'FEB',
      'MAR',
      'APR',
      'MAG',
      'GIU',
      'LUG',
      'AGO',
      'SET',
      'OTT',
      'NOV',
      'DIC'
    ][value - 1];
