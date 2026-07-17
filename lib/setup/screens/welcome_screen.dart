import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    return StepScaffold(
      title: l10n.welcomeTitle,
      subtitle: l10n.welcomeBody,
      showBack: false,
      bottom: PrimaryButton(
        l10n.getStarted,
        icon: Icons.arrow_forward_rounded,
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ScanScreen(session: SetupSession()),
          ));
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap.hLg,
          const HeroBadge(emoji: '👶', size: 140),
          Gap.hXl,
          TipBanner(
            l10n.welcomePrivacy,
            kind: TipKind.info,
            icon: Icons.lock_rounded,
          ),
        ],
      ),
    );
  }
}
