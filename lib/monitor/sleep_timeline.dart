import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'baby_stream.dart';
import 'sleep_tracker.dart';

/// The two-tier sleep timeline from the web: a compact summary + a 15-minute
/// detail bar always visible, and a 12-hour history bar when expanded. Green =
/// quiet (asleep), yellow = movement, red = crying, grey = no data (monitor was
/// closed). Rebuilt each tick from the [SleepTracker].
class SleepTimeline extends StatelessWidget {
  final SleepTracker tracker;
  const SleepTimeline({super.key, required this.tracker});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final s = context.status;
    final palette = _Palette(
      green: s.success,
      yellow: s.warning,
      red: s.danger,
      none: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
    final t = Theme.of(context).textTheme;

    final detail = tracker.getSlots(now, 15 * 60 * 1000, 15 * 1000);
    final history = tracker.getSlots(now, 12 * 3600 * 1000, 60 * 1000);
    final sum15 = tracker.getSummary(now, 15 * 60 * 1000);
    final wakes12 = tracker.getWakeCount(now, 12 * 3600 * 1000);

    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: Gap.sm),
        title: Text(l10n.sleep, style: t.labelLarge),
        subtitle: Text(_summaryLine(sum15, wakes12), style: t.labelMedium!.copyWith(color: muted)),
        children: [
          _label(context, 'Last 15 min'),
          _bar(detail, palette),
          Gap.hSm,
          _label(context, 'Last 12 h'),
          _bar(history, palette),
          Gap.hSm,
          _legend(context, palette),
        ],
      ),
    );
  }

  String _summaryLine(SleepSlot sum, int wakes) {
    final total = sum.total;
    if (total == 0) return 'No history yet';
    final quietPct = (sum.g / total * 100).round();
    final wakeStr = wakes == 0 ? 'no wake-ups' : '$wakes wake-up${wakes == 1 ? '' : 's'} (12 h)';
    return '$quietPct% quiet · $wakeStr';
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(text,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
      );

  Widget _bar(List<SleepSlot> slots, _Palette p) => ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sm),
        child: SizedBox(
          height: 14,
          width: double.infinity,
          child: CustomPaint(painter: _StripePainter(slots, p)),
        ),
      );

  Widget _legend(BuildContext context, _Palette p) {
    final t = Theme.of(context).textTheme.labelSmall!;
    Widget dot(Color c, String s) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(s, style: t),
        ]);
    return Wrap(spacing: Gap.md, runSpacing: 4, children: [
      dot(p.green, 'Quiet'),
      dot(p.yellow, 'Movement'),
      dot(p.red, 'Crying'),
      dot(p.none, 'No data'),
    ]);
  }
}

class _Palette {
  final Color green, yellow, red, none;
  const _Palette({required this.green, required this.yellow, required this.red, required this.none});

  Color of(Band? b) => switch (b) {
        Band.red => red,
        Band.yellow => yellow,
        Band.green => green,
        null => none,
      };
}

class _StripePainter extends CustomPainter {
  final List<SleepSlot> slots;
  final _Palette palette;
  _StripePainter(this.slots, this.palette);

  @override
  void paint(Canvas canvas, Size size) {
    if (slots.isEmpty) return;
    final w = size.width / slots.length;
    final paint = Paint();
    for (var i = 0; i < slots.length; i++) {
      paint.color = palette.of(slots[i].dominant);
      // +0.6 so adjacent stripes overlap and leave no anti-alias seams.
      canvas.drawRect(Rect.fromLTWH(i * w, 0, w + 0.6, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => true; // cheap; refreshed each tick
}
