import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/hero_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/step_scaffold.dart';
import '../../widgets/tip_banner.dart';
import '../setup_session.dart';
import 'applying_screen.dart';

class PasswordScreen extends StatefulWidget {
  final SetupSession session;
  const PasswordScreen({super.key, required this.session});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _controller = TextEditingController();
  bool _hidden = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isEmpty) return;
    widget.session.password = _controller.text;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ApplyingScreen(session: widget.session),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StepScaffold(
      title: 'Enter the WiFi password',
      subtitle: 'for “${widget.session.ssid}”',
      bottom: ValueListenableBuilder(
        valueListenable: _controller,
        builder: (_, value, __) => PrimaryButton(
          'Connect BabyLink',
          icon: Icons.check_rounded,
          onPressed: value.text.isEmpty ? null : _submit,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap.hLg,
          const HeroBadge(emoji: '🔒', size: 116),
          Gap.hXl,
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: _hidden,
            textInputAction: TextInputAction.go,
            keyboardType: TextInputType.visiblePassword,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: Semantics(
                label: _hidden ? 'Show password' : 'Hide password',
                child: IconButton(
                  icon: Icon(_hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
            ),
          ),
          Gap.hMd,
          const TipBanner(
            'This is your home WiFi password — the same one on your other devices.',
            kind: TipKind.info,
          ),
        ],
      ),
    );
  }
}
