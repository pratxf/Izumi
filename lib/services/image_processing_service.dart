import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class ProcessedImagePayload {
  const ProcessedImagePayload({
    required this.imageBytes,
    required this.thumbnailBytes,
  });

  final Uint8List? imageBytes;
  final Uint8List? thumbnailBytes;
}

class ImageProcessingService {
  /// Compresses an image into a full-size and thumbnail byte array.
  ///
  /// NOTE: FlutterImageCompress uses Flutter platform channels which are
  /// only available on the root isolate. Do NOT wrap this in Isolate.run().
  static Future<ProcessedImagePayload> preparePhotoForUpload(File file) async {
    Uint8List? imageBytes;
    Uint8List? thumbnailBytes;

    try {
      imageBytes = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 1024,
        minHeight: 1024,
        quality: 70,
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[ImageProcessingService] Full compression failed: $e');
    }

    try {
      thumbnailBytes = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 200,
        minHeight: 200,
        quality: 70,
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[ImageProcessingService] Thumbnail compression failed: $e');
      thumbnailBytes = imageBytes;
    }

    return ProcessedImagePayload(
      imageBytes: imageBytes,
      thumbnailBytes: thumbnailBytes,
    );
  }
}
