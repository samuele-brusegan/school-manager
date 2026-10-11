import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/school_data_controller.dart';
import 'app_palette.dart';

/// Unico punto di accesso a ClasseViva: usato dalle Impostazioni e come
/// destinazione di reindirizzo dalle pagine che richiedono la sessione.
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
    widget.onSignedIn?.call();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                controller.message ??
                    (controller.lastUpdated == null
                        ? 'Le credenziali restano nel portachiavi sicuro del dispositivo.'
                        : 'Ultimo aggiornamento: ${_shortDateTime(controller.lastUpdated!)}'),
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
                OutlinedButton(
                  onPressed: controller.isLoading
                      ? null
                      : () async {
                          await controller.useSavedSession();
                          widget.onSignedIn?.call();
                        },
                  child: const Text('Usa sessione salvata'),
                ),
                TextButton(
                  onPressed:
                      controller.isLoading ? null : controller.signOut,
                  child: const Text('Disconnetti'),
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
