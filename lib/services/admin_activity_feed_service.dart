import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/activity_log_model.dart';
import '../models/daily_summary_model.dart';
import '../models/photo_model.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import '../repositories/activity_log_repository.dart';
import '../repositories/photo_repository.dart';
import '../repositories/session_repository.dart';

class AdminRangeActivityFeedData {
  const AdminRangeActivityFeedData({
    required this.linkedEmployeeIds,
    required this.sessionIds,
    required this.sessions,
    required this.summary,
    required this.activities,
    required this.photos,
    this.totalSessionSeconds = 0,
    this.totalDistanceKm = 0.0,
    this.totalPhotos = 0,
  });

  final List<String> linkedEmployeeIds;
  final List<String> sessionIds;
  final List<SessionModel> sessions;
  final DailySummaryModel? summary;
  final List<ActivityLogModel> activities;
  final List<PhotoModel> photos;
  final int totalSessionSeconds;
  final double totalDistanceKm;
  final int totalPhotos;
}

class AdminRecentActivityFeedData {
  const AdminRecentActivityFeedData({
    required this.linkedEmployeeIds,
    required this.activeSessionIds,
    required this.activities,
    required this.photos,
  });

  final List<String> linkedEmployeeIds;
  final List<String> activeSessionIds;
  final List<ActivityLogModel> activities;
  final List<PhotoModel> photos;
}

class AdminActivityFeedService {
  AdminActivityFeedService({
    ActivityLogRepository? logRepository,
    PhotoRepository? photoRepository,
    SessionRepository? sessionRepository,
  })  : _logRepo = logRepository ?? ActivityLogRepository(),
        _photoRepo = photoRepository ?? PhotoRepository(),
        _sessionRepo = sessionRepository ?? SessionRepository();

  final ActivityLogRepository _logRepo;
  final PhotoRepository _photoRepo;
  final SessionRepository _sessionRepo;

  List<String> resolveLinkedEmployeeIds(
    String employeeId,
    Iterable<UserModel> employees, {
    Iterable<String> additionalIds = const [],
  }) {
    final ids = <String>{
      employeeId,
      ...additionalIds.where((id) => id.trim().isNotEmpty),
    };

    for (final employee in employees) {
      if (
          employee.id == employeeId ||
          employee.migratedFrom == employeeId ||
          ids.contains(employee.id) ||
          (employee.migratedFrom != null &&
              ids.contains(employee.migratedFrom))
      ) {
        ids.add(employee.id);
        final migratedFrom = employee.migratedFrom;
        if (migratedFrom != null && migratedFrom.trim().isNotEmpty) {
          ids.add(migratedFrom.trim());
        }
      }
    }

    return ids.toList();
  }

  Future<AdminRangeActivityFeedData> loadRangeFeed({
    required String employeeId,
    required Iterable<String> linkedEmployeeIds,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? enterpriseId,
  }) async {
    final normalizedIds = _normalizeIds(linkedEmployeeIds);

    // ── 1. Load sessions ────────────────────────────────────────────────
    var sessions = <SessionModel>[];
    try {
      sessions = await _sessionRepo.getSessionHistoryByEmployeeIds(
        normalizedIds,
        startDate: rangeStart,
        endDate: rangeEnd,
        limit: 300,
      );
    } catch (e) {
      debugPrint('[FeedService] sessions filtered query failed: $e');
      try {
        sessions = (await _sessionRepo.getSessionHistoryByEmployeeIdsUnfiltered(
          normalizedIds,
          limit: 500,
        )).where((session) {
          final sessionEnd = session.endTime ?? session.startTime;
          return !session.startTime.isAfter(rangeEnd) &&
              !sessionEnd.isBefore(rangeStart);
        }).toList();
      } catch (e2) {
        debugPrint('[FeedService] sessions unfiltered fallback also failed: $e2');
      }
    }

    final sessionIds = sessions.map((s) => s.id).toSet().toList();

    // ── 2. Load activity logs + photos in parallel ──────────────────────
    final results = await Future.wait([
      _loadActivityLogs(normalizedIds, sessionIds, rangeStart, rangeEnd),
      _loadAllPhotos(normalizedIds, sessionIds, rangeStart, rangeEnd),
    ]);

    final rawActivityLogs = results[0] as List<ActivityLogModel>;
    final rawPhotos = results[1] as List<PhotoModel>;

    // ── 3. Synthetic boundary logs + location fallback ──────────────────
    List<ActivityLogModel> sessionLocationActivities = const [];
    try {
      sessionLocationActivities = await _loadLocationActivitiesForSessions(
        sessions,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
    } catch (_) {}

    final allActivities = [
      ...rawActivityLogs,
      ...sessionLocationActivities,
      ..._buildSyntheticSessionBoundaryLogs(
        sessions: sessions,
        existingActivities: rawActivityLogs,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      ),
    ];

    // ── 4. Extract extra photos from activity log metadata ──────────────
    List<PhotoModel> photosFromActivityLogs = const [];
    try {
      photosFromActivityLogs = await _loadPhotosFromActivityLogs(
        allActivities,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
    } catch (e) {
      debugPrint('[FeedService] _loadPhotosFromActivityLogs failed: $e');
    }

    List<PhotoModel> sessionBackedPhotos = const [];
    try {
      sessionBackedPhotos = await _loadPhotosForSessions(
        sessions,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
    } catch (e) {
      debugPrint('[FeedService] _loadPhotosForSessions failed: $e');
    }

    // ── 5. Enterprise-wide photo fallback ─────────────────────────────
    // When all employee/session-scoped queries fail (often due to missing
    // Firestore composite indexes), query by enterprise ID (which works
    // reliably) and filter by employee+date in memory.
    List<PhotoModel> enterpriseFallbackPhotos = const [];
    final resolvedEnterpriseId = enterpriseId ??
        (sessions.isNotEmpty ? sessions.first.enterpriseId : null) ??
        (rawActivityLogs.isNotEmpty ? rawActivityLogs.first.enterpriseId : null);
    if (rawPhotos.isEmpty &&
        photosFromActivityLogs.isEmpty &&
        sessionBackedPhotos.isEmpty &&
        resolvedEnterpriseId != null &&
        resolvedEnterpriseId.isNotEmpty) {
      try {
        final empIdSet = normalizedIds.toSet();
        enterpriseFallbackPhotos =
            (await _photoRepo.getPhotosByEnterprise(resolvedEnterpriseId))
                .where((photo) =>
                    empIdSet.contains(photo.employeeId) &&
                    _isInRange(photo.timestamp, rangeStart, rangeEnd))
                .toList();
        debugPrint(
          '[FeedService] enterprise photo fallback: ${enterpriseFallbackPhotos.length} photos',
        );
      } catch (e) {
        debugPrint('[FeedService] enterprise photo fallback failed: $e');
      }
    }

    // ── 6. Merge and deduplicate ────────────────────────────────────────
    final mergedActivities = mergeActivityLogs(allActivities);
    final allPhotos = mergePhotos([
      ...rawPhotos,
      ..._loadPhotosFromActivityLogMetadata(allActivities),
      ...photosFromActivityLogs,
      ...sessionBackedPhotos,
      ...enterpriseFallbackPhotos,
    ]);

    // ── 7. Compute totals from sessions ─────────────────────────────────
    var totalSessionSeconds = 0;
    var totalDistanceKm = 0.0;
    for (final session in sessions) {
      totalSessionSeconds += session.totalDuration;
      totalDistanceKm += session.totalDistance;
    }

    final summary = DailySummaryModel(
      id: 'computed_${employeeId}_${rangeStart.toIso8601String().substring(0, 10)}',
      enterpriseId: sessions.isNotEmpty ? sessions.first.enterpriseId : '',
      employeeId: employeeId,
      date: rangeStart,
      totalDuration: totalSessionSeconds,
      totalDistance: totalDistanceKm,
      photosCount: allPhotos.length,
      tasksCompleted: 0,
      sessionIds: sessionIds,
    );

    return AdminRangeActivityFeedData(
      linkedEmployeeIds: normalizedIds,
      sessionIds: sessionIds,
      sessions: sessions,
      summary: totalSessionSeconds > 0 || allPhotos.isNotEmpty ? summary : null,
      activities: mergedActivities,
      photos: allPhotos,
      totalSessionSeconds: totalSessionSeconds,
      totalDistanceKm: totalDistanceKm,
      totalPhotos: allPhotos.length,
    );
  }

  Future<List<ActivityLogModel>> _loadActivityLogs(
    List<String> employeeIds,
    List<String> sessionIds,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) async {
    var logsByEmployee = <ActivityLogModel>[];
    try {
      logsByEmployee = await _logRepo.getLogsByEmployeeIds(
        employeeIds,
        startDate: rangeStart,
        endDate: rangeEnd,
        limit: 200,
      );
    } catch (_) {}
    if (logsByEmployee.isEmpty) {
      try {
        logsByEmployee = (await _logRepo.getLogsByEmployeeIdsUnfiltered(
          employeeIds,
          limit: 500,
        )).where((log) => _isInRange(log.timestamp, rangeStart, rangeEnd)).toList();
      } catch (_) {}
    }

    var logsBySession = <ActivityLogModel>[];
    if (sessionIds.isNotEmpty) {
      try {
        logsBySession = await _logRepo.getLogsBySessionIds(
          sessionIds,
          startDate: rangeStart,
          endDate: rangeEnd,
          limit: 300,
        );
      } catch (_) {}
      if (logsBySession.isEmpty) {
        try {
          logsBySession = (await _logRepo.getLogsBySessionIdsUnfiltered(
            sessionIds,
            limit: 500,
          )).where((log) => _isInRange(log.timestamp, rangeStart, rangeEnd)).toList();
        } catch (_) {}
      }
    }

    return [...logsByEmployee, ...logsBySession];
  }

  Future<List<PhotoModel>> _loadAllPhotos(
    List<String> employeeIds,
    List<String> sessionIds,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) async {
    var photosByEmployee = <PhotoModel>[];
    try {
      photosByEmployee = await _photoRepo.getPhotosByEmployeeIds(
        employeeIds,
        startDate: rangeStart,
        endDate: rangeEnd,
        limit: 500,
      );
    } catch (e) {
      debugPrint('[FeedService] getPhotosByEmployeeIds failed: $e');
    }
    if (photosByEmployee.isEmpty) {
      try {
        photosByEmployee = (await _photoRepo.getPhotosByEmployeeIdsUnfiltered(
          employeeIds,
          limit: 500,
        )).where((photo) => _isInRange(photo.timestamp, rangeStart, rangeEnd)).toList();
      } catch (e) {
        debugPrint('[FeedService] getPhotosByEmployeeIdsUnfiltered failed: $e');
      }
    }

    var photosBySession = <PhotoModel>[];
    if (sessionIds.isNotEmpty) {
      try {
        photosBySession = await _photoRepo.getPhotosBySessionIds(
          sessionIds,
          startDate: rangeStart,
          endDate: rangeEnd,
          limit: 500,
        );
      } catch (e) {
        debugPrint('[FeedService] getPhotosBySessionIds failed: $e');
      }
      if (photosBySession.isEmpty) {
        try {
          photosBySession = (await _photoRepo.getPhotosBySessionIdsUnfiltered(
            sessionIds,
            limit: 500,
          )).where((photo) => _isInRange(photo.timestamp, rangeStart, rangeEnd)).toList();
        } catch (e) {
          debugPrint('[FeedService] getPhotosBySessionIdsUnfiltered failed: $e');
        }
      }
    }

    return [...photosByEmployee, ...photosBySession];
  }

  Stream<AdminRecentActivityFeedData> streamRecentFeed({
    required Iterable<String> linkedEmployeeIds,
    Duration window = const Duration(hours: 24),
    int photoLimit = 24,
  }) {
    final normalizedIds = _normalizeIds(linkedEmployeeIds);
    final since = DateTime.now().subtract(window);
    final controller = StreamController<AdminRecentActivityFeedData>();

    StreamSubscription<List<ActivityLogModel>>? employeeLogSub;
    StreamSubscription<List<ActivityLogModel>>? sessionLogSub;
    StreamSubscription<List<PhotoModel>>? employeePhotoSub;
    StreamSubscription<List<PhotoModel>>? sessionPhotoSub;
    StreamSubscription<List<dynamic>>? sessionSub;

    List<String> activeSessionIds = const [];
    List<ActivityLogModel> employeeLogs = const [];
    List<ActivityLogModel> sessionLogs = const [];
    List<PhotoModel> employeePhotos = const [];
    List<PhotoModel> sessionPhotos = const [];

    void emit() {
      if (controller.isClosed) return;

      final allLogs = [...employeeLogs, ...sessionLogs]
          .where((log) => !log.timestamp.isBefore(since))
          .toList();

      // Merge direct photo streams with photos extracted from activity log
      // metadata as a fallback when Firestore photo queries fail.
      final streamedPhotos = [...employeePhotos, ...sessionPhotos]
          .where((photo) => !photo.timestamp.isBefore(since))
          .toList();
      final metadataPhotos = _loadPhotosFromActivityLogMetadata(allLogs);

      controller.add(
        AdminRecentActivityFeedData(
          linkedEmployeeIds: normalizedIds,
          activeSessionIds: activeSessionIds,
          activities: mergeActivityLogs(allLogs),
          photos: mergePhotos([...streamedPhotos, ...metadataPhotos]),
        ),
      );
    }

    void attachSessionStreams(List<String> sessionIds) {
      sessionLogSub?.cancel();
      sessionPhotoSub?.cancel();
      sessionLogs = const [];
      sessionPhotos = const [];

      if (sessionIds.isEmpty) {
        emit();
        return;
      }

      sessionLogSub = _logRepo
          .streamLogsBySessionIdsSince(
            sessionIds,
            since: since,
            limit: 300,
          )
          .listen((logs) {
        sessionLogs = logs;
        emit();
      }, onError: (e) {
        debugPrint('[FeedService] sessionLogSub error: $e');
        emit();
      });

      sessionPhotoSub = _photoRepo
          .streamPhotosBySessionIds(
            sessionIds,
            limit: photoLimit,
          )
          .listen((photos) {
        sessionPhotos = photos;
        emit();
      }, onError: (e) {
        debugPrint('[FeedService] sessionPhotoSub error: $e');
        emit();
      });
    }

    employeeLogSub = _logRepo
        .streamLogsByEmployeeIdsSince(
          normalizedIds,
          since: since,
          limit: 300,
        )
        .listen((logs) {
      employeeLogs = logs;
      emit();
    }, onError: (e) {
      debugPrint('[FeedService] employeeLogSub error: $e');
      emit();
    });

    employeePhotoSub = _photoRepo
        .streamPhotosByEmployeeIdsWithLimit(
          normalizedIds,
          limit: photoLimit,
        )
        .listen((photos) {
      employeePhotos = photos;
      emit();
    }, onError: (e) {
      debugPrint('[FeedService] employeePhotoSub error: $e');
      emit();
    });

    sessionSub = _sessionRepo
        .streamActiveSessionsByEmployeeIds(normalizedIds)
        .listen((sessions) {
      final nextSessionIds = sessions
          .map((session) => session.id)
          .where((id) => id.trim().isNotEmpty)
          .toSet()
          .toList();
      final changed =
          nextSessionIds.length != activeSessionIds.length ||
          !activeSessionIds.toSet().containsAll(nextSessionIds);
      activeSessionIds = nextSessionIds;
      if (changed) {
        attachSessionStreams(activeSessionIds);
      } else {
        emit();
      }
    }, onError: (e) {
      debugPrint('[FeedService] sessionSub error: $e');
      emit();
    });

    controller.onCancel = () async {
      await employeeLogSub?.cancel();
      await sessionLogSub?.cancel();
      await employeePhotoSub?.cancel();
      await sessionPhotoSub?.cancel();
      await sessionSub?.cancel();
    };

    return controller.stream;
  }

  List<ActivityLogModel> mergeActivityLogs(List<ActivityLogModel> logs) {
    final merged = <String, ActivityLogModel>{};
    for (final log in logs) {
      merged[log.id] = log;
    }
    return _dedupeLocationLogs(merged.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
  }

  List<PhotoModel> mergePhotos(List<PhotoModel> photos) {
    final merged = <String, PhotoModel>{};
    for (final photo in photos) {
      merged[photo.id] = photo;
    }
    return merged.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  List<ActivityLogModel> _dedupeLocationLogs(List<ActivityLogModel> logs) {
    final seenKeys = <String>{};
    final deduped = <ActivityLogModel>[];

    for (final log in logs) {
      final key = _activityDedupKey(log);
      if (!seenKeys.add(key)) continue;
      deduped.add(log);
    }
    return deduped;
  }

  String _activityDedupKey(ActivityLogModel log) {
    if (log.type != "location_update") {
      return "id:${log.id}";
    }
    final minuteBucket = DateTime(
      log.timestamp.year,
      log.timestamp.month,
      log.timestamp.day,
      log.timestamp.hour,
      log.timestamp.minute,
    );
    final lat =
        (log.metadata?["latitude"] as num?)?.toDouble().toStringAsFixed(5) ?? "";
    final lng =
        (log.metadata?["longitude"] as num?)?.toDouble().toStringAsFixed(5) ?? "";
    final detail = log.detail.trim().toLowerCase();
    final sessionId = log.sessionId ?? "";
    return "location|$sessionId|$minuteBucket|$lat|$lng|$detail";
  }

  List<String> _normalizeIds(Iterable<String> ids) {
    return ids.where((id) => id.trim().isNotEmpty).toSet().toList();
  }

  bool _isInRange(DateTime timestamp, DateTime start, DateTime end) {
    final local = timestamp.toLocal();
    return !local.isBefore(start) && !local.isAfter(end);
  }

  Future<List<ActivityLogModel>> _loadLocationActivitiesForSessions(
    List<SessionModel> sessions, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final locationActivities = <ActivityLogModel>[];

    for (final session in sessions) {
      final locations = await _sessionRepo.getSessionLocations(session.id);
      for (final location in locations) {
        if (!_isInRange(location.timestamp, rangeStart, rangeEnd)) {
          continue;
        }
        locationActivities.add(
          ActivityLogModel(
            id: 'session_location_${session.id}_${location.id}',
            enterpriseId: session.enterpriseId,
            employeeId: session.employeeId,
            sessionId: session.id,
            type: location.type,
            title:
                location.title.trim().isNotEmpty ? location.title : 'Location Update',
            detail: location.address.trim().isNotEmpty
                ? location.address
                : '${location.latitude}, ${location.longitude}',
            timestamp: location.timestamp,
            metadata: {
              'latitude': location.latitude,
              'longitude': location.longitude,
              'address': location.address,
              'source': 'session_locations_fallback',
            },
          ),
        );
      }
    }

    return locationActivities;
  }

  Future<List<PhotoModel>> _loadPhotosForSessions(
    List<SessionModel> sessions, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final photos = <PhotoModel>[];
    for (final session in sessions) {
      final sessionPhotos = await _photoRepo.getPhotosBySession(session.id);
      photos.addAll(
        sessionPhotos.where(
          (photo) => _isInRange(photo.timestamp, rangeStart, rangeEnd),
        ),
      );
    }
    return photos;
  }

  Future<List<PhotoModel>> _loadPhotosFromActivityLogs(
    List<ActivityLogModel> activities, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final photoIds = activities
        .where((activity) => activity.type == 'photo_captured')
        .map((activity) => activity.metadata?['photoId']?.toString())
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toSet()
        .toList();

    if (photoIds.isEmpty) {
      return const [];
    }

    final photos = await _photoRepo.getPhotosByIds(photoIds);
    return photos
        .where((photo) => _isInRange(photo.timestamp, rangeStart, rangeEnd))
        .toList();
  }

  List<PhotoModel> _loadPhotosFromActivityLogMetadata(
    List<ActivityLogModel> activities,
  ) {
    return activities
        .where((activity) => activity.type == 'photo_captured')
        .map((activity) {
          final metadata = activity.metadata;
          final payload = activity.payload;

          // Try metadata first, then payload for the image URL.
          // The Cloud Function writes imageUrl to metadata and photoUrl to payload.
          final imageUrl =
              metadata?['imageUrl']?.toString().trim() ??
              payload?['photoUrl']?.toString().trim() ??
              payload?['imageUrl']?.toString().trim() ??
              '';
          if (imageUrl.isEmpty) return null;

          final thumbnailUrl =
              metadata?['thumbnailUrl']?.toString().trim() ??
              payload?['thumbnailUrl']?.toString().trim() ??
              '';
          final photoId =
              metadata?['photoId']?.toString().trim() ??
              payload?['photoId']?.toString().trim() ??
              '';

          final timestamp = activity.timestamp;
          return PhotoModel(
            id: photoId.isNotEmpty ? photoId : activity.id,
            enterpriseId: activity.enterpriseId,
            employeeId: activity.employeeId,
            sessionId: activity.sessionId ?? '',
            imageUrl: imageUrl,
            thumbnailUrl: thumbnailUrl,
            timestamp: timestamp,
            location: metadata?['location']?.toString().trim() ??
                activity.detail.trim(),
            latitude:
                (metadata?['latitude'] as num?)?.toDouble() ?? 0.0,
            longitude:
                (metadata?['longitude'] as num?)?.toDouble() ?? 0.0,
            geotagData: const {},
            category: metadata?['category']?.toString(),
            customerName: metadata?['customerName']?.toString(),
            customerPhone: metadata?['customerPhone']?.toString(),
            notes: metadata?['notes']?.toString(),
            hasFollowUp: false,
            createdAt: timestamp,
          );
        })
        .whereType<PhotoModel>()
        .toList();
  }

  List<ActivityLogModel> _buildSyntheticSessionBoundaryLogs({
    required List<SessionModel> sessions,
    required List<ActivityLogModel> existingActivities,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final existingIds = existingActivities.map((activity) => activity.id).toSet();
    final syntheticLogs = <ActivityLogModel>[];

    for (final session in sessions) {
      final startedId = 'session_started_${session.id}';
      if (!existingIds.contains(startedId) &&
          _isInRange(session.startTime, rangeStart, rangeEnd)) {
        syntheticLogs.add(
          ActivityLogModel(
            id: startedId,
            enterpriseId: session.enterpriseId,
            employeeId: session.employeeId,
            sessionId: session.id,
            type: 'session_started',
            title: 'Session Started',
            detail: 'Field session started',
            timestamp: session.startTime,
            metadata: const {'source': 'session_history_fallback'},
          ),
        );
      }

      final endTime = session.endTime;
      if (endTime == null || !_isInRange(endTime, rangeStart, rangeEnd)) {
        continue;
      }

      final type = session.status == 'auto_ended'
          ? 'session_auto_ended'
          : 'session_ended';
      final endedId = '${type}_${session.id}';
      if (existingIds.contains(endedId)) {
        continue;
      }

      syntheticLogs.add(
        ActivityLogModel(
          id: endedId,
          enterpriseId: session.enterpriseId,
          employeeId: session.employeeId,
          sessionId: session.id,
          type: type,
          title: session.status == 'auto_ended'
              ? 'Session Auto Ended'
              : 'Session Ended',
          detail: session.formattedDuration,
          timestamp: endTime,
          metadata: const {'source': 'session_history_fallback'},
        ),
      );
    }

    return syntheticLogs;
  }
}
