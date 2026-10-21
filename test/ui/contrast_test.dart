import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sha/app/theme.dart';

/// WCAG 2.x contrast ratio, from [Color.computeLuminance] (relative
/// luminance of sRGB).
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const text = {
    'text': ShaColors.text,
    'textSecondary': ShaColors.textSecondary,
    'textMuted': ShaColors.textMuted,
  };
  const surfaces = {
    'background': ShaColors.background,
    'surface': ShaColors.surface,
    'surfaceHigh': ShaColors.surfaceHigh,
  };

  void expectAtLeast(String name, Color fg, Color bg, double minimum) {
    final ratio = contrast(fg, bg);
    expect(
      ratio,
      greaterThanOrEqualTo(minimum),
      reason: '$name is ${ratio.toStringAsFixed(2)}:1, needs $minimum:1',
    );
  }

  test('body text is readable on every surface (4.5:1)', () {
    for (final t in text.entries) {
      for (final s in surfaces.entries) {
        expectAtLeast('${t.key} on ${s.key}', t.value, s.value, 4.5);
      }
    }
  });

  test('status colours are readable where they are used (4.5:1)', () {
    expectAtLeast(
      'success on background',
      ShaColors.success,
      ShaColors.background,
      4.5,
    );
    expectAtLeast(
      'success on surface',
      ShaColors.success,
      ShaColors.surface,
      4.5,
    );
    expectAtLeast(
      'warning on warningContainer',
      ShaColors.warning,
      ShaColors.warningContainer,
      4.5,
    );
    expectAtLeast(
      'danger on background',
      ShaColors.danger,
      ShaColors.background,
      4.5,
    );
    expectAtLeast(
      'danger on dangerContainer',
      ShaColors.danger,
      ShaColors.dangerContainer,
      4.5,
    );
    // Label of the destructive dialog button.
    expectAtLeast(
      'dangerContainer on danger',
      ShaColors.dangerContainer,
      ShaColors.danger,
      4.5,
    );
  });

  test('field borders are visible (3:1, WCAG 1.4.11)', () {
    expectAtLeast(
      'fieldBorder on navBar',
      ShaColors.fieldBorder,
      ShaColors.navBar,
      3,
    );
    expectAtLeast(
      'fieldBorder on background',
      ShaColors.fieldBorder,
      ShaColors.background,
      3,
    );
  });

  test('the helper agrees with known WCAG values', () {
    expect(
      contrast(
        const Color.fromARGB(255, 0, 0, 0),
        const Color.fromARGB(255, 255, 255, 255),
      ),
      closeTo(21, 0.01),
    );
    expect(
      contrast(ShaColors.textMuted, ShaColors.surfaceHigh),
      closeTo(5.54, 0.01),
    );
  });
}
