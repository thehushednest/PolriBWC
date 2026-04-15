import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

Uint8List? encodeLiveCameraImage(
  CameraImage cameraImage, {
  int jpegQuality = 55,
  int? maxWidth,
}) {
  try {
    switch (cameraImage.format.group) {
      case ImageFormatGroup.yuv420:
        return _encodeYuv420(cameraImage, jpegQuality, maxWidth);
      case ImageFormatGroup.bgra8888:
        return _encodeBgra8888(cameraImage, jpegQuality, maxWidth);
      case ImageFormatGroup.jpeg:
        if (cameraImage.planes.isEmpty) return null;
        return cameraImage.planes.first.bytes;
      default:
        return null;
    }
  } catch (_) {
    return null;
  }
}

Uint8List _encodeYuv420(
  CameraImage cameraImage,
  int jpegQuality,
  int? maxWidth,
) {
  final width = cameraImage.width;
  final height = cameraImage.height;
  final yPlane = cameraImage.planes[0];
  final uPlane = cameraImage.planes[1];
  final vPlane = cameraImage.planes[2];
  final image = img.Image(width: width, height: height);

  for (var y = 0; y < height; y++) {
    final yRow = yPlane.bytesPerRow * y;
    final uvRow = uPlane.bytesPerRow * (y >> 1);
    for (var x = 0; x < width; x++) {
      final uvIndex = uvRow + (x >> 1) * (uPlane.bytesPerPixel ?? 1);
      final yp = yPlane.bytes[yRow + x];
      final up = uPlane.bytes[uvIndex];
      final vp = vPlane.bytes[uvIndex];

      final r = (yp + 1.402 * (vp - 128)).round();
      final g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round();
      final b = (yp + 1.772 * (up - 128)).round();

      image.setPixelRgb(
        x,
        y,
        _clampColor(r),
        _clampColor(g),
        _clampColor(b),
      );
    }
  }

  final rotated = _resizeIfNeeded(img.copyRotate(image, angle: 90), maxWidth);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: jpegQuality));
}

Uint8List _encodeBgra8888(
  CameraImage cameraImage,
  int jpegQuality,
  int? maxWidth,
) {
  final plane = cameraImage.planes.first;
  final buffer = plane.bytes.buffer;
  final image = img.Image.fromBytes(
    width: cameraImage.width,
    height: cameraImage.height,
    bytes: buffer,
    order: img.ChannelOrder.bgra,
  );
  final rotated = _resizeIfNeeded(img.copyRotate(image, angle: 90), maxWidth);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: jpegQuality));
}

int _clampColor(int value) => math.max(0, math.min(255, value));

img.Image _resizeIfNeeded(img.Image image, int? maxWidth) {
  if (maxWidth == null || maxWidth <= 0 || image.width <= maxWidth) {
    return image;
  }
  final ratio = maxWidth / image.width;
  final targetHeight = (image.height * ratio).round();
  return img.copyResize(
    image,
    width: maxWidth,
    height: targetHeight,
    interpolation: img.Interpolation.linear,
  );
}
