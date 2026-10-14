# Privacy policy — School Manager

Ultimo aggiornamento: 14 ottobre 2026

School Manager è un'app offline-first per organizzare la giornata scolastica.
Questa informativa descrive quali dati vengono trattati e dove risiedono.

## Titolare del trattamento

L'app è sviluppata e distribuita da Samuele Brusegan
(repository: https://github.com/samuele-brusegan/school-manager).
Per qualsiasi richiesta relativa alla privacy è possibile aprire una issue
sul repository o contattare il titolare tramite il profilo GitHub.

## Dati trattati e dove risiedono

Tutti i dati inseriti o importati restano **sul dispositivo dell'utente**.
L'app non ha un backend proprio e non invia dati a server dello sviluppatore.

- **Orario, materie, aule, professori, compiti e impostazioni**: salvati in un
  database locale (SQLite su Android/iOS/desktop, IndexedDB sul web).
- **Credenziali e sessione ClasseViva**: se l'utente collega il proprio
  account, le credenziali/token di sessione sono conservati nell'archiviazione
  protetta del sistema operativo (Android Keystore / iOS Keychain) e usati
  esclusivamente per chiamare le API del registro elettronico ClasseViva
  (domini `*.spaggiari.eu`), gestito da Gruppo Spaggiari Parma S.p.A.
- **Dati ClasseViva consultati** (orario, voti, agenda, note, ecc.): scaricati
  dai server ClasseViva e memorizzati in locale per la consultazione offline.

L'app agisce come client: l'account ClasseViva resta gestito dal registro
elettronico della scuola; per la relativa informativa si rimanda a ClasseViva.

## Dati NON raccolti

- Nessuna analytics, telemetria o tracciamento (nessun SDK di analytics è
  incluso nell'app).
- Nessuna pubblicità.
- Nessun dato venduto o condiviso con terze parti per scopi commerciali.

## Comunicazioni di rete

L'app effettua richieste di rete solo per:

- le API ClasseViva (`web.spaggiari.eu`), quando l'utente collega l'account o
  aggiorna i dati;
- un controllo facoltativo e non bloccante degli aggiornamenti su GitHub
  Releases (`api.github.com`), che non trasmette dati personali;
- l'apertura di link esterni (privacy policy, repository) su richiesta
  dell'utente.

Sulla versione web, le chiamate a ClasseViva passano per un proxy same-origin
senza stato che inoltra le richieste senza memorizzarle.

## Eliminazione dei dati

Dalla schermata Impostazioni → Zona pericolosa → «Elimina tutti i dati» è
possibile cancellare definitivamente tutti i dati locali e la sessione
ClasseViva. Disinstallare l'app rimuove comunque tutti i dati dal dispositivo.
L'app non crea account su server propri: non esistono dati remoti da eliminare.

## Minori

L'app è pensata anche per studenti minorenni. Non raccogliendo né trasmettendo
dati a terzi, non tratta dati personali di minori al di fuori del dispositivo.
L'account ClasseViva resta sotto la responsabilità della scuola e della famiglia.

## Permessi

Su Android l'app richiede unicamente il permesso `INTERNET`. Non accede a
contatti, posizione, fotocamera, microfono o file personali, salvo la scelta
esplicita di un file da parte dell'utente per importare/esportare la
configurazione.

## Modifiche a questa informativa

Eventuali modifiche saranno pubblicate in questo file con data di
aggiornamento. La versione vigente è sempre quella presente nel repository.
