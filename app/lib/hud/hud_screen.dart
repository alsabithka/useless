// hud_screen.dart — SAFE//SPIT
//
// PROVEN: HUD screen with camera passthrough + reticle overlay.
// PLANNED: Extended with NormalizedTelemetry stream, Demo Mode indicator,
//          trajectory line, telemetry bars, diagnostics.
//
// RULE 3: This screen reads NormalizedTelemetry and SimulationResult only.
//         No raw geolocator/sensors_plus imports.
// RULE 5: Demo Mode is always clearly labeled (Rule 8).
// RULE 8: "DEMO MODE" text is always visible when isDemoMode is true.

import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_state.dart';
import '../game/spit_lock_controller.dart';
import '../sensors/normalized_telemetry.dart';
import '../simulation/scenario.dart';
import '../simulation/trajectory_model.dart';
import '../services/audio_service.dart';
import '../services/haptic_service.dart';
import '../challenge/challenge_controller.dart';
import '../challenge/challenge_state.dart';
import 'missile_lock_reticle_painter.dart';
import 'static_head_guide_painter.dart';

/// The main HUD screen. Displays camera passthrough with tactical reticle overlay.
/// Listens to [GameState] via Provider.
class HudScreen extends StatefulWidget {
  const HudScreen({super.key});

  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen>
    with TickerProviderStateMixin {
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;
  CameraController? _cameraController;
  bool _cameraReady = false;
  bool _cameraError = false;

  late AnimationController _pulseController;
  late StreamSubscription<LockTransition> _lockTransitionSub;

  final AudioService _audio = AudioService();
  final HapticService _haptic = HapticService();
  final ChallengeController _challengeController = ChallengeController();
  ChallengeState _challengeState = ChallengeState.ready;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();

    _initCamera();
    _audio.initialize();
    _setupLockTransitionListener();
  }

  void _setupLockTransitionListener() {
    final gameState = context.read<GameState>();
    _lockTransitionSub = gameState.lockController.onTransition.listen(
      (transition) async {
        if (transition.isLockAcquired) {
          await _audio.playLockTone();
          await _haptic.onLockAcquired();
        } else if (transition.isLockLost) {
          await _haptic.onLockLost();
        }
      },
    );
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _cameraError = true);
        return;
      }
      await _setCamera(_selectedCameraIndex);
    } catch (e) {
      debugPrint('[HudScreen] Camera init error: $e');
      if (mounted) setState(() => _cameraError = true);
    }
  }

  Future<void> _setCamera(int index) async {
    await _cameraController?.dispose();
    _cameraController = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _cameraReady = true;
          _selectedCameraIndex = index;
        });
      }
    } catch (e) {
      debugPrint('[HudScreen] Camera error: $e');
      if (mounted) setState(() => _cameraError = true);
    }
  }

  void _toggleCamera() {
    if (_cameras.isEmpty) return;
    _setCamera((_selectedCameraIndex + 1) % _cameras.length);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _pulseController.dispose();
    _lockTransitionSub.cancel();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<GameState>(
        builder: (context, gameState, _) {
          final telemetry = gameState.telemetry;
          final simResult = gameState.simResult;
          final lockState = gameState.lockController.state;
          final lockQuality = gameState.lockController.lockQuality;
          List<TrajectoryPoint>? trajectory;
          if (simResult != null) {
            trajectory = computeTrajectoryArc(
              pitchDeg: telemetry.pitchDeg,
              speedKmh: telemetry.speedKmh,
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              _buildCameraLayer(),
              Container(color: kCameraTint.withValues(alpha: 0.05)),
              CustomPaint(
                painter: StaticHeadGuidePainter(color: kTacticalGreen),
                size: MediaQuery.of(context).size,
              ),
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, _) => CustomPaint(
                  painter: MissileLockReticlePainter(
                    targetPitchDeg: simResult?.targetPitchDeg ?? 0.0,
                    actualPitchDeg: telemetry.pitchDeg,
                    speedKmh: telemetry.speedKmh,
                    lockState: lockState,
                    lockQuality: lockQuality,
                    deltaDeg: simResult?.deltaDeg ?? 0.0,
                    rollDeg: telemetry.rollDeg,
                    isDemoMode: telemetry.isDemoMode,
                    trajectoryPoints: trajectory,
                    deviationM: simResult?.deviationM,
                    animValue: _pulseController.value,
                  ),
                  size: MediaQuery.of(context).size,
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopBar(simResult, telemetry, lockState),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(telemetry, lockState, gameState),
              ),
              if (telemetry.isDemoMode)
                Positioned(top: 80, right: 16, child: _buildDemoModeIndicator()),
              if (gameState.isFacingBackwards)
                Positioned(
                  top: telemetry.isDemoMode ? 120 : 80,
                  right: 16,
                  child: _buildRearFacingIndicator(),
                ),
              Positioned(
                top: telemetry.isDemoMode
                    ? (gameState.isFacingBackwards ? 160 : 120)
                    : (gameState.isFacingBackwards ? 120 : 80),
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.flip_camera_ios, color: kTacticalGreen),
                  onPressed: _toggleCamera,
                  tooltip: 'Switch Camera',
                ),
              ),
              if (lockState == SpitLockState.locked &&
                  gameState.phase != GamePhase.launched &&
                  gameState.phase != GamePhase.scored &&
                  !_challengeController.isRunning)
                Positioned(
                  bottom: 80,
                  left: 0,
                  right: 0,
                  child: _buildLaunchButton(gameState),
                ),
              if (_challengeController.isRunning)
                Center(
                  child: Text(
                    _challengeLabel(_challengeState),
                    style: const TextStyle(
                      color: kTacticalGreen,
                      fontFamily: 'SpaceMono',
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── RULE 8: Demo Mode indicator ──────────────────────────────────────────
  // ── PROVEN: Camera passthrough build ─────────────────────────────────────

  Widget _buildCameraLayer() {
    if (_cameraReady && _cameraController != null) {
      return CameraPreview(_cameraController!);
    }
    if (_cameraError) {
      // PROVEN fallback: black background with camera error indicator
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off, color: kTacticalGreen.withValues(alpha: 0.4), size: 48),
              const SizedBox(height: 8),
              Text(
                'OPTICAL SENSOR OFFLINE',
                style: TextStyle(
                  color: kTacticalGreen.withValues(alpha: 0.4),
                  fontFamily: 'SpaceMono',
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Loading state
    return Container(color: Colors.black);
  }

  // ── PROVEN: Top diagnostics bar ──────────────────────────────────────────

  Widget _buildTopBar(
      SimulationResult? simResult, NormalizedTelemetry telemetry, SpitLockState lockState) {
    final double tgt = simResult?.targetPitchDeg ?? 45.0;
    final double act = telemetry.pitchDeg;
    final double delta = simResult?.deltaDeg ?? (act - tgt).abs();

    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      padding: const EdgeInsets.fromLTRB(12, 36, 12, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: _hudText('SPIT v1.0')),
          Flexible(child: _hudText('TGT ${tgt.toStringAsFixed(1)}°')),
          Flexible(child: _hudText('ACT ${act.toStringAsFixed(1)}°')),
          Flexible(child: _hudText('Δ ${delta.toStringAsFixed(1)}°')),
        ],
      ),
    );
  }

  // ── PROVEN: Bottom telemetry bar ──────────────────────────────────────────

  Widget _buildBottomBar(
      NormalizedTelemetry telemetry, SpitLockState lockState, GameState gameState) {
    final String lockText = lockState == SpitLockState.locked
        ? '■ SPIT LOCK'
        : lockState == SpitLockState.locking
            ? '◈ ACQUIRING'
            : '○ SEARCHING';

    final Color lockColor = lockState == SpitLockState.locked
        ? kTacticalGreen
        : lockState == SpitLockState.locking
            ? kTacticalGreen.withValues(alpha: 0.7)
            : kTacticalGreen.withValues(alpha: 0.4);

    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: _hudText('${telemetry.speedKmh.toStringAsFixed(0)} KM/H')),
          Flexible(
            child: _hudText(
              '${_cardinal(telemetry.headingDeg ?? telemetry.anchorCompassHeading ?? 0.0)} ${(telemetry.headingDeg ?? telemetry.anchorCompassHeading ?? 0.0).toStringAsFixed(0)}°',
            ),
          ),
          Flexible(
            child: Text(
              lockText,
              style: TextStyle(
                color: lockColor,
                fontFamily: 'SpaceMono',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── RULE 8: Demo Mode indicator ──────────────────────────────────────────

  Widget _buildDemoModeIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: kTacticalGreen.withValues(alpha: 0.6)),
        color: Colors.black.withValues(alpha: 0.5),
      ),
      child: Text(
        'DEMO MODE',
        style: TextStyle(
          color: kTacticalGreen,
          fontFamily: 'SpaceMono',
          fontSize: 10,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _buildRearFacingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.amber.withValues(alpha: 0.8)),
        color: Colors.black.withValues(alpha: 0.7),
      ),
      child: const Text(
        'REAR-FACING',
        style: TextStyle(
          color: Colors.amber,
          fontFamily: 'SpaceMono',
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
        ),
      ),
    );
  }

  // ── Launch button ─────────────────────────────────────────────────────────

  Widget _buildLaunchButton(GameState gameState) {
    return Center(
      child: GestureDetector(
        onTap: () => _startChallenge(gameState),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: kTacticalGreen, width: 2),
            color: Colors.black.withValues(alpha: 0.7),
          ),
          child: const Text(
            'START SPIT',
            style: TextStyle(
              color: kTacticalGreen,
              fontFamily: 'SpaceMono',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startChallenge(GameState gameState) async {
    final result = await _challengeController.run(
      captureFrame: _captureFrame,
      onCountdownCue: _haptic.onLockLost,
      onGoCue: _haptic.onLaunch,
      onStateChanged: (state) {
        if (mounted) setState(() => _challengeState = state);
      },
    );
    if (!mounted) return;
    gameState.launch(challengeResult: result);
    setState(() => _challengeState = ChallengeState.ready);
  }

  Future<File?> _captureFrame() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      throw const CameraCaptureException('Camera is not ready');
    }
    try {
      final image = await controller.takePicture();
      return File(image.path);
    } catch (error) {
      throw CameraCaptureException('Could not capture camera frame: $error');
    }
  }

  String _challengeLabel(ChallengeState state) {
    switch (state) {
      case ChallengeState.countdown3:
        return '3';
      case ChallengeState.countdown2:
        return '2';
      case ChallengeState.countdown1:
        return '1';
      case ChallengeState.go:
        return 'GO!';
      case ChallengeState.capturing:
        return 'CAPTURE';
      case ChallengeState.analyzing:
        return 'ANALYZING';
      default:
        return '';
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _cardinal(double deg) {
    final d = ((deg % 360) + 360) % 360;
    if (d >= 337.5 || d < 22.5) return 'N';
    if (d < 67.5) return 'NE';
    if (d < 112.5) return 'E';
    if (d < 157.5) return 'SE';
    if (d < 202.5) return 'S';
    if (d < 247.5) return 'SW';
    if (d < 292.5) return 'W';
    return 'NW';
  }

  Widget _hudText(String text) => Text(
        text,
        style: const TextStyle(
          color: kTacticalGreen,
          fontFamily: 'SpaceMono',
          fontSize: 11,
          letterSpacing: 1.0,
        ),
      );
}
