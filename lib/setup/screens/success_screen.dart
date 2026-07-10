import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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
    final link = s.roomLink;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

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
            Gap.hMd,
            HeroBadge(icon: Icons.check_rounded, tint: context.status.success, size: 120),
            Gap.hLg,
            if (link != null) ...[
              Text('Share this link so others can join — as a parent (to listen) or a second baby device:', style: t.bodyLarge),
              Gap.hSm,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: Radii.rMd,
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, size: 18, color: t.labelMedium!.color),
                    Gap.wSm,
                    Expanded(child: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium)),
                  ],
                ),
              ),
              Gap.hMd,
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => SharePlus.instance.share(
                          ShareParams(text: 'Join ${s.effectiveRoomName} on BabyLink 👶\n$link')),
                      icon: const Icon(Icons.ios_share_rounded, size: 20),
                      label: const Text('Share link'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                  Gap.wSm,
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Link copied')));
                        }
                      },
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      label: const Text('Copy'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                  ),
                ],
              ),
              Gap.hLg,
            ],
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
