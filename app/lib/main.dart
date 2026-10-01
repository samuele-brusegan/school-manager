import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'controller/import_controller.dart';
import 'controller/timetable_controller.dart';
import 'model/infrastructure/classviva_rest_gateway.dart';
import 'model/infrastructure/secure_credential_store.dart';
import 'model/infrastructure/sqlite_timetable_repository.dart';
import 'model/services/import_proposal_builder.dart';
import 'view/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationDocumentsDirectory();
  final database = await openTimetableDatabase(
    p.join(directory.path, 'school_manager.sqlite'),
  );
  final repository = SqliteTimetableRepository(database);
  const secureStorage = FlutterSecureStorage();
  final credentialStore = SecureCredentialStore(secureStorage);
  final timetableController = TimetableController(repository);
  final importController = ImportController(
    gateway: ClassVivaRestGateway(
      client: http.Client(),
      credentialStore: credentialStore,
    ),
    repository: repository,
    builder: ImportProposalBuilder(),
  );
  runApp(
    SchoolManagerApp(
      timetableController: timetableController,
      importController: importController,
    ),
  );
}

class SchoolManagerApp extends StatelessWidget {
  const SchoolManagerApp({
    super.key,
    required this.timetableController,
    required this.importController,
  });

  final TimetableController timetableController;
  final ImportController importController;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'School Manager',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4355A5)),
          useMaterial3: true,
        ),
        home: HomePage(
          timetableController: timetableController,
          importController: importController,
        ),
      );
}
