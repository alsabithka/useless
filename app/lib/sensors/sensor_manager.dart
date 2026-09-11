// sensor_manager.dart — SAFE//SPIT
//
// PROVEN pipeline adapted to emit Stream<NormalizedTelemetry> (Phase 2).
// Preserves proven:
//  - GPS speed pipeline (v_ms * 3.6, onError/cancelOnError/onDone)
//  - Gyroscope pitch integration (dt, clamp [0°, 180°])
//  - Camera passthrough pattern
// Adds:
//  - NormalizedTelemetry as the output type
//  - SensorHealth tracking
//  - Explicit Demo Mode bypass
//
// RULE 3: Only this file may import geolocator, sensors_plus, camera.
//         All other app code consumes NormalizedTelemetry only.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';

import 'normalized_telemetry.dart';

/// The real-sensor implementation of the telemetry pipeline.
///
/// Emits a continuous [Stream<NormalizedTelemetry>] by combining:
/// 1. GPS speed (PROVEN pipeline)
/// 2. Gyroscope pitch integration (PROVEN pipeline)
///
/// Camera is handled separately by [HudScreen] via the camera package
/// (because CameraPreview must live in the widget tree).
class SensorManager {
  // ── Internal state ────────────────────────────────────────────────────────
  double _speedKmh = 0.0;
  double _pitchDeg = 45.0; // SENSOR_SPEC.md: default to 45° (optimal) not 0°
  double _rollDeg = 0.0;
  DateTime? _lastGyroTime;
  double? _gpsHeading;
  double? _compassHeading;
  double? _anchorCompassHeading;
  bool _isFacingBackwards = false;

  SensorHealthStatus _gpsHealth = SensorHealthStatus.permissionDenied;
  SensorHealthStatus _gyroHealth = SensorHealthStatus.permissionDenied;

  StreamSubscription<Position>? _gpsSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;

  final StreamController<NormalizedTelemetry> _controller =
      StreamController<NormalizedTelemetry>.broadcast();

  /// The normalized telemetry stream. Subscribe to receive updates.
  Stream<NormalizedTelemetry> get stream => _controller.stream;

  // ── Public lifecycle ──────────────────────────────────────────────────────

  Future<void> start() async {
    await _startGps();
    await _startAccel();
    _startCompass();
  }

  void dispose() {
    _gpsSubscription?.cancel();
    _orientationSubscription?.cancel();
    _compassSubscription?.cancel();
    _controller.close();
  }

  // ── PROVEN: GPS pipeline ──────────────────────────────────────────────────

  Future<void> _startGps() async {
    _gpsHealth = SensorHealthStatus.degraded; // assume degraded until first fix
    _emit();

    try {
      const LocationSettings settings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );

      _gpsSubscription = Geolocator.getPositionStream(locationSettings: settings)
          .listen(
        (Position position) {
          // PROVEN: v_ms * 3.6 → km/h
          _speedKmh = (position.speed * 3.6).clamp(0.0, double.infinity);
          if (_speedKmh > 5.0) {
            _gpsHeading = position.heading;
            _anchorCompassHeading = null; // Clear anchor when moving
          } else {
            // If stopped, capture an anchor
            if (_anchorCompassHeading == null && _compassHeading != null) {
              _anchorCompassHeading = _compassHeading;
            }
          }
          _checkFacingBackwards();
          _gpsHealth = SensorHealthStatus.ok;
          _emit();
        },
        onError: (Object error) {
          // PROVEN: explicit onError handler — GPS failure does not crash
          _gpsHealth = SensorHealthStatus.degraded;
          _emit();
        },
        cancelOnError: false, // PROVEN: stream continues after errors
        onDone: () {
          _gpsHealth = SensorHealthStatus.unavailable;
          _emit();
        },
      );
    } catch (e) {
      _gpsHealth = SensorHealthStatus.unavailable;
      _emit();
    }
  }

  // ── STABLE: Absolute orientation pipeline (hardware rotation vector) ──────
  //
  // Uses sensors_plus absoluteOrientationStream which fuses accel + gyro +
  // magnetometer at the OS level (Android TYPE_ROTATION_VECTOR).
  // This gives drift-free, jitter-free absolute pitch with no manual atan2.
  //
  // Convention after conversion:
  //   0°   = camera pointing at sky   (phone face-down)
  //   90°  = camera at horizon        (phone upright portrait)
  //   180° = camera pointing at ground (phone face-up)
  //
  // Additionally: if pitch lands within 5° of either flat extreme (0° or 180°)
  // it is snapped to 90° so the HUD always guides the user toward upward aim.

  bool _pitchInitialised = false;
  StreamSubscription<AbsoluteOrientationEvent>? _orientationSubscription;

  Future<void> _startAccel() async {
    _gyroHealth = SensorHealthStatus.degraded;
    _emit();

    try {
      _orientationSubscription = absoluteOrientationEventStream().listen(
        (AbsoluteOrientationEvent event) {
          // event.pitch: radians, range [-π/2, +π/2]
          //   +π/2 ≈ +90°  = phone face-up (screen towards sky)
          //   0            = phone upright portrait
          //   -π/2 ≈ -90°  = phone face-down (screen towards ground)
          //
          // Convert to app convention (0=camera-at-sky, 90=horizon, 180=ground):
          //   raw_deg = event.pitch * 180/π          → [-90°, +90°]
          //   app_pitch = 90° - raw_deg              → [0°, 180°]
          //     face-up   (+90°) → 90-90 = 0°   (camera at sky)   ✓
          //     portrait  (  0°) → 90-0  = 90°  (camera at horizon) ✓
          //     face-down (-90°) → 90+90 = 180° (camera at ground) ✓
          final double rawDeg  = event.pitch * (180.0 / math.pi);
          double newPitch = (90.0 - rawDeg).clamp(0.0, 180.0);

          // ── Flat-position snap ─────────────────────────────────────────
          // When phone is nearly flat (≤5° or ≥175°), the direction of "up"
          // along the phone's face is ambiguous. Snap to 90° (portrait / horizon)
          // so the HUD always guides the user to aim upward rather than locking
          // on an indeterminate flat position.
          if (newPitch <= 5.0 || newPitch >= 175.0) {
            newPitch = 90.0;
          }

          // ── Initialise from first reading instead of defaulting to 45° ──
          if (!_pitchInitialised) {
            _pitchDeg = newPitch;
            _pitchInitialised = true;
          } else {
            // ── Deadband: ignore sub-0.5° jitter ──────────────────────────
            if ((newPitch - _pitchDeg).abs() >= 0.5) {
              _pitchDeg = newPitch;
            }
          }

          _gyroHealth = SensorHealthStatus.ok;
          _emit();
        },
        onError: (Object error) {
          _gyroHealth = SensorHealthStatus.degraded;
          _emit();
        },
        cancelOnError: false,
        onDone: () {
          _gyroHealth = SensorHealthStatus.unavailable;
          _emit();
        },
      );
    } catch (e) {
      _gyroHealth = SensorHealthStatus.unavailable;
      _emit();
    }
  }

  // ── Auto-detect Facing Backwards ──────────────────────────────────────────

  void _startCompass() {
    try {
      _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
        if (event.heading != null) {
          _compassHeading = event.heading;
          _checkFacingBackwards();
          _emit();
        }
      }, onError: (e) {
        // compass missing/failed
      });
    } catch (e) {
      // ignore
    }
  }

  void _checkFacingBackwards() {
    if (_gpsHeading != null && _compassHeading != null && _speedKmh > 5.0) {
      // only check when moving significantly
      double diff = (_gpsHeading! - _compassHeading!).abs() % 360.0;
      if (diff > 180.0) diff = 360.0 - diff;
      
      // If difference between vehicle direction and phone facing is > 90 deg
      _isFacingBackwards = diff > 90.0;
    }
  }

  // ── Telemetry emission ────────────────────────────────────────────────────
  //
  // COORDINATE SYSTEM — VERIFIED FROM DEBUG LOGS
  // ─────────────────────────────────────────────────────────────────────────
  // The accelerometer formula:
  //   atan2(Z, Y)*180/π + 90
  //   →  0°   = phone face-DOWN  (back camera pointing UP / at sky)  ← target=0°
  //   → 90°   = phone upright portrait (back camera at horizon)       ← target=90°
  //   → 180°  = phone face-UP   (back camera pointing at ground)
  //
  // Physics engine uses same convention: 0=camera-at-sky, 90=horizontal.
  // NO CONVERSION NEEDED — pass raw pitch directly.
  // ─────────────────────────────────────────────────────────────────────────

  void _emit() {
    if (_controller.isClosed) return;

    // ── DEBUG: verify pitch vs target ───────────────────────────────────
    // Remove once lock is confirmed working.
    debugPrint('[PITCH] raw=${_pitchDeg.toStringAsFixed(1)}°');

    _controller.add(NormalizedTelemetry(
      speedKmh: _speedKmh,
      pitchDeg: _pitchDeg,            // raw = physics convention already
      rollDeg: _rollDeg,
      yawDeg: _compassHeading ?? 0.0,
      headingDeg: _gpsHeading,
      anchorCompassHeading: _anchorCompassHeading,
      timestamp: DateTime.now(),
      sensorHealth: SensorHealth(
        gps: _gpsHealth,
        gyro: _gyroHealth,
      ),
      isDemoMode: false,
      isFacingBackwards: _isFacingBackwards,
    ));
  }
}


