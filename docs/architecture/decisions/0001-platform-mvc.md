# ADR 0001: Flutter, MVC e archiviazione locale

**Stato:** accettata

## Contesto

Il prodotto è rivolto agli studenti, con Android prioritario e iOS richiesto. Deve funzionare senza backend e isolare le dipendenze esterne.

## Decisione

Usare Flutter/Dart con MVC esplicito e dependency injection nel composition root. SQLite conserva i dati dell'orario; secure storage conserva credenziali/token. ClasseViva è un adapter REST dietro un gateway. L'importazione crea una bozza locale da approvare prima della persistenza.

## Conseguenze

La UI e il dominio restano testabili senza rete. L'API non ufficiale può cambiare o non accettare account studente; il flusso manuale rimane autonomo. Il supporto iOS richiede build e firma su macOS.

