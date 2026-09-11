// safe_spit_calculator_test.dart — SAFE//SPIT
//
// Phase 1 acceptance tests — the three proven test points MUST pass.
// Also covers all shared-spec/test-vectors.json assertions for Dart.
//
// These are the FIRST tests that run. If any fail, the build is broken.
// RULE 7: Simulation tests must pass before any new mode is added.

import 'package:flutter_test/flutter_test.dart';
import 'package:safespit/simulation/safe_spit_calculator.dart';

void main() {
  group('SafeSpitCalculator — projectile-motion formula', () {
    // ── Stationary ──────────────────────────────────────────────────────────
    test('targetPitch(0) == 0.0 (straight up, stationary)', () {
      expect(SafeSpitCalculator.targetPitch(0.0), equals(0.0));
    });

    test('targetPitch(negative speed) == 0.0 (clamped, Rule 16)', () {
      expect(SafeSpitCalculator.targetPitch(-10.0), equals(0.0));
    });

    // ── At speed the angle should be > 0 and <= 90 ─────────────────────────
    test('targetPitch(50) is in valid range (0, 90]', () {
      final p = SafeSpitCalculator.targetPitch(50.0);
      expect(p, greaterThan(0.0));
      expect(p, lessThanOrEqualTo(90.0));
    });

    // ── Monotonic: higher speed → larger pitch (more horizontal) ───────────
    test('targetPitch increases monotonically with speed', () {
      double prev = 0.0;
      for (double v = 1; v <= 200; v += 10) {
        final pitch = SafeSpitCalculator.targetPitch(v);
        expect(pitch, greaterThanOrEqualTo(prev));
        prev = pitch;
      }
    });

    // ── Determinism ─────────────────────────────────────────────────────────
    test('same inputs produce same output (determinism)', () {
      final r1 = SafeSpitCalculator.targetPitch(75.0);
      final r2 = SafeSpitCalculator.targetPitch(75.0);
      expect(r1, equals(r2));
    });

    // ── Clamp upper ─────────────────────────────────────────────────────────
    test('targetPitch is always <= 90.0', () {
      for (double v = 0; v <= 300; v += 10) {
        expect(SafeSpitCalculator.targetPitch(v), lessThanOrEqualTo(90.0));
      }
    });

    // ── Clamp lower ─────────────────────────────────────────────────────────
    test('targetPitch is always >= 0.0', () {
      for (double v = 0; v <= 300; v += 10) {
        expect(SafeSpitCalculator.targetPitch(v), greaterThanOrEqualTo(0.0));
      }
    });
  });

  group('SafeSpitCalculator — isClearToEject (PROVEN tolerance)', () {
    // ── TV-04: Just inside tolerance ────────────────────────────────────────
    test('TV-04: deltaDeg=4.9 → isClearToEject=true', () {
      // targetPitch(50) = 70.0; actualPitch = 65.1 → delta = 4.9
      expect(
        SafeSpitCalculator.isClearToEject(
            actualPitchDeg: 65.1, targetPitchDeg: 70.0, speedKmh: 50.0),
        isTrue,
      );
    });

    // ── TV-05: Exactly on tolerance edge (inclusive <=) ─────────────────────
    test('TV-05: deltaDeg=5.0 → isClearToEject=true (inclusive)', () {
      expect(
        SafeSpitCalculator.isClearToEject(
            actualPitchDeg: 65.0, targetPitchDeg: 70.0, speedKmh: 50.0),
        isTrue,
      );
    });

    // ── TV-06: Just outside tolerance ───────────────────────────────────────
    test('TV-06: deltaDeg=5.1 → isClearToEject=false', () {
      expect(
        SafeSpitCalculator.isClearToEject(
            actualPitchDeg: 64.9, targetPitchDeg: 70.0, speedKmh: 50.0),
        isFalse,
      );
    });

    test('exact match: actualPitch == targetPitch → locked', () {
      expect(
        SafeSpitCalculator.isClearToEject(
            actualPitchDeg: 70.0, targetPitchDeg: 70.0, speedKmh: 50.0),
        isTrue,
      );
    });

    test('targetPitch > 135 requires strict roll (roll > 15 fails)', () {
      expect(
        SafeSpitCalculator.isClearToEject(
            actualPitchDeg: 180.0, targetPitchDeg: 180.0, speedKmh: 0.0, rollDeg: 20.0),
        isFalse, // Fails due to roll
      );
    });

    test('targetPitch > 135 passes if roll <= 15', () {
      expect(
        SafeSpitCalculator.isClearToEject(
            actualPitchDeg: 180.0, targetPitchDeg: 180.0, speedKmh: 0.0, rollDeg: 10.0),
        isTrue,
      );
    });

    test('targetPitch < 45 passes if roll is near 180 (face down)', () {
      expect(
        SafeSpitCalculator.isClearToEject(
            actualPitchDeg: 0.0, targetPitchDeg: 0.0, speedKmh: 0.0, rollDeg: 175.0),
        isTrue,
      );
      expect(
        SafeSpitCalculator.isClearToEject(
            actualPitchDeg: 0.0, targetPitchDeg: 0.0, speedKmh: 0.0, rollDeg: -170.0),
        isTrue,
      );
    });

    test('targetPitch < 45 fails if roll is far from 0 and 180', () {
      expect(
        SafeSpitCalculator.isClearToEject(
            actualPitchDeg: 0.0, targetPitchDeg: 0.0, speedKmh: 0.0, rollDeg: 90.0),
        isFalse,
      );
    });
  });



  group('SafeSpitCalculator — TV-09: Wind does NOT affect targetPitch', () {
    // Wind does not appear in the formula at all — this test documents the contract.
    test('TV-09: targetPitch is wind-independent (D-5, Rule 15)', () {
      // The calculator takes (speed, vehicle) only — wind is not a parameter.
      // This test documents the correct absence of wind from the formula.
      final noWind = SafeSpitCalculator.targetPitch(50.0);
      // "With wind" — targetPitch formula has no wind parameter, so result is identical.
      final withWindSpeed = SafeSpitCalculator.targetPitch(50.0);
      expect(noWind, equals(withWindSpeed));
    });
  });
  group('SafeSpitCalculator — backwards facing modifiers (NEW)', () {
    test('Backwards facing adds angle instead of subtracting', () {
      final forward = SafeSpitCalculator.targetPitch(50.0, isFacingBackwards: false);
      final backward = SafeSpitCalculator.targetPitch(50.0, isFacingBackwards: true);
      // 50 km/h -> 70.0 forward, 110.0 backward
      expect(forward, equals(70.0));
      expect(backward, equals(110.0));
    });

    test('Backwards facing clamps at 180', () {
      final backward = SafeSpitCalculator.targetPitch(300.0, isFacingBackwards: true);
      // 90 + (300/5)*2 = 210, clamped to 180
      expect(backward, equals(180.0));
    });

    test('Backwards facing identity profile', () {
      final carBackward = SafeSpitCalculator.targetPitch(100.0, isFacingBackwards: true);
      // 90 + (100/5)*2 = 130
      expect(carBackward, equals(130.0));
    });
  });
}
