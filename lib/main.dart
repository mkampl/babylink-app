import 'package:flutter/material.dart';

import 'home/home_screen.dart';
import 'l10n/app_localizations.dart';
import 'l10n/locale_controller.dart';
import 'theme.dart';

/// Global language controller — read by settings to change the app language.
final localeController = LocaleController();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  localeController.load();
  runApp(const BabyLinkApp());
}

class BabyLinkApp extends StatelessWidget {
  const BabyLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: localeController,
      builder: (context, _) => MaterialApp(
        title: 'BabyLink',
        debugShowCheckedModeBanner: false,
        theme: BabyLinkTheme.light(),
        darkTheme: BabyLinkTheme.dark(),
        themeMode: ThemeMode.system,
        locale: localeController.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeScreen(),
      ),
    );
  }
}
