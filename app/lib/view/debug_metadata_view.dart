import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/school_data_controller.dart';
import '../controller/timetable_controller.dart';
import '../model/contracts/classviva_data_gateway.dart';
import '../model/entities/classviva_record.dart';
import '../model/services/subject_matcher.dart';
import 'agenda_view.dart';

/// Testo compatto con i metadati grezzi di un record: da mostrare inline
/// quando l'overlay di debug è attivo.
String debugRecordText(ClassVivaRecord record) =>
    'id: ${record.id}\nvalues: ${jsonEncode(record.values)}';

/// Blocco monospace per i metadati di debug inline nelle viste.
class DebugInfoText extends StatelessWidget {
  const DebugInfoText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Theme.of(context).colorScheme.error,
              ),
        ),
      );
}

/// Vista di debug: scarica in testo semplice tutti i metadati grezzi
/// ClasseViva e i valori derivati dall'app (materia abbinata, flag
/// verifica, ecc.). Pensata per diagnosticare errori di matching.
class DebugMetadataView extends StatelessWidget {
  const DebugMetadataView({
    super.key,
    required this.timetableController,
    required this.schoolDataController,
  });

  final TimetableController timetableController;
  final SchoolDataController schoolDataController;

  String _dump() {
    final buffer = StringBuffer();
    final timetable = timetableController.timetable;
    final matcher =
        SubjectMatcher(timetable?.subjects ?? const []);

    buffer.writeln('=== MATERIE (locali) ===');
    for (final subject in timetable?.subjects ?? const []) {
      buffer.writeln(jsonEncode({
        'id': subject.id,
        'name': subject.name,
        'colorValue': subject.colorValue,
        'classvivaId': subject.classvivaId,
        'teachers': subject.teachers,
        'rooms': subject.rooms,
      }));
    }

    buffer.writeln('\n=== LEZIONI ===');
    for (final lesson in timetable?.lessons ?? const []) {
      buffer.writeln(jsonEncode(lesson.toMap()));
    }

    buffer.writeln('\n=== CAMPANELLE ===');
    for (final period in timetableController.periodTimes) {
      buffer.writeln(jsonEncode(period.toMap()));
    }

    buffer.writeln('\n=== COMPITI PERSONALI ===');
    for (final task in schoolDataController.tasks) {
      buffer.writeln(jsonEncode(task.toMap()));
    }

    buffer.writeln('\n=== OVERRIDE VERIFICHE (manuali) ===');
    buffer.writeln(jsonEncode(schoolDataController.testFlags));

    for (final section in ClassVivaSection.values) {
      final records =
          schoolDataController.records[section] ?? const <ClassVivaRecord>[];
      final error = schoolDataController.errors[section];
      buffer.writeln('\n=== SEZIONE ${section.name} '
          '(${records.length} record${error != null ? ', errore: $error' : ''}) ===');
      for (final record in records) {
        buffer.writeln('-- record ${record.id}');
        buffer.writeln('   title: ${record.title}');
        buffer.writeln('   subtitle: ${record.subtitle}');
        buffer.writeln('   date: ${record.date}');
        buffer.writeln('   values(raw): ${jsonEncode(record.values)}');
        buffer.writeln('   derivati:');
        buffer.writeln('     subjectName: ${record.subjectName}');
        buffer.writeln('     teacherName: ${record.teacherName}');
        buffer.writeln('     content: ${record.content}');
        buffer.writeln('     typeLabel(evtCode): ${record.typeLabel}');
        buffer.writeln('     begin: ${record.begin}  end: ${record.end}');
        final subject = matchRecordSubject(record, matcher, timetable);
        buffer.writeln(
            '     materia abbinata: ${subject?.name ?? '-'} (id: ${subject?.id ?? '-'})');
        final keyword = hasSchoolKeywordText(
            '${record.title} ${record.subtitle} ${record.content ?? ''}');
        final flag = schoolDataController.testFlags[record.id];
        buffer.writeln('     keyword verifica: $keyword  '
            'override manuale: $flag  -> isTest: ${flag ?? keyword}');
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final dump = _dump();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Metadati (debug)'),
        actions: [
          IconButton(
            tooltip: 'Copia tutto',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: dump));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Metadati copiati.')));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          dump,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}
