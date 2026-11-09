import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../contracts/classviva_data_gateway.dart';
import '../entities/classviva_record.dart';
import '../infrastructure/classviva_rest_gateway.dart';
import '../infrastructure/secure_credential_store.dart';
import '../infrastructure/sqlite_timetable_repository.dart';

/// Task periodico WorkManager.
const kBackgroundSyncTask = 'schoolManagerClasseVivaSync';

/// Sezioni ClasseViva controllate in background: nuovi elementi
/// generano una notifica locale.
const _syncedSections = [
  ClassVivaSection.agenda,
  ClassVivaSection.noticeboard,
  ClassVivaSection.grades,
  ClassVivaSection.notes,
];

const _channelId = 'classeviva_sync';
const _channelName = 'Aggiornamenti registro';

final _notifications = FlutterLocalNotificationsPlugin();

Future<void> _initNotifications() async {
  await _notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
}

Future<void> _notify(int id, String title, String body) async {
  await _notifications.show(
    id,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    ),
  );
}

String _sectionLabel(ClassVivaSection section) => switch (section) {
      ClassVivaSection.agenda => 'Agenda',
      ClassVivaSection.noticeboard => 'Bacheca',
      ClassVivaSection.grades => 'Voti',
      ClassVivaSection.notes => 'Note',
      _ => section.name,
    };

/// Eseguito da WorkManager in un isolate headless: apre il database,
/// interroga ClasseViva con la sessione salvata e notifica i nuovi
/// elementi. Restituisce sempre true: un fallimento di rete non deve
/// disattivare il task periodico.
@pragma('vm:entry-point')
void backgroundSyncCallback() {
  Workmanager().executeTask((task, inputData) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await _initNotifications();

      final databasePath = p.join(
        (await getApplicationDocumentsDirectory()).path,
        'school_manager.sqlite',
      );
      final database = await openTimetableDatabase(databasePath);
      final repository = SqliteSchoolDataRepository(database);
      final gateway = ClassVivaRestGateway(
        client: http.Client(),
        credentialStore:
            SecureCredentialStore(const FlutterSecureStorage()),
      );

      if (!await gateway.hasSession()) return true;

      var notified = 0;
      for (final section in _syncedSections) {
        final known = {
          for (final record in await repository.getRecords(section.name))
            record.id,
        };
        final List<ClassVivaRecord> fetched;
        try {
          fetched = await gateway.records(section);
        } on Object {
          continue; // sezione non disponibile o errore di rete
        }
        final fresh = fetched.where((r) => !known.contains(r.id)).toList();
        if (fresh.isEmpty) continue;
        await repository.saveRecords(section.name, fetched);

        for (final record in fresh) {
          if (notified >= 5) {
            await _notify(
              9000,
              'Nuovi aggiornamenti ClasseViva',
              '${fresh.length - notified} altri elementi in '
                  '${_sectionLabel(section)}',
            );
            break;
          }
          await _notify(
            (section.name + record.id).hashCode & 0x7FFFFFFF,
            '${_sectionLabel(section)}: ${record.title}',
            record.content ?? record.subtitle,
          );
          notified++;
        }
      }
      return true;
    } on Object {
      return true;
    }
  });
}

/// Configura il worker periodico e le notifiche locali (solo Android).
class BackgroundSync {
  BackgroundSync._();
  static final instance = BackgroundSync._();

  static bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (!_supported) return;
    await Workmanager().initialize(backgroundSyncCallback);
    await _initNotifications();
  }

  /// Attiva o disattiva il task periodico. [minutes] < 15 viene alzato
  /// al minimo consentito da WorkManager.
  Future<void> configure({required bool enabled, required int minutes}) async {
    if (!_supported) return;
    await Workmanager().cancelByUniqueName(kBackgroundSyncTask);
    if (!enabled) return;
    await Workmanager().registerPeriodicTask(
      kBackgroundSyncTask,
      kBackgroundSyncTask,
      frequency: Duration(minutes: minutes < 15 ? 15 : minutes),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  /// Permesso notifiche (Android 13+). Restituisce true se concesso o
  /// non necessario.
  Future<bool> requestNotificationPermission() async {
    if (!_supported) return false;
    final granted = await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    return granted ?? false;
  }
}
