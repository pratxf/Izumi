import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/photo_model.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';

class PhotoRepository {
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  static const String _collection = 'photos';

  Future<PhotoModel> uploadPhoto({
    required File imageFile,
    required String enterpriseId,
    required String employeeId,
    required String sessionId,
    required String location,
    required double latitude,
    required double longitude,
    required Map<String, String> geotagData,
  }) async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    // Upload full-size image
    final imageUrl = await _storageService.uploadPhoto(
      enterpriseId: enterpriseId,
      userId: employeeId,
      date: dateStr,
      file: imageFile,
    );

    // Upload thumbnail
    String thumbnailUrl = '';
    try {
      thumbnailUrl = await _storageService.uploadThumbnail(
        enterpriseId: enterpriseId,
        userId: employeeId,
        date: dateStr,
        file: imageFile,
      );
    } catch (_) {}

    // Create Firestore document
    final photoData = PhotoModel(
      id: '',
      enterpriseId: enterpriseId,
      employeeId: employeeId,
      sessionId: sessionId,
      imageUrl: imageUrl,
      thumbnailUrl: thumbnailUrl,
      timestamp: now,
      location: location,
      latitude: latitude,
      longitude: longitude,
      geotagData: geotagData,
      createdAt: now,
    );

    final docRef =
        await _firestoreService.addDocument(_collection, photoData.toFirestore());

    return photoData.copyWith(id: docRef.id);
  }

  Future<List<PhotoModel>> getPhotosByEmployee(
    String employeeId, {
    DateTime? date,
    int? limit,
  }) async {
    final filters = <QueryFilter>[
      QueryFilter('employeeId', FilterOp.isEqualTo, employeeId),
    ];

    if (date != null) {
      final startOfDay = DateTime(date.year, date.month, date.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      filters.add(QueryFilter(
        'timestamp',
        FilterOp.isGreaterThanOrEqualTo,
        Timestamp.fromDate(startOfDay),
      ));
      filters.add(QueryFilter(
        'timestamp',
        FilterOp.isLessThan,
        Timestamp.fromDate(endOfDay),
      ));
    }

    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: filters,
      orderBy: 'timestamp',
      descending: true,
      limit: limit,
    );

    return snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)).toList();
  }

  Future<List<PhotoModel>> getPhotosByEnterprise(
    String enterpriseId, {
    int? limit,
  }) async {
    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: [
        QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
      ],
      orderBy: 'timestamp',
      descending: true,
      limit: limit,
    );

    return snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)).toList();
  }

  Future<List<PhotoModel>> getPhotosBySession(String sessionId) async {
    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: [
        QueryFilter('sessionId', FilterOp.isEqualTo, sessionId),
      ],
      orderBy: 'timestamp',
      descending: true,
    );

    return snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)).toList();
  }

  Future<void> deletePhoto(String photoId) async {
    await _firestoreService.deleteDocument(_collection, photoId);
  }

  Stream<List<PhotoModel>> streamPhotosByEmployee(String employeeId) {
    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('employeeId', FilterOp.isEqualTo, employeeId),
          ],
          orderBy: 'timestamp',
          descending: true,
        )
        .map((snapshot) =>
            snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)).toList());
  }

  Stream<List<PhotoModel>> streamPhotosByEnterprise(String enterpriseId) {
    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('enterpriseId', FilterOp.isEqualTo, enterpriseId),
          ],
          orderBy: 'timestamp',
          descending: true,
        )
        .map((snapshot) =>
            snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)).toList());
  }
}
