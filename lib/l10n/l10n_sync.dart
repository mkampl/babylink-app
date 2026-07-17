import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';

/// Resolve [AppLocalizations] without a BuildContext — for background services
/// and notifications, which have no widget tree. Uses the saved language (the
/// same shared_preferences key the UI switcher writes), else the system locale,
/// falling back to English.
Future<AppLocalizations> l10nSync() async {
  String? code;
  try {
    code = (await SharedPreferences.getInstance()).getString('babylink-lang');
  } catch (_) {
    // no prefs available in this isolate — fall through to the system locale
  }
  code ??= PlatformDispatcher.instance.locale.languageCode;
  if (!AppLocalizations.supportedLocales.any((l) => l.languageCode == code)) {
    code = 'en';
  }
  return lookupAppLocalizations(Locale(code));
}
