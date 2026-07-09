import 'package:flutter/material.dart';

import '../../store/app_store.dart';
import '../../theme.dart';
import '../../widgets/hero_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/step_scaffold.dart';
import '../../widgets/tip_banner.dart';
import '../setup_session.dart';
import 'success_screen.dart';

enum _Stage { room, saving, restarting, joining, done, failed }

class ApplyingScreen extends StatefulWidget {
  final SetupSession session;
  const ApplyingScreen({super.key, required this.session});

  @override
  State<ApplyingScreen> createState() => _ApplyingScreenState();
}

class _ApplyingScreenState extends State<ApplyingScreen> {
  _Stage _stage = _Stage.room;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final s = widget.session;
    try {
      // 1) Create the room on the server (so the user never types server/room).
      setState(() => _stage = _Stage.room);
      s.room = await s.server.createRoom(s.deviceName);

      // 2) Stage the config, then 3) apply (device persists + reboots).
      setState(() => _stage = _Stage.saving);
      await s.ble.writeConfig(s.buildConfig());
      setState(() => _stage = _Stage.restarting);
      try {
        await s.ble.apply();
      } catch (_) {
        // The device reboots on apply and drops BLE mid-write — expected.
      }
      try {
        await s.ble.disconnect();
      } catch (_) {}

      // 4) Wait for it to join WiFi and reach the server.
      setState(() => _stage = _Stage.joining);
      final online = await s.server.waitForDeviceOnline(s.room!.roomId);

      if (online) {
        // Persist the room (with its share link + owner token) and the WiFi
        // password so re-provisioning another device is one tap.
        await AppStore.instance.saveWifi(s.ssid, s.password ?? '');
        await AppStore.instance.addRoom(SavedRoom(
          roomId: s.room!.roomId,
          ownerToken: s.room!.ownerToken,
          name: s.deviceName,
          ssid: s.ssid,
          serverHost: s.server.host,
          serverPort: s.server.port,
          createdAt: DateTime.now(),
        ));
      }
      if (!mounted) return;
      if (online) {
        setState(() => _stage = _Stage.done);
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => SuccessScreen(session: s)));
      } else {
        // Config was saved & applied, but we didn't see it online in time.
        // Likely a wrong password or weak signal.
        setState(() {
          _stage = _Stage.failed;
          _error = 'Your BabyLink couldn’t join that network in time. '
              'Double-check the password, or try a stronger signal.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = 'Something went wrong setting up the device. Let’s try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _Stage.failed) return _failed(context);
    final active = _stage;
    return PopScope(
      canPop: false,
      child: StepScaffold(
        title: 'Setting up your BabyLink',
        showBack: false,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Gap.hLg,
            const HeroBadge(emoji: '✨', pulse: true),
            Gap.hXl,
            _row('Creating your room', _Stage.room, active),
            _row('Saving WiFi', _Stage.saving, active),
            _row('Restarting the device', _Stage.restarting, active),
            _row('Joining your network', _Stage.joining, active),
            Gap.hLg,
            Center(
              child: Text(
                'This can take up to half a minute. Hang tight. 💙',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, _Stage stage, _Stage active) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final done = active.index > stage.index;
    final isActive = active == stage;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: done
                ? Icon(Icons.check_circle_rounded, color: cs.primary, size: 24)
                : isActive
                    ? const CircularProgressIndicator(strokeWidth: 2.4)
                    : Icon(Icons.circle_outlined, color: cs.outlineVariant, size: 22),
          ),
          Gap.wMd,
          Text(
            label,
            style: t.bodyLarge!.copyWith(
              color: (done || isActive) ? t.bodyLarge!.color : cs.outline,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _failed(BuildContext context) {
    return StepScaffold(
      title: 'Almost there',
      subtitle: 'The setup didn’t finish.',
      showBack: false,
      bottom: PrimaryButton(
        'Try again',
        icon: Icons.refresh_rounded,
        onPressed: () => Navigator.of(context)
          ..pop()
          ..pop(), // back to the password / wifi step to retry
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap.hLg,
          HeroBadge(emoji: '😕', tint: context.status.warning),
          Gap.hXl,
          TipBanner(_error ?? 'Please try again.', kind: TipKind.danger),
        ],
      ),
    );
  }
}
