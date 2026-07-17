import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';

/// Holds the user's language choice. A null [locale] follows the system
/// language (the "Auto" option); a set locale pins that language. The choice
/// persists in shared_preferences under the same key the web app uses.
class LocaleController extends ChangeNotifier {
  static const _key = 'babylink-lang';

  Locale? _locale;
  Locale? get locale => _locale;

  static List<Locale> get supported => AppLocalizations.supportedLocales;

  static bool _isSupported(String code) =>
      supported.any((l) => l.languageCode == code);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key);
    if (code != null && _isSupported(code)) {
      _locale = Locale(code);
    }
    notifyListeners();
  }

  /// Pass a language code to pin it, or null to fall back to the system locale.
  Future<void> setLocale(String? code) async {
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      _locale = null;
      await prefs.remove(_key);
    } else if (_isSupported(code)) {
      _locale = Locale(code);
      await prefs.setString(_key, code);
    }
    notifyListeners();
  }
}
