import 'dart:math' as math;

import '../entities/subject.dart';

/// Selects a vivid color that is perceptually separated from existing subjects.
class DistinctSubjectColorSelector {
  const DistinctSubjectColorSelector();

  static const List<int> _candidates = [
    0xFF6750A4,
    0xFF0077B6,
    0xFF008A6A,
    0xFFD1495B,
    0xFFB05A00,
    0xFF7B61A8,
    0xFF00838F,
    0xFF8C3F65,
    0xFF4D7C0F,
    0xFF536DFE,
    0xFFAD1457,
    0xFF6D4C41,
    0xFF3949AB,
    0xFF558B2F,
    0xFFE65100,
  ];

  int selectFor(Iterable<Subject> subjects) {
    final existing =
        subjects.map((subject) => _lab(subject.colorValue)).toList();
    if (existing.isEmpty) return _candidates.first;
    var bestColor = _candidates.first;
    var bestDistance = -1.0;
    for (final candidate in _candidates) {
      final lab = _lab(candidate);
      final nearest = existing
          .map((other) => _distance(lab, other))
          .reduce((a, b) => a < b ? a : b);
      if (nearest > bestDistance) {
        bestDistance = nearest;
        bestColor = candidate;
      }
    }
    return bestColor;
  }

  static List<double> _lab(int color) {
    double linear(int channel) {
      final value = channel / 255;
      return value <= 0.04045
          ? value / 12.92
          : ((value + 0.055) / 1.055) *
              ((value + 0.055) / 1.055) *
              ((value + 0.055) / 1.055);
    }

    final r = linear((color >> 16) & 0xff);
    final g = linear((color >> 8) & 0xff);
    final b = linear(color & 0xff);
    final x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047;
    final y = r * 0.2126 + g * 0.7152 + b * 0.0722;
    final z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883;
    double f(double value) =>
        value > 0.008856 ? _cbrt(value) : 7.787 * value + 16 / 116;
    final fx = f(x), fy = f(y), fz = f(z);
    return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
  }

  static double _cbrt(double value) => math.pow(value, 1 / 3).toDouble();

  static double _distance(List<double> a, List<double> b) {
    final l = a[0] - b[0], x = a[1] - b[1], y = a[2] - b[2];
    return l * l + x * x + y * y;
  }
}
