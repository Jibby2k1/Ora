import 'dart:io';

import 'package:image/image.dart' as img;

class ImageDownscaler {
  ImageDownscaler._();

  static Future<File> downscaleImageIfNeeded(
    File file, {
    int maxDimension = 1280,
    int jpegQuality = 80,
  }) async {
    final path = file.path;
    if (!_isImagePath(path)) return file;
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return file;
    final needsResize = decoded.width > maxDimension || decoded.height > maxDimension;
    final needsReencode = !_isJpeg(path);
    if (!needsResize && !needsReencode) return file;
    final resized = needsResize
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxDimension : null,
            height: decoded.height > decoded.width ? maxDimension : null,
            interpolation: img.Interpolation.cubic,
          )
        : decoded;
    final jpg = img.encodeJpg(resized, quality: jpegQuality);
    final outPath = '${Directory.systemTemp.path}/ora_upload_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final outFile = File(outPath);
    await outFile.writeAsBytes(jpg, flush: true);
    return outFile;
  }

  static bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.webp');
  }

  static bool _isJpeg(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') || lower.endsWith('.jpeg');
  }
}
