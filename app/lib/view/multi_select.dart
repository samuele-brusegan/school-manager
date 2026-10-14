import 'package:flutter/material.dart';

/// Campo a tendina che apre un dialog con checkbox: pensato per liste
/// potenzialmente lunghe (docenti, aule) dove una riga di chip non starebbe.
class MultiSelectField extends StatelessWidget {
  const MultiSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.emptyText = 'Nessuna voce disponibile.',
  });

  final String label;
  final Set<String> options;
  final Set<String> selected;
  final void Function(String option, bool selected) onChanged;
  final String emptyText;

  Future<void> _pick(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(label),
          content: SizedBox(
            width: 340,
            child: options.isEmpty
                ? Text(emptyText)
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final option in options)
                        CheckboxListTile(
                          dense: true,
                          title: Text(option),
                          value: selected.contains(option),
                          onChanged: (value) {
                            onChanged(option, value ?? false);
                            setDialogState(() {});
                          },
                        ),
                    ],
                  ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fatto'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = selected.isEmpty
        ? 'Nessuna selezione'
        : (selected.toList()..sort()).join(', ');
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _pick(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down),
        ),
        child: Text(
          summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: selected.isEmpty
              ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)
              : null,
        ),
      ),
    );
  }
}
