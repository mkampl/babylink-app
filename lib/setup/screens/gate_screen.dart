import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../widgets/hero_badge.dart';
import '../../widgets/step_scaffold.dart';
import '../../widgets/tip_banner.dart';
import '../setup_session.dart';
import 'pick_wifi_screen.dart';

/// The device is already configured, so provisioning is locked until the user
/// physically taps its button (anti-hijack). We subscribe to the INFO notify
/// and auto-advance the moment the window opens.
class GateScreen extends StatefulWidget {
  final SetupSession session;
  const GateScreen({super.key, required this.session});

  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  StreamSubscription? _infoSub;
  Timer? _slowTimer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _listen();
    _slowTimer = Timer(const Duration(seconds: 60), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _infoSub?.cancel();
    _slowTimer?.cancel();
    super.dispose();
  }

  void _listen() {
    _infoSub = widget.session.ble.watchInfo().listen((info) {
      widget.session.info = info;
      if (info.provOpen && mounted) {
        HapticFeedback.mediumImpact();
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => PickWifiScreen(session: widget.session),
        ));
      }
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return StepScaffold(
      title: l10n.gateTitle,
      subtitle: l10n.gateSecure,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap.hLg,
          const HeroBadge(emoji: '👆', pulse: true, size: 132),
          Gap.hXl,
          TipBanner(
            l10n.gatePress,
            kind: TipKind.info,
          ),
          Gap.hLg,
          Center(child: Text(l10n.waitingForYou, style: t.labelMedium)),
          if (_slow) ...[
            Gap.hLg,
            TipBanner(l10n.gateStillWaiting, kind: TipKind.warning),
          ],
        ],
      ),
    );
  }
}
