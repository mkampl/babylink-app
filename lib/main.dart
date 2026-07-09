import 'package:flutter/material.dart';

import 'setup/screens/welcome_screen.dart';
import 'theme.dart';

void main() {
  runApp(const BabyLinkApp());
}

class BabyLinkApp extends StatelessWidget {
  const BabyLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BabyLink',
      debugShowCheckedModeBanner: false,
      theme: BabyLinkTheme.light(),
      darkTheme: BabyLinkTheme.dark(),
      themeMode: ThemeMode.system,
      home: const WelcomeScreen(),
    );
  }
}
