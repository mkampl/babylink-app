import 'package:babylink_app/monitor/baby_stream.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bandFor', () {
    test('classifies green / yellow / red by level', () {
      expect(bandFor(0.05), Band.green);
      expect(bandFor(0.11), Band.green);
      expect(bandFor(0.12), Band.yellow);
      expect(bandFor(0.49), Band.yellow);
      expect(bandFor(0.5), Band.red);
      expect(bandFor(0.9), Band.red);
    });
  });

  group('nextAutoAudible (web-style VOX)', () {
    test('RED unmutes immediately', () {
      expect(
          nextAutoAudible(current: false, band: Band.red, yellowHeldMs: 0, greenHeldMs: 0, recentlyRed: false),
          isTrue);
    });

    test('YELLOW only unmutes after the delay', () {
      // brief movement — stays muted
      expect(
          nextAutoAudible(current: false, band: Band.yellow, yellowHeldMs: 500, greenHeldMs: 0, recentlyRed: false),
          isFalse);
      // sustained movement — unmutes
      expect(
          nextAutoAudible(current: false, band: Band.yellow, yellowHeldMs: 2000, greenHeldMs: 0, recentlyRed: false),
          isTrue);
      // already audible stays audible on yellow
      expect(
          nextAutoAudible(current: true, band: Band.yellow, yellowHeldMs: 0, greenHeldMs: 0, recentlyRed: false),
          isTrue);
    });

    test('GREEN mutes after the delay, longer after crying', () {
      // audible, brief quiet — stays audible
      expect(
          nextAutoAudible(current: true, band: Band.green, yellowHeldMs: 0, greenHeldMs: 3000, recentlyRed: false),
          isTrue);
      // audible, quiet past 5s — mutes
      expect(
          nextAutoAudible(current: true, band: Band.green, yellowHeldMs: 0, greenHeldMs: 5001, recentlyRed: false),
          isFalse);
      // just cried: 5s quiet isn't enough (needs 10s)
      expect(
          nextAutoAudible(current: true, band: Band.green, yellowHeldMs: 0, greenHeldMs: 6000, recentlyRed: true),
          isTrue);
      expect(
          nextAutoAudible(current: true, band: Band.green, yellowHeldMs: 0, greenHeldMs: 10001, recentlyRed: true),
          isFalse);
      // already muted stays muted
      expect(
          nextAutoAudible(current: false, band: Band.green, yellowHeldMs: 0, greenHeldMs: 99999, recentlyRed: false),
          isFalse);
    });
  });

  group('voxEffectiveMuted (resolution)', () {
    test('crying (red) is always heard, even through a manual mute', () {
      expect(
          voxEffectiveMuted(kind: BabyKind.pcm, red: true, listenHold: false, muteHold: true, autoAudible: false),
          isFalse);
    });

    test('manual listen-in overrides auto', () {
      expect(
          voxEffectiveMuted(kind: BabyKind.pcm, red: false, listenHold: true, muteHold: false, autoAudible: false),
          isFalse);
    });

    test('manual mute silences when not crying/listening', () {
      expect(
          voxEffectiveMuted(kind: BabyKind.pcm, red: false, listenHold: false, muteHold: true, autoAudible: true),
          isTrue);
    });

    test('PCM follows the auto latch', () {
      expect(
          voxEffectiveMuted(kind: BabyKind.pcm, red: false, listenHold: false, muteHold: false, autoAudible: true),
          isFalse);
      expect(
          voxEffectiveMuted(kind: BabyKind.pcm, red: false, listenHold: false, muteHold: false, autoAudible: false),
          isTrue);
    });

    test('WebRTC stays open under auto (no reliable receive level)', () {
      expect(
          voxEffectiveMuted(kind: BabyKind.webrtc, red: false, listenHold: false, muteHold: false, autoAudible: false),
          isFalse);
    });
  });
}
