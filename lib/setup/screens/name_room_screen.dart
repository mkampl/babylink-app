import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _controller.text = widget.session.roomName;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    widget.session.roomName = _controller.text.trim();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ApplyingScreen(session: widget.session),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: 'Name this room',
      subtitle: 'Give it a name you’ll recognise in your rooms list.',
      bottom: PrimaryButton(
        'Connect BabyLink',
        icon: Icons.check_rounded,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap.hLg,
          const HeroBadge(emoji: '🏷️', size: 116),
          Gap.hXl,
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Room name',
              hintText: 'Nursery',
            ),
          ),
          Gap.hMd,
          const TipBanner(
            'You can leave it blank — we’ll name it after the device.',
            kind: TipKind.info,
          ),
        ],
      ),
    );
  }
}
