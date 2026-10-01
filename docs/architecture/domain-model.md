# Modello di dominio

## Subject

- `id`: identificatore stabile locale.
- `name`: nome non vuoto e normalizzato ai bordi.
- `colorValue`: colore ARGB per la presentazione.

## Lesson

- `id`, `subjectId`.
- `weekday`: ISO-8601, lunedì 1 … domenica 7.
- `startMinute`, `endMinute`: minuti da mezzanotte, con `0 <= start < end <= 1440`.
- L'intervallo è semiaperto; lezioni dello stesso giorno non possono sovrapporsi.

## PeriodTime

- `number`: numero dell'ora riportato da ClasseViva.
- `startMinute`, `endMinute`: campanella configurata manualmente dall'utente.
- Numeri ora consecutivi possono avere intervalli adiacenti o pause; gli intervalli non possono sovrapporsi.

## Timetable

Insieme di materie e ricorrenze. La validazione richiede riferimenti materia esistenti, identificatori unici, nomi materia non vuoti e assenza di sovrapposizioni. Il repository applica ogni modifica in transazione.

## ClasseViva lesson

Record remoto con data, orario, descrizione materia e dati opzionali. Il mapper converte solo record con data e intervallo validi. Le materie sono abbinate senza distinzione tra maiuscole/minuscole dopo trim; nuovi nomi diventano materie della bozza. Nessuna scrittura viene eseguita durante il parsing.
