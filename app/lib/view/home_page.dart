import 'package:flutter/material.dart';

import '../controller/import_controller.dart';
import '../controller/school_data_controller.dart';
import '../controller/theme_controller.dart';
import '../controller/timetable_controller.dart';
import '../model/entities/lesson.dart';
import '../model/entities/subject.dart';
import '../model/entities/period_time.dart';
import '../model/services/app_analytics.dart';
import '../util/update_checker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'formatters.dart';
import 'multi_select.dart';
import 'welcome_dialog.dart';
import 'classviva_import_page.dart';
import 'school_pages.dart';
import 'settings_view.dart';

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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _showWelcomeIfNeeded());
  }

  /// Tutorial di benvenuto mostrato solo al primo avvio dell'app.
  Future<void> _showWelcomeIfNeeded() async {
    if (widget.themeController.hasSeenWelcome || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const WelcomeDialog(),
    );
    await widget.themeController.markWelcomeSeen();
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
              timetableController: widget.timetableController,
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
              icon: Icon(Icons.schedule_outlined),
              selectedIcon: Icon(Icons.schedule),
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
      showAppMessage(context, 'Crea prima una materia nelle impostazioni.');
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
      showAppMessage(context, 'Configura almeno un giorno nelle impostazioni.');
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
      if (context.mounted) showAppMessage(context, error.toString());
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
                                          child: Text(kDayNames[index]))),
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
      if (mounted) showAppMessage(context, error.toString());
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
      if (mounted) showAppMessage(context, error.toString());
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

  /// Altezza minima di un'ora: sotto questa soglia le lezioni non si
  /// leggono più e la griglia torna scrollabile.
  static const _minPeriodHeight = 56.0;
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
      // Le ore si comprimono per riempire lo schermo: se anche all'altezza
      // minima non ci stanno tutte, la griglia resta scrollabile.
      final reserved =
          42.0 + 12.0 + (_selected.isNotEmpty ? 56.0 : 0.0);
      final available = constraints.maxHeight - reserved;
      final periodHeight = rowCount == 0
          ? _WeekGrid._periodHeight
          : (available / rowCount)
              .clamp(_WeekGrid._minPeriodHeight, _WeekGrid._periodHeight);
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
                      child: Text(kDayNames[day - 1].toUpperCase(),
                          style: Theme.of(context).textTheme.titleSmall))),
          ]),
          Expanded(
              child: SingleChildScrollView(
                  child: SizedBox(
            height: rowCount * periodHeight + 12,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: _WeekGrid._periodLabelWidth,
                  child: Column(children: [
                    for (var index = 0; index < rowCount; index++)
                      SizedBox(
                          height: periodHeight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 5, right: 4),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(ordinalSuffix(index + 1),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge),
                                  if ((periodsByWeekday[weekdays.first] ??
                                              const <PeriodTime>[])
                                          .length >
                                      index) ...[
                                    Text(
                                        formatClock(periodsByWeekday[
                                                weekdays.first]![index]
                                            .startMinute),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall),
                                    Text(
                                        formatClock(periodsByWeekday[
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
                    height: rowCount * periodHeight,
                    child: _DayScheduleColumn(
                      day: day,
                      rowCount: rowCount,
                      dayWidth: dayWidth,
                      periodHeight: periodHeight,
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
      required this.periodHeight,
      required this.periods,
      required this.lessons,
      required this.subjects,
      required this.selected,
      required this.onTapCell,
      required this.onEdit,
      required this.onDelete});
  final int day, rowCount;
  final double dayWidth, periodHeight;
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
            top: (row - 1) * periodHeight,
            left: 0,
            right: 0,
            height: periodHeight,
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
            final top = (_start(lesson) - 1) * periodHeight +
                (joinedAbove ? 0 : 2);
            final bottom = (_end(lesson) - 1) * periodHeight -
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
              // Quando le ore sono compresse il contenuto eccede l'altezza:
              // lo scroll disattivato taglia il testo invece di far
              // traboccare il layout.
              child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
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
            ),
          )),
    );
  }
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
                      label: Text(kDayNames[day - 1].substring(0, 3)),
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
                              '${ordinalSuffix(period.number)} ora · ${formatClock(period.startMinute)}'),
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
              DropdownButtonFormField<int>(
                initialValue: _duration,
                decoration: const InputDecoration(labelText: 'Durata'),
                items: [
                  for (var duration = 1; duration <= _maxDuration; duration++)
                    DropdownMenuItem(
                      value: duration,
                      child: Text(
                          duration == 1 ? '1 ora' : '$duration ore'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _duration = value);
                },
              ),
              Text(
                '${ordinalSuffix(_startPeriod)}–${ordinalSuffix(_startPeriod + _duration - 1)} ora · ${formatClock(_period(_startPeriod)!.startMinute)}–${formatClock(_period(_startPeriod + _duration - 1)!.endMinute)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_selectedSubject?.teachers.isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                MultiSelectField(
                    label: 'Professori',
                    options: _selectedSubject!.teachers.toSet(),
                    selected: _teachers,
                    onChanged: (name, selected) => setState(() => selected
                        ? _teachers.add(name)
                        : _teachers.remove(name))),
              ],
              if (_selectedSubject?.rooms.isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                MultiSelectField(
                    label: 'Aula',
                    options: _selectedSubject!.rooms.toSet(),
                    selected: _rooms,
                    onChanged: (name, selected) => setState(() =>
                        selected ? _rooms.add(name) : _rooms.remove(name))),
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
                showAppMessage(
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

