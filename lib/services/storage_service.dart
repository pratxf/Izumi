import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final _uuid = const Uuid();

  // Upload a photo and return the download URL
  Future<String> uploadPhoto({
    required String enterpriseId,
    required String userId,
    required String date, // 'YYYY-MM-DD'
    required File file,
  }) async {
    final photoId = _uuid.v4();
    final ext = p.extension(file.path);
    final path = 'enterprises/$enterpriseId/photos/$userId/$date/$photoId$ext';

    final ref = _storage.ref(path);
    await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    return await ref.getDownloadURL();
  }

  // Upload a compressed thumbnail
  Future<String> uploadThumbnail({
    required String enterpriseId,
    required String userId,
    required String date,
    required File file,
  }) async {
    final photoId = _uuid.v4();
    final path =
        'enterprises/$enterpriseId/photos/$userId/$date/${photoId}_thumb.jpg';

    // Compress the image for thumbnail
    final compressed = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 200,
      minHeight: 200,
      quality: 70,
    );

    if (compressed == null) {
      throw Exception('Failed to compress image');
    }

    final ref = _storage.ref(path);
    await ref.putData(
      compressed,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    return await ref.getDownloadURL();
  }

  // Upload profile image
  Future<String> uploadProfileImage({
    required String enterpriseId,
    required String userId,
    required File file,
  }) async {
    final path = 'enterprises/$enterpriseId/profiles/$userId/avatar.jpg';

    // Compress profile image
    final compressed = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 300,
      minHeight: 300,
      quality: 80,
    );

    if (compressed == null) {
      throw Exception('Failed to compress image');
    }

    final ref = _storage.ref(path);
    await ref.putData(
      compressed,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    return await ref.getDownloadURL();
  }

  // Get download URL for a storage path
  Future<String> getDownloadUrl(String path) async {
    return await _storage.ref(path).getDownloadURL();
  }

  // Delete a file from storage
  Future<void> deleteFile(String path) async {
    await _storage.ref(path).delete();
  }

  // Delete a photo and its thumbnail
  Future<void> deletePhoto({
    required String storagePath,
  }) async {
    try {
      await _storage.ref(storagePath).delete();
    } catch (_) {}

    // Try to delete thumbnail too
    try {
      final thumbPath = storagePath.replaceAll(
        RegExp(r'\.(jpg|jpeg|png)$'),
        '_thumb.jpg',
      );
      await _storage.ref(thumbPath).delete();
    } catch (_) {}
  }
}
