import 'package:flutter/material.dart';

import '../controller/import_controller.dart';
import '../controller/school_data_controller.dart';
import '../controller/timetable_controller.dart';
import '../model/entities/period_time.dart';
import '../model/services/app_analytics.dart';
import 'app_palette.dart';
import 'classviva_login_view.dart';
import 'formatters.dart';

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
                      '${kDayNames[lesson.weekday - 1]} • ${formatClock(lesson.startMinute)}–${formatClock(lesson.endMinute)}',
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
    await _checkSession();
    if (mounted) showAppMessage(context, 'Sessione ClasseViva eliminata.');
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
      showAppMessage(context, 'Orario aggiornato.');
    } catch (error) {
      if (mounted) showAppMessage(context, error.toString());
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
      await widget.timetableController.load();
    } catch (error) {
      if (mounted) showAppMessage(context, error.toString());
    }
  }

  Future<void> _guessPeriodTimes() async {
    final guesses = await widget.importController.guessPeriodTimes();
    if (guesses.isEmpty || !mounted) {
      if (mounted) {
        showAppMessage(context, 'Non ci sono lezioni da cui stimare le ore.');
      }
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
                    title: Text(kDayNames[weekday - 1]),
                    subtitle: Text(guesses
                        .where((period) => period.weekday == weekday)
                        .map((period) =>
                            '${period.number}ª ${formatClock(period.startMinute)}–${formatClock(period.endMinute)}')
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
      await widget.timetableController.load();
    } catch (error) {
      if (mounted) showAppMessage(context, error.toString());
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
