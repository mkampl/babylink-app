import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import '../../widgets/hero_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/step_scaffold.dart';
import '../../widgets/tip_banner.dart';
import '../setup_session.dart';

class SuccessScreen extends StatefulWidget {
  final SetupSession session;
  const SuccessScreen({super.key, required this.session});

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return PopScope(
      canPop: false,
      child: StepScaffold(
        title: 'Your BabyLink is connected ✓',
        subtitle: 'It’s on “${s.ssid}” and ready to keep watch. 👶',
        showBack: false,
        bottom: PrimaryButton(
          'Done',
          icon: Icons.check_rounded,
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Gap.hLg,
            HeroBadge(icon: Icons.check_rounded, tint: context.status.success, size: 132),
            Gap.hXl,
            const TipBanner(
              'You can unplug and move it wherever you need — it’ll reconnect on its own.',
              kind: TipKind.success,
            ),
          ],
        ),
      ),
    );
  }
}
