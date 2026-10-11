import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../controller/import_controller.dart';
import '../controller/school_data_controller.dart';
import '../controller/theme_controller.dart';
import '../controller/timetable_controller.dart';
import '../model/entities/lesson.dart';
import '../model/entities/subject.dart';
import '../model/entities/period_time.dart';
import '../model/entities/classroom_resource.dart';
import '../model/services/app_analytics.dart';
import '../model/services/distinct_subject_color_selector.dart';
import '../util/text_file_download.dart';
import '../util/update_checker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_palette.dart';
import 'classviva_login_view.dart';
import 'debug_metadata_view.dart';
import 'school_pages.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.timetableController,
    required this.importController,
    required this.schoolDataController,
    required this.themeController,
    required this.analytics,
  });
  final TimetableController timetableController;
  final ImportController importController;
  final SchoolDataController schoolDataController;
  final ThemeController themeController;
  final AppAnalytics analytics;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  int _displayedDay = DateTime.now().weekday.clamp(1, 5);
  bool _dayMode = false;

  static const _screenNames = ['home', 'orario', 'agenda', 'voti', 'altro'];

  @override
  void initState() {
    super.initState();
    widget.timetableController.load();
    widget.schoolDataController.loadLocal();
    widget.analytics.screenView(_screenNames[_tab]);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkForUpdates());
  }

  /// Controllo non bloccante delle release su GitHub: se c'è una versione
  /// più recente propone di aprire la pagina della release.
  Future<void> _checkForUpdates() async {
    final update = await UpdateChecker(
            repo: 'samuele-brusegan/school-manager')
        .check();
    if (update == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aggiornamento disponibile'),
        content: Text(
            'È disponibile la versione ${update.version}. L’aggiornamento non è obbligatorio.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ignora'),
          ),
          FilledButton(
            onPressed: () {
              launchUrl(update.url,
                  mode: LaunchMode.externalApplication);
              Navigator.pop(context);
            },
            child: const Text('Scarica'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          actions: [
            if (_tab == 1)
              IconButton(
                tooltip: 'Importa da ClasseViva',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Importa da ClasseViva')),
                    body: ClassVivaImportView(
                      importController: widget.importController,
                      timetableController: widget.timetableController,
                      schoolDataController: widget.schoolDataController,
                      analytics: widget.analytics,
                    ),
                  ),
                )),
                icon: const Icon(Icons.download_outlined),
              ),
            IconButton(
              tooltip: 'Impostazioni',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Impostazioni')),
                  body: SettingsView(
                    controller: widget.timetableController,
                    themeController: widget.themeController,
                    importController: widget.importController,
                    schoolDataController: widget.schoolDataController,
                    analytics: widget.analytics,
                  ),
                ),
              )),
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            HomeView(
              timetableController: widget.timetableController,
              schoolDataController: widget.schoolDataController,
              themeController: widget.themeController,
            ),
            TimetableView(
              controller: widget.timetableController,
              onDisplayChanged: (day, dayMode) => setState(() {
                _displayedDay = day;
                _dayMode = dayMode;
              }),
            ),
            AgendaView(
              controller: widget.schoolDataController,
              timetableController: widget.timetableController,
              themeController: widget.themeController,
            ),
            PerformanceView(
              controller: widget.schoolDataController,
              themeController: widget.themeController,
            ),
            RegisterView(
              controller: widget.schoolDataController,
              themeController: widget.themeController,
            ),
          ],
        ),
        floatingActionButton: _tab == 1 || _tab == 2
            ? FloatingActionButton.extended(
                onPressed: _tab == 1
                    ? () => _addLesson(context,
                        weekday: _dayMode ? _displayedDay : null)
                    : () => _addTask(context),
                icon: Icon(_tab == 1 ? Icons.add : Icons.task_alt_outlined),
                label:
                    Text(_tab == 1 ? 'Aggiungi lezione' : 'Aggiungi compito'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) {
            setState(() => _tab = value);
            widget.analytics.screenView(_screenNames[value]);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_view_week),
              label: 'Orario',
            ),
            NavigationDestination(
              icon: Icon(Icons.event_note_outlined),
              label: 'Agenda',
            ),
            NavigationDestination(
              icon: Icon(Icons.trending_up_outlined),
              label: 'Voti',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'Altro',
            ),
          ],
        ),
      );

  Future<void> _addTask(BuildContext context) async {
    final title = TextEditingController();
    final subject = TextEditingController();
    var dueDate = DateTime.now();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nuovo compito'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Compito'),
            ),
            TextField(
              controller: subject,
              decoration:
                  const InputDecoration(labelText: 'Materia (facoltativa)'),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Scadenza'),
              subtitle: Text(
                  '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year}'),
              onTap: () async {
                final chosen = await showDatePicker(
                  context: context,
                  initialDate: dueDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (chosen != null) setDialogState(() => dueDate = chosen);
              },
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
    if (result == true && title.text.trim().isNotEmpty) {
      await widget.schoolDataController.addTask(
        title: title.text,
        subject: subject.text,
        dueDate: dueDate,
      );
      widget.analytics.event('add_task');
    }
    title.dispose();
    subject.dispose();
  }

  Future<void> _addLesson(BuildContext context,
      {int? weekday, int? startPeriod, int? endPeriod}) async {
    final subjects = widget.timetableController.timetable?.subjects ?? [];
    if (subjects.isEmpty) {
      setState(() => _tab = 1);
      _message(context, 'Crea prima una materia nelle impostazioni.');
      return;
    }
    bool complete(List<PeriodTime> periods) =>
        periods.isNotEmpty &&
        periods
            .asMap()
            .entries
            .every((entry) => entry.value.number == entry.key + 1);
    final periodsByWeekday = {
      for (var day = 1; day <= 5; day++)
        if (complete(widget.timetableController.periodsForWeekday(day)))
          day: widget.timetableController.periodsForWeekday(day),
    };
    if (periodsByWeekday.isEmpty) {
      setState(() => _tab = 1);
      _message(context, 'Configura almeno un giorno nelle impostazioni.');
      return;
    }
    final entry = await showDialog<_LessonFormResult>(
      context: context,
      builder: (_) => AddLessonDialog(
        periodsByWeekday: periodsByWeekday,
        subjects: subjects,
        existingLessons:
            widget.timetableController.timetable?.lessons ?? const [],
        initialWeekday: weekday,
        initialStartPeriod: startPeriod,
        initialEndPeriod: endPeriod,
      ),
    );
    if (entry == null || !context.mounted) return;
    try {
      await widget.timetableController.addLesson(
        subjectName: entry.subject,
        weekday: entry.weekday,
        startMinute: entry.start,
        endMinute: entry.end,
        startPeriod: entry.startPeriod,
        endPeriod: entry.endPeriod,
        subjectId: entry.subjectId,
        teachers: entry.teachers,
        rooms: entry.rooms,
      );
    } catch (error) {
      if (context.mounted) _message(context, error.toString());
    }
  }
}

class TimetableView extends StatefulWidget {
  const TimetableView(
      {super.key, required this.controller, required this.onDisplayChanged});
  final TimetableController controller;
  final void Function(int day, bool dayMode) onDisplayChanged;

  @override
  State<TimetableView> createState() => _TimetableViewState();
}

class _TimetableViewState extends State<TimetableView> {
  bool _weekView = true;
  int _selectedDay = DateTime.now().weekday > 5 ? 1 : DateTime.now().weekday;
  double _slideDirection = 1;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          if (controller.isLoading && controller.timetable == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (controller.error != null && controller.timetable == null) {
            return Center(child: Text(controller.error!));
          }
          final timetable = controller.timetable;
          if (timetable == null ||
              (timetable.lessons.isEmpty && controller.periodTimes.isEmpty)) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Il tuo orario è vuoto. Configura le campanelle e aggiungi la prima lezione.',
                ),
              ),
            );
          }
          final subjects = {
            for (final subject in timetable.subjects) subject.id: subject,
          };
          final lessons = timetable.lessons.toList()
            ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
          return Column(
            children: [
              Expanded(
                child: !List.generate(5,
                            (index) => controller.periodsForWeekday(index + 1))
                        .any((periods) => periods.isNotEmpty)
                    ? const Center(
                        child: Text('Configura le campanelle per iniziare.'))
                    : Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: Row(children: [
                              SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                      value: true,
                                      label: Text('Settimana'),
                                      icon: Icon(Icons.view_week_outlined)),
                                  ButtonSegment(
                                      value: false,
                                      label: Text('Giorno'),
                                      icon: Icon(Icons.view_day_outlined)),
                                ],
                                selected: {_weekView},
                                onSelectionChanged: (selection) => setState(() {
                                  _weekView = selection.first;
                                  widget.onDisplayChanged(
                                      _selectedDay, !_weekView);
                                }),
                              ),
                              if (!_weekView) ...[
                                const SizedBox(width: 8),
                                DropdownButton<int>(
                                  value: _selectedDay,
                                  items: List.generate(
                                      5,
                                      (index) => DropdownMenuItem(
                                          value: index + 1,
                                          child: Text(_dayNames[index]))),
                                  onChanged: (day) {
                                    if (day != null) {
                                      setState(() {
                                        _slideDirection =
                                            day > _selectedDay ? 1 : -1;
                                        _selectedDay = day;
                                        widget.onDisplayChanged(day, true);
                                      });
                                    }
                                  },
                                ),
                              ],
                            ]),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 82),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) =>
                                    SlideTransition(
                                  position: animation.drive(Tween<Offset>(
                                    begin: Offset(_slideDirection * .18, 0),
                                    end: Offset.zero,
                                  ).chain(
                                      CurveTween(curve: Curves.easeOutCubic))),
                                  child: FadeTransition(
                                      opacity: animation, child: child),
                                ),
                                child: _WeekGrid(
                                  key: ValueKey(
                                      _weekView ? 'week' : 'day-$_selectedDay'),
                                  lessons: lessons,
                                  periodsByWeekday: {
                                    for (var day = 1; day <= 5; day++)
                                      day: controller.periodsForWeekday(day),
                                  },
                                  weekdays: _weekView
                                      ? [1, 2, 3, 4, 5]
                                      : [_selectedDay],
                                  subjects: subjects,
                                  onEdit: _editLesson,
                                  onDelete: (lesson) =>
                                      _confirmDelete(context, lesson),
                                  onCreateSlot: (day, start, end) =>
                                      _createLesson(day, start, end),
                                  onDaySwipe: (day) => setState(() {
                                    _slideDirection =
                                        day > _selectedDay ? 1 : -1;
                                    _selectedDay = day;
                                    widget.onDisplayChanged(day, true);
                                  }),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      );

  Future<void> _editLesson(Lesson lesson, Subject? subject) async {
    final entry = await showDialog<_LessonFormResult>(
      context: context,
      builder: (_) => AddLessonDialog(
        initialLesson: lesson,
        initialSubject: subject,
        periodsByWeekday: {
          for (var day = 1; day <= 5; day++)
            if (widget.controller.periodsForWeekday(day).isNotEmpty)
              day: widget.controller.periodsForWeekday(day),
        },
        subjects: widget.controller.timetable?.subjects ?? const [],
        existingLessons: widget.controller.timetable?.lessons ?? const [],
      ),
    );
    if (entry == null || !mounted) return;
    try {
      await widget.controller.updateLesson(
        id: lesson.id,
        subjectName: entry.subject,
        weekday: entry.weekday,
        startMinute: entry.start,
        endMinute: entry.end,
        startPeriod: entry.startPeriod,
        endPeriod: entry.endPeriod,
        subjectId: entry.subjectId,
        teachers: entry.teachers,
        rooms: entry.rooms,
      );
    } catch (error) {
      if (mounted) _message(context, error.toString());
    }
  }

  Future<void> _createLesson(
      int weekday, int startPeriod, int endPeriod) async {
    final subjects = widget.controller.timetable?.subjects ?? const <Subject>[];
    final periods = {
      for (var day = 1; day <= 5; day++)
        if (widget.controller.periodsForWeekday(day).isNotEmpty)
          day: widget.controller.periodsForWeekday(day),
    };
    final entry = await showDialog<_LessonFormResult>(
        context: context,
        builder: (_) => AddLessonDialog(
              periodsByWeekday: periods,
              subjects: subjects,
              existingLessons: widget.controller.timetable?.lessons ?? const [],
              initialWeekday: weekday,
              initialStartPeriod: startPeriod,
              initialEndPeriod: endPeriod,
            ));
    if (entry == null || !mounted) return;
    try {
      await widget.controller.addLesson(
          subjectName: entry.subject,
          subjectId: entry.subjectId,
          weekday: entry.weekday,
          startMinute: entry.start,
          endMinute: entry.end,
          startPeriod: entry.startPeriod,
          endPeriod: entry.endPeriod,
          teachers: entry.teachers,
          rooms: entry.rooms);
    } catch (error) {
      if (mounted) _message(context, error.toString());
    }
  }

  Future<void> _confirmDelete(BuildContext context, Lesson lesson) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la lezione?'),
        content: const Text(
          'La lezione verrà rimossa dall’orario settimanale.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.deleteLesson(lesson.id);
  }
}

class _WeekGrid extends StatefulWidget {
  const _WeekGrid({
    super.key,
    required this.lessons,
    required this.periodsByWeekday,
    required this.weekdays,
    required this.subjects,
    required this.onEdit,
    required this.onDelete,
    required this.onCreateSlot,
    required this.onDaySwipe,
  });
  final List<Lesson> lessons;
  final Map<int, List<PeriodTime>> periodsByWeekday;
  final List<int> weekdays;
  final Map<String, Subject> subjects;
  final Future<void> Function(Lesson, Subject?) onEdit;
  final ValueChanged<Lesson> onDelete;
  final Future<void> Function(int, int, int) onCreateSlot;
  final ValueChanged<int> onDaySwipe;
  static const _dayWidth = 190.0;
  static const _periodHeight = 94.0;
  static const _periodLabelWidth = 48.0;

  @override
  State<_WeekGrid> createState() => _WeekGridState();
}

class _WeekGridState extends State<_WeekGrid> {
  final Map<int, Set<int>> _selected = {};

  void _toggle(int day, int hour) {
    setState(() {
      final selected = _selected.putIfAbsent(day, () => <int>{});
      if (!selected.add(hour)) selected.remove(hour);
      if (selected.isEmpty) _selected.remove(day);
    });
  }

  (int, int)? _selectionRange() {
    if (_selected.length != 1) return null;
    final hours = _selected.values.single.toList()..sort();
    if (hours.isEmpty || hours.last - hours.first + 1 != hours.length) {
      return null;
    }
    return (hours.first, hours.last + 1);
  }

  @override
  Widget build(BuildContext context) {
    final lessons = widget.lessons;
    final periodsByWeekday = widget.periodsByWeekday;
    final weekdays = widget.weekdays;
    final subjects = widget.subjects;
    final rowCount = weekdays
        .map((day) => periodsByWeekday[day]?.length ?? 0)
        .fold<int>(1, (max, count) => count > max ? count : max);
    final content = LayoutBuilder(builder: (context, constraints) {
      final dayWidth = weekdays.length == 1
          ? (constraints.maxWidth - _WeekGrid._periodLabelWidth)
              .clamp(280.0, 900.0)
              .toDouble()
          : _WeekGrid._dayWidth;
      final table = SizedBox(
        width: _WeekGrid._periodLabelWidth + dayWidth * weekdays.length,
        child: Column(children: [
          Row(children: [
            const SizedBox(width: _WeekGrid._periodLabelWidth, height: 42),
            for (final day in weekdays)
              SizedBox(
                  width: dayWidth,
                  height: 42,
                  child: Center(
                      child: Text(_dayNames[day - 1].toUpperCase(),
                          style: Theme.of(context).textTheme.titleSmall))),
          ]),
          Expanded(
              child: SingleChildScrollView(
                  child: SizedBox(
            height: rowCount * _WeekGrid._periodHeight + 12,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: _WeekGrid._periodLabelWidth,
                  child: Column(children: [
                    for (var index = 0; index < rowCount; index++)
                      SizedBox(
                          height: _WeekGrid._periodHeight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 5, right: 4),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(_ordinal(index + 1),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge),
                                  if ((periodsByWeekday[weekdays.first] ??
                                              const <PeriodTime>[])
                                          .length >
                                      index) ...[
                                    Text(
                                        _clock(periodsByWeekday[
                                                weekdays.first]![index]
                                            .startMinute),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall),
                                    Text(
                                        _clock(periodsByWeekday[
                                                weekdays.first]![index]
                                            .endMinute),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall),
                                  ],
                                ]),
                          )),
                  ])),
              for (final day in weekdays)
                SizedBox(
                    width: dayWidth,
                    height: rowCount * _WeekGrid._periodHeight,
                    child: _DayScheduleColumn(
                      day: day,
                      rowCount: rowCount,
                      dayWidth: dayWidth,
                      periods: periodsByWeekday[day] ?? const [],
                      lessons: lessons
                          .where((lesson) => lesson.weekday == day)
                          .toList(),
                      subjects: subjects,
                      selected: _selected[day] ?? const {},
                      onTapCell: _toggle,
                      onEdit: widget.onEdit,
                      onDelete: widget.onDelete,
                    )),
            ]),
          ))),
          if (_selected.isNotEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Expanded(
                      child: Text(_selectionRange() == null
                          ? 'Seleziona ore consecutive di un solo giorno'
                          : 'Ore selezionate: ${_selectionRange()!.$1}–${_selectionRange()!.$2 - 1}')),
                  TextButton(
                      onPressed: () => setState(_selected.clear),
                      child: const Text('Annulla')),
                  FilledButton.icon(
                      onPressed: _selectionRange() == null
                          ? null
                          : () async {
                              final range = _selectionRange()!;
                              final day = _selected.keys.single;
                              await widget.onCreateSlot(
                                  day, range.$1, range.$2);
                              if (mounted) setState(_selected.clear);
                            },
                      icon: const Icon(Icons.add),
                      label: const Text('Crea lezione')),
                ])),
        ]),
      );
      return weekdays.length == 1
          ? table
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal, child: table);
    });
    if (weekdays.length != 1) return content;
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() < 250) return;
        final available = [1, 2, 3, 4, 5];
        final index = available.indexOf(weekdays.single);
        final next = index + ((details.primaryVelocity ?? 0) < 0 ? 1 : -1);
        if (next >= 0 && next < available.length) {
          widget.onDaySwipe(available[next]);
        }
      },
      child: content,
    );
  }
}

class _DayScheduleColumn extends StatelessWidget {
  const _DayScheduleColumn(
      {required this.day,
      required this.rowCount,
      required this.dayWidth,
      required this.periods,
      required this.lessons,
      required this.subjects,
      required this.selected,
      required this.onTapCell,
      required this.onEdit,
      required this.onDelete});
  final int day, rowCount;
  final double dayWidth;
  final List<PeriodTime> periods;
  final List<Lesson> lessons;
  final Map<String, Subject> subjects;
  final Set<int> selected;
  final void Function(int, int) onTapCell;
  final Future<void> Function(Lesson, Subject?) onEdit;
  final ValueChanged<Lesson> onDelete;

  int _start(Lesson l) =>
      l.startPeriod ??
      (periods.isEmpty
          ? 1
          : periods
              .firstWhere((p) => p.startMinute == l.startMinute,
                  orElse: () => periods.first)
              .number);
  int _end(Lesson l) =>
      l.endPeriod ??
      (periods.isEmpty
          ? 2
          : periods
                  .firstWhere((p) => p.endMinute == l.endMinute,
                      orElse: () => periods.last)
                  .number +
              1);

  @override
  Widget build(BuildContext context) {
    final lanes = <Lesson, (int, int)>{};
    for (final lesson in lessons) {
      final overlapping = lessons.where((other) =>
          other.id != lesson.id &&
          _start(other) < _end(lesson) &&
          _start(lesson) < _end(other));
      final count = overlapping.length + 1;
      var lane = 0;
      while (overlapping.any((other) => lanes[other]?.$1 == lane)) {
        lane++;
      }
      lanes[lesson] = (lane, count);
    }
    return Stack(clipBehavior: Clip.hardEdge, children: [
      for (var row = 1; row <= rowCount; row++)
        Positioned(
            top: (row - 1) * _WeekGrid._periodHeight,
            left: 0,
            right: 0,
            height: _WeekGrid._periodHeight,
            child: GestureDetector(
              onTap: periods.any((period) => period.number == row)
                  ? () => onTapCell(day, row)
                  : null,
              child: Container(
                  decoration: BoxDecoration(
                      color: selected.contains(row)
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      border:
                          Border.all(color: Theme.of(context).dividerColor))),
            )),
      for (final lesson in lessons)
        if (_start(lesson) >= 1 && _end(lesson) <= rowCount + 1)
          Builder(builder: (context) {
            final joinedAbove = lessons.any((other) =>
                other.weekday == lesson.weekday &&
                _end(other) == _start(lesson) &&
                other.subjectId == lesson.subjectId);
            final joinedBelow = lessons.any((other) =>
                other.weekday == lesson.weekday &&
                _end(lesson) == _start(other) &&
                other.subjectId == lesson.subjectId);
            final top = (_start(lesson) - 1) * _WeekGrid._periodHeight +
                (joinedAbove ? 0 : 2);
            final bottom = (_end(lesson) - 1) * _WeekGrid._periodHeight -
                (joinedBelow ? 0 : 2);
            return Positioned(
              left: (dayWidth - 8) * lanes[lesson]!.$1 / lanes[lesson]!.$2 + 2,
              width: (dayWidth - 8) / lanes[lesson]!.$2,
              top: top,
              height: bottom - top,
              child: _GridLessonBlock(
                  lesson: lesson,
                  subject: subjects[lesson.subjectId],
                  joinedAbove: joinedAbove,
                  joinedBelow: joinedBelow,
                  onEdit: () => onEdit(lesson, subjects[lesson.subjectId]),
                  onDelete: () => onDelete(lesson)),
            );
          }),
    ]);
  }
}

class _GridLessonBlock extends StatelessWidget {
  const _GridLessonBlock({
    required this.lesson,
    required this.subject,
    required this.joinedAbove,
    required this.joinedBelow,
    required this.onEdit,
    required this.onDelete,
  });
  final Lesson lesson;
  final Subject? subject;
  final bool joinedAbove;
  final bool joinedBelow;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = Color(subject?.colorValue ?? 0xFF6750A4);
    final foreground =
        color.computeLuminance() > .45 ? Colors.black87 : Colors.white;
    final radius = BorderRadius.vertical(
      top: joinedAbove ? Radius.zero : const Radius.circular(8),
      bottom: joinedBelow ? Radius.zero : const Radius.circular(8),
    );
    final border = Border(
      left: BorderSide(color: color, width: 1.5),
      right: BorderSide(color: color, width: 1.5),
      top: joinedAbove ? BorderSide.none : BorderSide(color: color, width: 1.5),
      bottom:
          joinedBelow ? BorderSide.none : BorderSide(color: color, width: 1.5),
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: color,
        border: border,
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 4,
                        decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 4),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(subject?.name ?? 'Materia',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: foreground)),
                          ),
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Elimina lezione',
                              onPressed: onDelete,
                              icon: Icon(Icons.close,
                                  size: 16, color: foreground),
                            ),
                          ),
                        ]),
                    if (lesson.teachers.isNotEmpty)
                      Text('Prof: ${lesson.teachers.join(', ')}',
                          softWrap: true,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: foreground)),
                    if (lesson.rooms.isNotEmpty)
                      Text('Aula: ${lesson.rooms.join(', ')}',
                          softWrap: true,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: foreground)),
                  ]),
            ),
          )),
    );
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.controller,
    required this.themeController,
    required this.importController,
    required this.schoolDataController,
    required this.analytics,
  });
  final TimetableController controller;
  final ThemeController themeController;
  final ImportController importController;
  final SchoolDataController schoolDataController;
  final AppAnalytics analytics;

  Future<void> _configureDay(BuildContext context, int weekday) async {
    final periods = await showDialog<List<PeriodTime>>(
      context: context,
      builder: (_) => BellScheduleDialog(
        weekday: weekday,
        initialPeriods: controller.periodsForWeekday(weekday),
      ),
    );
    if (periods == null || !context.mounted) return;
    try {
      await controller.savePeriodTimes(periods);
    } catch (error) {
      if (context.mounted) _message(context, error.toString());
    }
  }

  Future<void> _editSubject(BuildContext context, [Subject? subject]) async {
    final subjects = controller.timetable?.subjects ?? const <Subject>[];
    final edited = await showDialog<Subject>(
      context: context,
      builder: (_) => SubjectEditorDialog(
        subject: subject,
        initialColor: subject?.colorValue ??
            const DistinctSubjectColorSelector().selectFor(subjects),
        availableTeachers: controller.resources
            .where((item) => item.category == ResourceCategory.teacher)
            .map((item) => item.name)
            .toList(),
        availableRooms: controller.resources
            .where((item) => item.category == ResourceCategory.room)
            .map((item) => item.name)
            .toList(),
      ),
    );
    if (edited == null || !context.mounted) return;
    try {
      await controller.saveSubject(edited);
    } catch (error) {
      if (context.mounted) _message(context, error.toString());
    }
  }

  Future<void> _editResource(BuildContext context, ResourceCategory category,
      [ClassroomResource? existing]) async {
    final resource = await showDialog<ClassroomResource>(
        context: context,
        builder: (_) =>
            ResourceEditorDialog(category: category, resource: existing));
    if (resource == null || !context.mounted) return;
    try {
      await controller.saveResource(resource);
    } catch (error) {
      if (context.mounted) _message(context, error.toString());
    }
  }

  Future<void> _deleteResource(
      BuildContext context, ClassroomResource resource) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text('Rimuovere ${resource.name}?'),
              content: const Text(
                  'La voce sarà rimossa anche dalle materie e dalle lezioni associate.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Annulla')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Rimuovi')),
              ],
            ));
    if (confirmed == true) await controller.deleteResource(resource.id);
  }

  Future<void> _deleteSubject(BuildContext context, Subject subject) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminare ${subject.name}?'),
        content: const Text(
            'Saranno eliminate anche le lezioni associate a questa materia.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Elimina')),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteSubject(subject.id);
  }

  Future<void> _exportConfig(BuildContext context) async {
    try {
      final json = await controller.exportConfigJson();
      if (kIsWeb) {
        downloadTextFile('school_manager_config.json', json);
        if (context.mounted) {
          analytics.event('export_config');
          _message(context, 'Configurazione esportata.');
        }
        return;
      }
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Esporta configurazione',
        fileName: 'school_manager_config.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(json),
      );
      if (!context.mounted) return;
      if (saved != null) analytics.event('export_config');
      _message(context, saved == null
          ? 'Esportazione annullata.'
          : 'Configurazione esportata.');
    } catch (error) {
      if (context.mounted) _message(context, error.toString());
    }
  }

  Future<void> _importConfig(BuildContext context) async {
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Importa configurazione',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      final bytes = picked?.files.single.bytes;
      if (bytes == null || !context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Importare la configurazione?'),
          content: const Text(
            'Materie, lezioni, campanelle, risorse e impostazioni attuali saranno sostituite dal file. Compiti e dati ClasseViva restano invariati.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importa'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      await controller.importConfigJson(utf8.decode(bytes));
      if (context.mounted) {
        analytics.event('import_config');
        _message(context, 'Configurazione importata.');
      }
    } on FormatException catch (error) {
      if (context.mounted) _message(context, error.message);
    } catch (error) {
      if (context.mounted) _message(context, error.toString());
    }
  }

  Future<void> _clearAllData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare tutti i dati?'),
        content: const Text(
          'Verranno eliminati definitivamente orario, materie, campanelle, aule, professori, compiti, dati ClasseViva salvati e la sessione collegata. L’operazione non è reversibile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina tutto'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await importController.signOut();
      await controller.clearAllData();
      await schoolDataController.loadLocal();
      if (context.mounted) _message(context, 'Tutti i dati sono stati eliminati.');
    } catch (error) {
      if (context.mounted) _message(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([controller, themeController]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            Text('Impostazioni',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Organizza campanelle, risorse e materie.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            Card(
              child: SwitchListTile.adaptive(
                secondary: Icon(themeController.isDarkMode
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined),
                title: const Text('Tema scuro'),
                subtitle: const Text('Mantieni questa scelta sul dispositivo.'),
                value: themeController.isDarkMode,
                onChanged: themeController.setDarkMode,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.weekend_outlined),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text('Fine settimana in agenda',
                              style:
                                  Theme.of(context).textTheme.titleMedium),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'all', label: Text('Lun–Dom')),
                          ButtonSegment(
                              value: 'sunday', label: Text('Lun–Sab')),
                          ButtonSegment(
                              value: 'none', label: Text('Lun–Ven')),
                        ],
                        selected: {themeController.weekendMode},
                        onSelectionChanged: (selection) =>
                            themeController
                                .setWeekendMode(selection.single),
                      ),
                    ]),
              ),
            ),
            const SizedBox(height: 20),
            const _SettingsSectionHeader(
                icon: Icons.link_outlined,
                title: 'ClasseViva',
                subtitle: 'Collega il registro elettronico per importare orario e dati',
                accent: AppPalette.classeViva),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ClassVivaLoginView(
                          controller: schoolDataController),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                                title:
                                    const Text('Importa da ClasseViva')),
                            body: ClassVivaImportView(
                              importController: importController,
                              timetableController: controller,
                              schoolDataController: schoolDataController,
                              analytics: analytics,
                            ),
                          ),
                        )),
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Importa orario'),
                      ),
                    ]),
              ),
            ),
            const SizedBox(height: 20),
            const _SettingsSectionHeader(
                icon: Icons.schedule_outlined,
                title: 'Orario scolastico',
                subtitle: 'Campanelle e numero di ore per giorno',
                accent: AppPalette.indigo),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (var day = 1; day <= 5; day++) ...[
                  if (day > 1)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: CircleAvatar(
                        child: Text(
                            '${controller.periodsForWeekday(day).length}')),
                    title: Text(_dayNames[day - 1]),
                    subtitle: Text(controller.periodsForWeekday(day).isEmpty
                        ? 'Non configurato'
                        : '${controller.periodsForWeekday(day).length} ore · ${_clock(controller.periodsForWeekday(day).first.startMinute)}–${_clock(controller.periodsForWeekday(day).last.endMinute)}'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => _configureDay(context, day),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 20),
            _resourceSection(context, ResourceCategory.room),
            const SizedBox(height: 16),
            _resourceSection(context, ResourceCategory.teacher),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                  child: const _SettingsSectionHeader(
                      icon: Icons.menu_book_outlined,
                      title: 'Materie',
                      subtitle: 'Colore, docenti e aule associate',
                      accent: AppPalette.amber)),
              FilledButton.tonalIcon(
                onPressed: () => _editSubject(context),
                icon: const Icon(Icons.add),
                label: const Text('Aggiungi'),
              ),
            ]),
            const SizedBox(height: 8),
            if (controller.timetable?.subjects.isEmpty ?? true)
              const Card(
                  child: ListTile(
                      title: Text(
                          'Crea le materie per poterle assegnare alle lezioni.'))),
            for (final subject
                in controller.timetable?.subjects ?? const <Subject>[])
              Card(
                child: ListTile(
                  leading:
                      CircleAvatar(backgroundColor: Color(subject.colorValue)),
                  title: Text(subject.name),
                  subtitle: Text([
                    if (subject.teachers.isNotEmpty)
                      'Professori: ${subject.teachers.join(', ')}',
                    if (subject.rooms.isNotEmpty)
                      'Aule: ${subject.rooms.join(', ')}',
                  ].isEmpty
                      ? 'Nessun professore o aula configurato'
                      : [
                          if (subject.teachers.isNotEmpty)
                            'Professori: ${subject.teachers.join(', ')}',
                          if (subject.rooms.isNotEmpty)
                            'Aule: ${subject.rooms.join(', ')}',
                        ].join('\n')),
                  isThreeLine:
                      subject.teachers.isNotEmpty && subject.rooms.isNotEmpty,
                  onTap: () => _editSubject(context, subject),
                  trailing: IconButton(
                    tooltip: 'Elimina materia',
                    onPressed: () => _deleteSubject(context, subject),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            const _SettingsSectionHeader(
                icon: Icons.backup_outlined,
                title: 'Backup',
                subtitle: 'Esporta o ripristina materie, orario e impostazioni',
                accent: AppPalette.teal),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.upload_outlined),
                  title: const Text('Esporta configurazione'),
                  subtitle: const Text(
                      'Materie, colori, professori, aule, campanelle e impostazioni. Le credenziali non vengono mai incluse.'),
                  onTap: () => _exportConfig(context),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Importa configurazione'),
                  subtitle: const Text(
                      'Ripristina un file JSON esportato in precedenza.'),
                  onTap: () => _importConfig(context),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            const _SettingsSectionHeader(
                icon: Icons.bug_report_outlined,
                title: 'Debug',
                subtitle: 'Strumenti avanzati per diagnosticare problemi',
                accent: AppPalette.indigo),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                SwitchListTile.adaptive(
                  secondary: const Icon(Icons.bug_report_outlined),
                  title: const Text('Overlay metadati'),
                  subtitle: const Text(
                      'Mostra i dati grezzi e quelli ricavati su ogni card e dialog.'),
                  value: themeController.debugMode,
                  onChanged: themeController.setDebugMode,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.data_object),
                  title: const Text('Metadati ClasseViva'),
                  subtitle: const Text(
                      'Mostra tutti i dati grezzi ricevuti e i valori ricavati dall’app (materia abbinata, tag verifica, tipo evento…).'),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DebugMetadataView(
                      timetableController: controller,
                      schoolDataController: schoolDataController,
                    ),
                  )),
                ),
              ]),
            ),
            const SizedBox(height: 20),
            _SettingsSectionHeader(
                icon: Icons.warning_amber_outlined,
                title: 'Zona pericolosa',
                subtitle: 'Operazioni irreversibili sui dati dell’app',
                accent: Theme.of(context).colorScheme.error),
            Card(
              child: ListTile(
                leading: Icon(Icons.delete_forever_outlined,
                    color: Theme.of(context).colorScheme.error),
                title: Text('Elimina tutti i dati',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
                subtitle: const Text(
                    'Orario, materie, compiti, dati ClasseViva e sessione collegata.'),
                trailing: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: () => _clearAllData(context),
                  child: const Text('Elimina'),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _resourceSection(BuildContext context, ResourceCategory category) {
    final rooms = category == ResourceCategory.room;
    final resources = controller.resources
        .where((resource) => resource.category == category)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: _SettingsSectionHeader(
          icon: rooms ? Icons.meeting_room_outlined : Icons.people_outline,
          title: rooms ? 'Aule e laboratori' : 'Professori',
          subtitle: rooms
              ? 'Spazi usati nelle lezioni'
              : 'Docenti e ITP associabili alle materie',
          accent: rooms ? AppPalette.teal : AppPalette.amber,
        )),
        FilledButton.tonalIcon(
          onPressed: () => _editResource(context, category),
          icon: const Icon(Icons.add),
          label: const Text('Aggiungi'),
        ),
      ]),
      const SizedBox(height: 6),
      if (resources.isEmpty)
        Card(
            child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Icon(
                      rooms
                          ? Icons.meeting_room_outlined
                          : Icons.person_add_alt_1_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(rooms
                          ? 'Nessuna aula o laboratorio. Aggiungine uno per associarlo alle materie.'
                          : 'Nessun professore. Aggiungine uno per associarlo alle materie.')),
                ]))),
      if (resources.isNotEmpty)
        Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var index = 0; index < resources.length; index++) ...[
                if (index > 0)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: CircleAvatar(
                      child: Icon(
                          rooms
                              ? (resources[index].type ==
                                      RoomType.laboratory.name
                                  ? Icons.science_outlined
                                  : Icons.meeting_room_outlined)
                              : Icons.person_outline,
                          size: 20)),
                  title: Text(resources[index].name),
                  subtitle: Text(rooms
                      ? (resources[index].type == RoomType.laboratory.name
                          ? 'Laboratorio'
                          : 'Aula')
                      : (resources[index].type == TeacherType.itp.name
                          ? 'ITP · Istruttore Tecnico Pratico'
                          : 'Docente')),
                  onTap: () =>
                      _editResource(context, category, resources[index]),
                  trailing: Wrap(spacing: 0, children: [
                    IconButton(
                        tooltip: 'Rinomina',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () =>
                            _editResource(context, category, resources[index])),
                    IconButton(
                        tooltip: 'Rimuovi',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            _deleteResource(context, resources[index])),
                  ]),
                ),
              ],
            ])),
    ]);
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.accent});
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? accent;

  @override
  Widget build(BuildContext context) => Row(children: [
        CircleAvatar(
            radius: 19,
            backgroundColor: accent,
            foregroundColor:
                accent == null ? null : Colors.white,
            child: Icon(icon, size: 20)),
        const SizedBox(width: 11),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(subtitle,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ])),
      ]);
}

class SubjectEditorDialog extends StatefulWidget {
  const SubjectEditorDialog(
      {super.key,
      this.subject,
      this.initialColor,
      this.availableTeachers = const [],
      this.availableRooms = const []});
  final Subject? subject;
  final int? initialColor;
  final List<String> availableTeachers;
  final List<String> availableRooms;

  @override
  State<SubjectEditorDialog> createState() => _SubjectEditorDialogState();
}

class _SubjectEditorDialogState extends State<SubjectEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _hex;
  late final TextEditingController _classvivaId;
  late final Set<String> _teachers;
  late final Set<String> _rooms;
  late int _color;
  String? _colorError;

  @override
  void initState() {
    super.initState();
    final subject = widget.subject;
    _color = subject?.colorValue ?? widget.initialColor ?? 0xFF6750A4;
    _name = TextEditingController(text: subject?.name ?? '');
    _classvivaId = TextEditingController(text: subject?.classvivaId ?? '');
    _hex = TextEditingController(
        text: '#${_color.toRadixString(16).padLeft(8, '0').toUpperCase()}');
    _teachers = {...?subject?.teachers};
    _rooms = {...?subject?.rooms};
  }

  @override
  void dispose() {
    _name.dispose();
    _hex.dispose();
    _classvivaId.dispose();
    super.dispose();
  }

  void _changeHex(String value) {
    final digits = value.trim().replaceFirst('#', '');
    final parsed = int.tryParse(digits, radix: 16);
    if (parsed == null || (digits.length != 6 && digits.length != 8)) {
      setState(() => _colorError = 'Inserisci #RRGGBB o #AARRGGBB');
      return;
    }
    setState(() {
      _color = digits.length == 6 ? 0xFF000000 | parsed : parsed;
      _colorError = null;
    });
  }

  Future<void> _pickColor() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => SubjectColorPickerDialog(initialColor: _color),
    );
    if (picked == null) return;
    setState(() {
      _color = picked;
      _hex.text = '#${picked.toRadixString(16).padLeft(8, '0').toUpperCase()}';
      _colorError = null;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title:
            Text(widget.subject == null ? 'Nuova materia' : 'Modifica materia'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: _name,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Materia')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                      controller: _hex,
                      onChanged: _changeHex,
                      decoration: InputDecoration(
                          labelText: 'Colore esadecimale',
                          prefixIcon: const Icon(Icons.palette_outlined),
                          errorText: _colorError)),
                ),
                IconButton(
                    tooltip: 'Scegli colore',
                    onPressed: _pickColor,
                    icon: const Icon(Icons.color_lens_outlined)),
              ]),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickColor,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                        color: Color(_color),
                        borderRadius: BorderRadius.circular(8))),
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: _classvivaId,
                  decoration: const InputDecoration(
                      labelText: 'Nome o ID materia su ClasseViva',
                      hintText: 'Es. MATEMATICA — per abbinare gli eventi',
                      prefixIcon: Icon(Icons.link_outlined))),
              const SizedBox(height: 12),
              _ResourceSelection(
                  label: 'Professori',
                  options: {...widget.availableTeachers, ..._teachers},
                  selected: _teachers,
                  onChanged: (name, selected) => setState(() =>
                      selected ? _teachers.add(name) : _teachers.remove(name))),
              const SizedBox(height: 12),
              _ResourceSelection(
                  label: 'Aule e laboratori',
                  options: {...widget.availableRooms, ..._rooms},
                  selected: _rooms,
                  onChanged: (name, selected) => setState(
                      () => selected ? _rooms.add(name) : _rooms.remove(name))),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla')),
          FilledButton(
            onPressed: _name.text.trim().isEmpty || _colorError != null
                ? null
                : () => Navigator.pop(
                    context,
                    Subject(
                      id: widget.subject?.id ??
                          'subject-${DateTime.now().microsecondsSinceEpoch}',
                      name: _name.text,
                      colorValue: _color,
                      classvivaId: _classvivaId.text.trim(),
                      teachers: _teachers.toList(),
                      rooms: _rooms.toList(),
                    )),
            child: const Text('Salva'),
          ),
        ],
      );
}

class _ResourceSelection extends StatelessWidget {
  const _ResourceSelection(
      {required this.label,
      required this.options,
      required this.selected,
      required this.onChanged});
  final String label;
  final Set<String> options;
  final Set<String> selected;
  final void Function(String, bool) onChanged;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        if (options.isEmpty)
          const Text('Aggiungi prima le voci nelle impostazioni.'),
        Wrap(spacing: 4, children: [
          for (final name in options)
            FilterChip(
                label: Text(name),
                selected: selected.contains(name),
                onSelected: (value) => onChanged(name, value)),
        ]),
      ]);
}

class ResourceEditorDialog extends StatefulWidget {
  const ResourceEditorDialog(
      {super.key, required this.category, this.resource});
  final ResourceCategory category;
  final ClassroomResource? resource;
  @override
  State<ResourceEditorDialog> createState() => _ResourceEditorDialogState();
}

class _ResourceEditorDialogState extends State<ResourceEditorDialog> {
  final _name = TextEditingController();
  String _type = RoomType.classroom.name;
  @override
  void initState() {
    super.initState();
    _name.text = widget.resource?.name ?? '';
    _type = widget.resource?.type ??
        (widget.category == ResourceCategory.teacher
            ? TeacherType.teacher.name
            : RoomType.classroom.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.category == ResourceCategory.room;
    return AlertDialog(
      title: Text(widget.resource == null
          ? (room ? 'Aggiungi aula' : 'Aggiungi professore')
          : (room ? 'Modifica aula o laboratorio' : 'Modifica professore')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            controller: _name,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
                labelText: room ? 'Nome aula/laboratorio' : 'Nome e cognome')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _type,
          decoration: InputDecoration(labelText: room ? 'Tipo' : 'Ruolo'),
          items: room
              ? const [
                  DropdownMenuItem(value: 'classroom', child: Text('Aula')),
                  DropdownMenuItem(
                      value: 'laboratory', child: Text('Laboratorio'))
                ]
              : const [
                  DropdownMenuItem(value: 'teacher', child: Text('Docente')),
                  DropdownMenuItem(
                      value: 'itp',
                      child: Text('ITP · Istruttore Tecnico Pratico'))
                ],
          onChanged: (value) {
            if (value != null) setState(() => _type = value);
          },
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla')),
        FilledButton(
            onPressed: _name.text.trim().isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    ClassroomResource(
                        id: widget.resource?.id ??
                            'resource-${DateTime.now().microsecondsSinceEpoch}',
                        name: _name.text.trim(),
                        category: widget.category,
                        type: _type)),
            child: const Text('Salva')),
      ],
    );
  }
}

class SubjectColorPickerDialog extends StatefulWidget {
  const SubjectColorPickerDialog({super.key, required this.initialColor});
  final int initialColor;

  @override
  State<SubjectColorPickerDialog> createState() =>
      _SubjectColorPickerDialogState();
}

class _SubjectColorPickerDialogState extends State<SubjectColorPickerDialog> {
  static const _palette = [
    0xFF6750A4,
    0xFF0077B6,
    0xFF008A6A,
    0xFFD1495B,
    0xFFB05A00,
    0xFF7B61A8,
    0xFF00838F,
    0xFF8C3F65,
    0xFF4D7C0F,
    0xFF536DFE,
    0xFFAD1457,
    0xFF6D4C41,
    0xFF3949AB,
    0xFF558B2F,
    0xFFE65100,
  ];
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(Color(widget.initialColor));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Scegli il colore'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final color in _palette)
                InkWell(
                  onTap: () =>
                      setState(() => _hsv = HSVColor.fromColor(Color(color))),
                  customBorder: const CircleBorder(),
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: Color(color),
                    child: _hsv.toColor().toARGB32() == color
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            Container(
                height: 32,
                decoration: BoxDecoration(
                    color: _hsv.toColor(),
                    borderRadius: BorderRadius.circular(8))),
            Slider(
              min: 0,
              max: 360,
              value: _hsv.hue,
              onChanged: (value) => setState(() => _hsv = _hsv.withHue(value)),
            ),
            Slider(
              min: 0.25,
              max: 1,
              value: _hsv.saturation,
              onChanged: (value) =>
                  setState(() => _hsv = _hsv.withSaturation(value)),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, _hsv.toColor().toARGB32()),
              child: const Text('Seleziona')),
        ],
      );
}

class ClassVivaImportView extends StatefulWidget {
  const ClassVivaImportView({
    super.key,
    required this.importController,
    required this.timetableController,
    required this.schoolDataController,
    required this.analytics,
  });
  final ImportController importController;
  final TimetableController timetableController;
  final SchoolDataController schoolDataController;
  final AppAnalytics analytics;

  @override
  State<ClassVivaImportView> createState() => _ClassVivaImportViewState();
}

class _ClassVivaImportViewState extends State<ClassVivaImportView> {
  bool? _hasSession;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = await widget.importController.hasSession();
    if (mounted) setState(() => _hasSession = session);
  }

  /// Le pagine che richiedono ClasseViva reindirizzano al login
  /// centralizzato (lo stesso mostrato nelle Impostazioni).
  Future<void> _openLogin() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Accedi a ClasseViva')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ClassVivaLoginView(
              controller: widget.schoolDataController,
              onSignedIn: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ));
    await _checkSession();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.importController,
        builder: (context, _) {
          final controller = widget.importController;
          if (_hasSession == false) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link_off_outlined, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'Per importare l’orario devi prima collegare il tuo account ClasseViva.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppPalette.classeViva,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _openLogin,
                      icon: const Icon(Icons.login),
                      label: const Text('Accedi a ClasseViva'),
                    ),
                  ],
                ),
              ),
            );
          }
          final proposal = controller.proposal;
          final subjectNames = proposal == null
              ? <String, String>{}
              : {
                  for (final subject in proposal.subjects)
                    subject.id: subject.name
                };
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Importa le lezioni della settimana precedente usando la sessione ClasseViva salvata.',
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: controller.isLoading ? null : _signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Elimina sessione salvata'),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: controller.isLoading ? null : _useSavedSession,
                icon: controller.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: const Text('Recupera lezioni'),
              ),
              if (controller.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  controller.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (proposal != null &&
                  (proposal.lessons.isNotEmpty ||
                      proposal.missingPeriods.isNotEmpty)) ...[
                const SizedBox(height: 20),
                Text(
                  'Bozza: ${proposal.lessons.length} lezioni',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                OutlinedButton.icon(
                  onPressed: _guessPeriodTimes,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Stima campanelle dalle lezioni'),
                ),
                const SizedBox(height: 8),
                ...proposal.lessons.map(
                  (lesson) => ListTile(
                    dense: true,
                    title: Text(subjectNames[lesson.subjectId] ?? 'Materia'),
                    subtitle: Text(
                      '${_dayNames[lesson.weekday - 1]} • ${_clock(lesson.startMinute)}–${_clock(lesson.endMinute)}',
                    ),
                  ),
                ),
                ...proposal.warnings.map(
                  (warning) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '• $warning',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ),
                if (proposal.missingPeriods.isNotEmpty) ...[
                  Text(
                    'Per importare tutte le lezioni configura l’orario delle ore ${proposal.missingPeriods.join(', ')}.',
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _configurePeriods(proposal.missingPeriods),
                    icon: const Icon(Icons.schedule),
                    label: const Text('Configura campanelle'),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: proposal.missingPeriods.isEmpty &&
                          proposal.lessons.isNotEmpty
                      ? _applyProposal
                      : null,
                  child: const Text('Conferma e sostituisci l’orario'),
                ),
                TextButton(
                  onPressed: controller.discard,
                  child: const Text('Annulla importazione'),
                ),
              ],
            ],
          );
        },
      );

  Future<void> _useSavedSession() async {
    await widget.importController.useSavedSession();
  }

  Future<void> _signOut() async {
    await widget.importController.signOut();
    if (mounted) _message(context, 'Sessione ClasseViva eliminata.');
  }

  Future<void> _applyProposal() async {
    final proposal = widget.importController.proposal;
    if (proposal == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sostituire l’orario attuale?'),
        content: const Text(
          'La bozza selezionata sostituirà tutte le lezioni e materie attualmente salvate.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sostituisci'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await widget.timetableController.applyImport(
        subjects: proposal.subjects,
        lessons: proposal.lessons,
      );
      widget.importController.discard();
      if (!mounted) return;
      widget.analytics.event('apply_import');
      _message(context, 'Orario aggiornato.');
    } catch (error) {
      if (mounted) _message(context, error.toString());
    }
  }

  Future<void> _configurePeriods(List<int> numbers) async {
    final configured = await showDialog<List<PeriodTime>>(
      context: context,
      builder: (context) => _PeriodSetupDialog(numbers: numbers),
    );
    if (configured == null || !mounted) return;
    try {
      await widget.importController.savePeriodTimes(configured);
    } catch (error) {
      if (mounted) _message(context, error.toString());
    }
  }

  Future<void> _guessPeriodTimes() async {
    final guesses = await widget.importController.guessPeriodTimes();
    if (guesses.isEmpty || !mounted) {
      if (mounted) _message(context, 'Non ci sono lezioni da cui stimare le ore.');
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stima campanelle'),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'Il numero di ore viene dalle lezioni ClasseViva. Per gli orari mancanti uso le campanelle già configurate; altrimenti stimo lezione da 60 minuti dalle 08:00, con 10 minuti di intervallo. Potrai correggere la stima in Impostazioni.',
              ),
              const SizedBox(height: 12),
              for (var weekday = 1; weekday <= 7; weekday++)
                if (guesses.any((period) => period.weekday == weekday))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_dayNames[weekday - 1]),
                    subtitle: Text(guesses
                        .where((period) => period.weekday == weekday)
                        .map((period) =>
                            '${period.number}ª ${_clock(period.startMinute)}–${_clock(period.endMinute)}')
                        .join(' · ')),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salva stima'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await widget.importController.savePeriodTimes(guesses);
    } catch (error) {
      if (mounted) _message(context, error.toString());
    }
  }
}

class _PeriodSetupDialog extends StatefulWidget {
  const _PeriodSetupDialog({required this.numbers});
  final List<int> numbers;
  @override
  State<_PeriodSetupDialog> createState() => _PeriodSetupDialogState();
}

class _PeriodSetupDialogState extends State<_PeriodSetupDialog> {
  final Map<int, (TimeOfDay, TimeOfDay)> _times = {};

  Future<void> _choose(int number) async {
    final previous = _times[number];
    final start = await showTimePicker(
      context: context,
      initialTime: previous?.$1 ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: previous?.$2 ??
          TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute),
    );
    if (end != null) setState(() => _times[number] = (start, end));
  }

  int _minute(TimeOfDay time) => time.hour * 60 + time.minute;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Orari delle ore'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: widget.numbers.map((number) {
              final interval = _times[number];
              return ListTile(
                title: Text('Ora $number'),
                subtitle: Text(
                  interval == null
                      ? 'Orario non impostato'
                      : '${interval.$1.format(context)} – ${interval.$2.format(context)}',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _choose(number),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: _times.length != widget.numbers.length ||
                    _times.values.any(
                      (pair) => _minute(pair.$1) >= _minute(pair.$2),
                    )
                ? null
                : () => Navigator.pop(context, [
                      for (final entry in _times.entries)
                        PeriodTime(
                          number: entry.key,
                          startMinute: _minute(entry.value.$1),
                          endMinute: _minute(entry.value.$2),
                        ),
                    ]),
            child: const Text('Salva orari'),
          ),
        ],
      );
}

class _LessonFormResult {
  const _LessonFormResult(
    this.subject,
    this.subjectId,
    this.weekday,
    this.start,
    this.end,
    this.startPeriod,
    this.endPeriod,
    this.teachers,
    this.rooms,
  );
  final String subject;
  final String subjectId;
  final int weekday;
  final int start;
  final int end;
  final int startPeriod;
  final int endPeriod;
  final List<String> teachers;
  final List<String> rooms;
}

class BellScheduleDialog extends StatefulWidget {
  const BellScheduleDialog(
      {super.key, required this.initialPeriods, required this.weekday});
  final List<PeriodTime> initialPeriods;
  final int weekday;

  @override
  State<BellScheduleDialog> createState() => _BellScheduleDialogState();
}

class _BellScheduleDialogState extends State<BellScheduleDialog> {
  late int _count;
  late List<PeriodTime?> _periods;

  @override
  void initState() {
    super.initState();
    final initial = [...widget.initialPeriods]
      ..sort((a, b) => a.number.compareTo(b.number));
    _count = initial.isEmpty ? 6 : initial.last.number;
    _periods = List<PeriodTime?>.generate(
      _count,
      (index) {
        for (final period in initial) {
          if (period.number == index + 1) return period;
        }
        return null;
      },
    );
    _fillDefaults(_periods.length);
  }

  void _fillDefaults(int count) {
    var nextStart = 8 * 60;
    for (var index = 0; index < count; index++) {
      if (_periods[index] == null) {
        final start = nextStart.clamp(0, 23 * 60);
        final end = (start + 60).clamp(start + 1, 1440);
        _periods[index] = PeriodTime(
          number: index + 1,
          startMinute: start,
          endMinute: end,
          weekday: widget.weekday,
        );
      }
      nextStart = _periods[index]!.endMinute;
    }
  }

  void _resize(int count) {
    setState(() {
      if (count < _periods.length) {
        _periods = _periods.take(count).toList();
      } else {
        _periods = [
          ..._periods,
          ...List<PeriodTime?>.filled(count - _periods.length, null)
        ];
        _fillDefaults(count);
      }
      _count = count;
    });
  }

  Future<void> _editPeriod(int index) async {
    final period = _periods[index]!;
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: period.startMinute ~/ 60, minute: period.startMinute % 60),
      helpText: 'Inizio ${_ordinal(index + 1)}',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: period.endMinute ~/ 60, minute: period.endMinute % 60),
      helpText: 'Fine ${_ordinal(index + 1)}',
    );
    if (end == null || !mounted) return;
    final startMinute = start.hour * 60 + start.minute;
    final endMinute = end.hour * 60 + end.minute;
    if (startMinute >= endMinute) {
      _message(context, 'La campanella di fine deve seguire quella di inizio.');
      return;
    }
    setState(() {
      _periods[index] = PeriodTime(
        number: index + 1,
        startMinute: startMinute,
        endMinute: endMinute,
        weekday: widget.weekday,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final valid = _periods.length == _count &&
        _periods.every((period) => period != null) &&
        _periods
            .cast<PeriodTime>()
            .every((period) => period.startMinute < period.endMinute) &&
        !_periods.cast<PeriodTime>().asMap().entries.any((entry) =>
            entry.key > 0 &&
            _periods[entry.key - 1]!.endMinute > entry.value.startMinute);
    return AlertDialog(
      title: const Text('Campanelle e ore scolastiche'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Gli orari iniziali sono esempi: tocca ogni ora per impostare le campanelle della tua scuola.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _count,
            decoration:
                const InputDecoration(labelText: 'Numero di ore al giorno'),
            items: List.generate(
                20,
                (index) => DropdownMenuItem(
                    value: index + 1, child: Text('${index + 1} ore'))),
            onChanged: (count) {
              if (count != null) _resize(count);
            },
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: (_periods.length * 56.0).clamp(112.0, 360.0),
            child: ListView.builder(
              itemCount: _periods.length,
              itemBuilder: (context, index) {
                final period = _periods[index]!;
                return ListTile(
                  dense: true,
                  title: Text('${_ordinal(index + 1)} ora'),
                  subtitle: Text(
                      '${_clock(period.startMinute)} – ${_clock(period.endMinute)}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editPeriod(index),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla')),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, [
                    for (final period in _periods.cast<PeriodTime>())
                      PeriodTime(
                        number: period.number,
                        startMinute: period.startMinute,
                        endMinute: period.endMinute,
                        weekday: widget.weekday,
                      ),
                  ])
              : null,
          child: const Text('Salva campanelle'),
        ),
      ],
    );
  }
}

class AddLessonDialog extends StatefulWidget {
  const AddLessonDialog(
      {super.key,
      this.initialLesson,
      this.initialSubject,
      this.periodsByWeekday = const {},
      this.subjects = const [],
      this.existingLessons = const [],
      this.initialWeekday,
      this.initialStartPeriod,
      this.initialEndPeriod});
  final Lesson? initialLesson;
  final Subject? initialSubject;
  final Map<int, List<PeriodTime>> periodsByWeekday;
  final List<Subject> subjects;
  final List<Lesson> existingLessons;
  final int? initialWeekday;
  final int? initialStartPeriod;
  final int? initialEndPeriod;
  @override
  State<AddLessonDialog> createState() => _AddLessonDialogState();
}

class _AddLessonDialogState extends State<AddLessonDialog> {
  late int _weekday;
  String? _subjectId;
  int _startPeriod = 1;
  int _duration = 1;
  final Set<String> _teachers = {};
  final Set<String> _rooms = {};

  List<int> get _days {
    final days = widget.periodsByWeekday.keys.toList()..sort();
    return days.isEmpty ? [1] : days;
  }

  List<PeriodTime> get _periods =>
      widget.periodsByWeekday[_weekday] ??
      List.generate(
          8,
          (index) => PeriodTime(
                number: index + 1,
                startMinute: 8 * 60 + index * 60,
                endMinute: 9 * 60 + index * 60,
                weekday: _weekday,
              ));
  Subject? get _selectedSubject {
    for (final subject in widget.subjects) {
      if (subject.id == _subjectId) return subject;
    }
    return null;
  }

  PeriodTime? _period(int number) {
    for (final period in _periods) {
      if (period.number == number) return period;
    }
    return null;
  }

  int get _maxDuration {
    var count = 0;
    while (_period(_startPeriod + count) != null) {
      count++;
    }
    return count;
  }

  Lesson? _lessonAtPeriod(int number) {
    for (final lesson in widget.existingLessons) {
      if (lesson.weekday != _weekday || lesson.id == widget.initialLesson?.id) {
        continue;
      }
      if (lesson.startPeriod != null && lesson.endPeriod != null) {
        if (number >= lesson.startPeriod! && number < lesson.endPeriod!) {
          return lesson;
        }
      } else {
        final period = _period(number);
        if (period != null &&
            period.startMinute < lesson.endMinute &&
            lesson.startMinute < period.endMinute) {
          return lesson;
        }
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final lesson = widget.initialLesson;
    _weekday = lesson?.weekday ??
        widget.initialWeekday ??
        (_days.isEmpty
            ? 1
            : DateTime.now().weekday <= 5 &&
                    _days.contains(DateTime.now().weekday)
                ? DateTime.now().weekday
                : _days.first);
    _subjectId = lesson?.subjectId ??
        widget.initialSubject?.id ??
        (widget.subjects.isEmpty ? null : widget.subjects.first.id);
    if (lesson != null) {
      _teachers.addAll(lesson.teachers);
      _rooms.addAll(lesson.rooms);
      final start = lesson.startPeriod ??
          _periods
              .where((period) => period.startMinute == lesson.startMinute)
              .map((period) => period.number)
              .firstOrNull ??
          _periods.first.number;
      _startPeriod = start;
      final end = lesson.endPeriod ??
          (_periods
                      .where((period) => period.endMinute == lesson.endMinute)
                      .map((period) => period.number)
                      .firstOrNull ??
                  _startPeriod) +
              1;
      _duration = (end - _startPeriod).clamp(1, _maxDuration.clamp(1, 20));
    } else if (widget.initialStartPeriod != null) {
      _startPeriod = widget.initialStartPeriod!;
      if (widget.initialEndPeriod != null) {
        _duration = widget.initialEndPeriod! - _startPeriod;
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.initialLesson == null
            ? 'Nuova lezione'
            : 'Modifica lezione'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _subjectId,
                decoration: const InputDecoration(labelText: 'Materia'),
                items: [
                  for (final subject in widget.subjects)
                    DropdownMenuItem(
                      value: subject.id,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        CircleAvatar(
                            radius: 7,
                            backgroundColor: Color(subject.colorValue)),
                        const SizedBox(width: 10),
                        Flexible(
                            child: Text(subject.name,
                                overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _subjectId = id;
                  final subject = _selectedSubject;
                  _teachers.removeWhere((teacher) =>
                      !(subject?.teachers.contains(teacher) ?? false));
                  _rooms.removeWhere(
                      (room) => !(subject?.rooms.contains(room) ?? false));
                }),
              ),
              if (widget.subjects.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Crea prima una materia nelle Impostazioni.'),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Giorno',
                    style: Theme.of(context).textTheme.labelLarge),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final day in _days)
                    ChoiceChip(
                      label: Text(_dayNames[day - 1].substring(0, 3)),
                      selected: _weekday == day,
                      onSelected: (_) => setState(() {
                        _weekday = day;
                        _startPeriod = _periods.first.number;
                        _duration = 1;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _startPeriod,
                decoration: const InputDecoration(labelText: 'Ora di inizio'),
                items: [
                  for (final period in _periods)
                    DropdownMenuItem(
                      value: period.number,
                      enabled: true,
                      child: Builder(builder: (context) {
                        final occupied = _lessonAtPeriod(period.number);
                        Subject? occupiedSubject;
                        for (final subject in widget.subjects) {
                          if (subject.id == occupied?.subjectId) {
                            occupiedSubject = subject;
                          }
                        }
                        return Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                              '${_ordinal(period.number)} ora · ${_clock(period.startMinute)}'),
                          if (occupiedSubject != null) ...[
                            const SizedBox(width: 8),
                            CircleAvatar(
                                radius: 6,
                                backgroundColor:
                                    Color(occupiedSubject.colorValue)),
                            const SizedBox(width: 5),
                            Flexible(
                                child: Text(occupiedSubject.name,
                                    overflow: TextOverflow.ellipsis)),
                          ],
                        ]);
                      }),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _startPeriod = value ?? 1;
                  _duration = 1;
                }),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Durata',
                    style: Theme.of(context).textTheme.labelLarge),
              ),
              Wrap(spacing: 6, children: [
                for (var duration = 1; duration <= _maxDuration; duration++)
                  ChoiceChip(
                    label: Text(duration == 1 ? '1 ora' : '$duration ore'),
                    selected: _duration == duration,
                    onSelected: _period(_startPeriod + duration - 1) == null
                        ? null
                        : (_) => setState(() => _duration = duration),
                  ),
              ]),
              Text(
                '${_ordinal(_startPeriod)}–${_ordinal(_startPeriod + _duration - 1)} ora · ${_clock(_period(_startPeriod)!.startMinute)}–${_clock(_period(_startPeriod + _duration - 1)!.endMinute)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_selectedSubject?.teachers.isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Professori',
                        style: Theme.of(context).textTheme.labelLarge)),
                Wrap(spacing: 4, children: [
                  for (final teacher in _selectedSubject!.teachers)
                    FilterChip(
                        label: Text(teacher),
                        selected: _teachers.contains(teacher),
                        onSelected: (selected) => setState(() => selected
                            ? _teachers.add(teacher)
                            : _teachers.remove(teacher))),
                ]),
              ],
              if (_selectedSubject?.rooms.isNotEmpty ?? false) ...[
                const SizedBox(height: 4),
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Aula',
                        style: Theme.of(context).textTheme.labelLarge)),
                Wrap(spacing: 4, children: [
                  for (final room in _selectedSubject!.rooms)
                    FilterChip(
                        label: Text(room),
                        selected: _rooms.contains(room),
                        onSelected: (selected) => setState(() =>
                            selected ? _rooms.add(room) : _rooms.remove(room))),
                ]),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              if (_subjectId == null ||
                  _periods.isEmpty ||
                  _period(_startPeriod + _duration - 1) == null) {
                _message(
                    context, 'Seleziona una materia e un intervallo valido.');
                return;
              }
              Navigator.pop(
                context,
                _LessonFormResult(
                  _selectedSubject!.name,
                  _subjectId!,
                  _weekday,
                  _period(_startPeriod)!.startMinute,
                  _period(_startPeriod + _duration - 1)!.endMinute,
                  _startPeriod,
                  _startPeriod + _duration,
                  _teachers.toList(),
                  _rooms.toList(),
                ),
              );
            },
            child: const Text('Salva'),
          ),
        ],
      );
}

const _dayNames = [
  'Lunedì',
  'Martedì',
  'Mercoledì',
  'Giovedì',
  'Venerdì',
  'Sabato',
  'Domenica',
];

String _clock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

String _ordinal(int number) => '$numberª';

void _message(BuildContext context, String message) => ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
