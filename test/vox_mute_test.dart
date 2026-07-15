import 'package:babylink_app/monitor/baby_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('voxEffectiveMuted', () {
    test('listen hold forces audible — overrides everything', () {
      // crying / manual "listen in" both feed listenHold.
      for (final kind in BabyKind.values) {
        expect(
            voxEffectiveMuted(kind: kind, listenHold: true, muteHold: false, quietForMs: 99999), isFalse);
        // listen beats a simultaneous mute (crying overriding a manual mute).
        expect(
            voxEffectiveMuted(kind: kind, listenHold: true, muteHold: true, quietForMs: 0), isFalse);
      }
    });

    test('mute hold silences when not listening', () {
      expect(voxEffectiveMuted(kind: BabyKind.pcm, listenHold: false, muteHold: true, quietForMs: 0), isTrue);
      expect(
          voxEffectiveMuted(kind: BabyKind.webrtc, listenHold: false, muteHold: true, quietForMs: 0), isTrue);
    });

    test('auto PCM follows VOX by quiet duration when no hold', () {
      expect(
          voxEffectiveMuted(
              kind: BabyKind.pcm, listenHold: false, muteHold: false, quietForMs: 0, voxHoldMs: 4000),
          isFalse);
      expect(
          voxEffectiveMuted(
              kind: BabyKind.pcm, listenHold: false, muteHold: false, quietForMs: 3999, voxHoldMs: 4000),
          isFalse);
      expect(
          voxEffectiveMuted(
              kind: BabyKind.pcm, listenHold: false, muteHold: false, quietForMs: 4001, voxHoldMs: 4000),
          isTrue);
    });

    test('auto WebRTC never self-mutes (no reliable receive level)', () {
      expect(
          voxEffectiveMuted(kind: BabyKind.webrtc, listenHold: false, muteHold: false, quietForMs: 99999),
          isFalse);
    });
  });

  group('BabyStream hold windows', () {
    test('holds are inactive by default and honor the deadline', () {
      final b = BabyStream('a', 'A');
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      expect(b.listenHoldActive(now), isFalse);
      expect(b.muteHoldActive(now), isFalse);

      b.listenHoldUntil = now.add(const Duration(seconds: 10));
      expect(b.listenHoldActive(now), isTrue);
      expect(b.listenHoldActive(now.add(const Duration(seconds: 11))), isFalse);
    });
  });
}
