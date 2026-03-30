import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class PersistentMediaFileManager {
  PersistentMediaFileManager._();

  static final PersistentMediaFileManager instance =
      PersistentMediaFileManager._();

  final Uuid _uuid = const Uuid();

  Future<File> persistCapturedPhoto(
    File sourceFile, {
    String? clientRequestId,
  }) async {
    final exists = await sourceFile.exists();
    if (!exists) {
      throw FileSystemException(
        'Source media file does not exist.',
        sourceFile.path,
      );
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    final queueDirectory = Directory(
      p.join(documentsDirectory.path, 'offline_media_queue'),
    );
    if (!await queueDirectory.exists()) {
      await queueDirectory.create(recursive: true);
    }

    final extension = p.extension(sourceFile.path);
    final safeExtension = extension.isEmpty ? '.jpg' : extension.toLowerCase();
    final fileName = '${clientRequestId ?? _uuid.v4()}$safeExtension';
    final persistedPath = p.join(queueDirectory.path, fileName);

    return sourceFile.copy(persistedPath);
  }

  Future<void> deleteIfExists(String? filePath) async {
    if (filePath == null || filePath.isEmpty) {
      return;
    }

    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
