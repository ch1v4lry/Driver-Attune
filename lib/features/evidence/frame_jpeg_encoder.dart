import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The pixel formats the camera delivers, as far as this encoder cares.
enum FramePixelFormat { bgra8888, nv21, yuv420 }

/// A camera frame flattened into plain, isolate-transferable data.
///
/// [CameraImage] itself can't cross an isolate boundary, so the bytes are
/// copied out on the caller's side and the encoding is done elsewhere.
class RawFrame {
  const RawFrame({
    required this.format,
    required this.width,
    required this.height,
    required this.planes,
    required this.bytesPerRow,
    required this.pixelStrides,
    required this.quarterTurns,
  });

  final FramePixelFormat format;
  final int width;
  final int height;
  final List<Uint8List> planes;
  final List<int> bytesPerRow;
  final List<int> pixelStrides;

  /// Clockwise quarter-turns needed to make the image upright.
  final int quarterTurns;
}

/// Encodes a camera frame to JPEG bytes.
///
/// Runs off a frame the detector has already seen, so the photo shows the exact
/// moment that was judged, instead of whatever the camera happens to capture a
/// second later. Meant to be run through `compute`.
Uint8List? encodeFrameToJpeg(RawFrame frame) {
  final image = switch (frame.format) {
    FramePixelFormat.bgra8888 => _fromBgra(frame),
    FramePixelFormat.nv21 => _fromNv21(frame),
    FramePixelFormat.yuv420 => _fromYuv420(frame),
  };
  if (image == null) {
    return null;
  }
  final upright = frame.quarterTurns == 0
      ? image
      : img.copyRotate(image, angle: frame.quarterTurns * 90);
  return img.encodeJpg(upright, quality: 80);
}

img.Image? _fromBgra(RawFrame frame) {
  if (frame.planes.isEmpty) {
    return null;
  }
  final bytes = frame.planes.first;
  final stride = frame.bytesPerRow.first;
  final out = img.Image(width: frame.width, height: frame.height);
  for (var y = 0; y < frame.height; y++) {
    final row = y * stride;
    for (var x = 0; x < frame.width; x++) {
      final i = row + x * 4;
      if (i + 3 >= bytes.length) {
        continue;
      }
      // BGRA byte order.
      out.setPixelRgb(x, y, bytes[i + 2], bytes[i + 1], bytes[i]);
    }
  }
  return out;
}

img.Image? _fromNv21(RawFrame frame) {
  if (frame.planes.isEmpty) {
    return null;
  }
  final bytes = frame.planes.first;
  final w = frame.width;
  final h = frame.height;
  final expected = w * h * 3 ~/ 2;
  if (bytes.length < expected) {
    return null;
  }
  final out = img.Image(width: w, height: h);
  final uvStart = w * h;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final yValue = bytes[y * w + x];
      // NV21 interleaves V then U at quarter resolution.
      final uvIndex = uvStart + (y >> 1) * w + (x & ~1);
      final v = bytes[uvIndex];
      final u = bytes[uvIndex + 1];
      _writeYuvPixel(out, x, y, yValue, u, v);
    }
  }
  return out;
}

img.Image? _fromYuv420(RawFrame frame) {
  if (frame.planes.length < 3) {
    return null;
  }
  final yPlane = frame.planes[0];
  final uPlane = frame.planes[1];
  final vPlane = frame.planes[2];
  final w = frame.width;
  final h = frame.height;
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final yIndex = y * frame.bytesPerRow[0] + x * frame.pixelStrides[0];
      final uvRow = (y >> 1) * frame.bytesPerRow[1];
      final uIndex = uvRow + (x >> 1) * frame.pixelStrides[1];
      final vIndex =
          (y >> 1) * frame.bytesPerRow[2] + (x >> 1) * frame.pixelStrides[2];
      if (yIndex >= yPlane.length ||
          uIndex >= uPlane.length ||
          vIndex >= vPlane.length) {
        continue;
      }
      _writeYuvPixel(out, x, y, yPlane[yIndex], uPlane[uIndex], vPlane[vIndex]);
    }
  }
  return out;
}

void _writeYuvPixel(img.Image out, int x, int y, int yv, int u, int v) {
  final c = yv - 16;
  final d = u - 128;
  final e = v - 128;
  final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
  final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
  final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);
  out.setPixelRgb(x, y, r, g, b);
}
