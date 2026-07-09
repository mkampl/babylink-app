import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/hero_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/step_scaffold.dart';
import '../../widgets/tip_banner.dart';
import '../setup_session.dart';
import 'scan_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: 'Set up your BabyLink',
      subtitle: 'Let’s get your monitor connected to WiFi. It only takes a minute.',
      showBack: false,
      bottom: PrimaryButton(
        'Get started',
        icon: Icons.arrow_forward_rounded,
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ScanScreen(session: SetupSession()),
          ));
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Gap.hLg,
          HeroBadge(emoji: '👶', size: 140),
          Gap.hXl,
          TipBanner(
            'Private by design. Everything stays on your home network — nothing goes to the cloud.',
            kind: TipKind.info,
            icon: Icons.lock_rounded,
          ),
        ],
      ),
    );
  }
}
