import 'package:flutter/material.dart';

import '../controller/school_data_controller.dart';
import '../controller/theme_controller.dart';
import '../controller/timetable_controller.dart';
import '../model/contracts/classviva_data_gateway.dart';
import '../model/entities/classviva_record.dart';
import '../model/entities/study_task.dart';
import '../model/entities/subject.dart';
import '../model/entities/timetable.dart';
import '../model/services/subject_matcher.dart';
import 'debug_metadata_view.dart';

enum _AgendaMode { list, day, week, month }

class AgendaView extends StatefulWidget {
  const AgendaView({
    super.key,
    required this.controller,
    required this.timetableController,
    required this.themeController,
  });
  final SchoolDataController controller;
  final TimetableController timetableController;
  final ThemeController themeController;

  @override
  State<AgendaView> createState() => _AgendaViewState();
}

/// Parole chiave per riconoscere verifiche e prove scolastiche.
const schoolTestKeywords = [
  'verifica',
  'test',
  'interrogazione',
  'compito in classe',
  'esame',
  'quiz',
  'prova',
];

/// Vero se il testo contiene parole riconducibili a una verifica/prova.
bool hasSchoolKeywordText(String text) {
  final normalized = text.toLowerCase();
  return schoolTestKeywords.any(normalized.contains);
}

/// Confronta due nomi di docente ignorando maiuscole e l'ordine delle
/// parole ("VIGLIETTI GRAZIELLA" == "graziella viglietti"). Matcha anche
/// le abbreviazioni: un insieme di parole contenuto nell'altro conta
/// come corrispondenza ("BEGOLO M." vs "BEGOLO MARCO" no, ma
/// "VIGLIETTI" vs "VIGLIETTI GRAZIELLA" sì).
bool teacherNamesMatch(String a, String b) {
  Set<String> tokens(String name) => name
      .toLowerCase()
      .split(RegExp(r'[^a-zà-öø-ÿ0-9]+'))
      .where((t) => t.isNotEmpty)
      .toSet();
  final ta = tokens(a);
  final tb = tokens(b);
  if (ta.isEmpty || tb.isEmpty) return false;
  return ta.containsAll(tb) || tb.containsAll(ta);
}

/// Risolve la materia locale di un record ClasseViva.
/// 1. Se il record ha subjectId o subjectDesc, si usano quelli.
/// 2. Altrimenti si guarda il docente: con una sola materia associata la
///    risposta è diretta; con più materie si cerca la lezione in orario a
///    quell'ora tenuta da quel docente.
/// 3. Ultima spiaggia: il titolo del record (es. "Verifica su dart").
Subject? matchRecordSubject(ClassVivaRecord record, SubjectMatcher matcher,
        Timetable? timetable) =>
    matchRecordSubjectTraced(record, matcher, timetable).$1;

/// Come [matchRecordSubject], ma restituisce anche il "percorso" del
/// match: quale passo ha risolto la materia o perché ogni tentativo è
/// fallito. Usato dall'overlay di debug.
(Subject?, List<String>) matchRecordSubjectTraced(
    ClassVivaRecord record, SubjectMatcher matcher, Timetable? timetable) {
  final trace = <String>[];
  final remoteId = '${record.values['subjectId'] ?? ''}'.trim();
  if (remoteId.isEmpty) {
    trace.add('subjectId assente');
  } else {
    final byId = matcher.matchId(remoteId);
    if (byId != null) {
      trace.add('subjectId "$remoteId" -> ${byId.name}');
      return (byId, trace);
    }
    trace.add('subjectId "$remoteId" senza match locale');
  }
  final name = record.subjectName;
  if (name == null || name.isEmpty) {
    trace.add('subjectDesc assente');
  } else {
    final byName = matcher.match(name);
    if (byName != null) {
      trace.add('subjectDesc "$name" -> ${byName.name}');
      return (byName, trace);
    }
    trace.add('subjectDesc "$name" non riconosciuta');
  }
  var teacherCandidates = const <Subject>[];
  final teacher = record.teacherName?.trim();
  if (timetable == null) {
    trace.add('orario non caricato: docente ignorato');
  } else if (teacher == null || teacher.isEmpty) {
    trace.add('docente assente');
  } else {
    bool namesMatch(String declared) =>
        teacherNamesMatch(declared, teacher);

    final candidates = timetable.subjects
        .where((subject) => subject.teachers.any(namesMatch))
        .toList();
    teacherCandidates = candidates;
    if (candidates.isEmpty) {
      trace.add('docente "$teacher" non associato ad alcuna materia');
    } else if (candidates.length == 1) {
      trace.add(
          'docente "$teacher" ha una sola materia -> ${candidates.single.name}');
      return (candidates.single, trace);
    } else {
      // Il docente insegna più materie: l'evento indica a che ora si
      // tiene, e in orario a quell'ora c'è la sua lezione.
      trace.add(
          'docente "$teacher" ambiguo (${candidates.map((s) => s.name).join(', ')})');
      final begin = record.begin;
      if (begin == null) {
        trace.add('evento senza orario: slot non verificabile');
      } else {
        final minute = begin.hour * 60 + begin.minute;
        final candidateIds = candidates.map((s) => s.id).toSet();
        var slotFound = false;
        for (final lesson in timetable.lessons) {
          final sameSlot = lesson.weekday == begin.weekday &&
              minute >= lesson.startMinute &&
              minute < lesson.endMinute;
          if (!sameSlot) continue;
          if (lesson.teachers.any(namesMatch) ||
              candidateIds.contains(lesson.subjectId)) {
            for (final subject in candidates) {
              if (subject.id == lesson.subjectId) {
                trace.add(
                    'lezione di ${subject.name} in orario a quell’ora -> ${subject.name}');
                return (subject, trace);
              }
            }
          }
          slotFound = true;
        }
        trace.add(slotFound
            ? 'a quell’ora c’è una lezione di un altro docente/materia'
            : 'nessuna lezione in orario a quell’ora');
        // L'evento può essere stato messo in un'ora sbagliata: guardo
        // tutte le lezioni del docente in quel giorno. Se tra le sue
        // candidate ne insegna una sola, quella è la materia.
        final todaysSubjects = timetable.lessons
            .where((lesson) =>
                lesson.weekday == begin.weekday &&
                (lesson.teachers.any(namesMatch) ||
                    candidateIds.contains(lesson.subjectId)))
            .map((lesson) => lesson.subjectId)
            .where(candidateIds.contains)
            .toSet();
        if (todaysSubjects.length == 1) {
          final subject =
              candidates.firstWhere((s) => s.id == todaysSubjects.single);
          trace.add(
              'quel giorno il docente ha solo ${subject.name} tra le candidate -> ${subject.name}');
          return (subject, trace);
        }
        trace.add(todaysSubjects.isEmpty
            ? 'quel giorno nessuna lezione del docente in orario'
            : 'quel giorno il docente ha più lezioni tra le candidate: slot non risolutivo');
      }
    }
  }
  // Ultima spiaggia: il testo del titolo (il compito può essere stato
  // inserito in un'ora diversa o l'orario può essere cambiato).
  final title = record.title;
  if (title.isEmpty) {
    trace.add('titolo assente');
  } else {
    final byTitle = matcher.match(title);
    if (byTitle != null) {
      trace.add('titolo "$title" -> ${byTitle.name}');
      return (byTitle, trace);
    }
    trace.add('titolo "$title" senza match');
  }
  // Ultimissima spiaggia: se il docente aveva candidate, vince la prima
  // dell'array (ordine di salvataggio nel DB).
  if (teacherCandidates.isNotEmpty) {
    final fallback = teacherCandidates.first;
    trace.add(
        'fallback: prima materia del docente -> ${fallback.name}');
    return (fallback, trace);
  }
  return (null, trace);
}

class _AgendaViewState extends State<AgendaView> {
  static const _gridStartMin = 7 * 60;
  static const _gridEndMin = 19 * 60;

  /// Null finché l'utente non sceglie: il default dipende dalla larghezza
  /// (settimana su schermi ampi, giorno sul telefono).
  _AgendaMode? _mode;
  DateTime _selectedDate = _dateOnly(DateTime.now());

  /// Swipe orizzontale tra periodi: ogni pagina mostra il giorno, la
  /// settimana o il mese spostato di (indice - _pageAnchor) rispetto a
  /// [_anchorDate].
  static const _pageAnchor = 10000;
  late final PageController _pageController =
      PageController(initialPage: _pageAnchor);
  DateTime _anchorDate = _dateOnly(DateTime.now());

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _dateForOffset(_AgendaMode mode, int offset) => switch (mode) {
        _AgendaMode.day => _anchorDate.add(Duration(days: offset)),
        _AgendaMode.week => _anchorDate.add(Duration(days: 7 * offset)),
        _AgendaMode.month =>
          DateTime(_anchorDate.year, _anchorDate.month + offset, 1),
        _AgendaMode.list => _anchorDate,
      };

  /// Sposta la vista su [date] riallineando l'ancora dello swipe, così la
  /// pagina corrente mostra subito il nuovo periodo.
  void _jumpTo(_AgendaMode mode, DateTime date) {
    setState(() {
      _anchorDate = _dateOnly(date);
      _selectedDate = _anchorDate;
    });
    if (_pageController.hasClients) {
      _pageController.jumpToPage(_pageAnchor);
    }
  }

  List<_AgendaEntry> _entries() {
    final matcher = SubjectMatcher(
        widget.timetableController.timetable?.subjects ?? const <Subject>[]);
    final flags = widget.controller.testFlags;
    final tasks = widget.controller.tasks
        .map((task) => _AgendaEntry.fromTask(task, matcher, flags));
    final records = (widget.controller.records[ClassVivaSection.agenda] ??
            const <ClassVivaRecord>[])
        .map((record) => _AgendaEntry.fromRecord(
            record, matcher, flags, widget.timetableController.timetable));
    return [...tasks, ...records]..sort((a, b) {
        final dateOrder = (a.date ?? DateTime(9999))
            .compareTo(b.date ?? DateTime(9999));
        if (dateOrder != 0) return dateOrder;
        final timeOrder =
            (a.beginMinute ?? 9999).compareTo(b.beginMinute ?? 9999);
        return timeOrder != 0 ? timeOrder : a.title.compareTo(b.title);
      });
  }

  @override
  Widget build(BuildContext context) {
    final mode =
        _mode ?? (MediaQuery.sizeOf(context).width >= 900
            ? _AgendaMode.week
            : _AgendaMode.day);
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.timetableController,
        widget.themeController,
      ]),
      builder: (context, _) {
        final entries = _entries();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Agenda',
                        style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  DropdownButton<_AgendaMode>(
                    value: mode,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                          value: _AgendaMode.list, child: Text('Lista')),
                      DropdownMenuItem(
                          value: _AgendaMode.day, child: Text('Giorno')),
                      DropdownMenuItem(
                          value: _AgendaMode.week, child: Text('Settimana')),
                      DropdownMenuItem(
                          value: _AgendaMode.month, child: Text('Mese')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _mode = value;
                          _anchorDate = _selectedDate;
                        });
                        if (_pageController.hasClients) {
                          _pageController.jumpToPage(_pageAnchor);
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
            if (mode != _AgendaMode.list) _dateNavigation(context, mode),
            Expanded(
              child: mode == _AgendaMode.list
                  ? _listView(entries)
                  : PageView.builder(
                      key: ValueKey(mode),
                      controller: _pageController,
                      onPageChanged: (index) => setState(() {
                        _selectedDate =
                            _dateForOffset(mode, index - _pageAnchor);
                      }),
                      itemBuilder: (context, index) {
                        final date =
                            _dateForOffset(mode, index - _pageAnchor);
                        return switch (mode) {
                          _AgendaMode.day =>
                            _dayView(context, entries, date),
                          _AgendaMode.week =>
                            _weekView(context, entries, date),
                          _AgendaMode.month =>
                            _monthView(context, entries, date),
                          _ => const SizedBox.shrink(),
                        };
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _dateNavigation(BuildContext context, _AgendaMode mode) {
    final label = switch (mode) {
      _AgendaMode.day => _agendaLongDate(_selectedDate),
      _AgendaMode.week => _weekLabel(_selectedDate),
      _AgendaMode.month =>
        '${_monthNames[_selectedDate.month - 1]} ${_selectedDate.year}',
      _AgendaMode.list => '',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Periodo precedente',
            onPressed: () => _move(-1, mode),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          TextButton(
            onPressed: () => _jumpTo(mode, DateTime.now()),
            child: const Text('Oggi'),
          ),
          IconButton(
            tooltip: 'Periodo successivo',
            onPressed: () => _move(1, mode),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  void _move(int direction, _AgendaMode mode) {
    _jumpTo(
        mode,
        switch (mode) {
          _AgendaMode.day => _selectedDate.add(Duration(days: direction)),
          _AgendaMode.week =>
            _selectedDate.add(Duration(days: 7 * direction)),
          _AgendaMode.month => DateTime(
              _selectedDate.year, _selectedDate.month + direction, 1),
          _AgendaMode.list => _selectedDate,
        });
  }

  Widget _listView(List<_AgendaEntry> entries) {
    final tasks = entries.where((entry) => entry.task != null).toList();
    final records = entries.where((entry) => entry.record != null).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Text(
            'Eventi ClasseViva e compiti personali, raccolti in un’unica lista.'),
        const SizedBox(height: 16),
        _sectionHeader('Compiti personali'),
        if (tasks.isEmpty)
          const _AgendaEmpty('Aggiungi un compito per iniziare.')
        else
          ...tasks.map(_entryTile),
        const SizedBox(height: 16),
        _sectionHeader('Eventi ClasseViva'),
        if (records.isEmpty)
          _AgendaEmpty(widget.controller.errors[ClassVivaSection.agenda] ??
              'Nessun evento caricato. Collega o aggiorna ClasseViva dal Registro.')
        else
          ...records.map(_entryTile),
      ],
    );
  }

  // ---------- Viste a griglia oraria ----------

  /// Finestra visibile: l'intervallo delle campanelle del giorno,
  /// esteso solo se ci sono eventi fuori orario.
  (int, int) _gridRange(List<_AgendaEntry> entries, int weekday) {
    final periods = widget.timetableController.periodsForWeekday(weekday);
    var start = _gridStartMin;
    var end = _gridEndMin;
    if (periods.isNotEmpty) {
      start = periods
          .map((period) => period.startMinute)
          .reduce((a, b) => a < b ? a : b);
      end = periods
          .map((period) => period.endMinute)
          .reduce((a, b) => a > b ? a : b);
    }
    for (final entry in entries) {
      final begin = entry.beginMinute;
      if (begin == null || entry.isAllDay) continue;
      final entryEnd = entry.endMinute ?? begin + 45;
      if (begin < start) start = (begin ~/ 60) * 60;
      if (entryEnd > end) end = ((entryEnd + 59) ~/ 60) * 60;
    }
    return (start, end.clamp(start + 60, 1440));
  }

  Widget _dayView(
      BuildContext context, List<_AgendaEntry> entries, DateTime date) {
    final dayEntries = _forDate(entries, date);
    if (dayEntries.isEmpty) {
      return const Center(
          child: _AgendaEmpty('Nessun impegno per questo giorno.'));
    }
    final (start, end) = _gridRange(dayEntries, date.weekday);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      children: [
        _allDayStrip(context, dayEntries),
        const SizedBox(height: 4),
        _timeGrid(context,
            entries: dayEntries,
            startMin: start,
            endMin: end,
            hourHeight: 56,
            compact: false),
      ],
    );
  }

  Widget _weekView(
      BuildContext context, List<_AgendaEntry> entries, DateTime weekDate) {
    final firstDay = _weekStart(weekDate);
    final dayCount = switch (widget.themeController.weekendMode) {
      'none' => 5,
      'sunday' => 6,
      _ => 7,
    };
    final days = List.generate(
        dayCount, (index) => firstDay.add(Duration(days: index)));
    // Se almeno un giorno ha eventi "tutto il giorno", tutte le colonne
    // riservano lo stesso spazio in alto per restare allineate.
    final maxAllDay = days
        .map((day) =>
            _forDate(entries, day).where((entry) => entry.isAllDay).length)
        .fold(0, (max, count) => count > max ? count : max);
    return LayoutBuilder(builder: (context, constraints) {
      final columnWidth =
          (constraints.maxWidth - 24) / dayCount < 120 ? 120.0 : (constraints.maxWidth - 24) / dayCount;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final day in days)
                SizedBox(
                  width: columnWidth,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _dayHeading(context, day, compact: true),
                        _allDayStrip(context, _forDate(entries, day),
                            compact: true,
                            slots: maxAllDay),
                        _timeGrid(context,
                            entries: _forDate(entries, day),
                            startMin:
                                _gridRange(_forDate(entries, day), day.weekday)
                                    .$1,
                            endMin:
                                _gridRange(_forDate(entries, day), day.weekday)
                                    .$2,
                            hourHeight: 40,
                            compact: true),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget _allDayStrip(BuildContext context, List<_AgendaEntry> dayEntries,
      {bool compact = false, int slots = 0}) {
    final allDay =
        dayEntries.where((entry) => entry.isAllDay).toList();
    final reserved = slots * 28 + (slots > 0 ? 8 : 0);
    if (allDay.isEmpty) {
      return SizedBox(height: reserved.toDouble());
    }
    return Container(
      height: reserved > 0 ? reserved.toDouble() : null,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in allDay)
            _eventBlock(context, entry, compact: true, allDay: true),
        ],
      ),
    );
  }

  /// Nero o bianco a seconda di quale contrasta meglio con lo sfondo.
  Color _contrastForeground(Color background) =>
      background.computeLuminance() > 0.4 ? Colors.black87 : Colors.white;

  /// Rosso del bordo "verifica": scuro su fondi chiari, vivo su fondi
  /// scuri, così resta distinguibile dal colore della materia.
  Color _testBorderColor(Color background) =>
      background.computeLuminance() > 0.4
          ? Colors.red.shade900
          : Colors.redAccent.shade100;

  /// Griglia con righe orarie ed eventi posizionati al minuto corretto.
  Widget _timeGrid(
    BuildContext context, {
    required List<_AgendaEntry> entries,
    required int startMin,
    required int endMin,
    required double hourHeight,
    required bool compact,
  }) {
    final labelWidth = compact ? 30.0 : 44.0;
    final height = (endMin - startMin) / 60 * hourHeight;
    final timed = entries
        .where((entry) => entry.beginMinute != null && !entry.isAllDay)
        .toList()
      ..sort((a, b) => a.beginMinute!.compareTo(b.beginMinute!));
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, constraints) {
        final laneWidth = constraints.maxWidth - labelWidth;
        final lanes = _assignLanes(timed);
        final laneCount =
            lanes.values.fold(0, (max, lane) => lane + 1 > max ? lane + 1 : max);
        final columns = laneCount == 0 ? 1 : laneCount;
        return Stack(children: [
          for (var minute = startMin; minute < endMin; minute += 60)
            Positioned(
              top: (minute - startMin) / 60 * hourHeight,
              left: 0,
              right: 0,
              child: Row(children: [
                SizedBox(
                  width: labelWidth,
                  child: Text(
                    '${(minute ~/ 60).toString().padLeft(2, '0')}:00',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: compact ? 9 : null,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Expanded(
                  child: Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outlineVariant),
                ),
              ]),
            ),
          for (final entry in timed)
            Positioned(
              top: ((entry.beginMinute! - startMin).clamp(0, endMin - startMin)) /
                  60 *
                  hourHeight,
              left: labelWidth +
                  laneWidth * (lanes[entry]! / columns),
              width: laneWidth / columns,
              height: ((entry.endMinute ?? entry.beginMinute! + 45) -
                          entry.beginMinute!)
                      .clamp(20, endMin - startMin) /
                  60 *
                  hourHeight,
              child: _eventBlock(context, entry, compact: compact),
            ),
        ]);
      }),
    );
  }

  /// Assegna ogni evento alla prima corsia libera (eventi sovrapposti
  /// vengono affiancati).
  Map<_AgendaEntry, int> _assignLanes(List<_AgendaEntry> timed) {
    final lanes = <_AgendaEntry, int>{};
    final laneEnds = <int>[];
    for (final entry in timed) {
      final begin = entry.beginMinute!;
      var lane = laneEnds.indexWhere((end) => end <= begin);
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(0);
      }
      laneEnds[lane] = entry.endMinute ?? begin + 45;
      lanes[entry] = lane;
    }
    return lanes;
  }

  Widget _eventBlock(BuildContext context, _AgendaEntry entry,
      {bool compact = false, bool allDay = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final subject = entry.subject;
    final background = subject != null
        ? Color(subject.colorValue)
        : colorScheme.secondaryContainer;
    final foreground = subject != null
        ? _contrastForeground(background)
        : colorScheme.onSecondaryContainer;
    return Padding(
      padding: EdgeInsets.only(right: compact ? 1 : 2, bottom: 1),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showEntryDetails(context, entry),
          child: Container(
            padding:
                EdgeInsets.symmetric(horizontal: compact ? 3 : 6, vertical: 2),
            decoration: entry.isTest
                ? BoxDecoration(
                    border: Border.all(
                        color: _testBorderColor(background), width: 3),
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: allDay || compact
                ? Text(
                    entry.compactLabel,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: foreground,
                        fontSize: compact ? 10 : 12,
                        fontWeight: FontWeight.w600),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: foreground,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                      if (entry.teacherName != null)
                        Text(
                          entry.teacherName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: foreground, fontSize: 11),
                        ),
                      // Testo del compito/evento: spesso coincide con il
                      // titolo (es. i "notes" dei compiti AGHW), quindi si
                      // mostra il primo tra contenuto e titolo diverso
                      // dall'etichetta di materia.
                      if (_entryBody(entry) != null)
                        Expanded(
                          child: Text(
                            _entryBody(entry)!,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: foreground, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Testo descrittivo del blocco: contenuto o titolo, purché diverso
  /// dall'etichetta già mostrata (materia o titolo stesso).
  String? _entryBody(_AgendaEntry entry) {
    for (final text in [entry.content, entry.title]) {
      if (text != null && text.isNotEmpty && text != entry.label) {
        return text;
      }
    }
    return null;
  }

  void _showEntryDetails(BuildContext context, _AgendaEntry entry) {
    final when = [
      if (entry.date != null) _agendaLongDate(entry.date!),
      if (entry.beginMinute != null)
        '${_minutes(entry.beginMinute!)}${entry.endMinute != null ? ' – ${_minutes(entry.endMinute!)}' : ''}',
    ].join(', ');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.isTest)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Chip(
                  avatar: const Icon(Icons.assignment_late_outlined, size: 18),
                  label: const Text('Verifica o prova'),
                  backgroundColor:
                      Theme.of(context).colorScheme.errorContainer,
                ),
              ),
            if (entry.displaySubject.isNotEmpty)
              _detailRow(context, Icons.menu_book_outlined, 'Materia',
                  entry.displaySubject),
            if (entry.teacherName != null)
              _detailRow(context, Icons.person_outline, 'Professore',
                  entry.teacherName!),
            if (when.isNotEmpty)
              _detailRow(context, Icons.schedule_outlined, 'Quando', when),
            if (entry.content != null && entry.content != entry.title) ...[
              const SizedBox(height: 12),
              Text('Contenuto',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(entry.content!),
                ),
              ),
            ],
            if (widget.themeController.debugMode) ...[
              const Divider(height: 20),
              DebugInfoText([
                'id: ${entry.id}',
                if (entry.record != null)
                  debugMatchTrace(
                      entry.record!, widget.timetableController.timetable),
                'keyword: ${entry.hasSchoolKeyword}  override: ${entry.testOverride}  isTest: ${entry.isTest}',
                'typeLabel: ${entry.record?.typeLabel ?? '-'}',
                if (entry.record != null) debugRecordText(entry.record!),
                if (entry.task != null)
                  'task: id=${entry.task!.id} done=${entry.task!.isDone} subject="${entry.task!.subject}" due=${entry.task!.dueDate}',
              ].join('\n')),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              widget.controller.setTestFlag(entry.id, !entry.isTest);
              Navigator.pop(context);
            },
            icon: Icon(entry.isTest
                ? Icons.label_off_outlined
                : Icons.assignment_late_outlined),
            label: Text(entry.isTest
                ? 'Rimuovi tag verifica'
                : 'Segna come verifica'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
          BuildContext context, IconData icon, String label, String value) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.labelSmall),
                  Text(value),
                ]),
          ),
        ]),
      );

  // ---------- Vista mensile ----------

  Widget _monthView(
      BuildContext context, List<_AgendaEntry> entries, DateTime monthDate) {
    final first = DateTime(monthDate.year, monthDate.month, 1);
    final dayCount =
        DateTime(monthDate.year, monthDate.month + 1, 0).day;
    final offset = first.weekday - 1;
    final cellCount = ((offset + dayCount + 6) ~/ 7) * 7;
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final dayWidth = (constraints.maxWidth - 24) / 7;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        child: Column(
          children: [
            Row(
              children: [
                for (final label in const ['L', 'M', 'M', 'G', 'V', 'S', 'D'])
                  SizedBox(
                    width: dayWidth,
                    child: Center(
                      child: Text(label,
                          style: Theme.of(context).textTheme.labelMedium),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cellCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: wide ? 1.1 : 0.88,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemBuilder: (context, index) {
                final dayNumber = index - offset + 1;
                if (dayNumber < 1 || dayNumber > dayCount) {
                  return const SizedBox.shrink();
                }
                final date = DateTime(
                    monthDate.year, monthDate.month, dayNumber);
                final dayEntries = _forDate(entries, date);
                final selected = _sameAgendaDate(date, _selectedDate);
                final today = _sameAgendaDate(date, DateTime.now());
                final colorScheme = Theme.of(context).colorScheme;
                return Material(
                  color: selected
                      ? colorScheme.secondaryContainer
                      : today
                          ? colorScheme.surfaceContainerHighest
                          : colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _selectedDate = date),
                    child: Padding(
                      padding: EdgeInsets.all(wide ? 6 : 2),
                      child: wide
                          ? _desktopMonthCell(
                              context, date, dayEntries, colorScheme)
                          : _mobileMonthCell(
                              context, date, dayEntries, colorScheme),
                    ),
                  ),
                );
              },
            ),
            if (!wide) ...[
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_agendaLongDate(_selectedDate),
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(height: 8),
              ..._forDate(entries, _selectedDate).map(_entryTile),
              if (_forDate(entries, _selectedDate).isEmpty)
                const _AgendaEmpty(
                    'Nessun compito o annotazione per questo giorno.'),
            ],
          ],
        ),
      );
    });
  }

  Widget _mobileMonthCell(BuildContext context, DateTime date,
      List<_AgendaEntry> entries, ColorScheme colors) {
    final color = entries.isEmpty
        ? colors.onSurface
        : entries.any((entry) => entry.isTest)
            ? colors.error
            : Colors.green.shade600;
    return Column(
      children: [
        Text('${date.day}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _sameAgendaDate(date, DateTime.now())
                      ? colors.primary
                      : null,
                )),
        const Spacer(),
        if (entries.isNotEmpty)
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const Spacer(),
      ],
    );
  }

  Widget _desktopMonthCell(BuildContext context, DateTime date,
          List<_AgendaEntry> entries, ColorScheme colors) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${date.day}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _sameAgendaDate(date, DateTime.now())
                        ? colors.primary
                        : null,
                  )),
          const SizedBox(height: 3),
          for (final entry in entries.take(3))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: entry.subject != null
                    ? Color(entry.subject!.colorValue)
                    : (entry.isTest
                        ? colors.errorContainer
                        : colors.secondaryContainer),
                borderRadius: BorderRadius.circular(4),
                border: entry.isTest
                    ? Border.all(color: colors.error, width: 1.5)
                    : null,
              ),
              child: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(
                        color: entry.subject != null
                            ? _contrastForeground(
                                Color(entry.subject!.colorValue))
                            : colors.onSecondaryContainer),
              ),
            ),
          if (entries.length > 3)
            Text('+${entries.length - 3}',
                style: Theme.of(context).textTheme.labelSmall),
        ],
      );

  Widget _dayHeading(BuildContext context, DateTime day,
      {bool compact = false}) {
    final today = _sameAgendaDate(day, DateTime.now());
    return Padding(
      padding:
          EdgeInsets.fromLTRB(12, compact ? 8 : 10, 8, compact ? 4 : 8),
      child: Row(
        children: [
          if (!compact)
            CircleAvatar(
              radius: 17,
              backgroundColor: today
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: today
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurface,
              child: Text('${day.day}'),
            ),
          if (!compact) const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_weekdayNames[day.weekday - 1]} ${day.day}/${day.month}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }

  List<_AgendaEntry> _forDate(List<_AgendaEntry> entries, DateTime date) =>
      entries
          .where((entry) =>
              entry.date != null && _sameAgendaDate(entry.date!, date))
          .toList();

  Widget _entryTile(_AgendaEntry entry) {
    final debug = widget.themeController.debugMode;
    if (entry.task case final task?) {
      return CheckboxListTile(
        key: ValueKey('task-${task.id}'),
        value: task.isDone,
        onChanged: (_) => widget.controller.toggleTask(task),
        title: Text(task.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text([
              if (task.subject.isNotEmpty) task.subject,
              _agendaShortDate(task.dueDate),
            ].join(' • ')),
            if (debug)
              DebugInfoText(
                  'task id: ${task.id}  done: ${task.isDone}  subject: "${task.subject}"\nmatched: ${entry.subject?.name ?? '-'} (${entry.subject?.id ?? '-'})  isTest: ${entry.isTest}'),
          ],
        ),
        secondary: IconButton(
          tooltip: 'Elimina compito',
          onPressed: () => widget.controller.deleteTask(task.id),
          icon: const Icon(Icons.delete_outline),
        ),
      );
    }
    return ListTile(
      key: ValueKey('record-${entry.record!.id}'),
      leading: CircleAvatar(
        backgroundColor: entry.subject != null
            ? Color(entry.subject!.colorValue)
            : null,
        foregroundColor: entry.subject != null
            ? _contrastForeground(Color(entry.subject!.colorValue))
            : null,
        child: Icon(
            entry.isTest
                ? Icons.assignment_late_outlined
                : Icons.event_note_outlined,
            size: 20),
      ),
      title: Text(entry.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              entry.displaySubject,
              if (entry.teacherName != null) entry.teacherName!,
              if (entry.date != null) _agendaShortDate(entry.date!),
            ].where((part) => part.isNotEmpty).join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (debug)
            DebugInfoText(
                '${debugMatchTrace(entry.record!, widget.timetableController.timetable)}\n${debugRecordText(entry.record!)}'),
        ],
      ),
      onTap: () => _showEntryDetails(context, entry),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Text(title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
      );

  String _weekLabel(DateTime date) {
    final start = _weekStart(date);
    final end = start.add(const Duration(days: 6));
    return '${start.day} ${_monthNames[start.month - 1]} – ${end.day} ${_monthNames[end.month - 1]} ${end.year}';
  }
}

class _AgendaEntry {
  const _AgendaEntry._({this.task, this.record, this.subject, this.testOverride});

  factory _AgendaEntry.fromTask(StudyTask task, SubjectMatcher matcher,
          Map<String, bool> flags) =>
      _AgendaEntry._(
        task: task,
        subject:
            task.subject.isEmpty ? null : matcher.match(task.subject),
        testOverride: flags[task.id],
      );

  factory _AgendaEntry.fromRecord(ClassVivaRecord record,
          SubjectMatcher matcher, Map<String, bool> flags,
          Timetable? timetable) =>
      _AgendaEntry._(
        record: record,
        subject: _matchSubject(record, matcher, timetable),
        testOverride: flags[record.id],
      );

  /// Risoluzione materia: nome remoto, poi ID remoto, titolo
  /// (es. "Verifica su dart" contiene "Dart"), e infine si indovina
  /// dalla lezione prevista a quell'ora o dal docente.
  static Subject? _matchSubject(ClassVivaRecord record, SubjectMatcher matcher,
          Timetable? timetable) =>
      matchRecordSubject(record, matcher, timetable);

  final StudyTask? task;
  final ClassVivaRecord? record;

  /// Override manuale del tag verifica (null = riconoscimento da keyword).
  final bool? testOverride;

  /// Materia locale associata tramite [SubjectMatcher] (colori e ID).
  final Subject? subject;

  /// Giorno di calendario: per gli eventi con orario si usa l'inizio
  /// convertito in locale (evtDate in cache può essere il giorno UTC).
  DateTime? get date {
    if (task != null) return task!.dueDate;
    final begin = record?.begin;
    if (begin != null) {
      return DateTime(begin.year, begin.month, begin.day);
    }
    return record?.date;
  }
  String get title => task?.title ?? record?.title ?? '';

  /// Nome della materia da mostrare: quella locale se mappata, altrimenti
  /// il nome remoto di ClasseViva.
  String get displaySubject =>
      subject?.name ?? record?.subjectName ?? task?.subject ?? '';

  /// Testo principale del blocco: la materia se presente, altrimenti il titolo.
  String get label =>
      displaySubject.isNotEmpty ? displaySubject : title;

  /// Testo nei blocchi compatti (vista settimana): solo il contenuto
  /// dell'evento, non la materia.
  String get compactLabel {
    final text = content?.trim();
    return text != null && text.isNotEmpty ? text : title;
  }

  String? get teacherName => record?.teacherName;
  String? get content => record?.content ?? record?.subtitle;

  DateTime? get _begin => record?.begin;
  DateTime? get _end => record?.end;

  int? get beginMinute =>
      _begin == null ? null : _begin!.hour * 60 + _begin!.minute;
  int? get endMinute =>
      _end == null ? null : _end!.hour * 60 + _end!.minute;

  /// ClasseViva marca gli eventi giornalieri come 00:00–23:59:
  /// vanno nella striscia "tutto il giorno", non nella griglia oraria.
  bool get isAllDay =>
      beginMinute == null || (beginMinute == 0 && (endMinute ?? 0) >= 1430);

  bool get hasSchoolKeyword => hasSchoolKeywordText(
      '$title ${record?.subtitle ?? ''} ${content ?? ''} ${task?.title ?? ''}');

  /// Vero se l'utente ha marcato l'evento, altrimenti riconoscimento
  /// automatico da parole chiave.
  bool get isTest => testOverride ?? hasSchoolKeyword;

  String get id => task?.id ?? record?.id ?? '';
}

class _AgendaEmpty extends StatelessWidget {
  const _AgendaEmpty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
DateTime _weekStart(DateTime date) =>
    _dateOnly(date).subtract(Duration(days: date.weekday - 1));
bool _sameAgendaDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String _agendaShortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String _agendaLongDate(DateTime date) =>
    '${_weekdayNames[date.weekday - 1]}, ${date.day} ${_monthNames[date.month - 1]}';
String _minutes(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

const _weekdayNames = [
  'Lunedì',
  'Martedì',
  'Mercoledì',
  'Giovedì',
  'Venerdì',
  'Sabato',
  'Domenica',
];
const _monthNames = [
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
  'dicembre',
];
