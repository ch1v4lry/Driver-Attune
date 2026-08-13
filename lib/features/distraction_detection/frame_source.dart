import 'package:camera/camera.dart';
import 'package:flutter/services.dart';

/// One camera frame handed to the detector, with the context needed to
/// interpret it (which camera, and how the device was held).
class DriverFrame {
  const DriverFrame({
    required this.timestamp,
    this.camera,
    this.image,
    this.deviceOrientation,
    this.width,
    this.height,
  });

  final DateTime timestamp;
  final CameraDescription? camera;
  final CameraImage? image;
  final DeviceOrientation? deviceOrientation;
  final int? width;
  final int? height;
}
