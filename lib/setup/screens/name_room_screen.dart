import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme.dart';
import '../../widgets/hero_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/step_scaffold.dart';
import '../../widgets/tip_banner.dart';
import '../setup_session.dart';
import 'applying_screen.dart';

/// Name the room — this is what shows in your rooms list and when you share
/// it, the same idea as naming a room in the web app.
class NameRoomScreen extends StatefulWidget {
  final SetupSession session;
  const NameRoomScreen({super.key, required this.session});

  @override
  State<NameRoomScreen> createState() => _NameRoomScreenState();
}

class _NameRoomScreenState extends State<NameRoomScreen> {
  final _controller = TextEditingController();

  // Adding a device to an existing room → name THIS device (baby), so several
  // devices in one room are distinguishable on the monitor. Otherwise name the
  // new room (which also names its first device).
  bool get _namingDevice => widget.session.targetRoom != null;

  @override
  void initState() {
    super.initState();
    _controller.text = _namingDevice ? widget.session.babyName : widget.session.roomName;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_namingDevice) {
      widget.session.babyName = _controller.text.trim();
    } else {
      widget.session.roomName = _controller.text.trim();
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ApplyingScreen(session: widget.session),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StepScaffold(
      title: _namingDevice ? l10n.nameThisDevice : l10n.nameThisRoom,
      subtitle: _namingDevice ? l10n.nameDeviceSub : l10n.nameRoomSub,
      bottom: PrimaryButton(
        l10n.connectBabylink,
        icon: Icons.check_rounded,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap.hLg,
          HeroBadge(emoji: _namingDevice ? '👶' : '🏷️', size: 116),
          Gap.hXl,
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: _namingDevice ? l10n.babyNameLabel : l10n.roomName,
              hintText: _namingDevice ? l10n.babyNameHint : l10n.roomNameHint,
            ),
          ),
          Gap.hMd,
          TipBanner(
            _namingDevice ? l10n.nameDeviceTip : l10n.nameRoomBlank,
            kind: TipKind.info,
          ),
        ],
      ),
    );
  }
}
