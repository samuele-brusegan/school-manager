import 'package:flutter/material.dart';

/// Tavolozza principale dell'app: quattro accenti coordinati.
abstract final class AppPalette {
  static const Color indigo = Color(0xFF4355A5);
  static const Color teal = Color(0xFF2E8B84);
  static const Color amber = Color(0xFFD9A441);
  static const Color classeViva = Color(0xFFD63031);

  /// Accenti ruotati nelle intestazioni delle sezioni.
  static const List<Color> sectionAccents = <Color>[
    indigo,
    teal,
    amber,
    classeViva,
  ];
}
