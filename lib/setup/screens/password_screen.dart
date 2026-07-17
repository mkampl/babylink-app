import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../store/app_store.dart';
import '../../theme.dart';
import '../../widgets/hero_badge.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/step_scaffold.dart';
import '../../widgets/tip_banner.dart';
import '../setup_session.dart';
import 'name_room_screen.dart';

class PasswordScreen extends StatefulWidget {
  final SetupSession session;
  const PasswordScreen({super.key, required this.session});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _controller = TextEditingController();
  bool _hidden = true;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    // Reuse a previously-saved password for this network, if we have one.
    AppStore.instance.wifiPassword(widget.session.ssid).then((pw) {
      if (pw != null && pw.isNotEmpty && mounted && _controller.text.isEmpty) {
        setState(() {
          _controller.text = pw;
          _prefilled = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isEmpty) return;
    widget.session.password = _controller.text;
    // Adding to an existing room? It's already named — go straight to applying.
    // Otherwise name the new room first.
    final s = widget.session;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NameRoomScreen(session: s),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StepScaffold(
      title: l10n.enterWifiPassword,
      subtitle: l10n.forSsid(widget.session.ssid),
      bottom: ValueListenableBuilder(
        valueListenable: _controller,
        builder: (_, value, __) => PrimaryButton(
          l10n.next,
          icon: Icons.arrow_forward_rounded,
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
              labelText: l10n.password,
              suffixIcon: Semantics(
                label: _hidden ? l10n.showPassword : l10n.hidePassword,
                child: IconButton(
                  icon: Icon(_hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _hidden = !_hidden),
                ),
              ),
            ),
          ),
          Gap.hMd,
          TipBanner(
            _prefilled
                ? l10n.savedPasswordNote
                : l10n.homeWifiNote,
            kind: _prefilled ? TipKind.success : TipKind.info,
          ),
        ],
      ),
    );
  }
}
