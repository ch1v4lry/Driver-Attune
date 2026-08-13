import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    as mlkit;

import 'face_observation.dart';
import 'frame_source.dart';

abstract interface class FaceDetectorService {
  Future<FaceObservation> analyze(DriverFrame frame);
  Future<void> close();
}

class MlKitFaceDetectorService implements FaceDetectorService {
  MlKitFaceDetectorService()
      : _detector = mlkit.FaceDetector(
          options: mlkit.FaceDetectorOptions(
            // Landmarks (nose and eyes for the reference) and lip contours
            // (inner lips for the mouth gap) both feed the yawn metric.
            // Classification gives the eye-open probabilities.
            enableClassification: true,
            enableLandmarks: true,
            enableContours: true,
            performanceMode: mlkit.FaceDetectorMode.fast,
          ),
        );

  final mlkit.FaceDetector _detector;

  static const Map<DeviceOrientation, int> _orientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  Future<FaceObservation> analyze(DriverFrame frame) async {
    final brightness =
        frame.image == null ? null : _averageBrightness(frame.image!);

    final inputImage = _inputImageFromFrame(frame);
    if (inputImage == null) {
      return FaceObservation(
        timestamp: frame.timestamp,
        faceVisible: false,
        frameBrightness: brightness,
      );
    }

    late final List<mlkit.Face> faces;
    try {
      faces = await _detector.processImage(inputImage);
    } on PlatformException catch (error) {
      final image = frame.image;
      final frameDetails =
          image == null ? 'no camera image' : _cameraImageDescription(image);
      throw StateError(
        'ML Kit ${error.code}: ${error.message ?? error.details}; '
        '$frameDetails',
      );
    }
    if (faces.isEmpty) {
      return FaceObservation(
        timestamp: frame.timestamp,
        faceVisible: false,
        frameBrightness: brightness,
      );
    }

    final face = faces.reduce(
      (largest, next) => _faceArea(next) > _faceArea(largest) ? next : largest,
    );
    final rotation = _rotationFor(
      frame.camera!,
      frame.deviceOrientation!,
    );
    final cropBounds = _faceContourBounds(face) ?? face.boundingBox;

    return FaceObservation(
      timestamp: frame.timestamp,
      faceVisible: true,
      headYawDegrees: face.headEulerAngleY,
      headPitchDegrees: face.headEulerAngleX,
      headRollDegrees: face.headEulerAngleZ,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      mouthOpenRatio: _mouthOpenRatio(face),
      faceBoundsFraction: _faceBoundsFraction(face, frame),
      faceNearEdge: _faceNearEdge(cropBounds, frame, rotation),
      frameBrightness: brightness,
    );
  }

  @override
  Future<void> close() => _detector.close();

  double _faceArea(mlkit.Face face) {
    return face.boundingBox.width * face.boundingBox.height;
  }

  Size? _orientedImageSize(
    DriverFrame frame,
    mlkit.InputImageRotation? rotation,
  ) {
    final w = frame.width;
    final h = frame.height;
    if (w == null || h == null || w <= 0 || h <= 0 || rotation == null) {
      return null;
    }
    final swapsAxes = rotation == mlkit.InputImageRotation.rotation90deg ||
        rotation == mlkit.InputImageRotation.rotation270deg;
    return swapsAxes
        ? Size(h.toDouble(), w.toDouble())
        : Size(w.toDouble(), h.toDouble());
  }

  // Face bounding-box area as a fraction of the whole frame. Small means the
  // phone is too far or the face is too small to read reliably.
  double? _faceBoundsFraction(mlkit.Face face, DriverFrame frame) {
    final w = frame.width;
    final h = frame.height;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return null;
    }
    return _faceArea(face) / (w * h);
  }

  // Whether the full face is at risk of being cropped. A little conservative on
  // purpose, since losing any part of the face can reduce eye, pose, and mouth
  // measurements, but a normally framed face should not warn just because its
  // bounding box is close to an edge.
  Rect? _faceContourBounds(mlkit.Face face) {
    final points = face.contours[mlkit.FaceContourType.face]?.points;
    if (points == null || points.isEmpty) {
      return null;
    }
    var left = points.first.x.toDouble();
    var top = points.first.y.toDouble();
    var right = left;
    var bottom = top;
    for (final point in points.skip(1)) {
      left = math.min(left, point.x.toDouble());
      top = math.min(top, point.y.toDouble());
      right = math.max(right, point.x.toDouble());
      bottom = math.max(bottom, point.y.toDouble());
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  bool _faceNearEdge(
    Rect bounds,
    DriverFrame frame,
    mlkit.InputImageRotation? rotation,
  ) {
    final imageSize = _orientedImageSize(frame, rotation);
    if (imageSize == null) {
      return false;
    }
    final w = imageSize.width;
    final h = imageSize.height;
    const edgeRiskFraction = 0.01;
    final marginX = w * edgeRiskFraction;
    final marginY = h * edgeRiskFraction;
    return bounds.left < marginX ||
        bounds.top < marginY ||
        bounds.right > w - marginX ||
        bounds.bottom > h - marginY;
  }

  // Average luma (0..1), sampled sparsely, for the low-visibility (too dark or
  // washed out) mount-quality check.
  double? _averageBrightness(CameraImage image) {
    if (image.planes.isEmpty) {
      return null;
    }
    final bytes = image.planes.first.bytes;
    if (bytes.isEmpty) {
      return null;
    }

    var sum = 0;
    var count = 0;
    if (Platform.isIOS) {
      // BGRA8888: 4 bytes per pixel (B, G, R, A). Sample luma from a subset.
      for (var i = 0; i + 2 < bytes.length; i += 4 * 37) {
        sum += (0.114 * bytes[i] + 0.587 * bytes[i + 1] + 0.299 * bytes[i + 2])
            .round();
        count++;
      }
    } else {
      // NV21: the luma (Y) plane comes first; sample it.
      final lumaEnd = math.min(image.width * image.height, bytes.length);
      for (var i = 0; i < lumaEnd; i += 37) {
        sum += bytes[i];
        count++;
      }
    }
    if (count == 0) {
      return null;
    }
    return (sum / count) / 255.0;
  }

  // Yawn signal: the average gap between the inner edges of the upper and lower
  // lips across the central lip points, divided by a vertical reference
  // (eye-line to nose base) robust to pose. Averaging reduces per-point noise,
  // and the reference cancels head tilt and face size. Returns null if
  // unavailable.
  double? _mouthOpenRatio(mlkit.Face face) {
    final nose = face.landmarks[mlkit.FaceLandmarkType.noseBase]?.position;
    final leftEye = face.landmarks[mlkit.FaceLandmarkType.leftEye]?.position;
    final rightEye = face.landmarks[mlkit.FaceLandmarkType.rightEye]?.position;
    if (nose == null || leftEye == null || rightEye == null) {
      return null;
    }

    final eyeMidX = (leftEye.x + rightEye.x) / 2.0;
    final eyeMidY = (leftEye.y + rightEye.y) / 2.0;
    final reference = math.sqrt(
      math.pow(nose.x - eyeMidX, 2) + math.pow(nose.y - eyeMidY, 2),
    );
    if (reference <= 0) {
      return null;
    }

    final innerTop =
        face.contours[mlkit.FaceContourType.upperLipBottom]?.points;
    final innerBottom =
        face.contours[mlkit.FaceContourType.lowerLipTop]?.points;
    if (innerTop == null ||
        innerBottom == null ||
        innerTop.length != innerBottom.length ||
        innerTop.length < 3) {
      return null;
    }

    final n = innerTop.length;
    final start = n ~/ 3;
    final end = n - start;
    var sum = 0.0;
    var count = 0;
    for (var i = start; i < end; i++) {
      sum += _distance(innerTop[i], innerBottom[i]);
      count++;
    }
    if (count == 0) {
      return null;
    }

    return (sum / count) / reference;
  }

  double _distance(math.Point<int> a, math.Point<int> b) {
    final dx = (a.x - b.x).toDouble();
    final dy = (a.y - b.y).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }

  mlkit.InputImage? _inputImageFromFrame(DriverFrame frame) {
    final image = frame.image;
    final camera = frame.camera;
    final deviceOrientation = frame.deviceOrientation;
    if (image == null || camera == null || deviceOrientation == null) {
      return null;
    }

    final rotation = _rotationFor(camera, deviceOrientation);
    if (rotation == null) {
      return null;
    }

    Uint8List bytes;
    mlkit.InputImageFormat format;
    int bytesPerRow;
    if (Platform.isAndroid) {
      final androidImage = _androidImageBytes(image);
      if (androidImage == null) {
        throw StateError(
          'Unsupported Android camera frame: ${_cameraImageDescription(image)}',
        );
      }
      bytes = androidImage.bytes;
      format = mlkit.InputImageFormat.nv21;
      bytesPerRow = androidImage.bytesPerRow;
    } else {
      final detectedFormat =
          mlkit.InputImageFormatValue.fromRawValue(image.format.raw);
      if (!Platform.isIOS ||
          detectedFormat != mlkit.InputImageFormat.bgra8888 ||
          image.planes.length != 1) {
        return null;
      }
      final plane = image.planes.first;
      bytes = plane.bytes;
      format = detectedFormat!;
      bytesPerRow = plane.bytesPerRow;
    }

    return mlkit.InputImage.fromBytes(
      bytes: bytes,
      metadata: mlkit.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: bytesPerRow,
      ),
    );
  }

  ({Uint8List bytes, int bytesPerRow})? _androidImageBytes(
    CameraImage image,
  ) {
    final format = mlkit.InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == mlkit.InputImageFormat.nv21 && image.planes.length == 1) {
      final plane = image.planes.first;
      final expectedLength = image.width * image.height * 3 ~/ 2;
      if (plane.bytes.length < expectedLength) {
        throw StateError(
          'Incomplete NV21 camera frame: expected $expectedLength bytes, '
          'received ${plane.bytes.length}; ${_cameraImageDescription(image)}',
        );
      }

      // ML Kit expects a compact NV21 byte array. CameraX normally supplies
      // exactly that, but discard any trailing capacity exposed by a
      // device-specific ImageProxy implementation.
      final bytes = plane.bytes.length == expectedLength
          ? plane.bytes
          : Uint8List.sublistView(plane.bytes, 0, expectedLength);
      return (bytes: bytes, bytesPerRow: image.width);
    }

    // Some physical devices ignore the requested NV21 format and provide
    // YUV_420_888 as three planes. Convert it to the compact NV21 layout that
    // google_mlkit_commons accepts.
    if (format != mlkit.InputImageFormat.yuv_420_888 ||
        image.planes.length != 3) {
      return null;
    }

    final width = image.width;
    final height = image.height;
    final output = Uint8List(width * height * 3 ~/ 2);
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final yPixelStride = yPlane.bytesPerPixel ?? 1;
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;

    var outputIndex = 0;
    for (var row = 0; row < height; row++) {
      final rowStart = row * yPlane.bytesPerRow;
      for (var column = 0; column < width; column++) {
        output[outputIndex++] = yPlane.bytes[rowStart + column * yPixelStride];
      }
    }
    for (var row = 0; row < height ~/ 2; row++) {
      final uRowStart = row * uPlane.bytesPerRow;
      final vRowStart = row * vPlane.bytesPerRow;
      for (var column = 0; column < width ~/ 2; column++) {
        output[outputIndex++] = vPlane.bytes[vRowStart + column * vPixelStride];
        output[outputIndex++] = uPlane.bytes[uRowStart + column * uPixelStride];
      }
    }
    return (bytes: output, bytesPerRow: width);
  }

  String _cameraImageDescription(CameraImage image) {
    final planes = image.planes.indexed.map((entry) {
      final (index, plane) = entry;
      return 'p$index=${plane.bytes.length}B/'
          'row${plane.bytesPerRow}/pixel${plane.bytesPerPixel ?? "?"}';
    }).join(', ');
    return '${image.width}x${image.height}, raw=${image.format.raw}, '
        '${image.planes.length} plane(s) [$planes]';
  }

  mlkit.InputImageRotation? _rotationFor(
    CameraDescription camera,
    DeviceOrientation deviceOrientation,
  ) {
    final sensorOrientation = camera.sensorOrientation;

    if (Platform.isIOS) {
      return mlkit.InputImageRotationValue.fromRawValue(sensorOrientation);
    }

    if (!Platform.isAndroid) {
      return null;
    }

    final orientation = _orientationDegrees[deviceOrientation];
    if (orientation == null) {
      return null;
    }

    final rotation = camera.lensDirection == CameraLensDirection.front
        ? (sensorOrientation + orientation) % 360
        : (sensorOrientation - orientation + 360) % 360;
    return mlkit.InputImageRotationValue.fromRawValue(rotation);
  }
}
