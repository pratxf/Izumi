import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final _uuid = const Uuid();

  Future<void> _ensureSourceFileExists(File file,
      {String? contextLabel}) async {
    final exists = await file.exists();
    debugPrint(
      '[StorageService] ${contextLabel ?? 'file'} source path=${file.path} exists=$exists',
    );
    if (!exists) {
      throw Exception(
        'Selected image is no longer available. Please retake the photo and try again.',
      );
    }
  }

  // Upload a photo (compressed) and return the download URL
  Future<String> uploadPhoto({
    required String enterpriseId,
    required String userId,
    required String date, // 'YYYY-MM-DD'
    required File file,
    String? fileNameBase,
  }) async {
    final photoId = fileNameBase ?? _uuid.v4();
    final path = 'enterprises/$enterpriseId/photos/$userId/$date/$photoId.jpg';
    await _ensureSourceFileExists(file, contextLabel: 'uploadPhoto');

    // Compress before upload to reduce file size (raw camera images can be 5-15MB)
    Uint8List? compressed;
    try {
      compressed = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 1920,
        minHeight: 1920,
        quality: 85,
      );
      debugPrint(
        '[StorageService] uploadPhoto compression result path=${file.path} bytes=${compressed?.lengthInBytes ?? 0}',
      );
    } catch (e) {
      debugPrint(
          '[StorageService] uploadPhoto compression failed for ${file.path}: $e');
    }

    final ref = _storage.ref(path);
    if (compressed != null) {
      await ref.putData(
        compressed,
        SettableMetadata(contentType: 'image/jpeg'),
      );
    } else {
      // Fallback to raw file if compression fails
      await _ensureSourceFileExists(file, contextLabel: 'uploadPhoto fallback');
      await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
    }

    return await ref.getDownloadURL();
  }

  // Upload a compressed thumbnail
  Future<String> uploadThumbnail({
    required String enterpriseId,
    required String userId,
    required String date,
    required File file,
    String? fileNameBase,
  }) async {
    final photoId = fileNameBase ?? _uuid.v4();
    final path =
        'enterprises/$enterpriseId/photos/$userId/$date/${photoId}_thumb.jpg';
    await _ensureSourceFileExists(file, contextLabel: 'uploadThumbnail');

    // Compress the image for thumbnail
    Uint8List? compressed;
    try {
      compressed = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 200,
        minHeight: 200,
        quality: 70,
      );
      debugPrint(
        '[StorageService] uploadThumbnail compression result path=${file.path} bytes=${compressed?.lengthInBytes ?? 0}',
      );
    } catch (e) {
      debugPrint(
          '[StorageService] uploadThumbnail compression failed for ${file.path}: $e');
    }

    final ref = _storage.ref(path);
    if (compressed != null) {
      await ref.putData(
        compressed,
        SettableMetadata(contentType: 'image/jpeg'),
      );
    } else {
      await _ensureSourceFileExists(file,
          contextLabel: 'uploadThumbnail fallback');
      await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
    }

    return await ref.getDownloadURL();
  }

  Future<String> uploadPhotoBytes({
    required String enterpriseId,
    required String userId,
    required String date,
    required Uint8List bytes,
    String? fileNameBase,
  }) async {
    final photoId = fileNameBase ?? _uuid.v4();
    final path = 'enterprises/$enterpriseId/photos/$userId/$date/$photoId.jpg';
    final ref = _storage.ref(path);
    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await ref.getDownloadURL();
  }

  Future<String> uploadThumbnailBytes({
    required String enterpriseId,
    required String userId,
    required String date,
    required Uint8List bytes,
    String? fileNameBase,
  }) async {
    final photoId = fileNameBase ?? _uuid.v4();
    final path =
        'enterprises/$enterpriseId/photos/$userId/$date/${photoId}_thumb.jpg';
    final ref = _storage.ref(path);
    await ref.putData(
      bytes,
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
    await _ensureSourceFileExists(file, contextLabel: 'uploadProfileImage');

    // Compress profile image
    Uint8List? compressed;
    try {
      compressed = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 300,
        minHeight: 300,
        quality: 80,
      );
      debugPrint(
        '[StorageService] uploadProfileImage compression result path=${file.path} bytes=${compressed?.lengthInBytes ?? 0}',
      );
    } catch (e) {
      debugPrint(
          '[StorageService] uploadProfileImage compression failed for ${file.path}: $e');
    }

    final ref = _storage.ref(path);
    if (compressed != null) {
      await ref.putData(
        compressed,
        SettableMetadata(contentType: 'image/jpeg'),
      );
    } else {
      await _ensureSourceFileExists(file,
          contextLabel: 'uploadProfileImage fallback');
      await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
    }

    return await ref.getDownloadURL();
  }

  // Upload a chat image and return the download URL
  // ImagePicker already constrains to 1200x1200 @ quality 80,
  // so skip redundant compression and upload directly.
  Future<String> uploadChatImage({
    required String enterpriseId,
    required String groupId,
    required File file,
  }) async {
    final photoId = _uuid.v4();
    final path = 'enterprises/$enterpriseId/chat/$groupId/$photoId.jpg';
    await _ensureSourceFileExists(file, contextLabel: 'uploadChatImage');

    final ref = _storage.ref(path);
    await ref.putFile(
      file,
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
