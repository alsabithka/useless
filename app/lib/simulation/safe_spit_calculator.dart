// safe_spit_calculator.dart — SAFE//SPIT
//
// Deterministic, pure-Dart virtual projectile calculator.
//
// This file keeps the existing public API while making the angle
// conventions and numerical behavior internally consistent.
//
// APP ANGLE CONVENTION:
//   0°   = phone/camera pointing straight up
//   90°  = phone/camera pointing at the horizon
//   180° = phone/camera pointing straight down
//
// PHYSICS ANGLE CONVENTION:
//   0°   = horizontal
//   90°  = vertically upward
//
// Conversion:
//   appPitch = 90° - physicsAngle
//
// No Flutter imports.
// Pure Dart.

import 'dart:math' as math;

class SafeSpitCalculator {
  // ── PHYSICS CONSTANTS ─────────────────────────────────────────────────────

  static const double g = 9.81;
  static const double spitSpeedMs = 8.0;

  // ── APP ANGLE CONVENTION ──────────────────────────────────────────────────

  static const double minAngle = 0.0;
  static const double maxAngle = 180.0;

  // ── LOCK TOLERANCE ────────────────────────────────────────────────────────

  static const double lockToleranceDeg = 5.0;
  static const double relaxedToleranceDeg = 15.0;

  // ──────────────────────────────────────────────────────────────────────────
  // Utility
  // ──────────────────────────────────────────────────────────────────────────

  static double _clampAngle(double angle) {
    return angle.clamp(minAngle, maxAngle);
  }

  static double _normalize180(double angle) {
    var result = angle % 360.0;

    if (result < 0.0) {
      result += 360.0;
    }

    if (result > 180.0) {
      result = 360.0 - result;
    }

    return result;
  }

  // ──────────────────────────────────────────────────────────────────────────
  /// Calculates the virtual projectile angle from vehicle/reference speed.
  ///
  /// The returned value uses the app convention:
  ///
  ///   0°  = up
  ///   90° = horizon
  ///   180° = down
  ///
  /// The calculation is deterministic and never modifies sensor data.
  static double targetPitch(
    double speedKmh, {
    bool isFacingBackwards = false,
  }) {
    final double speed = math.max(0.0, speedKmh);
    final double vehicleMs = speed / 3.6;

    // Stationary reference case.
    //
    // There is no horizontal displacement in this simplified model,
    // so the virtual high trajectory is vertical.
    if (vehicleMs <= 1e-9) {
      return isFacingBackwards ? 180.0 : 0.0;
    }

    final double v = spitSpeedMs;
    final double v2 = v * v;

    // Time scale used by the existing model.
    final double tReference = v / g;

    // Horizontal displacement of the moving reference.
    final double x = vehicleMs * tReference;

    // Same launch/target height.
    const double y = 0.0;

    // ── BALLISTIC SOLUTION ──────────────────────────────────────────────────
    //
    // tan(theta) =
    //   (v² ± sqrt(v⁴ - g(gx² + 2yv²))) / (gx)
    //
    // We use the shallower mathematical root when it exists.

    final double discriminant =
        (v2 * v2) - g * (g * x * x + 2.0 * y * v2);

    double physicsAngleDeg;

    if (x <= 1e-9) {
      physicsAngleDeg = 90.0;
    } else if (discriminant <= 0.0) {
      // Boundary of the reachable region.
      physicsAngleDeg = 45.0;
    } else {
      final double sqrtDisc = math.sqrt(discriminant);

      final double numerator = v2 - sqrtDisc;
      final double denominator = g * x;

      final double thetaRad = math.atan(numerator / denominator);
      physicsAngleDeg = thetaRad * 180.0 / math.pi;
    }

    physicsAngleDeg = physicsAngleDeg.clamp(0.0, 90.0);

    // Convert physics convention:
    //
    // physics 90° = straight up
    // app       0° = straight up
    //
    final double appPitch = 90.0 - physicsAngleDeg;

    if (isFacingBackwards) {
      // Mirror around the horizon in the app coordinate system.
      return _clampAngle(180.0 - appPitch);
    }

    return _clampAngle(appPitch);
  }

  // ──────────────────────────────────────────────────────────────────────────
  /// Determines whether the current device pitch satisfies the target.
  ///
  /// `actualPitchDeg` MUST already be expressed in the same app convention:
  ///
  ///   0°   = up
  ///   90°  = horizon
  ///   180° = down
  ///
  /// This method does not alter the sensor reading.
  static bool isClearToEject({
    required double actualPitchDeg,
    required double targetPitchDeg,
    required double speedKmh,
    double rollDeg = 0.0,
    bool isFacingBackwards = false,
  }) {
    final double actual = _normalize180(actualPitchDeg);
    final double target = _clampAngle(targetPitchDeg);

    final double delta = (actual - target).abs();

    final bool useRelaxedTolerance =
        isFacingBackwards || speedKmh < 2.0;

    final double tolerance = useRelaxedTolerance
        ? relaxedToleranceDeg
        : lockToleranceDeg;

    final bool pitchLocked = delta <= tolerance;

    if (!pitchLocked) {
      return false;
    }

    // For near-vertical orientations, require the device to remain
    // approximately upright.
    if (target < 45.0 || target > 135.0) {
      final double normalizedRoll = ((rollDeg + 180.0) % 360.0) - 180.0;

      final double distanceTo0 = normalizedRoll.abs();
      final double distanceTo180 =
          (normalizedRoll.abs() - 180.0).abs();

      final bool rollValid =
          distanceTo0 <= 15.0 || distanceTo180 <= 15.0;

      if (!rollValid) {
        return false;
      }
    }

    return true;
  }

  // ──────────────────────────────────────────────────────────────────────────
  /// Absolute pitch difference.
  ///
  /// Both values must use the same app-pitch convention.
  static double deltaDeg({
    required double actualPitchDeg,
    required double targetPitchDeg,
  }) {
    final double actual = _normalize180(actualPitchDeg);
    final double target = _clampAngle(targetPitchDeg);

    return (actual - target).abs();
  }
}