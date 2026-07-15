import 'package:babylink_app/monitor/baby_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('voxEffectiveMuted', () {
    test('muted mode is silent while quiet', () {
      for (final kind in BabyKind.values) {
        expect(voxEffectiveMuted(mode: ListenMode.muted, kind: kind, quietForMs: 0, level: 0), isTrue);
        expect(voxEffectiveMuted(mode: ListenMode.muted, kind: kind, quietForMs: 99999, level: 0.1), isTrue);
      }
    });

    test('crying overrides a hard mute — a cry is always heard', () {
      expect(voxEffectiveMuted(mode: ListenMode.muted, kind: BabyKind.pcm, quietForMs: 0, level: 0.8),
          isFalse);
      expect(voxEffectiveMuted(mode: ListenMode.muted, kind: BabyKind.webrtc, quietForMs: 0, level: 0.8),
          isFalse);
      // Just under the cry threshold stays muted.
      expect(voxEffectiveMuted(mode: ListenMode.muted, kind: BabyKind.pcm, quietForMs: 0, level: 0.49),
          isTrue);
    });

    test('listen mode is always audible — overrides VOX quiet', () {
      // The whole point of "listen in": even long quiet stays open.
      expect(voxEffectiveMuted(mode: ListenMode.listen, kind: BabyKind.pcm, quietForMs: 99999, level: 0),
          isFalse);
      expect(voxEffectiveMuted(mode: ListenMode.listen, kind: BabyKind.webrtc, quietForMs: 99999, level: 0),
          isFalse);
    });

    test('auto PCM follows VOX by quiet duration', () {
      expect(
          voxEffectiveMuted(mode: ListenMode.auto, kind: BabyKind.pcm, quietForMs: 0, level: 0, voxHoldMs: 4000),
          isFalse);
      expect(
          voxEffectiveMuted(mode: ListenMode.auto, kind: BabyKind.pcm, quietForMs: 3999, level: 0, voxHoldMs: 4000),
          isFalse);
      expect(
          voxEffectiveMuted(mode: ListenMode.auto, kind: BabyKind.pcm, quietForMs: 4001, level: 0, voxHoldMs: 4000),
          isTrue);
    });

    test('auto WebRTC never self-mutes (no reliable receive level)', () {
      expect(voxEffectiveMuted(mode: ListenMode.auto, kind: BabyKind.webrtc, quietForMs: 99999, level: 0),
          isFalse);
    });
  });
}
