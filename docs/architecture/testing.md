# Strategia di test

- **Dominio**: limiti di orario, nomi vuoti, durata, adiacenza, sovrapposizioni, giorni e identificatori.
- **Controller**: stati caricamento/successo/errore, CRUD, importazione senza rete, conferma e annullamento della bozza.
- **Repository**: persistenza, transazioni, reload, cancellazione materia e migrazione schema.
- **ClasseViva**: fixture JSON anonimizzate, parsing data/ora, risposta vuota, campo mancante, risposta malformata, 401, timeout e errore HTTP. Finti HTTP e secure storage; mai credenziali reali.
- **Widget**: form lezione e relativi controlli; verificare anche visualizzazione settimana, modifica/eliminazione e revisione import.
- **Accettazione manuale**: login ClasseViva con account proprietario, verifica delle lezioni di una settimana passata e conferma che l'orario resta disponibile offline dopo riavvio.

Eseguire `flutter analyze` e `flutter test --coverage`. Il test d'integrazione con ClasseViva reale è manuale e condizionato alla disponibilità dell'account e dell'API.
