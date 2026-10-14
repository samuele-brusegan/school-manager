import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'controller/import_controller.dart';
import 'controller/school_data_controller.dart';
import 'controller/timetable_controller.dart';
import 'controller/theme_controller.dart';
import 'model/infrastructure/sqlite_timetable_repository.dart';
import 'model/infrastructure/sqlite_theme_preference_repository.dart';
import 'model/infrastructure/classviva_rest_gateway.dart';
import 'model/infrastructure/secure_credential_store.dart';
import 'model/services/app_analytics.dart';
import 'model/services/import_proposal_builder.dart';
import 'view/app_palette.dart';
import 'view/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) databaseFactory = databaseFactoryFfiWeb;
  final databasePath = kIsWeb
      ? 'school_manager.sqlite'
      : p.join(
          (await getApplicationDocumentsDirectory()).path,
          'school_manager.sqlite',
        );
  final database = await openTimetableDatabase(
    databasePath,
  );
  final repository = SqliteTimetableRepository(database);
  final themeController = ThemeController(
    SqliteThemePreferenceRepository(database),
  );
  await themeController.load();
  final schoolDataRepository = SqliteSchoolDataRepository(database);
  const secureStorage = FlutterSecureStorage();
  final credentialStore = SecureCredentialStore(secureStorage);
  final timetableController = TimetableController(repository);
  const configuredClassVivaApi =
      String.fromEnvironment('CLASSVIVA_API_BASE_URL');
  final classVivaGateway = ClassVivaRestGateway(
    client: http.Client(),
    credentialStore: credentialStore,
    baseUri: kIsWeb
        ? Uri.parse(
            configuredClassVivaApi.isEmpty
                ? (kReleaseMode
                    ? Uri.base.resolve('/classeviva/rest/').toString()
                    : 'http://127.0.0.1:8787/rest/')
                : configuredClassVivaApi,
          )
        : null,
  );
  final importController = ImportController(
    gateway: classVivaGateway,
    repository: repository,
    builder: ImportProposalBuilder(),
  );
  final schoolDataController = SchoolDataController(
    dataGateway: classVivaGateway,
    sessionGateway: classVivaGateway,
    repository: schoolDataRepository,
  );
  schoolDataController
      .setAutoRefreshMinutes(themeController.autoRefreshMinutes);
  final analytics = await AppAnalytics.init();
  runApp(
    SchoolManagerApp(
      timetableController: timetableController,
      importController: importController,
      schoolDataController: schoolDataController,
      themeController: themeController,
      analytics: analytics,
    ),
  );
}

class SchoolManagerApp extends StatelessWidget {
  const SchoolManagerApp({
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
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: themeController,
        builder: (context, _) => MaterialApp(
          title: 'School Manager',
          theme: ThemeData(
            colorScheme:
                ColorScheme.fromSeed(seedColor: AppPalette.indigo).copyWith(
              secondary: AppPalette.teal,
              tertiary: AppPalette.amber,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF7986CB),
              brightness: Brightness.dark,
            ).copyWith(
              secondary: const Color(0xFF7FC9C2),
              tertiary: const Color(0xFFE8C37A),
            ),
            useMaterial3: true,
          ),
          themeMode: switch (themeController.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          home: HomePage(
            timetableController: timetableController,
            importController: importController,
            schoolDataController: schoolDataController,
            themeController: themeController,
            analytics: analytics,
          ),
        ),
      );
}
