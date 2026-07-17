import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';
import '../server/babylink_server.dart';
import '../store/app_store.dart';
import '../theme.dart';
import '../widgets/tip_banner.dart';

/// Point the app at a self-hosted BabyLink server. itvoodoo.at is only a public
/// demo — anyone running their own instance sets its address here. Existing
/// rooms keep the server they were created on; this is the default for NEW
/// rooms and devices.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  bool _custom = false;
  bool _testing = false;
  String? _okVersion; // set after a successful probe
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final server = await AppStore.instance.currentServer();
    final custom = await AppStore.instance.isCustomServer();
    if (!mounted) return;
    setState(() {
      _controller.text = server.baseUrl;
      _custom = custom;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  BabyLinkServer? _parsed() {
    try {
      return BabyLinkServer.parse(_controller.text);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      return null;
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _okVersion = null;
      _error = null;
    });
    final server = _parsed();
    if (server == null) {
      setState(() => _testing = false);
      return;
    }
    try {
      final version = await server.probe();
      if (mounted) setState(() => _okVersion = version);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final server = _parsed();
    if (server == null) return;
    // Insist on a successful probe before saving, so a typo can't silently
    // break every future room.
    if (_okVersion == null) {
      await _test();
      if (_okVersion == null) return;
    }
    await AppStore.instance.setServer(server.host, server.port);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).serverSaved)));
    Navigator.of(context).pop();
  }

  Future<void> _reset() async {
    await AppStore.instance.resetServer();
    await _load();
    if (mounted) {
      setState(() {
        _okVersion = null;
        _error = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).backToDemoServer)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.server)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            Text(l10n.babylinkServer, style: t.titleLarge),
            Gap.hSm,
            Text(
              l10n.selfHostedNote,
              style: t.bodyMedium,
            ),
            Gap.hLg,
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: (_) => setState(() {
                _okVersion = null;
                _error = null;
              }),
              decoration: InputDecoration(
                labelText: l10n.serverAddress,
                hintText: l10n.serverAddressHint,
                prefixIcon: const Icon(Icons.dns_rounded),
              ),
            ),
            Gap.hMd,
            if (_okVersion != null)
              TipBanner('Connected — BabyLink $_okVersion 🎉', kind: TipKind.success)
            else if (_error != null)
              TipBanner(_error!, kind: TipKind.danger),
            Gap.hMd,
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering_rounded),
                  label: Text(l10n.test),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
              Gap.wMd,
              Expanded(
                child: FilledButton.icon(
                  onPressed: _testing ? null : _save,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l10n.save),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ),
            ]),
            Gap.hSm,
            if (_custom)
              TextButton(onPressed: _reset, child: Text(l10n.resetToDemoServer)),
            Gap.hLg,
            const TipBanner(
              'Existing rooms keep the server they were set up on. This only changes '
              'where NEW rooms and devices are created.',
              kind: TipKind.info,
            ),
            Gap.hLg,
            _LanguageSection(t: t, l10n: l10n),
          ],
        ),
      ),
    );
  }
}

/// Language picker for the app UI. Language names are shown as endonyms (a user
/// recognises their own language by its own name), so they stay untranslated;
/// only the section title and the "Auto" option are localized. "Auto" follows
/// the system language. Selecting rebuilds the whole app via [localeController].
class _LanguageSection extends StatelessWidget {
  const _LanguageSection({required this.t, required this.l10n});

  final TextTheme t;
  final AppLocalizations l10n;

  static const _languages = <({String? code, String label})>[
    (code: 'en', label: 'English'),
    (code: 'de', label: 'Deutsch'),
    (code: 'es', label: 'Español'),
    (code: 'tr', label: 'Türkçe'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: localeController,
      builder: (context, _) {
        final current = localeController.locale?.languageCode;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.language, style: t.titleLarge),
            Gap.hMd,
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  RadioListTile<String?>(
                    value: null,
                    groupValue: current,
                    title: Text(l10n.languageAuto),
                    onChanged: (_) => localeController.setLocale(null),
                  ),
                  for (final lang in _languages)
                    RadioListTile<String?>(
                      value: lang.code,
                      groupValue: current,
                      title: Text(lang.label),
                      onChanged: (_) => localeController.setLocale(lang.code),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
