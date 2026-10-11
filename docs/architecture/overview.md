# Architettura applicativa

## Obiettivo

Applicazione Flutter Android/iOS, locale-first, per organizzare la giornata scolastica. Le pagine principali sono Oggi, Orario, Agenda, Rendimento e Registro. Orario, attività personali e cache ClasseViva sono in SQLite; credenziali temporanee e token sono in secure storage. Nessun server applicativo.

## MVC

- **View**: widget Flutter stateless o componenti di presentazione. Leggono lo stato esposto dal controller e invocano comandi; non conoscono database, HTTP né credenziali.
- **Controller**: coordinano casi d'uso asincroni e stato di presentazione, gestiscono errori e comandano navigazione. Dipendono da contratti, non da plugin.
- **Model**: entità immutabili, validazioni di dominio e interfacce repository/gateway. Gli adapter concreti sono infrastruttura del model.
- **Composition root**: `main.dart` crea gli adapter e li inietta nei controller. Non si usano service locator globali o istanze nascoste.

## Modello di dominio

`Subject` rappresenta una materia (`id`, `name`, `colorValue`). `Lesson` rappresenta una ricorrenza (`id`, `subjectId`, giorno ISO 1-7, minuti dall'inizio del giorno per inizio e fine). Un `Timetable` raccoglie materie e lezioni. Gli intervalli sono [inizio, fine): due lezioni adiacenti sono valide, sovrapposizioni nello stesso giorno non lo sono. Materie e lezioni sono persistite atomicamente; l'eliminazione di una materia rimuove le sue lezioni.

Una proposta importata è un insieme temporaneo di lezioni, non salvato finché lo studente non la conferma. Le lezioni reali sono aggregate per giorno della settimana e fascia oraria. Orari incoerenti, materia ambigua o righe duplicate sono segnalati prima della conferma.

## Flusso dati

```mermaid
classDiagram
  class TimetableController
  class TimetableView
  class ImportController
  class ImportReviewView
  class TimetableRepository~interface~
  class ClassVivaGateway~interface~
  class SecureCredentialStore~interface~
  class SqliteTimetableRepository
  class RestClassVivaGateway
  class Subject
  class Lesson
  TimetableView --> TimetableController
  ImportReviewView --> ImportController
  TimetableController --> TimetableRepository
  ImportController --> TimetableRepository
  ImportController --> ClassVivaGateway
  RestClassVivaGateway --> SecureCredentialStore
  SqliteTimetableRepository ..|> TimetableRepository
  RestClassVivaGateway ..|> ClassVivaGateway
  Subject "1" --> "0..*" Lesson : subjectId
```

Percorso di importazione: View → ImportController → gateway di ClasseViva → mapper della risposta → proposta in memoria → revisione/approvazione → repository locale. Login e token restano in secure storage, mai nel database o nei log.

Percorso dei dati del registro: Registro → SchoolDataController → ClassVivaDataGateway → adapter REST → normalizzazione dei record → cache SQLite. Se una sezione non è disponibile, la sincronizzazione conserva i dati locali e registra un errore limitato a quella sezione. Agenda e voti sono consultabili anche dalla pagina Oggi e Rendimento. I compiti personali sono locali e hanno stato completato/non completato.

## Integrazione ClasseViva

L'adapter REST implementa login, importazione lezioni e lettura di agenda, voti, assenze, note, bacheca, materiali, documenti e libri. Richieste e parsing sono separati per poter sostituire endpoint e schema senza cambiare controller o UI. Gestire timeout, assenza rete, credenziali errate, sessione scaduta, limitazioni dell'account e JSON inatteso con errori tipizzati. Nessun refresh automatico aggressivo: la sincronizzazione è manuale e le sezioni fallite non bloccano le altre.

Le API consultate sono reverse-engineered e non supportate ufficialmente; profili e scuole possono esporre insiemi diversi di dati. Il parser conserva i campi originali normalizzabili per tollerare varianti delle risposte. L'endpoint delle lezioni fornisce data, materia, numero dell'ora e durata, non orari di campanella: l'utente configura per ogni numero ora il relativo intervallo. Senza una mappatura completa la proposta segnala le ore mancanti e non consente conferma parziale. Nel browser l'API è raggiunta tramite proxy same-origin (`/classeviva/rest/`) perché ClasseViva non autorizza il preflight CORS; per sviluppo è disponibile `app/tool/classviva_proxy.dart`, vincolato a loopback. Verificare login e accesso da account autorizzato; mantenere la creazione manuale sempre disponibile. La prova con account reale è manuale, mai automatizzata nei test.

## Persistenza e sicurezza

SQLite locale tramite repository e schema versionato. Su Android e iOS il database usa il percorso documenti dell'app; sul web usa SQLite WASM persistito in IndexedDB. La cache del registro conserva risposte JSON normalizzate per sezione e l'ora dell'ultimo aggiornamento; i compiti personali hanno una tabella separata. Token e identificativo studente sono conservati tramite Keychain/Keystore e l'implementazione web di `flutter_secure_storage`; la password non viene conservata. Logout elimina token e identificativo, non i dati già scaricati. Non registrare header, password, token o payload personali. Tutte le richieste usano TLS. Nel browser l'archiviazione protetta richiede HTTPS o localhost.
