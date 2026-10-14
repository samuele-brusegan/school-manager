import 'dart:typed_data';

import '../entities/classviva_record.dart';

enum ClassVivaSection {
  agenda,
  grades,
  attendance,
  notes,
  noticeboard,
  didactics,
  documents,
  schoolbooks,
}

abstract interface class ClassVivaDataGateway {
  Future<List<ClassVivaRecord>> records(
    ClassVivaSection section, {
    DateTime? start,
    DateTime? end,
  });

  /// Testo di una comunicazione di bacheca, senza scaricare l'allegato PDF.
  Future<String> noticeboardText(ClassVivaRecord record);

  /// Allegato [index] (0-based) di una comunicazione di bacheca:
  /// nome file e byte, senza salvarli su disco.
  Future<({String fileName, Uint8List bytes})> noticeboardAttachment(
      ClassVivaRecord record, int index);
}
