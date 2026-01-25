import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    final dir = await _mediaDir(subdir: null);
    final outPath = p.join(dir.path, 'ora_media_${DateTime.now().millisecondsSinceEpoch}.jpg');
    final outFile = File(outPath);
    await outFile.writeAsBytes(jpg, flush: true);
    return outFile;
  }

  static Future<File> persistImage(File file) async {
    final dir = await _mediaDir();
    if (p.isWithin(dir.path, file.path)) return file;
    final ext = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
    final outPath = p.join(dir.path, 'ora_media_${DateTime.now().millisecondsSinceEpoch}$ext');
    return file.copy(outPath);
  }

  static Future<File> persistImageToSubdir(File file, String subdir) async {
    final dir = await _mediaDir(subdir: subdir);
    if (p.isWithin(dir.path, file.path)) return file;
    final ext = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
    final outPath = p.join(dir.path, 'ora_media_${DateTime.now().millisecondsSinceEpoch}$ext');
    return file.copy(outPath);
  }

  static Future<Directory> _mediaDir({String? subdir}) async {
    final root = await getApplicationDocumentsDirectory();
    final parts = <String>['media'];
    if (subdir != null && subdir.trim().isNotEmpty) {
      parts.addAll(subdir.split('/').where((segment) => segment.trim().isNotEmpty));
    }
    final dir = Directory(p.joinAll([root.path, ...parts]));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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
