import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../dev_tools.dart';

import '../alerts/sound_alert_service.dart';
import '../distraction_detection/distraction_analyzer.dart';
import '../distraction_detection/driver_state.dart';
import '../distraction_detection/face_detector_service.dart';
import '../distraction_detection/face_observation.dart';
import '../distraction_detection/frame_source.dart';
import '../distraction_detection/glance_sensitivity.dart';
import '../driving_record/driving_record.dart';
import '../evidence/drowsiness_evidence_store.dart';
import '../evidence/frame_jpeg_encoder.dart';
import '../motion/gps_accuracy.dart';
import '../motion/speed_service.dart';
import '../motion/automatic_driving_mode_detector.dart';
import '../motion/automatic_driving_mode_store.dart';
import '../motion/vehicle_activity_service.dart';
import '../motion/vehicle_motion_detector.dart';
import '../mount_quality/mount_quality_monitor.dart';
import '../mount_quality/shake_detector.dart';
import '../settings/drive_settings_screen.dart';
import '../settings/drive_settings_store.dart';
import 'drive_session_controller.dart';

/// The live driving view: camera preview, current driver state, mount-quality
/// warnings, and the controls for calibrating and starting a drive.
///
/// This widget owns the camera and the per-frame loop. The judging itself lives
/// in [DriveSessionController] and the classes under `distraction_detection/`,
/// which are plain Dart so they can be tested without a camera.
class DriveSessionScreen extends StatefulWidget {
  const DriveSessionScreen({
    super.key,
    required this.record,
    required this.evidenceStore,
  });

  /// Shared driving record this screen feeds from live detection.
  final DrivingRecord record;

  /// Where drowsiness photos are saved when that setting is on.
  final DrowsinessEvidenceStore evidenceStore;

  @override
  State<DriveSessionScreen> createState() => _DriveSessionScreenState();
}

enum _ChangedDriveSetting {
  yawn,
  drowsinessAlarm,
  sensitivity,
  evidencePhotos,
  evidenceAutoDelete,
  gpsAccuracy,
}

class _DriveSessionScreenState extends State<DriveSessionScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _displayRotationChannel =
      MethodChannel('driver_focus/display_rotation');

  late final DriveSessionController _controller;
  late final SoundAlertService _alertService;
  late final FaceDetectorService _faceDetectorService;
  CameraController? _cameraController;
  FaceObservation? _lastObservation;
  DriverState _state = DriverState.unknown;
  String? _cameraError;
  String? _detectionError;
  DateTime? _lastCameraFrameProcessedAt;
  DateTime? _phoneUseStartedAt;
  bool _phoneUseStartedWhileMoving = false;
  bool _isCameraFrameProcessing = false;
  bool _isCameraLoading = true;
  bool _isInitializingCamera = false;
  bool _isDriving = false;

  /// Forces the motion gate on so yaw detection can be exercised at a desk. Can
  /// be enabled by the developer-tools switch or initialized by the
  /// [kSimulateMoving] build flag.
  bool _simulateMoving = kSimulateMoving;
  DeviceOrientation _lastPortraitOrientation = DeviceOrientation.portraitUp;
  DeviceOrientation _lastLandscapeOrientation = DeviceOrientation.landscapeLeft;
  DeviceOrientation? _displayOrientation;
  final MountQualityMonitor _mountMonitor = MountQualityMonitor();
  final ShakeDetector _shakeDetector = ShakeDetector();
  final VehicleMotionDetector _motionDetector = VehicleMotionDetector();
  final SpeedService _speedService = SpeedService();
  final VehicleActivityService _vehicleActivityService =
      VehicleActivityService();
  final AutomaticDrivingModeStore _automaticDrivingModeStore =
      AutomaticDrivingModeStore();
  final DriveSettingsStore _driveSettingsStore = DriveSettingsStore();
  late final AutomaticDrivingModeDetector _automaticDrivingModeDetector;
  Future<void> _speedServiceOperations = Future<void>.value();
  Future<void> _vehicleActivityOperations = Future<void>.value();
  Future<void> _screenWakeLockOperations = Future<void>.value();
  bool _isAppResumed = true;
  bool _automaticDrivingModeEnabled = true;
  bool _automaticDrivingModeChanged = false;
  bool _evidencePhotosEnabled = false;
  final Set<_ChangedDriveSetting> _changedDriveSettings = {};
  bool _isCapturingEvidence = false;
  MountIssue _mountIssue = MountIssue.none;

  bool get _isVehicleMoving => _simulateMoving || _motionDetector.isMoving;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _alertService = SoundAlertService();
    _controller = DriveSessionController(
      analyzer: const DistractionAnalyzer(),
      alertService: _alertService,
    );
    _automaticDrivingModeDetector = AutomaticDrivingModeDetector(
      isDriving: () => _isDriving,
      onDrivingModeChanged: _applyAutomaticDrivingMode,
    );
    _faceDetectorService = MlKitFaceDetectorService();
    _shakeDetector.start();
    unawaited(_loadAutomaticDrivingModePreference());
    unawaited(_loadDriveSettings());
    if (Platform.isAndroid) {
      _displayRotationChannel.setMethodCallHandler(_handleDisplayRotationCall);
      unawaited(_loadDisplayOrientation());
    }
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid) {
      _displayRotationChannel.setMethodCallHandler(null);
    }
    unawaited(_cameraController?.stopImageStream() ?? Future<void>.value());
    _cameraController?.dispose();
    unawaited(_faceDetectorService.close());
    unawaited(_alertService.dispose());
    unawaited(_shakeDetector.dispose());
    _automaticDrivingModeDetector.dispose();
    widget.record.endSession(at: DateTime.now());
    _isAppResumed = false;
    _scheduleScreenWakeLockUpdate();
    _scheduleSpeedServiceUpdate();
    unawaited(_scheduleVehicleActivityUpdate());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isAppResumed = true;
      _scheduleScreenWakeLockUpdate();
      _scheduleSpeedServiceUpdate();
      unawaited(_scheduleVehicleActivityUpdate());
      final phoneUseStartedAt = _phoneUseStartedAt;
      _phoneUseStartedAt = null;
      if (phoneUseStartedAt != null &&
          _isDriving &&
          _phoneUseStartedWhileMoving) {
        widget.record.recordPhoneUse(
          DateTime.now().difference(phoneUseStartedAt),
        );
      }
      _phoneUseStartedWhileMoving = false;
      _initializeCamera();
      return;
    }

    // Any non-resumed state means the app is leaving the foreground. Release
    // the camera so the plugin does not crash, and if the driver switched away
    // to use the phone while driving, count that as a distraction.
    _isAppResumed = false;
    _scheduleScreenWakeLockUpdate();
    _scheduleSpeedServiceUpdate();
    unawaited(_scheduleVehicleActivityUpdate());
    unawaited(_releaseCamera());

    if (state == AppLifecycleState.detached) {
      widget.record.endSession(at: DateTime.now());
      return;
    }

    if (state == AppLifecycleState.paused && _isDriving) {
      _phoneUseStartedAt = DateTime.now();
      _phoneUseStartedWhileMoving = _isVehicleMoving;
      unawaited(_registerPhoneInteraction());
    }
  }

  Future<void> _releaseCamera() async {
    final controller = _cameraController;
    if (controller == null) {
      return;
    }

    _cameraController = null;
    try {
      await controller.stopImageStream();
    } catch (_) {
      // The stream may not be running; ignore.
    }
    await controller.dispose();
    if (mounted) {
      setState(() => _isCameraLoading = true);
    }
  }

  Future<void> _registerPhoneInteraction() async {
    final state = await _controller.registerPhoneInteraction(
      isDriving: _isDriving,
    );
    if (!mounted) {
      return;
    }
    setState(() => _state = state);
  }

  void _calibrate() {
    final observation = _lastObservation;
    final yaw = observation?.headYawDegrees;
    final pitch = observation?.headPitchDegrees;
    final messenger = ScaffoldMessenger.of(context);

    if (observation == null ||
        !observation.faceVisible ||
        yaw == null ||
        pitch == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Point your face at the road first, then calibrate.'),
        ),
      );
      return;
    }

    _controller.calibrate(
      yawDegrees: yaw,
      pitchDegrees: pitch,
      rollDegrees: observation.headRollDegrees ?? 0,
      mouthOpenRatio: observation.mouthOpenRatio,
      leftEyeOpen: observation.leftEyeOpenProbability,
      rightEyeOpen: observation.rightEyeOpenProbability,
    );
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Calibrated road, resting mouth, and eye openness.'),
      ),
    );
  }

  /// Copies a camera frame into plain data that can cross an isolate boundary.
  ///
  /// [CameraImage] is backed by native memory and can't be sent to a worker
  /// isolate, so the bytes are copied here and encoded elsewhere.
  RawFrame? _rawFrameFrom(CameraImage image, DeviceOrientation orientation) {
    final format = switch (image.format.group) {
      ImageFormatGroup.bgra8888 => FramePixelFormat.bgra8888,
      ImageFormatGroup.nv21 => FramePixelFormat.nv21,
      ImageFormatGroup.yuv420 => FramePixelFormat.yuv420,
      _ => null,
    };
    if (format == null) {
      return null;
    }
    return RawFrame(
      format: format,
      width: image.width,
      height: image.height,
      planes: [
        for (final p in image.planes) Uint8List.fromList(p.bytes),
      ],
      bytesPerRow: [for (final p in image.planes) p.bytesPerRow],
      pixelStrides: [for (final p in image.planes) p.bytesPerPixel ?? 1],
      // iOS gives a pre-rotated buffer; Android does not.
      quarterTurns: Platform.isAndroid ? _quarterTurnsFor(orientation) : 0,
    );
  }

  static int _quarterTurnsFor(DeviceOrientation orientation) {
    return switch (orientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeRight => 1,
      DeviceOrientation.portraitDown => 2,
      DeviceOrientation.landscapeLeft => 3,
    };
  }

  /// Saves a photo of the driver from the exact frame drowsiness was judged on.
  ///
  /// Not `takePicture()` on purpose: that re-drives the camera, which costs
  /// close to a second, long enough for the driver's eyes to reopen, so the
  /// photo would miss the moment it was supposed to prove, and on the front
  /// camera it fires the screen as a flash. Encoding the frame already analyzed
  /// has neither problem.
  ///
  /// Best-effort: a failed photo must never disturb detection, so errors are
  /// swallowed. The guard keeps overlapping captures from piling up.
  Future<void> _captureEvidence(RawFrame frame) async {
    if (_isCapturingEvidence) {
      return;
    }
    _isCapturingEvidence = true;
    final capturedAt = DateTime.now();
    try {
      final jpeg = await compute(encodeFrameToJpeg, frame);
      if (jpeg != null) {
        await widget.evidenceStore.saveBytes(jpeg, capturedAt);
      }
    } catch (_) {
      // Nothing to do, the alarm and warning still fired, which is the part
      // that matters.
    } finally {
      _isCapturingEvidence = false;
    }
  }

  void _onGpsAccuracyChanged(GpsAccuracyMode mode) {
    _changedDriveSettings.add(_ChangedDriveSetting.gpsAccuracy);
    unawaited(_driveSettingsStore.saveGpsAccuracy(mode));
    setState(() {});
    // Drop the last fix straight away rather than letting it age out, so
    // switching GPS off hands over to the accelerometer immediately.
    _motionDetector.reset();
    _scheduleSpeedServiceUpdate(accuracy: mode);
  }

  Future<void> _loadDriveSettings() async {
    final settings = await _driveSettingsStore.load();
    if (!mounted) {
      return;
    }
    if (!_changedDriveSettings.contains(_ChangedDriveSetting.yawn)) {
      _controller.yawnDetectionEnabled = settings.yawnEnabled;
    }
    if (!_changedDriveSettings.contains(_ChangedDriveSetting.sensitivity)) {
      _controller.sensitivity = settings.sensitivity;
    }
    if (!_changedDriveSettings.contains(_ChangedDriveSetting.drowsinessAlarm)) {
      _alertService.drowsinessAlarmEnabled = settings.drowsinessAlarmEnabled;
    }
    if (!_changedDriveSettings
        .contains(_ChangedDriveSetting.evidenceAutoDelete)) {
      widget.evidenceStore.autoDeleteEnabled =
          settings.evidenceAutoDeleteEnabled;
    }
    if (!_changedDriveSettings.contains(_ChangedDriveSetting.gpsAccuracy)) {
      await _speedService.setAccuracy(settings.gpsAccuracy);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      if (!_changedDriveSettings
          .contains(_ChangedDriveSetting.evidencePhotos)) {
        _evidencePhotosEnabled = settings.evidencePhotosEnabled;
      }
    });
    _scheduleSpeedServiceUpdate();
  }

  void _setYawnEnabled(bool value) {
    _changedDriveSettings.add(_ChangedDriveSetting.yawn);
    setState(() => _controller.yawnDetectionEnabled = value);
    unawaited(_driveSettingsStore.saveYawnEnabled(value));
  }

  void _setDrowsinessAlarmEnabled(bool value) {
    _changedDriveSettings.add(_ChangedDriveSetting.drowsinessAlarm);
    setState(() => _alertService.drowsinessAlarmEnabled = value);
    unawaited(_driveSettingsStore.saveDrowsinessAlarmEnabled(value));
  }

  void _setSensitivity(GlanceSensitivity value) {
    _changedDriveSettings.add(_ChangedDriveSetting.sensitivity);
    setState(() => _controller.sensitivity = value);
    unawaited(_driveSettingsStore.saveSensitivity(value));
  }

  void _setEvidencePhotosEnabled(bool value) {
    _changedDriveSettings.add(_ChangedDriveSetting.evidencePhotos);
    setState(() => _evidencePhotosEnabled = value);
    unawaited(_driveSettingsStore.saveEvidencePhotosEnabled(value));
  }

  void _setEvidenceAutoDeleteEnabled(bool value) {
    _changedDriveSettings.add(_ChangedDriveSetting.evidenceAutoDelete);
    setState(() => widget.evidenceStore.autoDeleteEnabled = value);
    unawaited(_driveSettingsStore.saveEvidenceAutoDeleteEnabled(value));
  }

  void _setDrivingMode(bool value) {
    _automaticDrivingModeDetector.manualDrivingModeChanged(value);
    if (!value) {
      widget.record.endSession(at: DateTime.now());
    }
    setState(() => _isDriving = value);
    _scheduleScreenWakeLockUpdate();
    _scheduleSpeedServiceUpdate();
  }

  Future<void> _loadAutomaticDrivingModePreference() async {
    final enabled = await _automaticDrivingModeStore.load();
    if (!mounted || _automaticDrivingModeChanged) {
      return;
    }
    setState(() => _automaticDrivingModeEnabled = enabled);
    unawaited(_scheduleVehicleActivityUpdate());
  }

  Future<bool> _setAutomaticDrivingModeEnabled(bool value) async {
    _automaticDrivingModeChanged = true;
    setState(() => _automaticDrivingModeEnabled = value);
    if (!value) {
      _automaticDrivingModeDetector.suspend();
    }
    await _automaticDrivingModeStore.save(value);
    await _scheduleVehicleActivityUpdate();
    return _automaticDrivingModeEnabled;
  }

  void _applyAutomaticDrivingMode(bool value) {
    if (!mounted || _isDriving == value) {
      return;
    }
    if (!value) {
      widget.record.endSession(at: DateTime.now());
    }
    setState(() => _isDriving = value);
    _scheduleScreenWakeLockUpdate();
    _scheduleSpeedServiceUpdate();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Driving mode enabled automatically.'
              : 'Driving mode disabled after leaving the vehicle.',
        ),
      ),
    );
  }

  Future<void> _scheduleVehicleActivityUpdate() {
    _vehicleActivityOperations = _vehicleActivityOperations.then((_) async {
      if (_automaticDrivingModeEnabled && _isAppResumed) {
        final started = await _vehicleActivityService.start(
          _automaticDrivingModeDetector.record,
        );
        if (!started &&
            mounted &&
            _automaticDrivingModeEnabled &&
            _isAppResumed) {
          _automaticDrivingModeChanged = true;
          setState(() => _automaticDrivingModeEnabled = false);
          _automaticDrivingModeDetector.suspend();
          unawaited(_automaticDrivingModeStore.save(false));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Automatic Driving mode needs Motion & Fitness permission.',
              ),
            ),
          );
        }
      } else {
        await _vehicleActivityService.stop();
        if (_automaticDrivingModeEnabled) {
          _automaticDrivingModeDetector.pause();
        } else {
          _automaticDrivingModeDetector.suspend();
        }
      }
    });
    return _vehicleActivityOperations;
  }

  /// Keep the display awake only while active driving detection is visible.
  /// Serializing updates prevents rapid mode or lifecycle changes from leaving
  /// an older platform request as the final wakelock state.
  void _scheduleScreenWakeLockUpdate() {
    _screenWakeLockOperations = _screenWakeLockOperations.then((_) async {
      try {
        await WakelockPlus.toggle(enable: _isDriving && _isAppResumed);
      } on PlatformException {
        // Screen-awake behavior is helpful but must not interrupt detection if
        // a platform cannot provide it.
      } on MissingPluginException {
        // Allows unsupported hosts and widget tests to run normally.
      }
    });
  }

  /// Serializes starts, stops, and accuracy changes so a lifecycle transition
  /// or a quick toggle cannot leave an older location request running.
  void _scheduleSpeedServiceUpdate({GpsAccuracyMode? accuracy}) {
    _speedServiceOperations = _speedServiceOperations.then((_) async {
      try {
        if (accuracy != null) {
          await _speedService.setAccuracy(accuracy);
        }

        if (_isDriving && _isAppResumed) {
          // Best-effort: if location is denied or unavailable the motion
          // detector falls back to the accelerometer.
          await _speedService.start(
            (speed) => _motionDetector.updateSpeed(
              at: DateTime.now(),
              speedMetersPerSecond: speed,
            ),
          );
        } else {
          await _speedService.dispose();
          _motionDetector.reset();
        }
      } catch (_) {
        // Location is an optional refinement. Its failure must not prevent
        // camera-based detection from continuing.
      }
    });
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DriveSettingsScreen(
          yawnEnabled: _controller.yawnDetectionEnabled,
          onYawnEnabledChanged: _setYawnEnabled,
          drowsinessAlarmEnabled: _alertService.drowsinessAlarmEnabled,
          onDrowsinessAlarmEnabledChanged: _setDrowsinessAlarmEnabled,
          recordingEnabled: widget.record.enabled,
          onRecordingEnabledChanged: (value) =>
              setState(() => widget.record.enabled = value),
          sensitivity: _controller.sensitivity,
          onSensitivityChanged: _setSensitivity,
          evidencePhotosEnabled: _evidencePhotosEnabled,
          onEvidencePhotosEnabledChanged: _setEvidencePhotosEnabled,
          evidenceAutoDeleteEnabled: widget.evidenceStore.autoDeleteEnabled,
          onEvidenceAutoDeleteEnabledChanged: _setEvidenceAutoDeleteEnabled,
          evidenceKeepLimit: DrowsinessEvidenceStore.maxPhotos,
          automaticDrivingModeEnabled: _automaticDrivingModeEnabled,
          onAutomaticDrivingModeEnabledChanged: _setAutomaticDrivingModeEnabled,
          gpsAccuracy: _speedService.accuracy,
          onGpsAccuracyChanged: _onGpsAccuracyChanged,
        ),
      ),
    );
  }

  Future<void> _initializeCamera() async {
    if (_isInitializingCamera || _cameraController != null) {
      return;
    }
    _isInitializingCamera = true;

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _setCameraError('No camera found');
        return;
      }

      final frontCamera = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      final camera = frontCamera.isNotEmpty ? frontCamera.first : cameras.first;
      final controller = CameraController(
        camera,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraError = null;
        _isCameraLoading = false;
      });

      await controller.startImageStream(
        (image) => _handleCameraImage(image, camera, controller),
      );
    } on CameraException catch (error) {
      _setCameraError(_cameraMessageFor(error));
    } catch (_) {
      _setCameraError('Camera unavailable');
    } finally {
      _isInitializingCamera = false;
    }
  }

  void _setCameraError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _cameraError = message;
      _isCameraLoading = false;
    });
  }

  String _cameraMessageFor(CameraException error) {
    return switch (error.code) {
      'CameraAccessDenied' => 'Camera permission denied',
      'CameraAccessDeniedWithoutPrompt' =>
        'Enable camera permission in Settings',
      'CameraAccessRestricted' => 'Camera access restricted',
      _ => 'Camera unavailable',
    };
  }

  // Sample faster when something looks off, slower when attentive, to save
  // battery on long trips.
  Duration get _frameInterval {
    return switch (_state) {
      DriverState.attentive => const Duration(milliseconds: 600),
      DriverState.unknown => const Duration(milliseconds: 500),
      _ => const Duration(milliseconds: 250),
    };
  }

  Future<void> _handleCameraImage(
    CameraImage image,
    CameraDescription camera,
    CameraController cameraController,
  ) async {
    if (_isCameraFrameProcessing) {
      return;
    }

    final now = DateTime.now();
    final lastProcessed = _lastCameraFrameProcessedAt;
    if (lastProcessed != null &&
        now.difference(lastProcessed) < _frameInterval) {
      return;
    }

    _lastCameraFrameProcessedAt = now;
    _isCameraFrameProcessing = true;

    try {
      final deviceOrientation = _stabilizedDeviceOrientation(
        cameraController.value.deviceOrientation,
      );
      final observation = await _faceDetectorService.analyze(
        DriverFrame(
          timestamp: now,
          camera: camera,
          image: image,
          deviceOrientation: deviceOrientation,
          width: image.width,
          height: image.height,
        ),
      );
      _lastObservation = observation;
      final vibration = _shakeDetector.vibration;
      _mountMonitor.record(observation, vibration: vibration);
      _motionDetector.update(at: observation.timestamp, vibration: vibration);
      final isVehicleMoving = _isVehicleMoving;
      final state = await _controller.processObservation(
        observation,
        isDriving: _isDriving,
        isVehicleMoving: isVehicleMoving,
      );
      widget.record.update(
        state: state,
        at: observation.timestamp,
        isDriving: _isDriving && isVehicleMoving,
        quality: _mountMonitor.quality,
      );
      // Drowsiness is already fired as a one-shot event by the controller, so
      // this captures once per episode rather than once per frame.
      if (state == DriverState.drowsy && _isDriving && _evidencePhotosEnabled) {
        final raw = _rawFrameFrom(image, deviceOrientation);
        if (raw != null) {
          unawaited(_captureEvidence(raw));
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _state = state;
        _mountIssue = _mountMonitor.quality;
        _detectionError = null;
      });
    } catch (error) {
      // Keep the preview alive, but surface device-specific camera/ML failures
      // so a release build can be diagnosed without adb.
      if (mounted && _detectionError == null) {
        setState(() => _detectionError = error.toString());
      }
    } finally {
      _isCameraFrameProcessing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      appBar: isLandscape
          ? null
          : AppBar(
              title: const Text('Driver Focus'),
              centerTitle: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: 'Settings',
                  onPressed: _openSettings,
                ),
              ],
            ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: OrientationBuilder(
            builder: (context, _) {
              final orientation = MediaQuery.orientationOf(context);
              final cameraPanel = _CameraStatusPanel(
                key: const Key('drive-camera-panel'),
                cameraController: _cameraController,
                isLoading: _isCameraLoading,
                errorMessage: _cameraError,
                state: _state,
                observation: _lastObservation,
                perclos: _controller.perclos,
                mountVibration: _shakeDetector.vibration,
                resolveDeviceOrientation: _stabilizedDeviceOrientation,
                isVehicleMoving: _motionDetector.isMoving,
                isMotionSimulated: _simulateMoving,
                speedMetersPerSecond: _motionDetector.speedMetersPerSecond,
                mountIssue: _mountIssue,
                detectionError: _detectionError,
              );

              if (orientation == Orientation.landscape) {
                // Reserve the control column first, then fit the 4:3 preview
                // into the remaining viewport. Nothing scrolls or changes size
                // when a warning appears because warnings live in the preview.
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final controlsWidth =
                        (constraints.maxWidth * 0.32).clamp(220.0, 300.0);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: _landscapePreviewAspectRatio,
                              child: cameraPanel,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        SizedBox(
                          width: controlsWidth,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: _buildDriveControls(showSettings: true),
                          ),
                        ),
                      ],
                    );
                  },
                );
              }

              // Controls claim their fixed natural height, the camera is
              // calculated from the viewport left over on the first layout.
              // Subsequent state/message changes cannot move either region.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _portraitPreviewAspectRatio,
                        child: cameraPanel,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildDriveControls(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Fixed shape of the portrait camera box, so it never resizes when a warning
  /// bar appears or clears. Matches the camera's own 3:4 portrait framing,
  /// which also keeps the cover-crop to a minimum.
  static const double _portraitPreviewAspectRatio = 3 / 4;

  /// Same idea in landscape, where the camera frames arrive 4:3.
  static const double _landscapePreviewAspectRatio = 4 / 3;

  Widget _buildDriveControls({bool showSettings = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSettings)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: _openSettings,
            ),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Driving mode'),
          value: _isDriving,
          onChanged: _setDrivingMode,
        ),
        // Keep the active build-time override visible so test results cannot be
        // mistaken for real motion detection.
        if (kShowDevTools || kSimulateMoving)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Simulate moving'),
            subtitle: Text(
              _simulateMoving
                  ? 'Pretending the car is moving — yaw is being checked.'
                  : 'Detected: ${_motionDetector.isMoving ? "moving" : "stopped"}'
                      ' (yaw is ${_motionDetector.isMoving ? "" : "not "}'
                      'being checked)',
            ),
            value: _simulateMoving,
            onChanged: (value) => setState(() => _simulateMoving = value),
          ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _calibrate,
          icon: const Icon(Icons.center_focus_strong),
          label: const Text('Calibrate (look at the road)'),
        ),
      ],
    );
  }

  DeviceOrientation _stabilizedDeviceOrientation(
    DeviceOrientation reported,
  ) {
    final displayOrientation = _displayOrientation;
    if (Platform.isAndroid && displayOrientation != null) {
      return displayOrientation;
    }

    // Camera and window-orientation events arrive independently. Always retain
    // a valid reading for its orientation family, even if the window has not
    // switched modes yet, so an early sensor event is ready when it does.
    if (reported == DeviceOrientation.landscapeLeft ||
        reported == DeviceOrientation.landscapeRight) {
      _lastLandscapeOrientation = reported;
    } else {
      _lastPortraitOrientation = reported;
    }

    final layoutOrientation = MediaQuery.orientationOf(context);
    if (layoutOrientation == Orientation.landscape) {
      return _lastLandscapeOrientation;
    }
    return _lastPortraitOrientation;
  }

  Future<void> _loadDisplayOrientation() async {
    final name =
        await _displayRotationChannel.invokeMethod<String>('getOrientation');
    _setDisplayOrientation(name);
  }

  Future<void> _handleDisplayRotationCall(MethodCall call) async {
    if (call.method == 'orientationChanged') {
      _setDisplayOrientation(call.arguments as String?);
    }
  }

  void _setDisplayOrientation(String? name) {
    final orientation = switch (name) {
      'portraitUp' => DeviceOrientation.portraitUp,
      'portraitDown' => DeviceOrientation.portraitDown,
      'landscapeLeft' => DeviceOrientation.landscapeLeft,
      'landscapeRight' => DeviceOrientation.landscapeRight,
      _ => null,
    };
    if (!mounted || orientation == null || orientation == _displayOrientation) {
      return;
    }
    setState(() => _displayOrientation = orientation);
  }
}

class _CameraStatusPanel extends StatelessWidget {
  const _CameraStatusPanel({
    super.key,
    required this.cameraController,
    required this.isLoading,
    required this.errorMessage,
    required this.state,
    required this.observation,
    required this.perclos,
    required this.mountVibration,
    required this.resolveDeviceOrientation,
    required this.isVehicleMoving,
    required this.isMotionSimulated,
    required this.speedMetersPerSecond,
    required this.mountIssue,
    required this.detectionError,
  });

  /// GPS speed in m/s, or null when the decision fell back to vibration.
  final double? speedMetersPerSecond;

  /// What the motion detector currently concludes, and whether the temporary
  /// test toggle is overriding it. Shown in the overlay so a screen recording
  /// made while driving captures it, since the drive controls need scrolling to
  /// reach and can't be read at the wheel.
  final bool isVehicleMoving;
  final bool isMotionSimulated;
  final MountIssue mountIssue;
  final String? detectionError;

  final CameraController? cameraController;
  final bool isLoading;
  final String? errorMessage;
  final DriverState state;
  final FaceObservation? observation;
  final double perclos;
  final double mountVibration;
  final DeviceOrientation Function(DeviceOrientation) resolveDeviceOrientation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final controller = cameraController;
    final hasPreview = controller != null && controller.value.isInitialized;
    final hasWarning = mountIssue != MountIssue.none || detectionError != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: colorScheme.surfaceContainerHighest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasPreview)
              _CameraPreview(
                controller: controller,
                resolveDeviceOrientation: resolveDeviceOrientation,
              )
            else
              _CameraPlaceholder(
                isLoading: isLoading,
                errorMessage: errorMessage,
              ),
            if (!hasWarning)
              const Align(
                alignment: Alignment.topRight,
                child: _DetectionModeBadge(),
              ),
            if (kShowDevTools)
              Align(
                alignment: Alignment.topLeft,
                child: _DebugReadout(
                  observation: observation,
                  perclos: perclos,
                  vibration: mountVibration,
                  isVehicleMoving: isVehicleMoving,
                  isMotionSimulated: isMotionSimulated,
                  speedMetersPerSecond: speedMetersPerSecond,
                ),
              ),
            if (hasWarning)
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (mountIssue != MountIssue.none)
                      _MountWarningBar(issue: mountIssue),
                    if (detectionError case final message?)
                      _DetectionErrorBar(message: message),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _DriverStateBadge(state: state),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectionModeBadge extends StatelessWidget {
  const _DetectionModeBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            'Live',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                ),
          ),
        ),
      ),
    );
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({
    required this.controller,
    required this.resolveDeviceOrientation,
  });

  final CameraController controller;
  final DeviceOrientation Function(DeviceOrientation) resolveDeviceOrientation;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final orientation = resolveDeviceOrientation(value.deviceOrientation);
        final isLandscape = orientation == DeviceOrientation.landscapeLeft ||
            orientation == DeviceOrientation.landscapeRight;
        final previewAspectRatio =
            isLandscape ? value.aspectRatio : 1 / value.aspectRatio;

        // Lay the texture out at its own natural size and let FittedBox scale
        // it. Sizing a box to the parent's constraints instead would let
        // SizedBox clamp an intentionally-overflowing cover box back to the
        // available width or height, clamping one axis and not the other, which
        // squashes the picture.
        final source = value.previewSize;
        final double naturalWidth;
        final double naturalHeight;
        if (source != null && source.width > 0 && source.height > 0) {
          // previewSize is reported in the sensor's own landscape orientation,
          // so swap it when the device is upright.
          naturalWidth = isLandscape ? source.width : source.height;
          naturalHeight = isLandscape ? source.height : source.width;
        } else {
          // No preview size yet: any box with the right ratio will do, since
          // FittedBox only cares about the proportions.
          naturalWidth = previewAspectRatio * 1000;
          naturalHeight = 1000;
        }

        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: naturalWidth,
              height: naturalHeight,
              child: _OrientedCameraTexture(
                controller: controller,
                orientation: orientation,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OrientedCameraTexture extends StatelessWidget {
  const _OrientedCameraTexture({
    required this.controller,
    required this.orientation,
  });

  final CameraController controller;
  final DeviceOrientation orientation;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.android) {
      return CameraPreview(controller);
    }

    final quarterTurns = switch (orientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeRight => 1,
      DeviceOrientation.portraitDown => 2,
      DeviceOrientation.landscapeLeft => 3,
    };
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: controller.buildPreview(),
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder({
    required this.isLoading,
    required this.errorMessage,
  });

  final bool isLoading;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Starting camera',
                style: textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ] else ...[
              Icon(
                Icons.videocam_off_outlined,
                size: 40,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                errorMessage ?? 'Camera unavailable',
                style: textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DriverStateBadge extends StatelessWidget {
  const _DriverStateBadge({required this.state});

  final DriverState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(
            state.label,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// Temporary on-screen diagnostic of the latest ML Kit reading, used to tune
// thresholds against real device values. Can be removed once dialed in.
class _DebugReadout extends StatelessWidget {
  const _DebugReadout({
    required this.observation,
    required this.perclos,
    required this.vibration,
    required this.isVehicleMoving,
    required this.isMotionSimulated,
    required this.speedMetersPerSecond,
  });

  final FaceObservation? observation;
  final double perclos;
  final double vibration;
  final bool isVehicleMoving;
  final bool isMotionSimulated;
  final double? speedMetersPerSecond;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final o = observation;

    String deg(double? v) => v == null ? '—' : '${v.toStringAsFixed(0)}°';
    String prob(double? v) => v == null ? '—' : v.toStringAsFixed(2);

    // Sits next to VIB because VIB is what decides it. Seeing the number and
    // the verdict together is what makes the thresholds tunable from a
    // recording.
    // Always reports what the detector concluded. When the test toggle is
    // overriding it, say so explicitly, so a recording can't be misread as the
    // detector having got it right.
    final detected = isVehicleMoving ? 'moving' : 'stopped';
    final motion = isMotionSimulated ? '$detected  [FORCED moving]' : detected;
    // Name the signal that actually decided, so a recording says whether GPS
    // was in play or it fell back to vibration.
    final speed = speedMetersPerSecond;
    final source = speed == null
        ? 'VIB ${vibration.toStringAsFixed(2)}'
        : 'GPS ${(speed * 3.6).toStringAsFixed(0)}km/h';

    final text = o == null
        ? 'no reading yet'
        : 'yaw ${deg(o.headYawDegrees)}   pitch ${deg(o.headPitchDegrees)}   roll ${deg(o.headRollDegrees)}\n'
            'L ${prob(o.leftEyeOpenProbability)}   R ${prob(o.rightEyeOpenProbability)}   MAR ${prob(o.mouthOpenRatio)}\n'
            'PERCLOS ${(perclos * 100).toStringAsFixed(0)}%   BRT ${prob(o.frameBrightness)}\n'
            '$source -> $motion';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// Persistent amber bar shown while phone-mount/environment quality is poor.
class _MountWarningBar extends StatelessWidget {
  const _MountWarningBar({required this.issue});

  final MountIssue issue;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF4A3B00) : const Color(0xFFFFF3CD);
    final foreground =
        isDark ? const Color(0xFFFFE08A) : const Color(0xFF6B5200);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              issue.message,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectionErrorBar extends StatelessWidget {
  const _DetectionErrorBar({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Detection error: $message',
        style: TextStyle(color: colorScheme.onErrorContainer),
      ),
    );
  }
}
