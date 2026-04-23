import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/photo_model.dart';
import '../models/upload_status.dart';
import '../offline_queue/offline_job.dart';
import '../offline_queue/offline_job_store.dart';
import '../offline_queue/offline_queue_manager.dart';
import '../offline_queue/persistent_media_file_manager.dart';
import '../repositories/photo_repository.dart';
import '../services/image_processing_service.dart';
import '../services/storage_service.dart';

class PhotoProvider extends ChangeNotifier {
  final PhotoRepository _photoRepo = PhotoRepository();
  final OfflineJobStore _offlineJobStore = OfflineJobStore.instance;
  final OfflineQueueManager _offlineQueueManager = OfflineQueueManager.instance;

  List<PhotoModel> _photos = [];
  Map<String, List<PhotoModel>> _photosByDate = {};
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _photosSubscription;
  StreamSubscription<OfflineQueueJobEvent>? _queueEventsSubscription;

  final Map<String, PhotoModel> _optimisticPhotosByRequestId = {};
  final Map<String, Completer<PhotoModel?>> _uploadCompleters = {};

  PhotoProvider() {
    unawaited(_initializeOfflineQueue());
  }

  List<PhotoModel> get photos => _photos;
  Map<String, List<PhotoModel>> get photosByDate => _photosByDate;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> _initializeOfflineQueue() async {
    await _offlineQueueManager.start();
    await _queueEventsSubscription?.cancel();
    _queueEventsSubscription = _offlineQueueManager.events.listen(
      _handleQueueEvent,
    );
  }

  Future<void> loadPhotos(
    String employeeId, {
    required String enterpriseId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final remotePhotos = await _photoRepo.getPhotosByEmployee(
        employeeId,
        enterpriseId: enterpriseId,
      );
      _applyRemotePhotos(remotePhotos);
      await _hydrateQueuedPhotos(
        (payload) => payload['employeeId']?.toString() == employeeId,
      );
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  void streamPhotos(
    String employeeId, {
    required String enterpriseId,
  }) {
    debugPrint(
        '[PhotoProvider] streamPhotos called for employeeId=$employeeId');
    if (employeeId.isEmpty) {
      debugPrint('[PhotoProvider] ERROR: employeeId is empty, skipping stream');
      return;
    }
    _photosSubscription?.cancel();
    _photosSubscription = _photoRepo.streamPhotosByEmployee(employeeId).listen(
      (photos) {
        debugPrint('[PhotoProvider] stream received ${photos.length} photos');
        _applyRemotePhotos(photos);
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[PhotoProvider] stream error: $e');
        loadPhotos(employeeId, enterpriseId: enterpriseId);
      },
    );
    unawaited(_hydrateQueuedPhotos(
      (payload) => payload['employeeId']?.toString() == employeeId,
    ));
  }

  void streamTeamPhotos(
    List<String> employeeIds, {
    required String enterpriseId,
  }) {
    debugPrint(
      '[PhotoProvider] streamTeamPhotos called for ${employeeIds.length} employees',
    );
    if (employeeIds.isEmpty) return;
    _photosSubscription?.cancel();
    _isLoading = true;
    notifyListeners();
    _photosSubscription =
        _photoRepo.streamPhotosByEmployeeIds(
          employeeIds,
          enterpriseId: enterpriseId,
        ).listen(
      (photos) {
        debugPrint(
            '[PhotoProvider] team stream received ${photos.length} photos');
        _applyRemotePhotos(photos);
        _isLoading = false;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[PhotoProvider] streamTeamPhotos error: $e');
        _isLoading = false;
        notifyListeners();
      },
    );
    final employeeIdSet = employeeIds.toSet();
    unawaited(_hydrateQueuedPhotos(
      (payload) => employeeIdSet.contains(payload['employeeId']?.toString()),
    ));
  }

  void streamPhotosForEnterprise(String enterpriseId) {
    _photosSubscription?.cancel();
    _isLoading = true;
    notifyListeners();
    _photosSubscription =
        _photoRepo.streamPhotosByEnterprise(enterpriseId).listen(
      (photos) {
        _applyRemotePhotos(photos);
        _isLoading = false;
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[PhotoProvider] streamPhotosForEnterprise error: $e');
        _isLoading = false;
        notifyListeners();
        getPhotosByEnterprise(enterpriseId);
      },
    );
    unawaited(_hydrateQueuedPhotos(
      (payload) => payload['enterpriseId']?.toString() == enterpriseId,
    ));
  }

  Future<void> getPhotosByEnterprise(String enterpriseId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final remotePhotos = await _photoRepo.getPhotosByEnterprise(
        enterpriseId,
        limit: 500,
      );
      _applyRemotePhotos(remotePhotos);
      await _hydrateQueuedPhotos(
        (payload) => payload['enterpriseId']?.toString() == enterpriseId,
      );
    } catch (e) {
      _error = e.toString();
      debugPrint('[PhotoProvider] getPhotosByEnterprise error: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  final StorageService _storageService = StorageService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<PhotoModel?> uploadPhoto({
    required File imageFile,
    required String enterpriseId,
    required String employeeId,
    required String sessionId,
    required String location,
    required double latitude,
    required double longitude,
    String? category,
    String? customerType,
    String? customerName,
    String? customerPhone,
    String? notes,
    String? groupId,
    bool hasFollowUp = false,
    List<String> shareToGroupIds = const [],
    String? shareCaption,
    String? shareSenderId,
    String? shareSenderName,
    Map<String, dynamic>? followUpTask,
  }) async {
    _error = null;
    final now = DateTime.now();
    final clientRequestId = _nextClientRequestId();
    final geotagData = {
      'date': DateFormat('dd MMM yyyy').format(now),
      'time': DateFormat('HH:mm:ss a').format(now),
      'coordinates':
          'Lat: ${latitude.toStringAsFixed(4)} N | Long: ${longitude.toStringAsFixed(4)} E',
    };

    // Show local preview immediately
    final localPhoto = PhotoModel(
      id: 'local-$clientRequestId',
      clientRequestId: clientRequestId,
      enterpriseId: enterpriseId,
      employeeId: employeeId,
      sessionId: sessionId,
      imageUrl: imageFile.path,
      thumbnailUrl: imageFile.path,
      localFilePath: imageFile.path,
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
      uploadStatus: UploadStatus.pending,
    );

    _optimisticPhotosByRequestId[clientRequestId] = localPhoto;
    _uploadCompleters[clientRequestId] = Completer<PhotoModel?>();
    _mergeCurrentPhotos();
    notifyListeners();

    // Direct upload — no offline queue, no compression, just like chat camera
    try {
      final rawBytes = await imageFile.readAsBytes();
      Uint8List fullImageBytes = rawBytes;
      Uint8List thumbnailBytes = rawBytes;

      // Try compression to fix EXIF rotation and reduce size
      try {
        final processed = await ImageProcessingService.preparePhotoForUpload(
          imageFile,
        ).timeout(const Duration(seconds: 20));
        fullImageBytes = processed.imageBytes ?? rawBytes;
        thumbnailBytes = processed.thumbnailBytes ?? fullImageBytes;
      } catch (_) {
        // Compression failed/timed out — upload raw bytes
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(now);

      // Upload full image + thumbnail in parallel
      final uploadResults = await Future.wait([
        _storageService.uploadPhotoBytes(
          enterpriseId: enterpriseId,
          userId: employeeId,
          date: dateStr,
          bytes: fullImageBytes,
          fileNameBase: clientRequestId,
        ),
        _storageService
            .uploadThumbnailBytes(
              enterpriseId: enterpriseId,
              userId: employeeId,
              date: dateStr,
              bytes: thumbnailBytes,
              fileNameBase: clientRequestId,
            )
            .catchError((_) => ''),
      ]);
      final imageUrl = uploadResults[0];
      final thumbnailUrl = uploadResults[1];

      // Write Firestore doc
      final photoDocRef = _firestore.collection('photos').doc(clientRequestId);
      final photo = PhotoModel(
        id: photoDocRef.id,
        clientRequestId: clientRequestId,
        enterpriseId: enterpriseId,
        employeeId: employeeId,
        sessionId: sessionId,
        imageUrl: imageUrl,
        thumbnailUrl: thumbnailUrl,
        localFilePath: imageFile.path,
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
        uploadStatus: UploadStatus.success,
      );

      final batch = _firestore.batch();
      batch.set(photoDocRef, photo.toFirestore());

      // Share to chat groups if requested
      for (final chatGroupId in shareToGroupIds) {
        final messageRef = _firestore
            .collection('chatGroups')
            .doc(chatGroupId)
            .collection('messages')
            .doc('photo_share_$clientRequestId');
        batch.set(messageRef, {
          'senderId': shareSenderId ?? employeeId,
          'senderName': shareSenderName ?? '',
          'type': 'image',
          'imageUrl': imageUrl,
          if (thumbnailUrl.isNotEmpty) 'thumbnailUrl': thumbnailUrl,
          if (shareCaption != null) 'caption': shareCaption,
          'createdAt': Timestamp.fromDate(now),
        });
      }

      await batch.commit();

      // Update RTDB photo count
      try {
        await FirebaseDatabase.instance
            .ref('activeStats/$enterpriseId/$employeeId/photosToday')
            .set(ServerValue.increment(1));
      } catch (_) {}

      // Write photo_captured activity log directly from the client.
      // The Cloud Function also writes one — duplicates are deduplicated
      // by the feed service using document ID.
      unawaited(
        _firestore.collection('activityLogs').doc('photo_captured_${photo.id}').set({
          'enterpriseId': enterpriseId,
          'employeeId': employeeId,
          'sessionId': sessionId,
          'orgId': enterpriseId,
          'type': 'photo_captured',
          'title': 'Photo Captured',
          'detail': (() {
            final parts = [
              if (location.isNotEmpty) location,
              if (category != null && category.isNotEmpty) category,
              if (customerName != null && customerName.isNotEmpty) customerName,
            ];
            return parts.isEmpty ? 'Photo uploaded' : parts.join(' • ');
          })(),
          'timestamp': Timestamp.fromDate(now),
          'date': DateFormat('yyyy-MM-dd').format(now),
          'payload': {
            'photoId': photo.id,
            'photoUrl': imageUrl,
            'thumbnailUrl': thumbnailUrl,
          },
          'metadata': {
            'photoId': photo.id,
            'latitude': latitude,
            'longitude': longitude,
            'address': location,
            'imageUrl': imageUrl,
            'thumbnailUrl': thumbnailUrl,
            if (category != null) 'category': category,
            if (customerName != null) 'customerName': customerName,
            if (customerPhone != null) 'customerPhone': customerPhone,
            if (notes != null) 'notes': notes,
            'source': 'client_direct',
          },
        }, SetOptions(merge: true)).catchError((e) {
          debugPrint('[PhotoProvider] photo_captured activity log failed: $e');
        }),
      );

      // Update optimistic photo with uploaded URLs
      _optimisticPhotosByRequestId[clientRequestId] = photo;
      _mergeCurrentPhotos();
      notifyListeners();

      final completer = _uploadCompleters[clientRequestId];
      if (completer != null && !completer.isCompleted) {
        completer.complete(photo);
      }

      return photo;
    } catch (e) {
      _error = e.toString();
      _optimisticPhotosByRequestId[clientRequestId] = localPhoto.copyWith(
        uploadStatus: UploadStatus.error,
      );
      _mergeCurrentPhotos();
      notifyListeners();
      return localPhoto;
    }
  }

  Future<PhotoModel?> waitForUpload(String clientRequestId) async {
    final completer = _uploadCompleters[clientRequestId];
    if (completer == null) {
      return null;
    }
    return completer.future;
  }

  void retryUpload(String clientRequestId) {
    unawaited(_retryUploadInternal(clientRequestId));
  }

  Future<void> _retryUploadInternal(String clientRequestId) async {
    final optimisticPhoto = _optimisticPhotosByRequestId[clientRequestId];
    if (optimisticPhoto == null) {
      return;
    }

    final existingJob = await _offlineJobStore.getJobById(clientRequestId);
    if (existingJob == null) {
      return;
    }

    if (existingJob.status == OfflineJobStatus.pending ||
        existingJob.status == OfflineJobStatus.processing) {
      return;
    }

    _optimisticPhotosByRequestId[clientRequestId] = optimisticPhoto.copyWith(
      uploadStatus: UploadStatus.pending,
    );
    _mergeCurrentPhotos();
    notifyListeners();
    await _offlineQueueManager.retryJob(clientRequestId);
  }

  Future<bool> deletePhoto(String photoId) async {
    try {
      final requestId = photoId.replaceFirst('local-', '');
      final localPhoto = _optimisticPhotosByRequestId[requestId];
      _photos.removeWhere((p) => p.id == photoId);
      _optimisticPhotosByRequestId.remove(requestId);
      _groupPhotosByDate();
      notifyListeners();

      if (photoId.startsWith('local-')) {
        await _offlineJobStore.deleteJob(requestId);
        await PersistentMediaFileManager.instance
            .deleteIfExists(localPhoto?.localFilePath);
      } else {
        await _photoRepo.deletePhoto(photoId);
      }
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  List<PhotoModel> searchPhotos(String query) {
    if (query.isEmpty) return _photos;
    final lowerQuery = query.toLowerCase();
    return _photos
        .where((p) => p.location.toLowerCase().contains(lowerQuery))
        .toList();
  }

  int get todayCount {
    final today = DateTime.now();
    return _photos
        .where(
          (p) =>
              p.timestamp.year == today.year &&
              p.timestamp.month == today.month &&
              p.timestamp.day == today.day,
        )
        .length;
  }

  Future<void> _hydrateQueuedPhotos(
    bool Function(Map<String, dynamic> payload) predicate,
  ) async {
    final queuedJobs = await _offlineJobStore.getJobsByStatuses(
      const [
        OfflineJobStatus.pending,
        OfflineJobStatus.processing,
        OfflineJobStatus.error,
      ],
    );

    for (final job in queuedJobs) {
      if (job.type != OfflineJobType.photo || !predicate(job.payload)) {
        continue;
      }
      _optimisticPhotosByRequestId[job.id] = _queuedPhotoFromJob(job);
    }

    _mergeCurrentPhotos();
    notifyListeners();
  }

  void _applyRemotePhotos(List<PhotoModel> remotePhotos) {
    final dedupedRemotePhotos = _dedupePhotos(remotePhotos);
    final streamedRequestIds = remotePhotos
        .map((photo) => photo.clientRequestId)
        .whereType<String>()
        .toSet();

    _optimisticPhotosByRequestId.removeWhere(
      (requestId, _) => streamedRequestIds.contains(requestId),
    );

    _photos = dedupedRemotePhotos;
    _mergeCurrentPhotos();
  }

  void _mergeCurrentPhotos() {
    final optimisticPhotos = _optimisticPhotosByRequestId.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final merged = [...optimisticPhotos, ..._photos];
    merged.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    _photos = _dedupePhotos(merged);
    _groupPhotosByDate();
  }

  List<PhotoModel> _dedupePhotos(List<PhotoModel> photos) {
    final byKey = <String, PhotoModel>{};
    for (final photo in photos) {
      final clientRequestId = photo.clientRequestId?.trim();
      final dedupeKey = (clientRequestId != null && clientRequestId.isNotEmpty)
          ? 'req:$clientRequestId'
          : 'doc:${photo.id}';
      byKey.putIfAbsent(dedupeKey, () => photo);
    }

    final deduped = byKey.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return deduped;
  }

  void _groupPhotosByDate() {
    _photosByDate = {};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final photo in _photos) {
      final photoDate = DateTime(
          photo.timestamp.year, photo.timestamp.month, photo.timestamp.day);

      String dateKey;
      if (photoDate == today) {
        dateKey = 'Today';
      } else if (photoDate == yesterday) {
        dateKey = 'Yesterday';
      } else {
        dateKey = DateFormat('dd MMM yyyy').format(photo.timestamp);
      }

      _photosByDate.putIfAbsent(dateKey, () => []).add(photo);
    }
  }

  void _handleQueueEvent(OfflineQueueJobEvent event) {
    if (event.type != OfflineJobType.photo) {
      return;
    }

    final currentPhoto = _optimisticPhotosByRequestId[event.jobId];
    if (event.status == UploadStatus.error) {
      _error = event.error?.toString();
      if (currentPhoto != null) {
        _optimisticPhotosByRequestId[event.jobId] = currentPhoto.copyWith(
          uploadStatus: UploadStatus.error,
        );
      }
    } else if (event.status == UploadStatus.success) {
      final uploadedPhoto = event.photo;
      if (currentPhoto != null && uploadedPhoto != null) {
        _optimisticPhotosByRequestId[event.jobId] = currentPhoto.copyWith(
          id: uploadedPhoto.id,
          imageUrl: uploadedPhoto.imageUrl,
          thumbnailUrl: uploadedPhoto.thumbnailUrl,
          uploadStatus: UploadStatus.success,
        );
      }
      final completer = _uploadCompleters[event.jobId];
      if (completer != null && !completer.isCompleted) {
        completer.complete(uploadedPhoto);
      }
    }

    _mergeCurrentPhotos();
    notifyListeners();
  }

  PhotoModel _queuedPhotoFromJob(OfflineJob job) {
    final payload = job.payload;
    final createdAtMs = (payload['createdAtMs'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final timestampMs =
        (payload['timestampMs'] as num?)?.toInt() ?? createdAtMs;
    final localFilePath = job.localFilePath ?? '';

    return PhotoModel(
      id: 'local-${job.id}',
      clientRequestId: job.id,
      enterpriseId: payload['enterpriseId']?.toString() ?? '',
      employeeId: payload['employeeId']?.toString() ?? '',
      sessionId: payload['sessionId']?.toString() ?? '',
      imageUrl: localFilePath,
      thumbnailUrl: localFilePath,
      localFilePath: localFilePath,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      location: payload['location']?.toString() ?? '',
      latitude: (payload['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (payload['longitude'] as num?)?.toDouble() ?? 0,
      geotagData: (payload['geotagData'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          const <String, String>{},
      category: payload['category']?.toString(),
      customerType: payload['customerType']?.toString(),
      customerName: payload['customerName']?.toString(),
      customerPhone: payload['customerPhone']?.toString(),
      notes: payload['notes']?.toString(),
      groupId: payload['groupId']?.toString(),
      hasFollowUp: payload['hasFollowUp'] == true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      uploadStatus: job.status == OfflineJobStatus.error
          ? UploadStatus.error
          : UploadStatus.pending,
    );
  }

  String _nextClientRequestId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  @override
  void dispose() {
    _photosSubscription?.cancel();
    _queueEventsSubscription?.cancel();
    super.dispose();
  }
}
