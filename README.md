# School Manager

App Flutter offline-first per organizzare la giornata scolastica, con Android come piattaforma primaria e supporto iOS.

## Stato

MVP in sviluppo. Include le pagine Oggi, Orario, Agenda, Rendimento e Registro. Orario e compiti personali sono locali; i dati ClasseViva letti vengono memorizzati in SQLite per la consultazione offline. Il protocollo ClasseViva è reverse-engineered, non ufficiale e può cambiare; alcune sezioni dipendono dai permessi del profilo. Backend applicativo e sincronizzazione cloud sono fuori dal MVP; il web usa un proxy HTTP senza stato per superare CORS.

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

Per compilare la versione web: `cd app && flutter build web --release`. I dati locali del browser sono memorizzati in IndexedDB. Servire l'app sotto HTTPS (oppure `localhost`) per consentire l'uso dell'archiviazione protetta ClasseViva. Il browser non può chiamare direttamente l'API ClasseViva per via di CORS: il deploy web deve esporre un proxy same-origin da `/classeviva/rest/` a `https://web.spaggiari.eu/rest/`.

Durante lo sviluppo, avviare il proxy locale in un terminale e Flutter in un altro:

```sh
cd app
dart run tool/classviva_proxy.dart
```

In un secondo terminale:

```sh
cd app
flutter run -d chrome
```

Il proxy locale accetta solo origini `localhost` e `127.0.0.1`, ascolta su loopback e stampa metodo, status e percorso redatto; non stampa header, body o credenziali. In modalità debug la console Flutter mostra anche status HTTP e dimensione della risposta. In produzione, impostare `CLASSVIVA_API_BASE_URL` all'URL HTTPS del proxy same-origin oppure lasciare il valore predefinito `/classeviva/rest/` e configurare il reverse proxy del server web.

## Possibili evoluzioni future

- **Importazione dell'orario da immagine con AI locale**: riconoscimento della griglia oraria da foto/screenshot con un modello eseguito sul dispositivo (anche su telefono). In valutazione; non pianificata nel MVP.

## Verifiche

```sh
cd app
flutter analyze
flutter test --coverage
```
