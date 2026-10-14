import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controller/import_controller.dart';
import '../controller/school_data_controller.dart';
import '../controller/theme_controller.dart';
import '../controller/timetable_controller.dart';
import '../model/contracts/classviva_data_gateway.dart';
import '../model/entities/classroom_resource.dart';
import '../model/entities/period_time.dart';
import '../model/entities/subject.dart';
import '../model/services/app_analytics.dart';
import '../model/services/distinct_subject_color_selector.dart';
import '../util/text_file_download.dart';
import 'app_palette.dart';
import 'classviva_import_page.dart';
import 'classviva_login_view.dart';
import 'debug_metadata_view.dart';
import 'formatters.dart';
import 'multi_select.dart';

/// Una voce ricercabile delle impostazioni: apre la pagina che la contiene.
class _SettingEntry {
  const _SettingEntry({
    required this.icon,
    required this.title,
    required this.section,
    required this.page,
    this.keywords = '',
  });
  final IconData icon;
  final String title;

  /// Nome della pagina che contiene l'impostazione.
  final String section;
  final String keywords;
  final Widget page;

  bool matches(String query) {
    final haystack = '$title $section $keywords'.toLowerCase();
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .every(haystack.contains);
  }
}

/// Home delle impostazioni: indice delle pagine e ricerca globale.
class SettingsView extends StatefulWidget {
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

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Widget> get _pages => [
        _ClasseVivaPage(
          controller: widget.controller,
          themeController: widget.themeController,
          importController: widget.importController,
          schoolDataController: widget.schoolDataController,
          analytics: widget.analytics,
        ),
        _SchedulePage(controller: widget.controller),
        _SubjectsPage(controller: widget.controller),
        _ResourcesPage(controller: widget.controller),
        _TargetsPage(
          themeController: widget.themeController,
          schoolDataController: widget.schoolDataController,
        ),
        _AppearancePage(themeController: widget.themeController),
        _BackupPage(
          controller: widget.controller,
          importController: widget.importController,
          schoolDataController: widget.schoolDataController,
          analytics: widget.analytics,
        ),
        _InfoPage(themeController: widget.themeController),
        _DebugPage(
          controller: widget.controller,
          themeController: widget.themeController,
          schoolDataController: widget.schoolDataController,
        ),
        _DangerPage(
          controller: widget.controller,
          importController: widget.importController,
          schoolDataController: widget.schoolDataController,
        ),
      ];

  /// Ordine logico dell'indice: prima l'account/dati, poi la
  /// configurazione della scuola, infine app, backup e zona pericolosa.
  List<_SettingEntry> get _entries {
    final pages = _pages;
    return [
      _SettingEntry(
        icon: Icons.link_outlined,
        title: 'ClasseViva',
        section: 'ClasseViva',
        keywords: 'account registro elettronico sessione accedi login',
        page: pages[0],
      ),
      _SettingEntry(
        icon: Icons.login,
        title: 'Account ClasseViva',
        section: 'ClasseViva',
        keywords: 'sessione accedi credenziali disconnetti',
        page: pages[0],
      ),
      _SettingEntry(
        icon: Icons.download_outlined,
        title: 'Importa orario da ClasseViva',
        section: 'ClasseViva',
        keywords: 'lezioni settimana',
        page: pages[0],
      ),
      _SettingEntry(
        icon: Icons.sync_outlined,
        title: 'Aggiornamento automatico',
        section: 'ClasseViva',
        keywords: 'refresh intervallo minuti dati',
        page: pages[0],
      ),
      _SettingEntry(
        icon: Icons.percent_outlined,
        title: 'Percentuale assenze',
        section: 'ClasseViva',
        keywords: 'presenze assenze statistica giorni scuola',
        page: pages[0],
      ),
      _SettingEntry(
        icon: Icons.schedule_outlined,
        title: 'Orario scolastico',
        section: 'Orario scolastico',
        keywords: 'campanelle ore giorni condivise',
        page: pages[1],
      ),
      _SettingEntry(
        icon: Icons.notifications_outlined,
        title: 'Campanelle condivise',
        section: 'Orario scolastico',
        keywords: 'orari ore inizio fine',
        page: pages[1],
      ),
      _SettingEntry(
        icon: Icons.format_list_numbered,
        title: 'Numero di ore per giorno',
        section: 'Orario scolastico',
        keywords: 'giorni ore lezioni',
        page: pages[1],
      ),
      _SettingEntry(
        icon: Icons.menu_book_outlined,
        title: 'Materie',
        section: 'Materie',
        keywords: 'colore docenti aule classeviva',
        page: pages[2],
      ),
      _SettingEntry(
        icon: Icons.meeting_room_outlined,
        title: 'Aule e professori',
        section: 'Aule e professori',
        keywords: 'aule laboratori professori docenti risorse',
        page: pages[3],
      ),
      _SettingEntry(
        icon: Icons.meeting_room_outlined,
        title: 'Aule e laboratori',
        section: 'Aule e professori',
        keywords: 'risorse stanze lab',
        page: pages[3],
      ),
      _SettingEntry(
        icon: Icons.people_outline,
        title: 'Professori',
        section: 'Aule e professori',
        keywords: 'docenti itp insegnanti email telefono compleanno',
        page: pages[3],
      ),
      _SettingEntry(
        icon: Icons.flag_outlined,
        title: 'Obiettivi voti',
        section: 'Obiettivi voti',
        keywords: 'target media voti obiettivo materie',
        page: pages[4],
      ),
      _SettingEntry(
        icon: Icons.palette_outlined,
        title: 'Aspetto',
        section: 'Aspetto',
        keywords: 'tema scuro chiaro colori weekend agenda',
        page: pages[5],
      ),
      _SettingEntry(
        icon: Icons.dark_mode_outlined,
        title: 'Tema',
        section: 'Aspetto',
        page: pages[5],
      ),
      _SettingEntry(
        icon: Icons.weekend_outlined,
        title: 'Fine settimana in agenda',
        section: 'Aspetto',
        keywords: 'sabato domenica weekend',
        page: pages[5],
      ),
      _SettingEntry(
        icon: Icons.backup_outlined,
        title: 'Backup',
        section: 'Backup',
        keywords: 'esporta importa configurazione json ripristina',
        page: pages[6],
      ),
      _SettingEntry(
        icon: Icons.privacy_tip_outlined,
        title: 'Info e privacy',
        section: 'Info e privacy',
        keywords: 'privacy policy versione dati licenza open source',
        page: pages[7],
      ),
      if (widget.themeController.debugUnlocked)
        _SettingEntry(
          icon: Icons.bug_report_outlined,
          title: 'Debug',
          section: 'Debug',
          keywords: 'overlay metadati diagnostica',
          page: pages[8],
        ),
      _SettingEntry(
        icon: Icons.warning_amber_outlined,
        title: 'Zona pericolosa',
        section: 'Zona pericolosa',
        keywords: 'elimina dati cancella reset',
        page: pages[9],
      ),
    ];
  }

  void _open(_SettingEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(entry.section)),
        body: entry.page,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.themeController,
        builder: (context, _) => _buildIndex(context),
      );

  Widget _buildIndex(BuildContext context) {
    final query = _search.text.trim();
    final results =
        query.isEmpty ? const <_SettingEntry>[] : _entries.where((e) => e.matches(query)).toList();
    final index = _entries
        .where((e) => e.section == e.title)
        .toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: SearchBar(
          controller: _search,
          hintText: 'Cerca nelle impostazioni',
          leading: const Icon(Icons.search),
          trailing: [
            if (query.isNotEmpty)
              IconButton(
                tooltip: 'Cancella',
                icon: const Icon(Icons.close),
                onPressed: () => setState(_search.clear),
              ),
          ],
          onChanged: (_) => setState(() {}),
        ),
      ),
      Expanded(
        child: query.isNotEmpty
            ? (results.isEmpty
                ? const Center(
                    child: Text('Nessuna impostazione trovata.'))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      for (final entry in results)
                        Card(
                          child: ListTile(
                            leading: Icon(entry.icon),
                            title: Text(entry.title),
                            subtitle: Text(entry.section),
                            trailing:
                                const Icon(Icons.chevron_right),
                            onTap: () => _open(entry),
                          ),
                        ),
                    ],
                  ))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  Text('Organizza campanelle, materie, account e dati.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
                  const SizedBox(height: 12),
                  for (final entry in index)
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              _indexColor(entry.title).withValues(alpha: .14),
                          foregroundColor: _indexColor(entry.title),
                          child: Icon(entry.icon, size: 20),
                        ),
                        title: Text(entry.title),
                        subtitle: Text(_indexSubtitle(entry.title)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(entry),
                      ),
                    ),
                ],
              ),
      ),
    ]);
  }

  String _indexSubtitle(String title) => switch (title) {
        'Aspetto' => 'Tema e visualizzazione dell’agenda',
        'ClasseViva' =>
          'Account, aggiornamento automatico e importazione orario',
        'Orario scolastico' => 'Campanelle condivise e ore per giorno',
        'Materie' => 'Colore, docenti e aule associate',
        'Aule e professori' => 'Risorse assegnabili a materie e lezioni',
        'Backup' => 'Esporta o ripristina la configurazione',
        'Debug' => 'Strumenti avanzati di diagnostica',
        'Zona pericolosa' => 'Operazioni irreversibili sui dati',
        'Obiettivi voti' => 'Target di media globale e per materia',
        'Info e privacy' => 'Versione, privacy policy e licenze',
        _ => '',
      };

  /// Colore distintivo di ogni voce dell'indice.
  Color _indexColor(String title) => switch (title) {
        'ClasseViva' => AppPalette.classeViva,
        'Orario scolastico' => AppPalette.indigo,
        'Materie' => AppPalette.teal,
        'Aule e professori' => AppPalette.amber,
        'Obiettivi voti' => Colors.green.shade700,
        'Aspetto' => Colors.deepPurple.shade400,
        'Backup' => Colors.blue.shade700,
        'Info e privacy' => Colors.blueGrey.shade600,
        'Debug' => Colors.orange.shade800,
        'Zona pericolosa' => Colors.red.shade700,
        _ => Theme.of(context).colorScheme.primary,
      };
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

/// Wrapper comune delle pagine di impostazioni.
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: children,
      );
}

class _AppearancePage extends StatelessWidget {
  const _AppearancePage({required this.themeController});
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: themeController,
        builder: (context, _) => _SettingsPage(children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.brightness_6_outlined),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text('Tema',
                            style:
                                Theme.of(context).textTheme.titleMedium),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                            value: 'system',
                            label: Text('Sistema'),
                            icon: Icon(Icons.settings_suggest_outlined)),
                        ButtonSegment(
                            value: 'light',
                            label: Text('Chiaro'),
                            icon: Icon(Icons.light_mode_outlined)),
                        ButtonSegment(
                            value: 'dark',
                            label: Text('Scuro'),
                            icon: Icon(Icons.dark_mode_outlined)),
                      ],
                      selected: {themeController.themeMode},
                      onSelectionChanged: (selection) => themeController
                          .setThemeMode(selection.single),
                    ),
                  ]),
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
                      onSelectionChanged: (selection) => themeController
                          .setWeekendMode(selection.single),
                    ),
                  ]),
            ),
          ),
        ]),
      );
}

class _ClasseVivaPage extends StatelessWidget {
  const _ClasseVivaPage({
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([themeController, schoolDataController]),
        builder: (context, _) => _SettingsPage(children: [
          const _SettingsSectionHeader(
              icon: Icons.link_outlined,
              title: 'Account',
              subtitle:
                  'Collega il registro elettronico per importare orario e dati',
              accent: AppPalette.classeViva),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClassVivaLoginView(controller: schoolDataController),
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
          const SizedBox(height: 16),
          const _SettingsSectionHeader(
              icon: Icons.sync_outlined,
              title: 'Aggiornamento automatico',
              subtitle:
                  'Ricarica i dati ClasseViva in background finché la sessione è attiva',
              accent: AppPalette.teal),
          Card(
            child: ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Intervallo di aggiornamento'),
              subtitle: Text(themeController.autoRefreshMinutes <= 0
                  ? 'Disattivato'
                  : 'Ogni ${themeController.autoRefreshMinutes} minuti'),
              trailing: DropdownButton<int>(
                value: themeController.autoRefreshMinutes,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Mai')),
                  DropdownMenuItem(value: 5, child: Text('5 min')),
                  DropdownMenuItem(value: 15, child: Text('15 min')),
                  DropdownMenuItem(value: 30, child: Text('30 min')),
                  DropdownMenuItem(value: 60, child: Text('1 ora')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  themeController.setAutoRefreshMinutes(value);
                  schoolDataController.setAutoRefreshMinutes(value);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SettingsSectionHeader(
              icon: Icons.how_to_reg_outlined,
              title: 'Presenze',
              subtitle: 'Statistiche mostrate nella scheda Presenze',
              accent: AppPalette.indigo),
          Card(
            child: SwitchListTile.adaptive(
              secondary: const Icon(Icons.percent_outlined),
              title: const Text('Percentuale assenze'),
              subtitle: const Text(
                  'Mostra i giorni assenti rispetto alle giornate di scuola stimate.'),
              value: themeController.showAttendanceRate,
              onChanged: themeController.setShowAttendanceRate,
            ),
          ),
        ]),
      );
}

class _SchedulePage extends StatelessWidget {
  const _SchedulePage({required this.controller});
  final TimetableController controller;

  Future<void> _configureSharedBells(BuildContext context) async {
    final periods = await showDialog<List<PeriodTime>>(
      context: context,
      builder: (_) => BellScheduleDialog(
        weekday: 0,
        initialPeriods: controller.sharedPeriods,
      ),
    );
    if (periods == null || !context.mounted) return;
    try {
      await controller.savePeriodTimes(periods);
    } catch (error) {
      if (context.mounted) showAppMessage(context, error.toString());
    }
  }

  Future<void> _setDayCount(
      BuildContext context, int weekday, int count) async {
    try {
      await controller.setDayPeriodCount(weekday, count);
    } catch (error) {
      if (context.mounted) showAppMessage(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final shared = controller.sharedPeriods;
          return _SettingsPage(children: [
            const _SettingsSectionHeader(
                icon: Icons.notifications_outlined,
                title: 'Campanelle condivise',
                subtitle:
                    'Gli stessi orari valgono per ogni giorno della settimana',
                accent: AppPalette.indigo),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading:
                    CircleAvatar(child: Text('${shared.length}')),
                title: const Text('Orari delle ore'),
                subtitle: Text(shared.isEmpty
                    ? 'Non configurate'
                    : '${shared.length} ore · ${formatClock(shared.first.startMinute)}–${formatClock(shared.last.endMinute)}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _configureSharedBells(context),
              ),
            ),
            const SizedBox(height: 16),
            const _SettingsSectionHeader(
                icon: Icons.format_list_numbered,
                title: 'Ore per giorno',
                subtitle:
                    'Ogni giorno può usare un numero diverso di ore; gli orari restano quelli condivisi',
                accent: AppPalette.amber),
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
                    title: Text(kDayNames[day - 1]),
                    subtitle: Text(controller
                                .periodTimes
                                .any((period) => period.weekday == day)
                            ? '${controller.periodsForWeekday(day).length} ore'
                            : 'Come le campanelle condivise'),
                    trailing: DropdownButton<int>(
                      value:
                          controller.periodsForWeekday(day).isEmpty
                              ? null
                              : controller.periodsForWeekday(day).length,
                      hint: const Text('–'),
                      items: [
                        for (var count = 1; count <= 20; count++)
                          DropdownMenuItem(
                              value: count, child: Text('$count ore')),
                      ],
                      onChanged: shared.isEmpty
                          ? null
                          : (count) {
                              if (count != null) {
                                _setDayCount(context, day, count);
                              }
                            },
                    ),
                  ),
                ],
              ]),
            ),
          ]);
        },
      );
}

class _SubjectsPage extends StatelessWidget {
  const _SubjectsPage({required this.controller});
  final TimetableController controller;

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
      if (context.mounted) showAppMessage(context, error.toString());
    }
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _SettingsPage(children: [
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
        ]),
      );
}

class _ResourcesPage extends StatelessWidget {
  const _ResourcesPage({required this.controller});
  final TimetableController controller;

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
      if (context.mounted) showAppMessage(context, error.toString());
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => _SettingsPage(children: [
          _resourceSection(context, ResourceCategory.room),
          const SizedBox(height: 16),
          _resourceSection(context, ResourceCategory.teacher),
        ]),
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
                      : ([
                          resources[index].type == TeacherType.itp.name
                              ? 'ITP · Istruttore Tecnico Pratico'
                              : 'Docente',
                          if (resources[index].email case final v?)
                            v,
                          if (resources[index].phone case final v?)
                            v,
                          if (resources[index].birthday != null)
                            'Nato il '
                                '${resources[index].birthday!.day.toString().padLeft(2, '0')}/'
                                '${resources[index].birthday!.month.toString().padLeft(2, '0')}/'
                                '${resources[index].birthday!.year}',
                          if (resources[index].notes case final v?)
                            v,
                        ]).join(' · ')),
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

class _BackupPage extends StatelessWidget {
  const _BackupPage({
    required this.controller,
    required this.importController,
    required this.schoolDataController,
    required this.analytics,
  });
  final TimetableController controller;
  final ImportController importController;
  final SchoolDataController schoolDataController;
  final AppAnalytics analytics;

  Future<void> _exportConfig(BuildContext context) async {
    try {
      final json = await controller.exportConfigJson();
      if (kIsWeb) {
        downloadTextFile('school_manager_config.json', json);
        if (context.mounted) {
          analytics.event('export_config');
          showAppMessage(context, 'Configurazione esportata.');
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
      showAppMessage(context, saved == null
          ? 'Esportazione annullata.'
          : 'Configurazione esportata.');
    } catch (error) {
      if (context.mounted) showAppMessage(context, error.toString());
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
        showAppMessage(context, 'Configurazione importata.');
      }
    } on FormatException catch (error) {
      if (context.mounted) showAppMessage(context, error.message);
    } catch (error) {
      if (context.mounted) showAppMessage(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => _SettingsPage(children: [
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
      ]);
}

class _DebugPage extends StatelessWidget {
  const _DebugPage({
    required this.controller,
    required this.themeController,
    required this.schoolDataController,
  });
  final TimetableController controller;
  final ThemeController themeController;
  final SchoolDataController schoolDataController;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: themeController,
        builder: (context, _) => _SettingsPage(children: [
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
        ]),
      );
}

class _DangerPage extends StatelessWidget {
  const _DangerPage({
    required this.controller,
    required this.importController,
    required this.schoolDataController,
  });
  final TimetableController controller;
  final ImportController importController;
  final SchoolDataController schoolDataController;

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
      if (context.mounted) {
        showAppMessage(context, 'Tutti i dati sono stati eliminati.');
      }
    } catch (error) {
      if (context.mounted) showAppMessage(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => _SettingsPage(children: [
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
      ]);
}

/// Obiettivi di media: target globale di default e override per materia.
class _TargetsPage extends StatelessWidget {
  const _TargetsPage({
    required this.themeController,
    required this.schoolDataController,
  });

  final ThemeController themeController;
  final SchoolDataController schoolDataController;

  static String _fmt(double value) => value % 1 == 0
      ? '${value.toInt()}'
      : value.toStringAsFixed(1).replaceAll('.', ',');

  /// Dialog di scelta del target (slider 4–10 a step di 0,5).
  /// Restituisce il valore scelto, -1 per rimuovere, null se annullato.
  static Future<double?> _pickTarget(BuildContext context, double initial) {
    var value = initial;
    return showDialog<double>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Obiettivo di media'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_fmt(value),
                style: Theme.of(context)
                    .textTheme
                    .displaySmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
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
  }

  Future<void> _editGlobal(BuildContext context) async {
    final chosen = await _pickTarget(
        context, themeController.defaultGradeTarget ?? 6.0);
    if (chosen == null) return;
    await themeController
        .setDefaultGradeTarget(chosen < 0 ? null : chosen);
  }

  Future<void> _editSubject(BuildContext context, String subject) async {
    final chosen = await _pickTarget(
        context,
        themeController.gradeTargets[subject] ??
            themeController.defaultGradeTarget ??
            6.0);
    if (chosen == null) return;
    await themeController.setGradeTarget(subject, chosen < 0 ? null : chosen);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation:
            Listenable.merge([themeController, schoolDataController]),
        builder: (context, _) {
          final grades = schoolDataController
                  .records[ClassVivaSection.grades] ??
              const [];
          final subjects = grades
              .map((record) => (record.values['subjectDesc'] ??
                      record.values['subjectName'] ??
                      record.values['subject'])
                  ?.toString()
                  .trim())
              .whereType<String>()
              .where((name) => name.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          final global = themeController.defaultGradeTarget;
          return _SettingsPage(children: [
            const _SettingsSectionHeader(
                icon: Icons.flag_outlined,
                title: 'Obiettivi voti',
                subtitle:
                    'Target di media: globale per tutte le materie, o personalizzato',
                accent: AppPalette.amber),
            Card(
              child: ListTile(
                leading: const Icon(Icons.public_outlined),
                title: const Text('Target globale'),
                subtitle: Text(global == null
                    ? 'Non impostato: le materie senza target non mostrano consigli.'
                    : 'Media ${_fmt(global)} per tutte le materie senza override.'),
                trailing: FilledButton.tonal(
                  onPressed: () => _editGlobal(context),
                  child: Text(global == null ? 'Imposta' : _fmt(global)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _SettingsSectionHeader(
                icon: Icons.menu_book_outlined,
                title: 'Per materia',
                subtitle:
                    'Override del target globale per singole materie',
                accent: AppPalette.indigo),
            if (subjects.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('Nessuna materia trovata'),
                  subtitle: Text(
                      'Le materie compaiono dopo aver scaricato i voti da ClasseViva.'),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  for (var index = 0; index < subjects.length; index++) ...[
                    if (index > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    Builder(builder: (context) {
                      final subject = subjects[index];
                      final custom = themeController.gradeTargets[subject];
                      return ListTile(
                        title: Text(subject,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(custom != null
                            ? 'Target ${_fmt(custom)} (personalizzato)'
                            : global == null
                                ? 'Nessun target'
                                : 'Globale ${_fmt(global)}'),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _editSubject(context, subject),
                      );
                    }),
                  ],
                ]),
              ),
          ]);
        },
      );
}

class _InfoPage extends StatefulWidget {
  const _InfoPage({required this.themeController});
  final ThemeController themeController;

  static final Uri _privacyUrl = Uri.parse(
      'https://github.com/samuele-brusegan/school-manager/blob/main/docs/privacy-policy.md');
  static final Uri _sourceUrl =
      Uri.parse('https://github.com/samuele-brusegan/school-manager');

  @override
  State<_InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<_InfoPage> {
  String _version = '';
  int _versionTaps = 0;

  /// Stile Android: 7 tocchi sulla versione sbloccano la pagina Debug.
  void _onVersionTap() {
    if (widget.themeController.debugUnlocked) return;
    _versionTaps++;
    final remaining = 7 - _versionTaps;
    if (remaining <= 0) {
      widget.themeController.unlockDebug();
      showAppMessage(
          context, 'Impostazioni di debug sbloccate: le trovi in home.');
    } else if (remaining <= 3) {
      showAppMessage(
          context, 'Ancora $remaining tocchi per sbloccare il debug.');
    }
  }

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    });
  }

  @override
  Widget build(BuildContext context) => _SettingsPage(children: [
        const _SettingsSectionHeader(
            icon: Icons.privacy_tip_outlined,
            title: 'Info e privacy',
            subtitle: 'Versione dell’app, privacy e codice sorgente',
            accent: AppPalette.teal),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              subtitle: const Text(
                  'Come vengono trattati i dati dell’app e dell’account ClasseViva.'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () =>
                  launchUrl(_InfoPage._privacyUrl, mode: LaunchMode.externalApplication),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.code_outlined),
              title: const Text('Codice sorgente'),
              subtitle: const Text('Repository pubblico su GitHub.'),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () =>
                  launchUrl(_InfoPage._sourceUrl, mode: LaunchMode.externalApplication),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Versione'),
              subtitle: Text(_version.isEmpty ? '…' : _version),
              onTap: _onVersionTap,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Licenze open source'),
              subtitle:
                  const Text('Licenze delle librerie utilizzate dall’app.'),
              onTap: () => showLicensePage(context: context),
            ),
          ]),
        ),
      ]);
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
      helpText: 'Inizio ${ordinalSuffix(index + 1)}',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: period.endMinute ~/ 60, minute: period.endMinute % 60),
      helpText: 'Fine ${ordinalSuffix(index + 1)}',
    );
    if (end == null || !mounted) return;
    final startMinute = start.hour * 60 + start.minute;
    final endMinute = end.hour * 60 + end.minute;
    if (startMinute >= endMinute) {
      showAppMessage(
          context, 'La campanella di fine deve seguire quella di inizio.');
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
      title: Text(widget.weekday == 0
          ? 'Campanelle condivise'
          : 'Campanelle e ore scolastiche'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            widget.weekday == 0
                ? 'Questi orari valgono per tutti i giorni: cambia solo il numero di ore dei singoli giorni.'
                : 'Gli orari iniziali sono esempi: tocca ogni ora per impostare le campanelle della tua scuola.',
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
                  title: Text('${ordinalSuffix(index + 1)} ora'),
                  subtitle: Text(
                      '${formatClock(period.startMinute)} – ${formatClock(period.endMinute)}'),
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
              MultiSelectField(
                  label: 'Professori',
                  options: {...widget.availableTeachers, ..._teachers},
                  selected: _teachers,
                  emptyText: 'Aggiungi prima i docenti nelle impostazioni.',
                  onChanged: (name, selected) => setState(() =>
                      selected ? _teachers.add(name) : _teachers.remove(name))),
              const SizedBox(height: 12),
              MultiSelectField(
                  label: 'Aule e laboratori',
                  options: {...widget.availableRooms, ..._rooms},
                  selected: _rooms,
                  emptyText: 'Aggiungi prima le aule nelle impostazioni.',
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
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _notes = TextEditingController();
  String _type = RoomType.classroom.name;
  DateTime? _birthday;

  @override
  void initState() {
    super.initState();
    _name.text = widget.resource?.name ?? '';
    _type = widget.resource?.type ??
        (widget.category == ResourceCategory.teacher
            ? TeacherType.teacher.name
            : RoomType.classroom.name);
    _email.text = widget.resource?.email ?? '';
    _phone.text = widget.resource?.phone ?? '';
    _notes.text = widget.resource?.notes ?? '';
    _birthday = widget.resource?.birthday;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(1970),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      helpText: 'Compleanno',
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  Map<String, String> _meta() => {
        if (_email.text.trim().isNotEmpty)
          TeacherMeta.email: _email.text.trim(),
        if (_phone.text.trim().isNotEmpty)
          TeacherMeta.phone: _phone.text.trim(),
        if (_birthday != null)
          TeacherMeta.birthday:
              '${_birthday!.year.toString().padLeft(4, '0')}-${_birthday!.month.toString().padLeft(2, '0')}-${_birthday!.day.toString().padLeft(2, '0')}',
        if (_notes.text.trim().isNotEmpty)
          TeacherMeta.notes: _notes.text.trim(),
      };

  @override
  Widget build(BuildContext context) {
    final room = widget.category == ResourceCategory.room;
    return AlertDialog(
      title: Text(widget.resource == null
          ? (room ? 'Aggiungi aula' : 'Aggiungi professore')
          : (room ? 'Modifica aula o laboratorio' : 'Modifica professore')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  labelText:
                      room ? 'Nome aula/laboratorio' : 'Nome e cognome')),
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
          if (!room) ...[
            const SizedBox(height: 12),
            TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.mail_outline))),
            const SizedBox(height: 12),
            TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Telefono',
                    prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cake_outlined),
              title: Text(_birthday == null
                  ? 'Compleanno'
                  : 'Compleanno: ${_birthday!.day.toString().padLeft(2, '0')}/${_birthday!.month.toString().padLeft(2, '0')}/${_birthday!.year}'),
              trailing: _birthday == null
                  ? const Icon(Icons.edit_outlined)
                  : IconButton(
                      tooltip: 'Rimuovi compleanno',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _birthday = null)),
              onTap: _pickBirthday,
            ),
            TextField(
                controller: _notes,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Annotazioni',
                    prefixIcon: Icon(Icons.notes_outlined))),
          ],
        ]),
      ),
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
                        type: _type,
                        meta: _meta())),
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
