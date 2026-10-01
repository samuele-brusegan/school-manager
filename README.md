# School Manager

App Flutter offline-first per creare e consultare l'orario scolastico, con Android come piattaforma primaria e supporto iOS.

## Stato

MVP in sviluppo. Include gestione manuale dell'orario e un'integrazione ClasseViva incapsulata dietro interfacce. Il protocollo ClasseViva è non ufficiale e può cambiare; testare il collegamento solo con un account autorizzato e dati propri. Importazione da foto, backend e sincronizzazione cloud sono fuori dal MVP.

## Architettura

MVC rigoroso: le view rendono lo stato e inoltrano intenzioni ai controller; i controller coordinano casi d'uso; il model contiene entità, regole e contratti repository. Gli adapter SQLite, secure storage e REST implementano interfacce del model. Dettagli in [docs/architecture/overview.md](docs/architecture/overview.md).

## Avvio

Con Flutter stabile installato:

```sh
cd app
flutter pub get
flutter run
```

Per generare APK: `flutter build apk --release`. Per iOS serve macOS con Xcode: `flutter build ipa --release`.

## Verifiche

```sh
cd app
flutter analyze
flutter test --coverage
```

