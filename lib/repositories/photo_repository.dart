import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/customer_suggestion_model.dart';
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
    String? category,
    String? customerType,
    String? customerName,
    String? customerPhone,
    String? notes,
    String? groupId,
    bool hasFollowUp = false,
    String? clientRequestId,
    Uint8List? compressedImageBytes,
    Uint8List? compressedThumbnailBytes,
  }) async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    // Upload full-size image and thumbnail in parallel
    final results = await Future.wait([
      compressedImageBytes != null
          ? _storageService.uploadPhotoBytes(
              enterpriseId: enterpriseId,
              userId: employeeId,
              date: dateStr,
              bytes: compressedImageBytes,
            )
          : _storageService.uploadPhoto(
              enterpriseId: enterpriseId,
              userId: employeeId,
              date: dateStr,
              file: imageFile,
            ),
      compressedThumbnailBytes != null
          ? _storageService
              .uploadThumbnailBytes(
                enterpriseId: enterpriseId,
                userId: employeeId,
                date: dateStr,
                bytes: compressedThumbnailBytes,
              )
              .catchError((_) => '')
          : _storageService
              .uploadThumbnail(
                enterpriseId: enterpriseId,
                userId: employeeId,
                date: dateStr,
                file: imageFile,
              )
              .catchError((_) => ''),
    ]);
    final imageUrl = results[0];
    final thumbnailUrl = results[1];

    // Create Firestore document
    final photoData = PhotoModel(
      id: '',
      clientRequestId: clientRequestId,
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
      category: category,
      customerType: customerType,
      customerName: customerName,
      customerPhone: customerPhone,
      notes: notes,
      groupId: groupId,
      hasFollowUp: hasFollowUp,
      createdAt: now,
    );

    final docRef = await _firestoreService.addDocument(
        _collection, photoData.toFirestore());

    return photoData.copyWith(id: docRef.id);
  }

  Future<List<PhotoModel>> getPhotosByEmployee(
    String employeeId, {
    DateTime? date,
    int? limit,
  }) async {
    return getPhotosByEmployeeIds(
      [employeeId],
      date: date,
      limit: limit,
    );
  }

  Future<List<PhotoModel>> getPhotosByEmployeeIds(
    List<String> employeeIds, {
    DateTime? date,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final normalizedIds =
        employeeIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) return const [];

    // Iterate per-ID to avoid whereIn + range-filter index conflict.
    // whereIn combined with timestamp inequality is not supported by Firestore
    // composite indexes and silently returns 0 results.
    final results = <PhotoModel>[];

    for (final empId in normalizedIds) {
      final filters = <QueryFilter>[
        QueryFilter('employeeId', FilterOp.isEqualTo, empId),
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
      } else {
        if (startDate != null) {
          filters.add(QueryFilter(
            'timestamp',
            FilterOp.isGreaterThanOrEqualTo,
            Timestamp.fromDate(startDate),
          ));
        }
        if (endDate != null) {
          filters.add(QueryFilter(
            'timestamp',
            FilterOp.isLessThanOrEqualTo,
            Timestamp.fromDate(endDate),
          ));
        }
      }

      final snapshot = await _firestoreService.getCollection(
        _collection,
        filters: filters,
        orderBy: 'timestamp',
        descending: true,
        limit: limit,
      );

      results.addAll(
        snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)),
      );
    }

    // Deduplicate and sort by timestamp desc
    final byId = <String, PhotoModel>{};
    for (final photo in results) {
      byId[photo.id] = photo;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (limit != null && merged.length > limit) {
      return merged.take(limit).toList();
    }
    return merged;
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
    );

    final photos = snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return photos;
  }

  Future<List<PhotoModel>> getPhotosBySessionIds(
    List<String> sessionIds, {
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final normalizedIds =
        sessionIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) return const [];

    // Iterate per-ID to avoid whereIn + range-filter index conflict.
    // whereIn combined with timestamp inequality silently returns 0 results.
    final results = <PhotoModel>[];
    for (final sessionId in normalizedIds) {
      final filters = <QueryFilter>[
        QueryFilter('sessionId', FilterOp.isEqualTo, sessionId),
        if (startDate != null)
          QueryFilter(
            'timestamp',
            FilterOp.isGreaterThanOrEqualTo,
            Timestamp.fromDate(startDate),
          ),
        if (endDate != null)
          QueryFilter(
            'timestamp',
            FilterOp.isLessThanOrEqualTo,
            Timestamp.fromDate(endDate),
          ),
      ];

      final snapshot = await _firestoreService.getCollection(
        _collection,
        filters: filters,
        orderBy: 'timestamp',
        descending: true,
        limit: limit,
      );

      results.addAll(
        snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)),
      );
    }

    final byId = <String, PhotoModel>{};
    for (final photo in results) {
      byId[photo.id] = photo;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (limit != null && merged.length > limit) {
      return merged.take(limit).toList();
    }
    return merged;
  }

  Future<List<PhotoModel>> getPhotosByEmployeeIdsUnfiltered(
    List<String> employeeIds, {
    int? limit,
  }) async {
    final normalizedIds =
        employeeIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) return const [];

    final results = <PhotoModel>[];
    // Query per-ID without orderBy to avoid requiring a composite index.
    // Firestore auto-creates single-field indexes, so equality-only queries
    // always work. We sort in memory below.
    for (final empId in normalizedIds) {
      final snapshot = await _firestoreService.getCollection(
        _collection,
        filters: [
          QueryFilter('employeeId', FilterOp.isEqualTo, empId),
        ],
        limit: limit,
      );

      results.addAll(
        snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)),
      );
    }

    final byId = <String, PhotoModel>{};
    for (final photo in results) {
      byId[photo.id] = photo;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (limit != null && merged.length > limit) {
      return merged.take(limit).toList();
    }
    return merged;
  }

  Future<List<PhotoModel>> getPhotosBySessionIdsUnfiltered(
    List<String> sessionIds, {
    int? limit,
  }) async {
    final normalizedIds =
        sessionIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) return const [];

    final results = <PhotoModel>[];
    // Query per-ID without orderBy to avoid composite index requirement.
    for (final sessionId in normalizedIds) {
      final snapshot = await _firestoreService.getCollection(
        _collection,
        filters: [
          QueryFilter('sessionId', FilterOp.isEqualTo, sessionId),
        ],
        limit: limit,
      );

      results.addAll(
        snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)),
      );
    }

    final byId = <String, PhotoModel>{};
    for (final photo in results) {
      byId[photo.id] = photo;
    }

    final merged = byId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (limit != null && merged.length > limit) {
      return merged.take(limit).toList();
    }
    return merged;
  }

  Future<List<PhotoModel>> getPhotosByIds(
    List<String> photoIds,
  ) async {
    final normalizedIds =
        photoIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalizedIds.isEmpty) return const [];

    final photos = <PhotoModel>[];
    for (final photoId in normalizedIds) {
      final doc = await _firestoreService.getDocument(_collection, photoId);
      if (!doc.exists) continue;
      photos.add(PhotoModel.fromFirestore(doc));
    }

    photos.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return photos;
  }

  Future<void> deletePhoto(String photoId) async {
    await _firestoreService.deleteDocument(_collection, photoId);
  }

  Stream<List<PhotoModel>> streamPhotosByEmployee(String employeeId) {
    return streamPhotosByEmployeeWithLimit(employeeId);
  }

  Stream<List<PhotoModel>> streamPhotosByEmployeeIdsWithLimit(
    List<String> employeeIds, {
    int? limit,
  }) {
    final normalized =
        employeeIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalized.isEmpty) return Stream.value(const <PhotoModel>[]);

    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            if (normalized.length == 1)
              QueryFilter('employeeId', FilterOp.isEqualTo, normalized.first)
            else
              QueryFilter('employeeId', FilterOp.whereIn, normalized),
          ],
          orderBy: 'timestamp',
          descending: true,
          limit: limit,
        )
        .map((snapshot) =>
            snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)).toList());
  }

  Stream<List<PhotoModel>> streamPhotosBySessionIds(
    List<String> sessionIds, {
    int? limit,
  }) {
    final normalized =
        sessionIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (normalized.isEmpty) return Stream.value(const <PhotoModel>[]);

    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            if (normalized.length == 1)
              QueryFilter('sessionId', FilterOp.isEqualTo, normalized.first)
            else
              QueryFilter('sessionId', FilterOp.whereIn, normalized),
          ],
          orderBy: 'timestamp',
          descending: true,
          limit: limit,
        )
        .map((snapshot) =>
            snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)).toList());
  }

  Stream<List<PhotoModel>> streamPhotosByEmployeeWithLimit(
    String employeeId, {
    int? limit,
  }) {
    return _firestoreService
        .streamCollection(
          _collection,
          filters: [
            QueryFilter('employeeId', FilterOp.isEqualTo, employeeId),
          ],
          orderBy: 'timestamp',
          descending: true,
          limit: limit,
        )
        .map((snapshot) =>
            snapshot.docs.map((doc) => PhotoModel.fromFirestore(doc)).toList());
  }

  Stream<List<PhotoModel>> streamPhotosByEmployeeIds(List<String> employeeIds) {
    return streamPhotosByEmployeeIdsWithLimit(employeeIds);
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

  Future<List<CustomerSuggestionModel>> getRecentCustomerSuggestions({
    required String employeeId,
    required String category,
    int limit = 120,
  }) async {
    final normalizedCategory = category.trim().toLowerCase();
    final snapshot = await _firestoreService.getCollection(
      _collection,
      filters: [
        QueryFilter('employeeId', FilterOp.isEqualTo, employeeId),
      ],
      orderBy: 'timestamp',
      descending: true,
      limit: limit,
    );

    final seenKeys = <String>{};
    final suggestions = <CustomerSuggestionModel>[];

    for (final doc in snapshot.docs) {
      final photo = PhotoModel.fromFirestore(doc);
      final name = photo.customerName?.trim() ?? '';
      if (name.isEmpty) continue;
      if ((photo.category ?? '').trim().toLowerCase() != normalizedCategory) {
        continue;
      }

      final dedupeKey =
          '${name.toLowerCase()}|${(photo.customerPhone ?? '').trim()}|$normalizedCategory';
      if (!seenKeys.add(dedupeKey)) continue;

      suggestions.add(
        CustomerSuggestionModel(
          customerName: name,
          customerPhone: photo.customerPhone?.trim().isNotEmpty == true
              ? photo.customerPhone!.trim()
              : null,
          category: photo.category,
          customerType: photo.customerType,
          notes: photo.notes?.trim().isNotEmpty == true
              ? photo.notes!.trim()
              : null,
          location:
              photo.location.trim().isNotEmpty ? photo.location.trim() : null,
          lastSeenAt: photo.timestamp,
        ),
      );
    }

    return suggestions;
  }
}
