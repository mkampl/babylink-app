import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against localization drift: every locale must define exactly the same
/// keys as the English template, and each string's ICU placeholders must match.
void main() {
  final dir = Directory('lib/l10n');
  final arbs = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.arb'))
      .toList();

  Map<String, String> keysOf(File f) {
    final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return {
      for (final e in json.entries)
        if (!e.key.startsWith('@')) e.key: e.value.toString(),
    };
  }

  Set<String> placeholders(String s) =>
      RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

  final en = keysOf(File('lib/l10n/app_en.arb'));

  test('every locale has the same key set as English', () {
    for (final f in arbs) {
      final k = keysOf(f).keys.toSet();
      expect(k, en.keys.toSet(), reason: 'key mismatch in ${f.path}');
    }
  });

  test('placeholders match English for every key in every locale', () {
    for (final f in arbs) {
      final loc = keysOf(f);
      for (final key in en.keys) {
        expect(placeholders(loc[key] ?? ''), placeholders(en[key]!),
            reason: 'placeholder mismatch for "$key" in ${f.path}');
      }
    }
  });

  test('en/de/es/tr are all present', () {
    final locales =
        arbs.map((f) => f.uri.pathSegments.last).toSet();
    expect(locales, containsAll(<String>{
      'app_en.arb',
      'app_de.arb',
      'app_es.arb',
      'app_tr.arb',
    }));
  });
}
