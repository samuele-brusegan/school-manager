import 'dart:math' show pi;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../controller/school_data_controller.dart';
import '../controller/theme_controller.dart';
import '../controller/timetable_controller.dart';
import '../model/contracts/classviva_data_gateway.dart';
import '../model/entities/classviva_record.dart';
import '../model/entities/lesson.dart';
import '../model/entities/subject.dart';
import '../model/entities/study_task.dart';
import '../model/services/subject_matcher.dart';
import 'package:pdfx/pdfx.dart';
import 'agenda_view.dart';
import 'app_palette.dart';
import 'attachment_viewer.dart';
import 'debug_metadata_view.dart';
export 'agenda_view.dart';

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.timetableController,
    required this.schoolDataController,
    required this.themeController,
  });

  final TimetableController timetableController;
  final SchoolDataController schoolDataController;
  final ThemeController themeController;

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
            [timetableController, schoolDataController, themeController]),
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
          final commitments = <({
            DateTime? date,
            String title,
            Subject? subject,
            ClassVivaRecord? record,
            StudyTask? task,
          })>[];
          for (final record in inWeek.where((r) => !isTest(r))) {
            commitments.add((
              date: record.date,
              title: record.title,
              subject: matchRecordSubject(record, matcher, timetable),
              record: record,
              task: null,
            ));
          }
          for (final task in schoolDataController.tasks
              .where((task) => !task.isDone)) {
            commitments.add((
              date: task.dueDate,
              title: task.title,
              subject: task.subject.isEmpty
                  ? null
                  : matcher.match(task.subject),
              record: null,
              task: task,
            ));
          }
          commitments.sort((a, b) => (a.date ?? DateTime(9999))
              .compareTo(b.date ?? DateTime(9999)));
          final debug = themeController.debugMode;
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
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text([
                              if (subject != null)
                                subject.name
                              else if (record.subjectName != null)
                                record.subjectName!,
                              if (record.date != null)
                                '${_weekday(record.date!.weekday)} ${_shortDate(record.date!)}',
                            ].join(' • ')),
                            if (debug)
                              DebugInfoText(
                                  'matched: ${subject?.name ?? '-'} (${subject?.id ?? '-'})\n${debugRecordText(record)}'),
                          ],
                        ),
                        onTap: () => _showDetails(
                          context,
                          schoolDataController,
                          title: record.title,
                          subject: subject,
                          fallbackSubjectName: record.subjectName,
                          date: record.date,
                          record: record,
                          debug: debug,
                        ),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Compiti e impegni'),
              if (commitments.isEmpty)
                const _EmptyText('Nessun compito o impegno in vista.')
              else
                ...commitments.take(6).map((item) {
                  final subjectName = item.subject?.name ??
                      (item.record?.subjectName ??
                          (item.task?.subject.isNotEmpty == true
                              ? item.task!.subject
                              : null));
                  final color = item.subject != null
                      ? Color(item.subject!.colorValue)
                      : Theme.of(context).colorScheme.secondaryContainer;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      decoration: BoxDecoration(
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
                        leading: const Icon(Icons.task_alt_outlined),
                        title: Text(item.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text([
                              if (subjectName != null) subjectName,
                              if (item.date != null)
                                '${_weekday(item.date!.weekday)} ${_shortDate(item.date!)}',
                            ].join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            if (debug)
                              DebugInfoText([
                                'matched: ${item.subject?.name ?? '-'} (${item.subject?.id ?? '-'})',
                                if (item.record != null)
                                  debugRecordText(item.record!),
                                if (item.task != null)
                                  'task id: ${item.task!.id}  done: ${item.task!.isDone}  subject: "${item.task!.subject}"',
                              ].join('\n')),
                          ],
                        ),
                        onTap: () => _showDetails(
                          context,
                          schoolDataController,
                          title: item.title,
                          subject: item.subject,
                          fallbackSubjectName: subjectName,
                          date: item.date,
                          record: item.record,
                          task: item.task,
                          debug: debug,
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      );
}

class PerformanceView extends StatefulWidget {
  const PerformanceView(
      {super.key, required this.controller, required this.themeController});
  final SchoolDataController controller;
  final ThemeController themeController;

  @override
  State<PerformanceView> createState() => _PerformanceViewState();
}

class _PerformanceViewState extends State<PerformanceView> {
  Color _gradeColor(double? value) {
    if (value == null) return Colors.blueGrey;
    if (value >= 6) return Colors.green.shade700;
    if (value >= 5) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([widget.controller, widget.themeController]),
        builder: (context, _) {
          final allGrades =
              widget.controller.records[ClassVivaSection.grades] ?? const [];
          String? subjectOf(ClassVivaRecord record) => _firstRecordValue(
              record, const ['subjectDesc', 'subjectName', 'subject']);
          bool counts(ClassVivaRecord record) =>
              record.values['canceled'] != true &&
              record.values['noAverage'] != true &&
              _gradeValue(record) != null;
          final subjects = allGrades
              .map(subjectOf)
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
          final grades = allGrades.toList()
            ..sort((a, b) =>
                (a.date ?? DateTime(1)).compareTo(b.date ?? DateTime(1)));
          final numericGrades = grades
              .where(counts)
              .map((record) => _gradeValue(record)!)
              .toList();
          final values = grades
              .where((record) => record.date != null && counts(record))
              .map((record) => (record.date!, _gradeValue(record)!))
              .toList();
          final average = numericGrades.isEmpty
              ? null
              : numericGrades.reduce((a, b) => a + b) / numericGrades.length;
          String? periodOf(ClassVivaRecord record) => _firstRecordValue(
              record, const ['periodDesc', 'periodLabel']);
          // Media generale per ogni periodo (tutte le materie).
          final periodAverages = <String, double>{};
          for (final period in periods) {
            final votes = allGrades
                .where((r) => periodOf(r) == period && counts(r))
                .map(_gradeValue)
                .whereType<double>()
                .toList();
            if (votes.isNotEmpty) {
              periodAverages[period] =
                  votes.reduce((a, b) => a + b) / votes.length;
            }
          }
          // Per ogni materia: media complessiva e media per periodo.
          final subjectDashboard = <String, ({double? total, Map<String, double?> byPeriod})>{};
          for (final subject in subjects) {
            final subjectGrades =
                allGrades.where((r) => subjectOf(r) == subject && counts(r));
            final all = subjectGrades
                .map(_gradeValue)
                .whereType<double>()
                .toList();
            final byPeriod = <String, double?>{};
            for (final period in periods) {
              final votes = subjectGrades
                  .where((r) => periodOf(r) == period)
                  .map(_gradeValue)
                  .whereType<double>()
                  .toList();
              byPeriod[period] = votes.isEmpty
                  ? null
                  : votes.reduce((a, b) => a + b) / votes.length;
            }
            subjectDashboard[subject] = (
              total: all.isEmpty
                  ? null
                  : all.reduce((a, b) => a + b) / all.length,
              byPeriod: byPeriod,
            );
          }
          final lowest = numericGrades.isEmpty
              ? null
              : numericGrades.reduce((a, b) => a < b ? a : b);
          final highest = numericGrades.isEmpty
              ? null
              : numericGrades.reduce((a, b) => a > b ? a : b);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text('Voti',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: 20, horizontal: 16),
                  child: Column(children: [
                    _GradeGauge(
                      value: average,
                      size: 200,
                      emphasize: true,
                      color: _gradeColor(average),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Media generale',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      '${numericGrades.length} valutazioni numeriche'
                      '${lowest == null ? '' : ' · min ${lowest % 1 == 0 ? lowest.toInt() : lowest} · max ${highest! % 1 == 0 ? highest.toInt() : highest}'}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ]),
                ),
              ),
              if (values.length > 1) ...[
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text('Andamento voti',
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: CustomPaint(
                            painter: _GradeChartPainter(
                              values: values,
                              color: Theme.of(context).colorScheme.primary,
                              labelStyle: Theme.of(context)
                                  .textTheme
                                  .labelSmall!
                                  .copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (periodAverages.length > 1) ...[
                const SizedBox(height: 16),
                _SectionTitle(title: 'Media per periodo'),
                SizedBox(
                  height: 108,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final entry in periodAverages.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _GaugeCard(
                            value: entry.value,
                            label: entry.key,
                            color: _gradeColor(entry.value),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (subjectDashboard.isNotEmpty) ...[
                const SizedBox(height: 16),
                _SectionTitle(title: 'Media per materia'),
                for (final entry in subjectDashboard.entries)
                  _SubjectGaugeCard(
                    subject: entry.key,
                    total: entry.value.total,
                    byPeriod: entry.value.byPeriod,
                    colorOf: _gradeColor,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SubjectGradesPage(
                        subject: entry.key,
                        controller: widget.controller,
                        themeController: widget.themeController,
                      ),
                    )),
                  ),
              ],
              const SizedBox(height: 16),
              _SectionTitle(title: 'Valutazioni'),
              if (grades.isEmpty)
                _EmptyText(widget.controller.errors[ClassVivaSection.grades] ??
                    'Nessun voto caricato. Collega o aggiorna ClasseViva dal Registro.')
              else
                ...grades.reversed.map((record) =>
                    _GradeTile(record: record, color: _gradeColor(_gradeValue(record)), debug: widget.themeController.debugMode)),
            ],
          );
        },
      );
}

/// Card di una valutazione: voto grande colorato, materia, data e tipo.
class _GradeTile extends StatelessWidget {
  const _GradeTile(
      {required this.record, required this.color, this.debug = false});
  final ClassVivaRecord record;
  final Color color;
  final bool debug;

  @override
  Widget build(BuildContext context) {
    final subject = _firstRecordValue(
        record, const ['subjectDesc', 'subjectName', 'subject']);
    final display = _firstRecordValue(
            record, const ['displayValue', 'decimalValue', 'gradeValue', 'vote', 'value', 'evtValue']) ??
        '–';
    final details = [
      if (record.date != null) _shortDate(record.date!),
      if (_firstRecordValue(record, const ['periodDesc', 'periodLabel'])
          case final period?)
        period,
      if (record.subtitle.isNotEmpty) record.subtitle,
      if (record.values['canceled'] == true) 'annullato',
    ].join(' · ');
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .14),
          foregroundColor: color,
          child: Text(display,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Text(subject ?? record.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (details.isNotEmpty)
              Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (debug) DebugInfoText(debugRecordText(record)),
          ],
        ),
      ),
    );
  }
}

/// Hub del tab "Altro": le sezioni del registro non sono più tab ma
/// card in un menu; ogni card apre una pagina dedicata con AppBar.
class RegisterView extends StatelessWidget {
  const RegisterView(
      {super.key,
      required this.controller,
      required this.themeController,
      required this.timetableController});
  final SchoolDataController controller;
  final ThemeController themeController;
  final TimetableController timetableController;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([controller, themeController]),
        builder: (context, _) {
          final debug = themeController.debugMode;
          final attendance =
              controller.records[ClassVivaSection.attendance] ?? const [];
          final notices =
              controller.records[ClassVivaSection.noticeboard] ?? const [];
          final materials =
              (controller.records[ClassVivaSection.didactics] ?? const [])
                  .length +
                  (controller.records[ClassVivaSection.documents] ?? const [])
                      .length;
          final books =
              controller.records[ClassVivaSection.schoolbooks] ?? const [];
          final notes =
              controller.records[ClassVivaSection.notes] ?? const [];

          String countLabel(int count, String singular, String plural) =>
              count == 0
                  ? 'Nessun elemento'
                  : count == 1
                      ? '1 $singular'
                      : '$count $plural';

          final absences = attendance
              .where((r) =>
                  '${r.values['evtCode'] ?? ''}'.startsWith('ABA'))
              .length;
          final delays = attendance
              .where((r) =>
                  '${r.values['evtCode'] ?? ''}'.startsWith('ABR'))
              .length;
          final exits = attendance
              .where((r) =>
                  '${r.values['evtCode'] ?? ''}'.startsWith('ABU'))
              .length;
          final attendanceSubtitle = [
            if (absences > 0) '$absences assenz${absences == 1 ? 'a' : 'e'}',
            if (delays > 0) '$delays ritard${delays == 1 ? 'o' : 'i'}',
            if (exits > 0) '$exits uscit${exits == 1 ? 'a' : 'e'}',
          ].join(' · ');
          final latestNotice = notices.isEmpty
              ? null
              : _firstRecordValue(
                  notices.first, const ['cntTitle', 'title', 'subject']);

          void open(String title, Widget page) =>
              Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(title)), body: page)));

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(children: [
                Expanded(
                    child: Text('Altro',
                        style:
                            Theme.of(context).textTheme.headlineSmall)),
                IconButton(
                  tooltip: 'Aggiorna dati',
                  onPressed:
                      controller.isLoading ? null : controller.refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ]),
              const SizedBox(height: 4),
              _AltroMenuCard(
                icon: Icons.how_to_reg_outlined,
                color: const Color(0xFFE53935),
                title: 'Presenze',
                subtitle: attendanceSubtitle.isEmpty
                    ? 'Assenze, ritardi e uscite'
                    : attendanceSubtitle,
                onTap: () => open(
                    'Presenze',
                    Column(children: [
                      if (themeController.showAttendanceRate)
                        _AttendanceRateCard(
                          controller: controller,
                          timetableController: timetableController,
                        ),
                      Expanded(
                        child: _RecordSection(
                          controller: controller,
                          debug: debug,
                          sections: const [ClassVivaSection.attendance],
                        ),
                      ),
                    ])),
              ),
              _AltroMenuCard(
                icon: Icons.edit_note_outlined,
                color: const Color(0xFF00897B),
                title: 'Note',
                subtitle: countLabel(notes.length, 'nota', 'note'),
                onTap: () => open(
                    'Note',
                    _RecordSection(
                      controller: controller,
                      debug: debug,
                      sections: const [ClassVivaSection.notes],
                    )),
              ),
              _AltroMenuCard(
                icon: Icons.campaign_outlined,
                color: const Color(0xFFFB8C00),
                title: 'Comunicazioni',
                subtitle: latestNotice == null
                    ? countLabel(
                        notices.length, 'circolare', 'circolari')
                    : 'Ultime: $latestNotice',
                onTap: () => open(
                    'Comunicazioni',
                    _NoticeboardList(controller: controller, debug: debug)),
              ),
              _AltroMenuCard(
                icon: Icons.folder_copy_outlined,
                color: const Color(0xFF1E88E5),
                title: 'Materiali',
                subtitle: countLabel(
                    materials, 'documento', 'documenti'),
                onTap: () => open(
                    'Materiali',
                    _RecordSection(
                      controller: controller,
                      debug: debug,
                      sections: const [
                        ClassVivaSection.didactics,
                        ClassVivaSection.documents
                      ],
                    )),
              ),
              _AltroMenuCard(
                icon: Icons.menu_book_outlined,
                color: const Color(0xFF43A047),
                title: 'Libri',
                subtitle:
                    countLabel(books.length, 'libro', 'libri'),
                onTap: () => open(
                    'Libri',
                    _RecordSection(
                      controller: controller,
                      debug: debug,
                      sections: const [ClassVivaSection.schoolbooks],
                    )),
              ),
              _AltroMenuCard(
                icon: Icons.insights_outlined,
                color: const Color(0xFF8E24AA),
                title: 'Statistiche',
                subtitle: 'Medie, grafici e riepilogo assenze',
                onTap: () => open(
                    'Statistiche',
                    StatsView(
                      controller: controller,
                      themeController: themeController,
                      timetableController: timetableController,
                    )),
              ),
            ],
          );
        },
      );
}

/// Card del menu "Altro": icona in tondo colorato, titolo, sottotitolo
/// di riepilogo e chevron di navigazione.
class _AltroMenuCard extends StatelessWidget {
  const _AltroMenuCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: .14),
            child: Icon(icon, color: color),
          ),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, maxLines: 1,
              overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}

/// Statistiche assenze in ore su tutto l'anno scolastico: le ore assenti
/// si confrontano con il 25% delle ore annuali (limite per l'ammissione
/// all'esame/scrutinio). Contano le assenze (giornata intera), i ritardi
/// non brevi e le uscite anticipate (stimati 1h ciascuno).
({int absentMinutes, int annualMinutes, int limitMinutes})
    attendanceStats(
        List<ClassVivaRecord> records, TimetableController timetable) {
  final now = DateTime.now();
  final year = now.month >= 9 ? now.year : now.year - 1;
  final start = DateTime(year, 9, 1);
  final end = DateTime(year + 1, 6, 30);
  final configured = {
    for (var day = 1; day <= 7; day++)
      if (timetable.periodsForWeekday(day).isNotEmpty) day,
  };
  int minutesFor(int weekday) {
    final periods = timetable.periodsForWeekday(weekday);
    if (periods.isEmpty) {
      // Senza orario configurato: stima di 5 ore per lun–ven, 0 nel weekend.
      return configured.isEmpty && weekday <= 5 ? 300 : 0;
    }
    return periods.fold(0, (sum, p) => sum + p.endMinute - p.startMinute);
  }

  var annual = 0;
  for (var day = start; !day.isAfter(end); day = day.add(const Duration(days: 1))) {
    annual += minutesFor(day.weekday);
  }
  var absent = 0;
  for (final record in records) {
    final code = record.values['evtCode']?.toString().toUpperCase() ?? '';
    if (record.date == null) continue;
    if (code.startsWith('ABA')) {
      // Assenza: tutta la giornata.
      absent += minutesFor(record.date!.weekday);
    } else if (code == 'ABR0' || code.startsWith('ABU')) {
      // Ritardo non breve o uscita anticipata: ~1 ora persa.
      absent += 60;
    }
  }
  return (
    absentMinutes: absent,
    annualMinutes: annual,
    limitMinutes: (annual * 0.25).round(),
  );
}

String _hoursLabel(int minutes) {
  final hours = minutes / 60;
  return hours == hours.round() ? '${hours.toInt()}h' : '${hours.toStringAsFixed(1)}h';
}

/// Card con ore di assenza sull'anno scolastico, quota rispetto al limite
/// del 25% e countdown quando restano meno di 30 ore di margine.
class _AttendanceRateCard extends StatelessWidget {
  const _AttendanceRateCard({
    required this.controller,
    required this.timetableController,
  });

  final SchoolDataController controller;
  final TimetableController timetableController;

  @override
  Widget build(BuildContext context) {
    final records =
        controller.records[ClassVivaSection.attendance] ?? const [];
    final stats = attendanceStats(records, timetableController);
    if (stats.annualMinutes == 0) return const SizedBox.shrink();
    final percent = stats.absentMinutes / stats.annualMinutes * 100;
    final remaining = stats.limitMinutes - stats.absentMinutes;
    final over = remaining < 0;
    final nearLimit = !over && remaining <= 30 * 60;
    final color = over
        ? Colors.red.shade700
        : nearLimit
            ? Colors.orange.shade800
            : Colors.green.shade700;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: .15),
                foregroundColor: color,
                child: Text(
                  '${percent.toStringAsFixed(1)}%',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              title: const Text('Assenze nell’anno scolastico'),
              subtitle: Text(
                '${_hoursLabel(stats.absentMinutes)} assenti su '
                '~${_hoursLabel(stats.annualMinutes)} annue '
                '(limite ammissione: 25% = ${_hoursLabel(stats.limitMinutes)})',
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (stats.absentMinutes / stats.limitMinutes)
                    .clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: color.withValues(alpha: .15),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                over
                    ? 'Limite superato di ${_hoursLabel(-remaining)}: '
                        'rischio non ammissione allo scrutinio.'
                    : nearLimit
                        ? 'Attenzione: restano solo ${_hoursLabel(remaining)} '
                            'di assenza prima del limite del 25%.'
                        : 'Margine residuo: ${_hoursLabel(remaining)} '
                            'di assenza prima del limite.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RecordSection extends StatelessWidget {
  const _RecordSection(
      {required this.controller,
      required this.sections,
      this.debug = false});
  final SchoolDataController controller;
  final List<ClassVivaSection> sections;
  final bool debug;

  @override
  Widget build(BuildContext context) {
    // Le sezioni senza dati né errori (es. "Note" vuota) non vengono mostrate.
    final visible = sections
        .where((section) =>
            (controller.records[section] ?? const []).isNotEmpty ||
            controller.errors[section] != null)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (visible.isEmpty)
          const _EmptyText('Nessun dato caricato.')
        else
          for (final section in visible) ...[
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
              ...(controller.records[section] ?? const []).map((record) =>
                  _RecordTile(
                    record: record,
                    debug: debug,
                    onRead: section == ClassVivaSection.noticeboard
                        ? () => _showNotice(context, controller, record)
                        : section == ClassVivaSection.notes
                            ? () => _showNote(context, record)
                            : null,
                  )),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

enum _NoticeSort { date, name }

/// Una circolare si considera letta se `readStatus` è true.
bool _isNoticeRead(ClassVivaRecord record) =>
    record.values['readStatus'] == true ||
    '${record.values['readStatus']}' == 'true';

/// Lista delle circolari con ricerca (titolo, sottotitolo, testo e nomi
/// degli allegati), ordinamento per data o nome e opzione "non lette
/// prima".
class _NoticeboardList extends StatefulWidget {
  const _NoticeboardList({required this.controller, this.debug = false});
  final SchoolDataController controller;
  final bool debug;

  @override
  State<_NoticeboardList> createState() => _NoticeboardListState();
}

class _NoticeboardListState extends State<_NoticeboardList> {
  final _search = TextEditingController();
  _NoticeSort _sort = _NoticeSort.date;
  bool _unreadFirst = false;

  // TODO: ricerca full-text dentro i PDF allegati — l'infrastruttura
  // (extractPdfText in pdf_text.dart) esiste già, ma il download di
  // tutti gli allegati è stato disabilitato temporaneamente.

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// La ricerca copre titolo, sottotitolo, contenuto e ogni campo
  /// testuale degli allegati (es. il nome del file).
  bool _matches(ClassVivaRecord record, String query) {
    final haystack = [
      record.title,
      record.subtitle,
      record.content ?? '',
      for (final attach in _noticeAttachments(record))
        ...attach.values.map((v) => '$v'),
    ].join('\n').toLowerCase();
    return haystack.contains(query);
  }

  List<ClassVivaRecord> _visible() {
    final query = _search.text.trim().toLowerCase();
    final records =
        (widget.controller.records[ClassVivaSection.noticeboard] ?? const [])
            .where((r) => query.isEmpty || _matches(r, query))
            .toList();
    int byOrder(ClassVivaRecord a, ClassVivaRecord b) =>
        _sort == _NoticeSort.name
            ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
            : (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0));
    records.sort((a, b) {
      if (_unreadFirst && _isNoticeRead(a) != _isNoticeRead(b)) {
        return _isNoticeRead(a) ? 1 : -1;
      }
      return byOrder(a, b);
    });
    return records;
  }

  @override
  Widget build(BuildContext context) {
    final records = _visible();
    final hasData =
        (widget.controller.records[ClassVivaSection.noticeboard] ?? const [])
            .isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Row(children: [
          Expanded(child: _SectionTitle(title: 'Bacheca')),
          IconButton(
            tooltip: 'Aggiorna bacheca',
            onPressed: widget.controller.isLoading
                ? null
                : () => widget.controller
                    .refreshSection(ClassVivaSection.noticeboard),
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ]),
        SearchBar(
          controller: _search,
          hintText: 'Cerca per titolo, testo o allegato…',
          leading: const Icon(Icons.search),
          onChanged: (_) => setState(() {}),
          trailing: [
            if (_search.text.isNotEmpty)
              IconButton(
                tooltip: 'Cancella ricerca',
                onPressed: () => setState(_search.clear),
                icon: const Icon(Icons.clear),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: SegmentedButton<_NoticeSort>(
              segments: const [
                ButtonSegment(
                    value: _NoticeSort.date,
                    label: Text('Per data'),
                    icon: Icon(Icons.schedule)),
                ButtonSegment(
                    value: _NoticeSort.name,
                    label: Text('Per nome'),
                    icon: Icon(Icons.sort_by_alpha)),
              ],
              selected: {_sort},
              onSelectionChanged: (selection) =>
                  setState(() => _sort = selection.first),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Mostra prima quelle non lette'),
          value: _unreadFirst,
          onChanged: (value) => setState(() => _unreadFirst = value),
        ),
        const SizedBox(height: 4),
        if (!hasData)
          _EmptyText(widget.controller
                  .errors[ClassVivaSection.noticeboard] ??
              'Nessun dato caricato.')
        else if (records.isEmpty)
          const _EmptyText('Nessuna circolare corrisponde alla ricerca.')
        else
          for (final record in records)
            _RecordTile(
              record: record,
              debug: widget.debug,
              onRead: () =>
                  _showNotice(context, widget.controller, record),
            ),
      ],
    );
  }
}

/// Dialog con i dettagli di una verifica, di un evento d'agenda o di un
/// compito personale: materia, data, docente e testo dell'evento.
Future<void> _showDetails(
  BuildContext context,
  SchoolDataController controller, {
  required String title,
  Subject? subject,
  String? fallbackSubjectName,
  DateTime? date,
  ClassVivaRecord? record,
  StudyTask? task,
  bool debug = false,
}) {
  final subjectName = subject?.name ?? fallbackSubjectName;
  final rows = <(String, String)>[
    if (subjectName != null && subjectName.isNotEmpty)
      ('Materia', subjectName),
    if (date != null) ('Data', _longDate(date)),
    if (record?.teacherName case final teacher? when teacher.isNotEmpty)
      ('Docente', teacher),
    if (record?.typeLabel case final type? when type.isNotEmpty)
      ('Tipo', type)
    else if (record != null &&
        record.subtitle.isNotEmpty &&
        record.subtitle != title)
      ('Tipo', record.subtitle),
    if (record?.content case final content?
        when content.isNotEmpty && content != title)
      ('Dettagli', content),
  ];
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: rows.isEmpty
          ? const Text('Nessun dettaglio disponibile.')
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: Theme.of(context).textTheme.labelSmall),
                        Text(value),
                      ],
                    ),
                  ),
                if (debug) ...[
                  const Divider(height: 20),
                  if (record != null)
                    DebugInfoText(debugRecordText(record)),
                  if (task != null)
                    DebugInfoText(
                        'task id: ${task.id}  done: ${task.isDone}  subject: "${task.subject}"'),
                  DebugInfoText(
                      'matched subject: ${subject?.name ?? '-'} (id: ${subject?.id ?? '-'}, classviva_id: ${subject?.classvivaId ?? '-'})'),
                ],
              ],
            ),
      actions: [
        if (task != null)
          FilledButton.tonal(
            onPressed: () {
              controller.toggleTask(task);
              Navigator.of(context).pop();
            },
            child: const Text('Segna come completato'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  );
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record, this.debug = false, this.onRead});
  final ClassVivaRecord record;
  final bool debug;

  /// Se impostata, il tile è apribile per leggere il contenuto completo
  /// (usato per le comunicazioni di bacheca).
  final VoidCallback? onRead;

  @override
  Widget build(BuildContext context) {
    final isNotice = record.section == ClassVivaSection.noticeboard.name;
    // Una circolare letta si distingue subito: titolo attenuato e
    // niente pallino colorato.
    final isRead = isNotice && _isNoticeRead(record);
    final attachmentCount =
        isNotice ? _noticeAttachments(record).length : 0;
    final titleStyle = isRead
        ? TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)
        : const TextStyle(fontWeight: FontWeight.w600);
    final tile = ListTile(
          leading: record.section == ClassVivaSection.attendance.name
              ? _attendanceBadge(context, record)
              : record.date == null
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
          title: Row(children: [
            if (isNotice && !isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            Expanded(
              child: Text(record.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle),
            ),
          ]),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (record.subtitle.isNotEmpty &&
                  record.subtitle != record.title)
                Text(record.subtitle),
              if (attachmentCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Theme.of(context)
                          .colorScheme
                          .secondaryContainer,
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('$attachmentCount',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 4),
                      Icon(Icons.attach_file,
                          size: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer),
                    ]),
                  ),
                ),
              if (debug) DebugInfoText(debugRecordText(record)),
            ],
          ),
          trailing: _trailingValue(record),
          onTap: onRead,
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: isNotice && !isRead
          // Barra verticale primaria: la circolare non letta si nota
          // anche a colpo d'occhio nella lista. Lo Stack si dimensiona
          // sulla tile, evitando i problemi di misura di IntrinsicHeight.
          ? Stack(children: [
              tile,
              Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 4,
                  child:
                      ColoredBox(color: Theme.of(context).colorScheme.primary)),
            ])
          : tile,
    );
  }
}

/// Bollino colorato per assenze, ritardi e uscite, in base al codice
/// evento ClasseViva (ABA0, ABR0, ABR1, ABU0, ecc.): colori presi dalla
/// palette dell'app, coerenti con le card e il tema (chiaro/scuro).
Widget _attendanceBadge(BuildContext context, ClassVivaRecord record) {
  final scheme = Theme.of(context).colorScheme;
  final code = record.values['evtCode']?.toString().trim().toUpperCase() ?? '';
  final (label, color) = switch (code) {
    'ABA0' || 'ABA1' => ('A', scheme.error),
    'ABR0' => ('R', AppPalette.amber),
    'ABR1' => ('RB', AppPalette.amber),
    'ABU0' => ('U', AppPalette.teal),
    // Ritardo con uscita anticipata: codice da verificare.
    'ABU1' || 'ABRU' => ('?', AppPalette.indigo),
    'ABP0' || 'PX' => ('PX', scheme.outline),
    _ => ('?', scheme.outlineVariant),
  };
  return CircleAvatar(
    radius: 16,
    backgroundColor: color.withValues(alpha: .16),
    foregroundColor: color,
    child: Text(label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
  );
}

/// Dialog di lettura di una nota disciplinare/di classe: autore, data
/// e testo completo (evtText/noteText o il titolo del record).
void _showNote(BuildContext context, ClassVivaRecord record) {
  final author = _firstRecordValue(record,
      const ['authorName', 'evtAuthor', 'teacherName', 'teacherDesc']);
  final text = _firstRecordValue(record, const [
        'evtText',
        'noteText',
        'notes',
        'comment',
        'description'
      ]) ??
      (record.title == 'Nota' ? record.subtitle : record.title);
  final meta = [
    if (author != null) author,
    if (record.date != null) _longDate(record.date!),
    if (_firstRecordValue(record, const ['warningType', 'warningDesc'])
        case final type?)
      type,
  ].join(' · ');
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nota'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (meta.isNotEmpty) ...[
              Text(meta, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 10),
            ],
            Text(text.isEmpty ? 'Nota senza testo.' : text),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  );
}

/// Mostra il testo di una comunicazione di bacheca senza scaricare
/// l'allegato PDF: il corpo viene richiesto all'API di ClasseViva.
void _showNotice(
    BuildContext context, SchoolDataController controller, ClassVivaRecord record) {
  final attachments = _noticeAttachments(record);
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(record.title),
      content: SizedBox(
        width: 480,
        child: FutureBuilder<String>(
          future: controller.noticeboardText(record),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text('Impossibile caricare la comunicazione.\n'
                  '${snapshot.error}');
            }
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final text = snapshot.data!.trim();
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(text.isEmpty
                      ? 'Questa comunicazione contiene solo allegati.'
                      : text),
                  if (attachments.isNotEmpty) ...[
                    const Divider(height: 28),
                    Text('Allegati',
                        style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 10),
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      for (var index = 0;
                          index < attachments.length;
                          index++)
                        _AttachmentTile(
                          controller: controller,
                          record: record,
                          index: index,
                        ),
                    ]),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  );
}

/// Anteprima di un allegato di circolare: per i PDF renderizza la prima
/// pagina, per gli altri tipi un'icona del formato. Il tap apre il
/// viewer in-app (i byte non vengono mai salvati su disco).
class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.controller,
    required this.record,
    required this.index,
  });
  final SchoolDataController controller;
  final ClassVivaRecord record;
  final int index;

  /// Carica l'allegato e, se è un PDF, anche l'immagine della prima
  /// pagina come anteprima.
  Future<({String fileName, Uint8List bytes, Uint8List? preview})>
      _load() async {
    final file = await controller.noticeboardAttachment(record, index);
    if (!AttachmentViewerPage.isPdf(file.fileName)) {
      return (fileName: file.fileName, bytes: file.bytes, preview: null);
    }
    try {
      // Copia: sul web pdfx scollega l'ArrayBuffer originale.
      final doc = await PdfDocument.openData(Uint8List.fromList(file.bytes));
      final page = await doc.getPage(1);
      final image = await page.render(
        width: page.width * 2,
        height: page.height * 2,
        format: PdfPageImageFormat.jpeg,
        quality: 80,
        backgroundColor: '#FFFFFF',
      );
      await page.close();
      await doc.close();
      return (fileName: file.fileName, bytes: file.bytes, preview: image?.bytes);
    } on Object {
      return (fileName: file.fileName, bytes: file.bytes, preview: null);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _load(),
        builder: (context, snapshot) {
          final file = snapshot.data;
          final name = file?.fileName ?? 'Allegato ${index + 1}';
          return Column(children: [
            Material(
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: InkWell(
                onTap: file == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => AttachmentViewerPage(
                            fileName: file.fileName, bytes: file.bytes))),
                child: SizedBox(
                  width: 110,
                  height: 140,
                  child: snapshot.hasError
                      ? const Icon(Icons.error_outline)
                      : file == null
                          ? const Center(
                              child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)))
                          : file.preview != null
                              ? Image.memory(file.preview!,
                                  fit: BoxFit.cover)
                              : Icon(
                                  AttachmentViewerPage.isPdf(file.fileName)
                                      ? Icons.picture_as_pdf_outlined
                                      : AttachmentViewerPage.iconFor(
                                          file.fileName),
                                  size: 40),
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 110,
              child: Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall),
            ),
          ]);
        },
      );
}

/// Tachimetro circolare (arco di 270°) per una media 0–10: bande di
/// sufficienza in sfondo, arco colorato animato e valore al centro.
class _GradeGauge extends StatelessWidget {
  const _GradeGauge({
    required this.value,
    required this.color,
    this.size = 72,
    this.emphasize = false,
  });

  final double? value;
  final Color color;
  final double size;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    return TweenAnimationBuilder<double>(
      tween: Tween(
          begin: 0,
          end: value == null ? 0 : (value! / 10).clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(children: [
          CustomPaint(
            size: Size.square(size),
            painter: _GaugePainter(
              progress: progress,
              color: value == null
                  ? Theme.of(context).colorScheme.outlineVariant
                  : color,
              trackColor: track,
            ),
          ),
          Positioned.fill(
            top: size * 0.34,
            child: Column(children: [
              Text(
                value == null ? '–' : value!.toStringAsFixed(1),
                style: (emphasize
                        ? Theme.of(context).textTheme.displaySmall
                        : Theme.of(context).textTheme.titleMedium)
                    ?.copyWith(
                        color: value == null
                            ? Theme.of(context).colorScheme.outline
                            : color,
                        fontWeight: FontWeight.bold),
              ),
              if (emphasize)
                Text('su 10',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  static const _start = pi * 0.75; // 135°
  static const _sweep = pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.085;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Bande di riferimento: sotto 5 rosso, 5–6 arancio, da 6 verde.
    final zonePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.55
      ..strokeCap = StrokeCap.butt;
    void zone(double from, double to, Color zoneColor) {
      zonePaint.color = zoneColor;
      canvas.drawArc(rect, _start + _sweep * from, _sweep * (to - from),
          false, zonePaint);
    }

    zone(0.0, 0.5, Colors.red.withValues(alpha: .18));
    zone(0.5, 0.6, Colors.orange.withValues(alpha: .18));
    zone(0.6, 1.0, Colors.green.withValues(alpha: .18));

    canvas.drawArc(
        rect,
        _start,
        _sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 0.35
          ..color = trackColor);

    if (progress > 0) {
      canvas.drawArc(
          rect,
          _start,
          _sweep * progress,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round
            ..color = color);
      // Tacca alla sufficienza (6).
      final tickAngle = _start + _sweep * 0.6;
      final tickPaint = Paint()
        ..color = color.withValues(alpha: .9)
        ..strokeWidth = 2;
      canvas.drawLine(
        center + Offset.fromDirection(tickAngle, radius - stroke * 0.9),
        center + Offset.fromDirection(tickAngle, radius + stroke * 0.4),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor;
}

/// Card compatta con gauge e nome del periodo.
class _GaugeCard extends StatelessWidget {
  const _GaugeCard({
    required this.value,
    required this.label,
    required this.color,
  });

  final double? value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _GradeGauge(value: value, color: color, size: 56),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      );
}

/// Card di una materia: gauge complessiva più un mini-tachimetro per
/// ogni periodo. Tappandola si apre la pagina di dettaglio della materia.
class _SubjectGaugeCard extends StatelessWidget {
  const _SubjectGaugeCard({
    required this.subject,
    required this.total,
    required this.byPeriod,
    required this.colorOf,
    this.onTap,
  });

  final String subject;
  final double? total;
  final Map<String, double?> byPeriod;
  final Color Function(double?) colorOf;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _GradeGauge(value: total, color: colorOf(total), size: 68),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        for (final entry in byPeriod.entries)
                          Column(mainAxisSize: MainAxisSize.min, children: [
                            _GradeGauge(
                                value: entry.value,
                                color: colorOf(entry.value),
                                size: 44),
                            const SizedBox(height: 2),
                            Text(_periodShort(entry.key),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(fontSize: 9)),
                          ]),
                      ],
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );

  /// Abbrevia le etichette dei periodi ("Primo quadrimestre" → "P1", ecc.).
  static String _periodShort(String period) {
    final lower = period.toLowerCase();
    if (lower.contains('prim')) return 'P1';
    if (lower.contains('second')) return 'P2';
    if (lower.contains('terz')) return 'P3';
    final match = RegExp(r'\d+').firstMatch(period);
    if (match != null) return 'P${match.group(0)}';
    return period.length <= 4 ? period : '${period.substring(0, 3)}.';
  }
}

/// Panoramica statistica: voti, distribuzione per fascia, presenze e
/// contenuti del registro.
class StatsView extends StatelessWidget {
  const StatsView({
    super.key,
    required this.controller,
    required this.themeController,
    required this.timetableController,
  });

  final SchoolDataController controller;
  final ThemeController themeController;
  final TimetableController timetableController;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge(
            [controller, themeController, timetableController]),
        builder: (context, _) {
          final grades =
              controller.records[ClassVivaSection.grades] ?? const [];
          bool counts(ClassVivaRecord record) =>
              record.values['canceled'] != true &&
              record.values['noAverage'] != true &&
              _gradeValue(record) != null;
          String? subjectOf(ClassVivaRecord record) => _firstRecordValue(
              record, const ['subjectDesc', 'subjectName', 'subject']);

          // Tutti i voti validi in ordine cronologico (senza data in
          // coda): l'animazione li rivela uno alla volta e ogni widget
          // si popola progressivamente.
          final ordered = [
            for (final record in grades)
              if (counts(record))
                (
                  record.date,
                  _gradeValue(record)!,
                  subjectOf(record) ?? '',
                ),
          ]..sort((a, b) {
              if (a.$1 == null) return 1;
              if (b.$1 == null) return -1;
              return a.$1!.compareTo(b.$1!);
            });
          final timeline = [
            for (final entry in ordered)
              if (entry.$1 != null) (entry.$1!, entry.$2),
          ];

          // Presenze.
          final attendance =
              controller.records[ClassVivaSection.attendance] ?? const [];
          final stats = attendanceStats(attendance, timetableController);
          int countCodes(String prefix) => attendance.where((record) =>
              (record.values['evtCode']?.toString().toUpperCase() ?? '')
                  .startsWith(prefix)).length;
          final absences = countCodes('ABA');
          final lates = countCodes('ABR');
          final exits = countCodes('ABU');
          final notes =
              controller.records[ClassVivaSection.notes]?.length ?? 0;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text('Statistiche',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              // Tutti i widget dei voti si popolano un voto alla volta,
              // in ordine cronologico.
              _GradePopulate(
                itemCount: ordered.length,
                builder: (context, visible, replay) {
                  final shown = ordered.take(visible).toList();
                  final votes = [for (final e in shown) e.$2];
                  final average = votes.isEmpty
                      ? null
                      : votes.reduce((a, b) => a + b) / votes.length;
                  // Distribuzione per fascia di voto.
                  const bands = [
                    '<5', '5–5,9', '6–6,9', '7–7,9', '8–8,9', '9+'
                  ];
                  final distribution = <String, int>{
                    for (final b in bands) b: 0
                  };
                  for (final vote in votes) {
                    final band = vote < 5
                        ? '<5'
                        : vote < 6
                            ? '5–5,9'
                            : vote < 7
                                ? '6–6,9'
                                : vote < 8
                                    ? '7–7,9'
                                    : vote < 9
                                        ? '8–8,9'
                                        : '9+';
                    distribution[band] = distribution[band]! + 1;
                  }
                  final maxBand =
                      distribution.values.fold(0, (a, b) => a > b ? a : b);
                  // Materie sotto la sufficienza, sui soli voti visibili.
                  final perSubject = <String, List<double>>{};
                  for (final entry in shown) {
                    if (entry.$3.isEmpty) continue;
                    perSubject.putIfAbsent(entry.$3, () => []).add(entry.$2);
                  }
                  final belowSix = {
                    for (final entry in perSubject.entries)
                      entry.key: entry.value.reduce((a, b) => a + b) /
                          entry.value.length,
                  }
                    ..removeWhere((_, avg) => avg >= 6);
                  // Rivelazione del grafico allineata ai voti datati.
                  final shownDated =
                      shown.where((e) => e.$1 != null).length;
                  final reveal = timeline.length <= 1
                      ? (shownDated > 0 ? 1.0 : 0.0)
                      : (shownDated / (timeline.length - 1))
                          .clamp(0.0, 1.0);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionTitle(title: 'Voti'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            _GradeGauge(
                                value: average,
                                color: _gradeColorOf(average),
                                size: 84),
                            const SizedBox(width: 16),
                            Expanded(
                              child:
                                  Wrap(spacing: 8, runSpacing: 8, children: [
                                _StatChip(
                                    'Valutazioni', '${votes.length}'),
                                if (votes.isNotEmpty) ...[
                                  _StatChip(
                                      'Min',
                                      SubjectGradesPage._fmt(votes.reduce(
                                          (a, b) => a < b ? a : b))),
                                  _StatChip(
                                      'Max',
                                      SubjectGradesPage._fmt(votes.reduce(
                                          (a, b) => a > b ? a : b))),
                                  _StatChip('Sufficienze',
                                      '${votes.where((v) => v >= 6).length}'),
                                ],
                              ]),
                            ),
                          ]),
                        ),
                      ),
                      if (belowSix.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Card(
                          child: Column(children: [
                            for (final entry in belowSix.entries)
                              ListTile(
                                dense: true,
                                leading: Icon(Icons.warning_amber,
                                    color: Colors.orange.shade800),
                                title: Text(entry.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                trailing: Text(
                                  SubjectGradesPage._fmt(entry.value),
                                  style: TextStyle(
                                      color: _gradeColorOf(entry.value),
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                          ]),
                        ),
                      ],
                      if (timeline.length > 1) ...[
                        const SizedBox(height: 16),
                        Row(children: [
                          const Expanded(
                              child: _SectionTitle(
                                  title: 'Andamento voti')),
                          IconButton(
                            tooltip: 'Riproduci animazione',
                            iconSize: 20,
                            onPressed: replay,
                            icon: const Icon(Icons.replay),
                          ),
                        ]),
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: Padding(
                            padding:
                                const EdgeInsets.fromLTRB(8, 16, 12, 8),
                            child: SizedBox(
                              height: 180,
                              width: double.infinity,
                              child: CustomPaint(
                                painter: _GradeChartPainter(
                                  values: timeline,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                  labelStyle: Theme.of(context)
                                      .textTheme
                                      .labelSmall!
                                      .copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                  reveal: reveal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (votes.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _SectionTitle(title: 'Distribuzione voti'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      SizedBox(
                        width: 130,
                        height: 130,
                        child: CustomPaint(
                          painter: _DonutChartPainter(
                            slices: [
                              for (final band in bands)
                                (
                                  distribution[band]!.toDouble(),
                                  _bandColor(band),
                                ),
                            ],
                            centerLabel: '${votes.length}',
                            centerSubLabel: 'voti',
                            centerStyle:
                                Theme.of(context).textTheme.titleLarge,
                            subStyle: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final band in bands)
                              if (distribution[band]! > 0)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: _bandColor(band),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(band)),
                                    Text('${distribution[band]}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ]),
                                ),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      for (final band in bands)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(children: [
                            SizedBox(
                                width: 52,
                                child: Text(band,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium)),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: maxBand == 0
                                      ? 0
                                      : distribution[band]! / maxBand,
                                  minHeight: 14,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  valueColor:
                                      AlwaysStoppedAnimation(_bandColor(band)),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 32,
                              child: Text('${distribution[band]}',
                                  textAlign: TextAlign.end,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelMedium),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Presenze'),
              Card(
                child: Column(children: [
                  _StatRow('Assenze', '$absences',
                      '${_hoursLabel(stats.absentMinutes)} · limite 25% = ${_hoursLabel(stats.limitMinutes)}'),
                  _StatRow('Ritardi', '$lates', null),
                  _StatRow('Uscite anticipate', '$exits', null),
                  _StatRow('Note disciplinari', '$notes', null),
                ]),
              ),
            ],
          );
        },
      );
}

/// Colore della fascia di voto nella distribuzione (torta e barre).
Color _bandColor(String band) => switch (band) {
      '<5' => Colors.red.shade400,
      '5–5,9' => Colors.deepOrange.shade300,
      '6–6,9' => Colors.orange.shade400,
      '7–7,9' => Colors.lightGreen.shade600,
      '8–8,9' => Colors.green.shade500,
      _ => Colors.teal.shade600,
    };

/// Grafico a torta "donut": fette proporzionali ai conteggi e totale
/// al centro.
class _DonutChartPainter extends CustomPainter {
  const _DonutChartPainter({
    required this.slices,
    required this.centerLabel,
    this.centerSubLabel,
    this.centerStyle,
    this.subStyle,
  });

  final List<(double, Color)> slices;
  final String centerLabel;
  final String? centerSubLabel;
  final TextStyle? centerStyle;
  final TextStyle? subStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold(0.0, (sum, s) => sum + s.$1);
    if (total <= 0) return;
    final stroke = size.width * 0.16;
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(
        center: center, radius: (size.width - stroke) / 2);
    var angle = -pi / 2;
    for (final (value, color) in slices) {
      if (value <= 0) continue;
      final sweep = value / total * 2 * pi;
      canvas.drawArc(
          rect,
          angle + 0.01,
          sweep - 0.02, // piccolo distacco tra le fette
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.butt
            ..color = color);
      angle += sweep;
    }
    void centerText(String text, TextStyle? style, double dy) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
          canvas, center - Offset(painter.width / 2, -dy + painter.height / 2));
    }

    centerText(centerLabel, centerStyle, centerSubLabel == null ? 0 : -10);
    if (centerSubLabel != null) {
      centerText(centerSubLabel!, subStyle, 12);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter old) =>
      old.slices != slices || old.centerLabel != centerLabel;
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ]),
      );
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value, this.subtitle);
  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Text(value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
      );
}

/// Pagina di dettaglio di una materia: medie per periodo, target
/// configurabile e consiglio sul voto necessario per raggiungerlo.
class SubjectGradesPage extends StatelessWidget {
  const SubjectGradesPage({
    super.key,
    required this.subject,
    required this.controller,
    required this.themeController,
  });

  final String subject;
  final SchoolDataController controller;
  final ThemeController themeController;

  static String _fmt(double value) =>
      value % 1 == 0 ? '${value.toInt()}' : value.toStringAsFixed(1).replaceAll('.', ',');

  /// Arrotonda per eccesso al mezzo voto (voti ClasseViva a step di 0,5).
  static double _ceilHalf(double value) => (value * 2).ceil() / 2;

  /// Consiglio testuale per raggiungere il target di media.
  static String targetAdvice(double? average, int count, double? target) {
    if (target == null) {
      return 'Imposta un obiettivo per vedere che voto ti serve.';
    }
    if (average == null || count == 0) {
      return 'Non ci sono ancora voti numerici per questa materia.';
    }
    if (average >= target) {
      final floor = target * (count + 1) - average * count;
      final safe = floor.clamp(1.0, 10.0);
      return 'Sei sopra il target ${_fmt(target)}: al prossimo voto basta '
          'non scendere sotto ${_fmt(safe)} per mantenerlo.';
    }
    // Voto minimo per raggiungere il target con k nuove valutazioni.
    for (var k = 1; k <= 5; k++) {
      final needed = _ceilHalf(
          (target * (count + k) - average * count) / k);
      if (needed <= 10) {
        return k == 1
            ? 'Media ${_fmt(average)} su $count voti: per arrivare a '
                '${_fmt(target)} devi prendere almeno un ${_fmt(needed)}.'
            : 'Media ${_fmt(average)} su $count voti: per arrivare a '
                '${_fmt(target)} ti servono almeno $k voti da '
                '${_fmt(needed)} in su.';
      }
    }
    return 'Media ${_fmt(average)} su $count voti: il target ${_fmt(target)} '
        'è lontano, serviranno diverse valutazioni alte.';
  }

  Future<void> _editTarget(BuildContext context) async {
    var value = themeController.gradeTargets[subject] ??
        themeController.defaultGradeTarget ??
        6.0;
    final chosen = await showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Obiettivo di media'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_fmt(value),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold)),
            Slider(
              value: value,
              min: 4,
              max: 10,
              divisions: 12,
              label: _fmt(value),
              onChanged: (v) => setState(() => value = v),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, -1.0),
              child: const Text('Rimuovi'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, value),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await themeController.setGradeTarget(subject, chosen < 0 ? null : chosen);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(subject)),
        body: AnimatedBuilder(
          animation: Listenable.merge([controller, themeController]),
          builder: (context, _) {
            final allGrades =
                controller.records[ClassVivaSection.grades] ?? const [];
            String? subjectOf(ClassVivaRecord record) => _firstRecordValue(
                record, const ['subjectDesc', 'subjectName', 'subject']);
            String? periodOf(ClassVivaRecord record) => _firstRecordValue(
                record, const ['periodDesc', 'periodLabel']);
            bool counts(ClassVivaRecord record) =>
                record.values['canceled'] != true &&
                record.values['noAverage'] != true &&
                _gradeValue(record) != null;
            final grades = allGrades
                .where((record) => subjectOf(record) == subject)
                .toList()
              ..sort((a, b) =>
                  (a.date ?? DateTime(1)).compareTo(b.date ?? DateTime(1)));
            final votes = grades
                .where(counts)
                .map(_gradeValue)
                .whereType<double>()
                .toList();
            final average = votes.isEmpty
                ? null
                : votes.reduce((a, b) => a + b) / votes.length;
            final periods = grades
                .map(periodOf)
                .whereType<String>()
                .toSet()
                .toList()
              ..sort();
            final byPeriod = <String, double?>{
              for (final period in periods)
                period: () {
                  final inPeriod = grades
                      .where((r) => periodOf(r) == period && counts(r))
                      .map(_gradeValue)
                      .whereType<double>()
                      .toList();
                  return inPeriod.isEmpty
                      ? null
                      : inPeriod.reduce((a, b) => a + b) / inPeriod.length;
                }(),
            };
            final values = [
              for (final record in grades)
                if (record.date != null && counts(record))
                  (record.date!, _gradeValue(record)!),
            ];
            final subjectTarget = themeController.gradeTargets[subject];
            final target = themeController.targetFor(subject);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 16),
                    child: Column(children: [
                      _GradeGauge(
                          value: average,
                          size: 180,
                          emphasize: true,
                          color: _gradeColorOf(average)),
                      const SizedBox(height: 4),
                      Text('${votes.length} valutazioni numeriche',
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
                if (byPeriod.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SectionTitle(title: 'Media per periodo'),
                  SizedBox(
                    height: 108,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final entry in byPeriod.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _GaugeCard(
                                value: entry.value,
                                label: entry.key,
                                color: _gradeColorOf(entry.value)),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _SectionTitle(title: 'Obiettivo'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                              target == null
                                  ? 'Nessun obiettivo impostato'
                                  : subjectTarget != null
                                      ? 'Target: media ${_fmt(target)} (personalizzato)'
                                      : 'Target globale: media ${_fmt(target)}',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _editTarget(context),
                            icon: const Icon(Icons.flag_outlined, size: 18),
                            label: Text(target == null ? 'Imposta' : 'Modifica'),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Text(targetAdvice(average, votes.length, target)),
                      ],
                    ),
                  ),
                ),
                if (values.length > 1) ...[
                  const SizedBox(height: 16),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text('Andamento',
                                style:
                                    Theme.of(context).textTheme.titleMedium),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 160,
                            width: double.infinity,
                            child: CustomPaint(
                              painter: _GradeChartPainter(
                                values: values,
                                color:
                                    Theme.of(context).colorScheme.primary,
                                labelStyle: Theme.of(context)
                                    .textTheme
                                    .labelSmall!
                                    .copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
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
                  const _EmptyText('Nessun voto in questa materia.')
                else
                  ...grades.reversed.map((record) => _GradeTile(
                      record: record,
                      color: _gradeColorOf(_gradeValue(record)),
                      debug: themeController.debugMode)),
              ],
            );
          },
        ),
      );
}

Color _gradeColorOf(double? value) {
  if (value == null) return Colors.blueGrey;
  if (value >= 6) return Colors.green.shade700;
  if (value >= 5) return Colors.orange.shade800;
  return Colors.red.shade700;
}

/// Anima il popolamento delle statistiche dei voti: rivela un voto alla
/// volta in ordine cronologico. Il [builder] riceve il numero di voti
/// visibili e una callback per riavviare l'animazione.
class _GradePopulate extends StatefulWidget {
  const _GradePopulate({required this.itemCount, required this.builder});

  final int itemCount;
  final Widget Function(
      BuildContext context, int visible, VoidCallback replay) builder;

  @override
  State<_GradePopulate> createState() => _GradePopulateState();
}

class _GradePopulateState extends State<_GradePopulate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration:
          Duration(milliseconds: 500 + widget.itemCount * 160),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => widget.builder(
          context,
          (_controller.value * widget.itemCount)
              .floor()
              .clamp(0, widget.itemCount),
          () => _controller.forward(from: 0),
        ),
      );
}

/// Grafico dell'andamento dei voti: scala verticale 1–10, curva morbida
/// (Catmull-Rom), leggera sfumatura azzurra sotto la linea e date sul
/// bordo inferiore.
class _GradeChartPainter extends CustomPainter {
  const _GradeChartPainter({
    required this.values,
    required this.color,
    required this.labelStyle,
    this.reveal = 1,
  });

  final List<(DateTime, double)> values;
  final Color color;
  final TextStyle labelStyle;

  /// 0–1: quota della linea temporale visibile, per l'animazione
  /// cronologica dei voti.
  final double reveal;

  /// Colore della sfumatura sotto la curva: azzurro, molto tenue.
  static const _fillColor = Color(0xFF64B5F6);

  static const _left = 30.0; // spazio per la scala 1–10
  static const _bottom = 22.0; // spazio per le date
  static const _top = 10.0;
  static const _right = 10.0;
  static const _minGrade = 1.0;
  static const _maxGrade = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final plotW = size.width - _left - _right;
    final plotH = size.height - _top - _bottom;
    final plotBottom = _top + plotH;

    double xFor(int index) =>
        _left + (values.length == 1 ? plotW / 2 : plotW * index / (values.length - 1));
    double yFor(double grade) =>
        _top + plotH * (_maxGrade - grade) / (_maxGrade - _minGrade);

    // Scala verticale 1–10 con linee guida orizzontali.
    final guide = Paint()
      ..color = color.withValues(alpha: .12)
      ..strokeWidth = 1;
    for (var grade = _minGrade.toInt(); grade <= _maxGrade.toInt(); grade++) {
      final y = yFor(grade.toDouble());
      canvas.drawLine(Offset(_left, y), Offset(size.width - _right, y), guide);
      _text(canvas, '$grade', Offset(0, y - 6), labelStyle, width: _left - 6,
          align: TextAlign.right);
    }

    final points = [
      for (var index = 0; index < values.length; index++)
        Offset(xFor(index),
            yFor(values[index].$2.clamp(_minGrade, _maxGrade))),
    ];

    // Curva Catmull-Rom → cubiche di Bézier.
    final curve = Path()..moveTo(points.first.dx, points.first.dy);
    for (var index = 0; index < points.length - 1; index++) {
      final p0 = points[index == 0 ? 0 : index - 1];
      final p1 = points[index];
      final p2 = points[index + 1];
      final p3 = points[index + 2 < points.length ? index + 2 : points.length - 1];
      curve.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }

    // L'animazione cronologica rivela curva, riempimento e punti da
    // sinistra a destra, lasciando sempre visibili scala e date.
    final revealX = _left + plotW * reveal.clamp(0.0, 1.0) + 8;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, revealX, size.height));

    // Area sfumata sotto la curva.
    final fill = Path.from(curve)
      ..lineTo(points.last.dx, plotBottom)
      ..lineTo(points.first.dx, plotBottom)
      ..close();
    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _fillColor.withValues(alpha: .18),
              _fillColor.withValues(alpha: .02),
            ],
          ).createShader(Rect.fromLTWH(0, _top, size.width, plotH)));

    canvas.drawPath(
        curve,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke);

    // Punti con alone bianco.
    for (final point in points) {
      canvas.drawCircle(point, 5, Paint()..color = Colors.white);
      canvas.drawCircle(
          point, 4, Paint()..color = color..style = PaintingStyle.fill);
      canvas.drawCircle(
          point,
          4.6,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6);
    }
    canvas.restore();

    // Date: prima, ultima e due intermedie se c'è spazio.
    final labelCount = values.length >= 4 ? 4 : values.length;
    for (var slot = 0; slot < labelCount; slot++) {
      final index = labelCount == 1
          ? 0
          : (slot * (values.length - 1) / (labelCount - 1)).round();
      _text(canvas, _shortDate(values[index].$1),
          Offset(xFor(index), plotBottom + 6), labelStyle,
          align: slot == 0
              ? TextAlign.left
              : slot == labelCount - 1
                  ? TextAlign.right
                  : TextAlign.center,
          pivotFrom: _left,
          pivotTo: size.width - _right);
    }
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style,
      {double width = 60, TextAlign align = TextAlign.center,
      double? pivotFrom, double? pivotTo}) {
    var dx = at.dx;
    var effectiveAlign = align;
    // Allinea il punto di ancoraggio ai bordi del grafico.
    if (effectiveAlign == TextAlign.left) {
      dx = pivotFrom ?? dx;
      effectiveAlign = TextAlign.left;
    } else if (effectiveAlign == TextAlign.right) {
      dx = (pivotTo ?? dx) - width;
      effectiveAlign = TextAlign.left;
    } else {
      dx -= width / 2;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    painter.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(covariant _GradeChartPainter old) =>
      old.values != values ||
      old.color != color ||
      old.labelStyle != labelStyle ||
      old.reveal != reveal;
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

/// Allegati di una circolare: la lista sotto "attachments"/"attach" se
/// presente, altrimenti tante voci vuote quante dichiara il conteggio.
List<Map> _noticeAttachments(ClassVivaRecord record) {
  for (final key in const ['attachments', 'attach', 'files', 'allegati']) {
    final value = record.values[key];
    if (value is List) {
      return value.whereType<Map>().toList();
    }
  }
  final count = int.tryParse(
          '${record.values['numOfAttach'] ?? record.values['numAttach'] ?? ''}') ??
      (record.values['cntHasAttach'] == true ||
              '${record.values['cntHasAttach']}' == 'true'
          ? 1
          : 0);
  return List.generate(count, (_) => <String, Object?>{});
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
