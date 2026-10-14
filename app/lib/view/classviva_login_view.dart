import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/school_data_controller.dart';
import 'app_palette.dart';

/// Unico punto di accesso a ClasseViva: usato dalle Impostazioni e come
/// destinazione di reindirizzo dalle pagine che richiedono la sessione.
/// Se esiste già una sessione salvata il modulo di accesso non viene
/// mostrato: serve prima disconnettersi.
class ClassVivaLoginView extends StatefulWidget {
  const ClassVivaLoginView({
    super.key,
    required this.controller,
    this.onSignedIn,
  });

  final SchoolDataController controller;

  /// Chiamato dopo un accesso o aggiornamento riuscito.
  final VoidCallback? onSignedIn;

  @override
  State<ClassVivaLoginView> createState() => _ClassVivaLoginViewState();
}

class _ClassVivaLoginViewState extends State<ClassVivaLoginView> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool? _hasSession;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = await widget.controller.hasSession();
    if (mounted) setState(() => _hasSession = session);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    TextInput.finishAutofillContext();
    await widget.controller.signInAndRefresh(
      username: _username.text.trim(),
      password: _password.text.trim(),
    );
    _password.clear();
    await _checkSession();
    if (widget.controller.message != null &&
        widget.controller.message != 'Dati ClasseViva aggiornati.') {
      return;
    }
    widget.onSignedIn?.call();
  }

  Future<void> _signOut() async {
    await widget.controller.signOut();
    await _checkSession();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          if (_hasSession == true) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  CircleAvatar(
                    backgroundColor:
                        Colors.green.withValues(alpha: .15),
                    foregroundColor: Colors.green,
                    child: const Icon(Icons.check_circle_outline),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Account collegato',
                            style:
                                Theme.of(context).textTheme.titleMedium),
                        Text(
                          controller.message ??
                              (controller.lastUpdated == null
                                  ? 'Sessione ClasseViva attiva.'
                                  : 'Ultimo aggiornamento: ${_shortDateTime(controller.lastUpdated!)}'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  FilledButton.tonalIcon(
                    onPressed: controller.isLoading
                        ? null
                        : () async {
                            await controller.useSavedSession();
                            widget.onSignedIn?.call();
                          },
                    icon: const Icon(Icons.sync),
                    label: const Text('Aggiorna dati'),
                  ),
                  TextButton.icon(
                    onPressed: controller.isLoading ? null : _signOut,
                    icon: const Icon(Icons.logout),
                    label: const Text('Disconnetti'),
                  ),
                ]),
                if (controller.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                controller.message ??
                    'Le credenziali restano nel portachiavi sicuro del dispositivo.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              AutofillGroup(
                child: Column(children: [
                  TextField(
                    controller: _username,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Codice utente ClasseViva',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) =>
                        controller.isLoading ? null : _signIn(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 4, children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.classeViva,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: controller.isLoading ? null : _signIn,
                  icon: const Icon(Icons.login),
                  label: const Text('Accedi e aggiorna'),
                ),
              ]),
              if (controller.isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );
        },
      );
}

String _shortDateTime(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} '
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
