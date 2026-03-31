import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/chat_message_model.dart';
import '../models/photo_model.dart';
import '../models/task_model.dart';
import '../models/upload_status.dart';
import '../repositories/chat_repository.dart';
import '../services/image_processing_service.dart';
import '../services/storage_service.dart';
import 'offline_job.dart';
import 'offline_job_store.dart';
import 'persistent_media_file_manager.dart';

class OfflineQueueJobEvent {
  const OfflineQueueJobEvent({
    required this.jobId,
    required this.type,
    required this.status,
    this.chatMessage,
    this.photo,
    this.error,
  });

  final String jobId;
  final OfflineJobType type;
  final UploadStatus status;
  final ChatMessageModel? chatMessage;
  final PhotoModel? photo;
  final Object? error;
}

class OfflineQueueManager {
  OfflineQueueManager._();

  static final OfflineQueueManager instance = OfflineQueueManager._();

  static const Duration _baseRetryDelay = Duration(seconds: 30);
  static const int _maxRetryExponent = 6;
  static const Duration _staleProcessingTimeout = Duration(minutes: 1);

  final OfflineJobStore _jobStore = OfflineJobStore.instance;
  final ChatRepository _chatRepository = ChatRepository();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StorageService _storageService = StorageService();
  final StreamController<OfflineQueueJobEvent> _eventsController =
      StreamController<OfflineQueueJobEvent>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _initialized = false;
  bool _isProcessing = false;
  bool _processAgain = false;
  bool _isOnline = true;
  int? _lastProcessingStartMs;

  Stream<OfflineQueueJobEvent> get events => _eventsController.stream;

  Future<void> start() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    final connectivityResults = await Connectivity().checkConnectivity();
    _isOnline = _hasNetwork(connectivityResults);

    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = _hasNetwork(results);
      if (!wasOnline && _isOnline) {
        unawaited(processQueue(reason: 'connectivity_restored'));
      }
    });

    await _recoverStaleProcessingJobs();

    if (_isOnline) {
      unawaited(processQueue(reason: 'startup'));
    }
  }

  Future<void> processQueue({String reason = 'manual'}) async {
    await start();

    if (_isProcessing) {
      // Force-break if processing has been stuck for > 2 minutes
      final startMs = _lastProcessingStartMs;
      if (startMs != null &&
          DateTime.now().millisecondsSinceEpoch - startMs > 120000) {
        _isProcessing = false;
        _lastProcessingStartMs = null;
      } else {
        _processAgain = true;
        return;
      }
    }

    if (!_isOnline) {
      debugPrint(
          '[OfflineQueueManager] Skip processing while offline ($reason)');
      return;
    }

    await _recoverStaleProcessingJobs();

    _isProcessing = true;
    _lastProcessingStartMs = DateTime.now().millisecondsSinceEpoch;
    try {
      do {
        _processAgain = false;
        final job = await _nextEligibleJob();
        if (job == null) {
          break;
        }

        await _markJobProcessing(job);
        // Timeout entire job processing at 60s to prevent permanent hang
        try {
          await _processJob(job).timeout(const Duration(seconds: 60));
        } on TimeoutException {
          final failedJob = await _jobStore.getJobById(job.id) ?? job;
          await _jobStore.upsertJob(
            failedJob.copyWith(
              status: OfflineJobStatus.error,
              retryCount: failedJob.retryCount + 1,
              lastAttemptAtMs: DateTime.now().millisecondsSinceEpoch,
              nextAttemptAtMs:
                  DateTime.now().add(const Duration(seconds: 30)).millisecondsSinceEpoch,
            ),
          );
          _emitEvent(
            OfflineQueueJobEvent(
              jobId: job.id,
              type: job.type,
              status: UploadStatus.error,
              error: 'Upload timed out after 60 seconds',
            ),
          );
        }
      } while (_isOnline);
    } finally {
      _isProcessing = false;
      _lastProcessingStartMs = null;
      if (_processAgain && _isOnline) {
        unawaited(processQueue(reason: 'rerun_requested'));
      }
    }
  }

  /// Reset backoff on all errored/stuck jobs and process immediately.
  Future<void> retryAllNow() async {
    final jobs = await _jobStore.getJobsByStatuses(
      const [OfflineJobStatus.error, OfflineJobStatus.processing],
    );
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final job in jobs) {
      // Reset stuck processing jobs and errored jobs
      final isStaleProcessing = job.status == OfflineJobStatus.processing &&
          (job.lastAttemptAtMs == null ||
              nowMs - job.lastAttemptAtMs! > 60000);
      if (job.status == OfflineJobStatus.error || isStaleProcessing) {
        await _jobStore.upsertJob(
          job.copyWith(
            status: OfflineJobStatus.pending,
            nextAttemptAtMs: nowMs,
            clearLastAttemptAtMs: true,
          ),
        );
      }
    }
    if (jobs.isNotEmpty) {
      await processQueue(reason: 'retry_all');
    }
  }

  Future<void> retryJob(String jobId) async {
    final job = await _jobStore.getJobById(jobId);
    if (job == null) {
      return;
    }

    await _jobStore.upsertJob(
      job.copyWith(
        status: OfflineJobStatus.pending,
        nextAttemptAtMs: DateTime.now().millisecondsSinceEpoch,
        clearLastAttemptAtMs: true,
      ),
    );

    _emitEvent(
      OfflineQueueJobEvent(
        jobId: job.id,
        type: job.type,
        status: UploadStatus.pending,
        chatMessage: job.type == OfflineJobType.chat
            ? _chatMessageFromPayload(job)
            : null,
        photo: job.type == OfflineJobType.photo ? _photoFromPayload(job) : null,
      ),
    );

    await processQueue(reason: 'manual_retry');
  }

  Future<OfflineJob?> _nextEligibleJob() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final jobs = await _jobStore.getJobsByStatuses(
      const [
        OfflineJobStatus.pending,
        OfflineJobStatus.error,
      ],
    );

    for (final job in jobs) {
      if (job.status == OfflineJobStatus.pending) {
        return job;
      }
      final nextAttemptAtMs = job.nextAttemptAtMs ?? 0;
      if (nextAttemptAtMs <= nowMs) {
        return job;
      }
    }
    return null;
  }

  Future<void> _recoverStaleProcessingJobs() async {
    final processingJobs = await _jobStore.getJobsByStatuses(
      const [OfflineJobStatus.processing],
    );
    if (processingJobs.isEmpty) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    for (final job in processingJobs) {
      final lastAttemptAtMs = job.lastAttemptAtMs;
      final isStale = lastAttemptAtMs == null ||
          nowMs - lastAttemptAtMs >= _staleProcessingTimeout.inMilliseconds;
      if (!isStale) {
        continue;
      }

      await _jobStore.upsertJob(
        job.copyWith(
          status: OfflineJobStatus.error,
          nextAttemptAtMs: nowMs,
        ),
      );

      _emitEvent(
        OfflineQueueJobEvent(
          jobId: job.id,
          type: job.type,
          status: UploadStatus.error,
          chatMessage: job.type == OfflineJobType.chat
              ? _chatMessageFromPayload(job)
              : null,
          photo: job.type == OfflineJobType.photo ? _photoFromPayload(job) : null,
          error: StateError('Recovered stale queued job'),
        ),
      );
    }
  }

  Future<void> _markJobProcessing(OfflineJob job) async {
    await _jobStore.upsertJob(
      job.copyWith(
        status: OfflineJobStatus.processing,
        lastAttemptAtMs: DateTime.now().millisecondsSinceEpoch,
        clearNextAttemptAtMs: true,
      ),
    );
  }

  Future<void> _processJob(OfflineJob job) async {
    try {
      switch (job.type) {
        case OfflineJobType.chat:
          final sentMessage = await _processChatJob(job);
          await _jobStore.deleteJob(job.id);
          _emitEvent(
            OfflineQueueJobEvent(
              jobId: job.id,
              type: job.type,
              status: UploadStatus.success,
              chatMessage: sentMessage,
            ),
          );
          break;
        case OfflineJobType.photo:
          final uploadedPhoto = await _processPhotoJob(job);
          await _jobStore.deleteJob(job.id);
          await PersistentMediaFileManager.instance
              .deleteIfExists(job.localFilePath);
          _emitEvent(
            OfflineQueueJobEvent(
              jobId: job.id,
              type: job.type,
              status: UploadStatus.success,
              photo: uploadedPhoto,
            ),
          );
          break;
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[OfflineQueueManager] Job ${job.id} (${job.type.name}) FAILED: $error\n$stackTrace',
      );
      final failedJob = await _jobStore.getJobById(job.id) ?? job;
      final updatedRetryCount = failedJob.retryCount + 1;
      final backoffDelay = _backoffDuration(updatedRetryCount);
      await _jobStore.upsertJob(
        failedJob.copyWith(
          status: OfflineJobStatus.error,
          retryCount: updatedRetryCount,
          lastAttemptAtMs: DateTime.now().millisecondsSinceEpoch,
          nextAttemptAtMs:
              DateTime.now().add(backoffDelay).millisecondsSinceEpoch,
        ),
      );

      _emitEvent(
        OfflineQueueJobEvent(
          jobId: failedJob.id,
          type: failedJob.type,
          status: UploadStatus.error,
          chatMessage: failedJob.type == OfflineJobType.chat
              ? _chatMessageFromPayload(failedJob)
              : null,
          photo: failedJob.type == OfflineJobType.photo
              ? _photoFromPayload(failedJob)
              : null,
          error: error,
        ),
      );
      debugPrint(
        '[OfflineQueueManager] Job ${failedJob.id} failed (retry=$updatedRetryCount): $error',
      );
    }
  }

  Future<ChatMessageModel> _processChatJob(OfflineJob job) async {
    final payload = job.payload;
    final groupId = payload['groupId']?.toString() ?? '';
    if (groupId.isEmpty) {
      throw StateError('Chat job missing groupId');
    }

    final message = _chatMessageFromPayload(job);
    await _chatRepository.sendMessage(groupId, message, documentId: job.id);
    return message.copyWith(uploadStatus: UploadStatus.success);
  }

  Future<PhotoModel> _processPhotoJob(OfflineJob job) async {
    final filePath = job.localFilePath;
    if (filePath == null || filePath.isEmpty) {
      throw StateError('Photo job missing local file path');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException(
        'Queued media file no longer exists.',
        filePath,
      );
    }

    final payload = job.payload;
    final rawBytes = await file.readAsBytes();
    Uint8List fullImageBytes = rawBytes;
    Uint8List thumbnailBytes = rawBytes;

    // Try compression but don't block upload if it fails or hangs
    try {
      final processedImage = await ImageProcessingService.preparePhotoForUpload(
        file,
      ).timeout(const Duration(seconds: 20));
      fullImageBytes = processedImage.imageBytes ?? rawBytes;
      thumbnailBytes = processedImage.thumbnailBytes ?? fullImageBytes;
    } catch (_) {
      // Compression failed/timed out — upload raw bytes instead
    }
    final enterpriseId = payload['enterpriseId']?.toString() ?? '';
    final employeeId = payload['employeeId']?.toString() ?? '';
    final sessionId = payload['sessionId']?.toString() ?? '';
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      (payload['timestampMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      (payload['createdAtMs'] as num?)?.toInt() ??
          timestamp.millisecondsSinceEpoch,
    );
    final dateStr = DateFormat('yyyy-MM-dd').format(timestamp);

    final uploadResults = await Future.wait([
      _storageService.uploadPhotoBytes(
        enterpriseId: enterpriseId,
        userId: employeeId,
        date: dateStr,
        bytes: fullImageBytes,
        fileNameBase: job.id,
      ),
      _storageService
          .uploadThumbnailBytes(
            enterpriseId: enterpriseId,
            userId: employeeId,
            date: dateStr,
            bytes: thumbnailBytes,
            fileNameBase: job.id,
          )
          .catchError((_) => ''),
    ]);
    final imageUrl = uploadResults[0];
    final thumbnailUrl = uploadResults[1];

    final batch = _firestore.batch();
    final photoDocRef = _firestore.collection('photos').doc(job.id);
    final photo = PhotoModel(
      id: photoDocRef.id,
      clientRequestId: job.id,
      enterpriseId: enterpriseId,
      employeeId: employeeId,
      sessionId: sessionId,
      imageUrl: imageUrl,
      thumbnailUrl: thumbnailUrl,
      localFilePath: filePath,
      timestamp: timestamp,
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
      createdAt: createdAt,
      uploadStatus: UploadStatus.success,
    );
    batch.set(photoDocRef, photo.toFirestore());

    final shareToGroupIds = (payload['shareToGroupIds'] as List?)
            ?.map((entry) => entry.toString())
            .where((entry) => entry.trim().isNotEmpty)
            .toSet()
            .toList() ??
        const <String>[];
    final shareCaption = payload['shareCaption']?.toString();
    final shareSenderId = payload['shareSenderId']?.toString() ?? employeeId;
    final shareSenderName = payload['shareSenderName']?.toString() ?? '';

    for (final groupId in shareToGroupIds) {
      final messageRef = _firestore
          .collection('chatGroups')
          .doc(groupId)
          .collection('messages')
          .doc('photo_share_${job.id}');
      final sharedMessage = ChatMessageModel(
        id: messageRef.id,
        senderId: shareSenderId,
        senderName: shareSenderName,
        type: 'image',
        imageUrl: imageUrl,
        thumbnailUrl: thumbnailUrl.isNotEmpty ? thumbnailUrl : null,
        caption: shareCaption,
        createdAt: createdAt,
      );
      batch.set(messageRef, sharedMessage.toFirestore());
    }

    final followUpPayload = payload['followUpTask'];
    if (followUpPayload is Map) {
      final taskDocRef = _firestore.collection('tasks').doc('photo_followup_${job.id}');
      final dueDate = DateTime.fromMillisecondsSinceEpoch(
        (followUpPayload['dueDateMs'] as num?)?.toInt() ??
            createdAt.millisecondsSinceEpoch,
      );
      final taskCreatedAt = DateTime.fromMillisecondsSinceEpoch(
        (followUpPayload['createdAtMs'] as num?)?.toInt() ??
            createdAt.millisecondsSinceEpoch,
      );
      final taskUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
        (followUpPayload['updatedAtMs'] as num?)?.toInt() ??
            taskCreatedAt.millisecondsSinceEpoch,
      );
      final task = TaskModel(
        id: taskDocRef.id,
        enterpriseId:
            followUpPayload['enterpriseId']?.toString() ?? enterpriseId,
        title: followUpPayload['title']?.toString() ?? 'Follow-up',
        description: followUpPayload['description']?.toString(),
        type: followUpPayload['type']?.toString() ?? 'followup',
        priority: followUpPayload['priority']?.toString() ?? 'medium',
        status: followUpPayload['status']?.toString() ?? 'pending',
        assignedTo: followUpPayload['assignedTo']?.toString() ?? employeeId,
        assignedBy: followUpPayload['assignedBy']?.toString() ?? employeeId,
        assignedByName: followUpPayload['assignedByName']?.toString(),
        assignedToName: followUpPayload['assignedToName']?.toString(),
        groupId: followUpPayload['groupId']?.toString(),
        dueDate: dueDate,
        contactType: followUpPayload['contactType']?.toString(),
        contactPhone: followUpPayload['contactPhone']?.toString(),
        sendNotification: followUpPayload['sendNotification'] != false,
        createdAt: taskCreatedAt,
        updatedAt: taskUpdatedAt,
      );
      final taskData = task.toFirestore()
        ..addAll({
          'linkedPhotoId': photo.id,
          'linkedPhotoUrl': imageUrl,
          'linkedPhotoThumbnailUrl': thumbnailUrl,
          'linkedPhotoClientRequestId': job.id,
        });
      batch.set(taskDocRef, taskData);
    }

    final now = DateTime.now();
    final summaryDocId =
        '${employeeId}_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final summaryRef =
        _firestore.collection('dailySummaries').doc(summaryDocId);
    batch.set(
      summaryRef,
      {
        'employeeId': employeeId,
        'enterpriseId': enterpriseId,
        'date': Timestamp.fromDate(DateTime(now.year, now.month, now.day)),
        'photosCount': FieldValue.increment(1),
        'isOffDuty': false,
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    try {
      final rtdbRef = FirebaseDatabase.instance
          .ref('activeStats/$enterpriseId/$employeeId/photosToday');
      await rtdbRef.set(ServerValue.increment(1));
    } catch (_) {}
    return photo;
  }

  ChatMessageModel _chatMessageFromPayload(OfflineJob job) {
    final payload = job.payload;
    return ChatMessageModel(
      id: 'local-${job.id}',
      clientRequestId: job.id,
      senderId: payload['senderId']?.toString() ?? '',
      senderName: payload['senderName']?.toString() ?? '',
      type: payload['type']?.toString() ?? 'text',
      text: payload['text']?.toString(),
      imageUrl: payload['imageUrl']?.toString(),
      thumbnailUrl: payload['thumbnailUrl']?.toString(),
      latitude: (payload['latitude'] as num?)?.toDouble(),
      longitude: (payload['longitude'] as num?)?.toDouble(),
      address: payload['address']?.toString(),
      caption: payload['caption']?.toString(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (payload['createdAtMs'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      replyToId: payload['replyToId']?.toString(),
      replyToSenderName: payload['replyToSenderName']?.toString(),
      replyToText: payload['replyToText']?.toString(),
      replyToType: payload['replyToType']?.toString(),
      replyToImageUrl: payload['replyToImageUrl']?.toString(),
      uploadStatus: job.status == OfflineJobStatus.error
          ? UploadStatus.error
          : UploadStatus.pending,
    );
  }

  PhotoModel _photoFromPayload(OfflineJob job) {
    final payload = job.payload;
    final filePath = job.localFilePath ?? '';
    final createdAtMs = (payload['createdAtMs'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final timestampMs =
        (payload['timestampMs'] as num?)?.toInt() ?? createdAtMs;

    return PhotoModel(
      id: 'local-${job.id}',
      clientRequestId: job.id,
      enterpriseId: payload['enterpriseId']?.toString() ?? '',
      employeeId: payload['employeeId']?.toString() ?? '',
      sessionId: payload['sessionId']?.toString() ?? '',
      imageUrl: filePath,
      thumbnailUrl: filePath,
      localFilePath: filePath,
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

  Duration _backoffDuration(int retryCount) {
    final exponent = retryCount.clamp(0, _maxRetryExponent);
    final multiplier = 1 << exponent;
    return Duration(seconds: _baseRetryDelay.inSeconds * multiplier);
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  void _emitEvent(OfflineQueueJobEvent event) {
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    await _eventsController.close();
    _initialized = false;
  }
}
