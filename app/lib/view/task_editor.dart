import 'package:flutter/material.dart';

import '../model/entities/lesson.dart';
import '../model/entities/study_task.dart';
import '../model/entities/subject.dart';

/// Bozza di compito personale compilata nell'editor.
typedef TaskDraft = ({
  String title,
  String subject,
  DateTime dueDate,
  int? startMinute,
  int? endMinute,
});

/// Dialog per creare ([initial] nullo) o modificare un compito
/// personale. La materia si sceglie da un menu a tendina con opzioni
/// radio, più la voce "Nessuna" per lasciarla vuota. L'orario è
/// facoltativo: manuale (inizio/fine) oppure agganciato a uno slot di
/// lezione dell'orario scolastico, che fissa anche la data al giorno
/// della lezione. Restituisce la bozza salvata oppure null.
Future<TaskDraft?> showTaskEditor(
  BuildContext context, {
  required List<Subject> subjects,
  List<Lesson> lessons = const [],
  StudyTask? initial,
}) {
  final title = TextEditingController(text: initial?.title);
  var subject = initial?.subject ?? '';
  var dueDate = initial?.dueDate ?? DateTime.now();
  var startMinute = initial?.startMinute;
  var endMinute = initial?.endMinute;
  return showDialog<TaskDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        Future<void> pickTime(bool isStart) async {
          final current = isStart ? startMinute : endMinute;
          final chosen = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(
                hour: (current ?? 8 * 60) ~/ 60, minute: (current ?? 0) % 60),
          );
          if (chosen == null) return;
          setDialogState(() {
            final minute = chosen.hour * 60 + chosen.minute;
            if (isStart) {
              startMinute = minute;
              if (endMinute != null && endMinute! <= minute) {
                endMinute = minute + 45;
              }
            } else {
              endMinute = minute;
            }
          });
        }

        final subjectLessons = lessons
            .where((lesson) => subject.isEmpty ||
                subjects
                    .where((s) => s.name == subject)
                    .any((s) => s.id == lesson.subjectId))
            .toList();
        return AlertDialog(
          title:
              Text(initial == null ? 'Nuovo compito' : 'Modifica compito'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: title,
                autofocus: initial == null,
                decoration: const InputDecoration(labelText: 'Compito'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: subject,
                decoration: const InputDecoration(labelText: 'Materia'),
                selectedItemBuilder: (context) => [
                  const Text('Nessuna'),
                  for (final s in subjects) Text(s.name),
                  if (subject.isNotEmpty &&
                      !subjects.any((s) => s.name == subject))
                    Text(subject),
                ],
                items: [
                  _subjectItem('', 'Nessuna', subject),
                  for (final s in subjects)
                    _subjectItem(s.name, s.name, subject,
                        colorValue: s.colorValue),
                  // Compiti salvati con una materia non più presente
                  // (inserita a mano o rinominata): voce extra per non
                  // perdere il valore corrente.
                  if (subject.isNotEmpty &&
                      !subjects.any((s) => s.name == subject))
                    _subjectItem(subject, subject, subject),
                ],
                onChanged: (value) =>
                    setDialogState(() => subject = value ?? ''),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Scadenza'),
                subtitle: Text(_shortDate(dueDate)),
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
              if (subjectLessons.isNotEmpty)
                DropdownButtonFormField<int>(
                  initialValue: null,
                  decoration: const InputDecoration(
                      labelText: 'Aggancia a una lezione'),
                  items: [
                    for (var i = 0; i < subjectLessons.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(_lessonLabel(subjectLessons[i])),
                      ),
                  ],
                  onChanged: (index) {
                    if (index == null) return;
                    setDialogState(() {
                      final lesson = subjectLessons[index];
                      dueDate = _nextWeekday(lesson.weekday);
                      startMinute = lesson.startMinute;
                      endMinute = lesson.endMinute;
                    });
                  },
                ),
              Row(children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inizio'),
                    subtitle: Text(startMinute == null
                        ? '—'
                        : _fmtMinute(startMinute!)),
                    onTap: () => pickTime(true),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fine'),
                    subtitle: Text(
                        endMinute == null ? '—' : _fmtMinute(endMinute!)),
                    onTap: () => pickTime(false),
                  ),
                ),
                if (startMinute != null || endMinute != null)
                  IconButton(
                    tooltip: 'Rimuovi orario',
                    icon: const Icon(Icons.schedule_outlined, size: 18),
                    onPressed: () => setDialogState(() {
                      startMinute = null;
                      endMinute = null;
                    }),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (
                title: title.text,
                subject: subject,
                dueDate: dueDate,
                startMinute: startMinute,
                endMinute: endMinute,
              )),
              child: const Text('Salva'),
            ),
          ],
        );
      },
    ),
  );
}

/// Voce del menu materie: pallino colorato, nome e radio di selezione.
DropdownMenuItem<String> _subjectItem(String value, String label,
        String selected,
        {int? colorValue}) =>
    DropdownMenuItem(
      value: value,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        RadioGroup<String>(
          groupValue: selected,
          onChanged: (_) {},
          child: IgnorePointer(
            child: Radio<String>(value: value),
          ),
        ),
        if (colorValue != null) ...[
          CircleAvatar(radius: 7, backgroundColor: Color(colorValue)),
          const SizedBox(width: 4),
        ],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ]),
    );

String _fmtMinute(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

String _shortDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

const _dayNames = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];

String _lessonLabel(Lesson lesson) =>
    '${_dayNames[lesson.weekday - 1]} ${_fmtMinute(lesson.startMinute)}–${_fmtMinute(lesson.endMinute)}';

/// Prossima data (oggi incluso) che cade nel giorno [weekday].
DateTime _nextWeekday(int weekday) {
  final now = DateTime.now();
  final delta = (weekday - now.weekday) % 7;
  final date = now.add(Duration(days: delta));
  return DateTime(date.year, date.month, date.day);
}
