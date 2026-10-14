import 'package:flutter/material.dart';

/// Tutorial di benvenuto al primo avvio: quattro pagine scorrevoli con
/// i concetti principali dell'app. Non chiudibile con tap fuori.
class WelcomeDialog extends StatefulWidget {
  const WelcomeDialog({super.key});

  @override
  State<WelcomeDialog> createState() => _WelcomeDialogState();
}

class _WelcomeDialogState extends State<WelcomeDialog> {
  final _pages = PageController();
  var _page = 0;

  static const _slides = [
    (
      Icons.school_outlined,
      'Benvenuto in School Manager',
      'Organizza orario, materie, compiti e voti in un’unica app, '
          'anche senza connessione: tutto è salvato sul dispositivo.',
    ),
    (
      Icons.schedule_outlined,
      'Orario e campanelle',
      'Imposta le campanelle condivise e il numero di ore per ogni '
          'giorno, poi aggiungi materie e lezioni dalla tab Orario.',
    ),
    (
      Icons.event_note_outlined,
      'Agenda e voti',
      'Scorri tra giorni, settimane e mesi, segna verifiche e compiti '
          'e tieni d’occhio medie e obiettivi nella pagina Voti.',
    ),
    (
      Icons.link_outlined,
      'ClasseViva',
      'Collega il registro elettronico dalle Impostazioni per '
          'importare orario, voti, presenze e comunicazioni, con '
          'aggiornamento automatico ogni 5 minuti.',
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              onPageChanged: (index) => setState(() => _page = index),
              itemCount: _slides.length,
              itemBuilder: (context, index) {
                final (icon, title, body) = _slides[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 40,
                      child: Icon(icon, size: 40),
                    ),
                    const SizedBox(height: 20),
                    Text(title,
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Text(body,
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center),
                  ]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(children: [
              Row(children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _page == i ? 18 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: _page == i
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant
                              .withValues(alpha: .3),
                    ),
                  ),
              ]),
              const Spacer(),
              if (!last)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Salta'),
                ),
              FilledButton(
                onPressed: () {
                  if (last) {
                    Navigator.pop(context);
                  } else {
                    _pages.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    );
                  }
                },
                child: Text(last ? 'Inizia' : 'Avanti'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
