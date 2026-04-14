import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/activity_log_model.dart';
import '../models/daily_summary_model.dart';
import '../models/photo_model.dart';
import '../models/session_model.dart';
import '../repositories/activity_log_repository.dart';
import '../repositories/photo_repository.dart';
import '../repositories/session_repository.dart';
import 'session_query_helper.dart';

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
    SessionQueryHelper? sessionQueryHelper,
  })  : _logRepo = logRepository ?? ActivityLogRepository(),
        _photoRepo = photoRepository ?? PhotoRepository(),
        _sessionRepo = sessionRepository ?? SessionRepository(),
        _sessionHelper = sessionQueryHelper ?? SessionQueryHelper();

  final ActivityLogRepository _logRepo;
  final PhotoRepository _photoRepo;
  final SessionRepository _sessionRepo;
  final SessionQueryHelper _sessionHelper;

  Future<AdminRangeActivityFeedData> loadRangeFeed({
    required String employeeId,
    required Iterable<String> linkedEmployeeIds,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? enterpriseId,
  }) async {
    final normalizedIds = _normalizeIds(linkedEmployeeIds);

    // ── 1. Load sessions via shared helper (cached + multi-layer fallback)
    var sessions = await _sessionHelper.loadSessions(
      enterpriseId: enterpriseId ?? '',
      startDate: rangeStart,
      endDate: rangeEnd,
      employeeIds: normalizedIds,
    );

    final sessionIds = sessions.map((s) => s.id).toSet().toList();

    // ── 2. Load activity logs + photos in parallel ──────────────────────
    final results = await Future.wait([
      _loadActivityLogs(normalizedIds, sessionIds, rangeStart, rangeEnd,
          enterpriseId: enterpriseId),
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

    // ── 5. Enterprise-wide photo sweep ──────────────────────────────
    // Always run the enterprise query to catch photos stored under old
    // (pre-migration) employeeIds that employee/session-scoped queries miss.
    // mergePhotos() deduplicates by document ID so duplicates are safe.
    List<PhotoModel> enterpriseFallbackPhotos = const [];
    final resolvedEnterpriseId = enterpriseId ??
        (sessions.isNotEmpty ? sessions.first.enterpriseId : null) ??
        (rawActivityLogs.isNotEmpty ? rawActivityLogs.first.enterpriseId : null);
    if (resolvedEnterpriseId != null && resolvedEnterpriseId.isNotEmpty) {
      try {
        final empIdSet = normalizedIds.toSet();
        final sessionIdSet = sessionIds.toSet();
        enterpriseFallbackPhotos =
            (await _photoRepo.getPhotosByEnterprise(
              resolvedEnterpriseId,
              startDate: rangeStart,
              endDate: rangeEnd,
              limit: 500,
            ))
                .where((photo) =>
                    empIdSet.contains(photo.employeeId) ||
                    sessionIdSet.contains(photo.sessionId))
                .toList();
        debugPrint(
          '[FeedService] enterprise photo sweep: ${enterpriseFallbackPhotos.length} photos',
        );
      } catch (e) {
        debugPrint('[FeedService] enterprise photo sweep failed: $e');
      }
    }

    // ── 6. Merge and deduplicate ────────────────────────────────────────
    final mergedActivities = mergeActivityLogs(allActivities);

    // Deduplicate session boundary events by type + sessionId + minute-bucket
    // (synthetic entries have generated IDs, so ID-based dedup misses them)
    final boundaryKeys = <String>{};
    mergedActivities.removeWhere((log) {
      if (log.type == 'session_started' || log.type == 'session_ended' || log.type == 'session_auto_ended') {
        final bucket = log.timestamp.toIso8601String().substring(0, 16);
        final key = '${log.type}_${log.sessionId}_$bucket';
        return !boundaryKeys.add(key);
      }
      return false;
    });

    // Sort ascending for history timeline (oldest first)
    mergedActivities.sort((a, b) => a.timestamp.compareTo(b.timestamp));

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
    DateTime rangeEnd, {
    String? enterpriseId,
  }) async {
    var logsByEmployee = <ActivityLogModel>[];
    try {
      logsByEmployee = await _logRepo.getLogsByEmployeeIds(
        employeeIds,
        startDate: rangeStart,
        endDate: rangeEnd,
        limit: 1000,
      );
    } catch (e) {
      debugPrint('[FeedService] getLogsByEmployeeIds failed: $e');
    }
    if (logsByEmployee.isEmpty) {
      try {
        logsByEmployee = (await _logRepo.getLogsByEmployeeIdsUnfiltered(
          employeeIds,
          limit: 1000,
        )).where((log) => _isInRange(log.timestamp, rangeStart, rangeEnd)).toList();
      } catch (e) {
        debugPrint('[FeedService] getLogsByEmployeeIdsUnfiltered failed: $e');
      }
    }

    var logsBySession = <ActivityLogModel>[];
    if (sessionIds.isNotEmpty) {
      try {
        logsBySession = await _logRepo.getLogsBySessionIds(
          sessionIds,
          startDate: rangeStart,
          endDate: rangeEnd,
          limit: 1000,
        );
      } catch (e) {
        debugPrint('[FeedService] getLogsBySessionIds failed: $e');
      }
      if (logsBySession.isEmpty) {
        try {
          logsBySession = (await _logRepo.getLogsBySessionIdsUnfiltered(
            sessionIds,
            limit: 1000,
          )).where((log) => _isInRange(log.timestamp, rangeStart, rangeEnd)).toList();
        } catch (e) {
          debugPrint('[FeedService] getLogsBySessionIdsUnfiltered failed: $e');
        }
      }
    }

    final combined = [...logsByEmployee, ...logsBySession];

    // Enterprise-wide activity log fallback — when employee/session scoped
    // queries return nothing (often due to missing composite indexes).
    if (combined.isEmpty &&
        enterpriseId != null &&
        enterpriseId.isNotEmpty) {
      try {
        final empIdSet = employeeIds.toSet();
        final enterpriseLogs = (await _logRepo.getLogsByEnterprise(
          enterpriseId,
          startDate: rangeStart,
          endDate: rangeEnd,
          limit: 1000,
        ))
            .where((log) => empIdSet.contains(log.employeeId))
            .toList();
        debugPrint(
          '[FeedService] enterprise activity log fallback: ${enterpriseLogs.length} logs',
        );
        return enterpriseLogs;
      } catch (e) {
        debugPrint('[FeedService] enterprise activity log fallback failed: $e');
      }
    }

    return combined;
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

    // ── Retry tracking — max 2 retries per stream, 5s delay ──
    const maxRetries = 2;
    const retryDelay = Duration(seconds: 5);
    int employeeLogRetries = 0;
    int sessionLogRetries = 0;
    int employeePhotoRetries = 0;
    int sessionPhotoRetries = 0;
    final pendingRetryTimers = <Timer>[];

    void scheduleRetry(int currentCount, void Function() retryFn) {
      if (controller.isClosed || currentCount >= maxRetries) return;
      final timer = Timer(retryDelay, () {
        if (controller.isClosed) return;
        retryFn();
      });
      pendingRetryTimers.add(timer);
    }

    void subscribeEmployeeLogs() {
      employeeLogSub?.cancel();
      employeeLogSub = _logRepo
          .streamLogsByEmployeeIdsSince(
            normalizedIds,
            since: since,
            limit: 1000,
          )
          .listen((logs) {
        employeeLogs = logs;
        emit();
      }, onError: (e) {
        debugPrint(
          '[FeedService] employeeLogSub error '
          '(retry ${employeeLogRetries + 1}/$maxRetries): $e',
        );
        emit();
        employeeLogRetries++;
        scheduleRetry(employeeLogRetries, subscribeEmployeeLogs);
      });
    }

    void subscribeEmployeePhotos() {
      employeePhotoSub?.cancel();
      employeePhotoSub = _photoRepo
          .streamPhotosByEmployeeIdsWithLimit(
            normalizedIds,
            limit: photoLimit,
          )
          .listen((photos) {
        employeePhotos = photos;
        emit();
      }, onError: (e) {
        debugPrint(
          '[FeedService] employeePhotoSub error '
          '(retry ${employeePhotoRetries + 1}/$maxRetries): $e',
        );
        emit();
        employeePhotoRetries++;
        scheduleRetry(employeePhotoRetries, subscribeEmployeePhotos);
      });
    }

    void attachSessionStreams(List<String> sessionIds) {
      sessionLogSub?.cancel();
      sessionPhotoSub?.cancel();
      sessionLogs = const [];
      sessionPhotos = const [];
      // Reset session-scoped retry counters when session set changes.
      sessionLogRetries = 0;
      sessionPhotoRetries = 0;

      if (sessionIds.isEmpty) {
        emit();
        return;
      }

      void subscribeSessionLogs() {
        sessionLogSub?.cancel();
        sessionLogSub = _logRepo
            .streamLogsBySessionIdsSince(
              sessionIds,
              since: since,
              limit: 1000,
            )
            .listen((logs) {
          sessionLogs = logs;
          emit();
        }, onError: (e) {
          debugPrint(
            '[FeedService] sessionLogSub error '
            '(retry ${sessionLogRetries + 1}/$maxRetries): $e',
          );
          emit();
          sessionLogRetries++;
          scheduleRetry(sessionLogRetries, subscribeSessionLogs);
        });
      }

      void subscribeSessionPhotos() {
        sessionPhotoSub?.cancel();
        sessionPhotoSub = _photoRepo
            .streamPhotosBySessionIds(
              sessionIds,
              limit: photoLimit,
            )
            .listen((photos) {
          sessionPhotos = photos;
          emit();
        }, onError: (e) {
          debugPrint(
            '[FeedService] sessionPhotoSub error '
            '(retry ${sessionPhotoRetries + 1}/$maxRetries): $e',
          );
          emit();
          sessionPhotoRetries++;
          scheduleRetry(sessionPhotoRetries, subscribeSessionPhotos);
        });
      }

      subscribeSessionLogs();
      subscribeSessionPhotos();
    }

    subscribeEmployeeLogs();
    subscribeEmployeePhotos();

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
      activeSessionIds = [];
      attachSessionStreams([]);
    });

    // Fallback: ensure the feed never stays blank if streams are slow
    Timer(const Duration(seconds: 4), () {
      if (!controller.isClosed) emit();
    });

    controller.onCancel = () async {
      for (final t in pendingRetryTimers) {
        t.cancel();
      }
      pendingRetryTimers.clear();
      await employeeLogSub?.cancel();
      await sessionLogSub?.cancel();
      await employeePhotoSub?.cancel();
      await sessionPhotoSub?.cancel();
      await sessionSub?.cancel();
    };

    return controller.stream;
  }

  List<ActivityLogModel> mergeActivityLogs(List<ActivityLogModel> logs) {
    return _dedupeAndThinLocationLogs(logs);
  }

  List<PhotoModel> mergePhotos(List<PhotoModel> photos) {
    final merged = <String, PhotoModel>{};
    for (final photo in photos) {
      merged[photo.id] = photo;
    }
    return merged.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Deduplicates activity logs by ID, then thins location_update entries
  /// to one per 20-minute window per session. Within each window, prefers
  /// entries with a named address over raw coordinates.
  ///
  /// This runs AFTER merge (which combines all sources: activityLogs collection,
  /// session subcollection fallback, synthetic boundary logs) so thinning
  /// applies uniformly regardless of where the entry originated.
  List<ActivityLogModel> _dedupeAndThinLocationLogs(List<ActivityLogModel> logs) {
    // Phase 1: deduplicate by ID
    final byId = <String, ActivityLogModel>{};
    for (final log in logs) {
      byId[log.id] = log;
    }
    final deduped = byId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp)); // ascending for thinning

    // Phase 2: thin location_update entries to one per 20-min window per session.
    // Track the last kept location timestamp per session.
    final lastKeptBySession = <String, DateTime>{};
    final thinned = <ActivityLogModel>[];

    for (final log in deduped) {
      if (log.type != 'location_update') {
        thinned.add(log);
        continue;
      }

      final sessionId = log.sessionId ?? '';

      // Within the current window, decide whether to keep this entry
      final lastKept = lastKeptBySession[sessionId];
      if (lastKept != null &&
          log.timestamp.difference(lastKept).abs() < _locationDisplayInterval) {
        // Same window — replace previous entry if this one has a better address
        final lastIndex = thinned.lastIndexWhere(
          (l) => l.type == 'location_update' && (l.sessionId ?? '') == sessionId,
        );
        if (lastIndex >= 0) {
          final existing = thinned[lastIndex];
          if (_hasRawCoordinateDetail(existing) && !_hasRawCoordinateDetail(log)) {
            thinned[lastIndex] = log;
          }
        }
        continue;
      }

      // New window — keep this entry
      lastKeptBySession[sessionId] = log.timestamp;
      thinned.add(log);
    }

    return thinned;
  }

  /// Returns true if a location entry's detail is raw coordinates rather
  /// than a resolved place name.
  bool _hasRawCoordinateDetail(ActivityLogModel log) {
    final detail = log.detail.trim();
    if (detail.isEmpty) return true;
    if (detail.startsWith('Lat:')) return true;
    // Starts with digit or minus sign → likely raw "29.7231, 77.5642"
    final firstChar = detail.codeUnitAt(0);
    if (firstChar >= 48 && firstChar <= 57) return true; // 0-9
    if (firstChar == 45) return true; // minus sign
    return false;
  }

  List<String> _normalizeIds(Iterable<String> ids) {
    return ids.where((id) => id.trim().isNotEmpty).toSet().toList();
  }

  bool _isInRange(DateTime timestamp, DateTime start, DateTime end) {
    final local = timestamp.toLocal();
    return !local.isBefore(start) && !local.isAfter(end);
  }

  /// Minimum interval between location entries shown in the feed.
  /// GPS polls happen every 60s but we only show one entry per this interval
  /// to avoid flooding the activity timeline.
  static const Duration _locationDisplayInterval = Duration(minutes: 20);

  Future<List<ActivityLogModel>> _loadLocationActivitiesForSessions(
    List<SessionModel> sessions, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    final locationActivities = <ActivityLogModel>[];

    // Load all session locations in parallel instead of sequentially
    final allLocations = await Future.wait(
      sessions.map((s) => _sessionRepo.getSessionLocations(s.id)),
    );

    for (var i = 0; i < sessions.length; i++) {
      final session = sessions[i];
      final locations = allLocations[i];

      // Thin out location_update entries to one per ~20-min window.
      // Keep non-location types (check_in, check_out, visit) always.
      DateTime? lastLocationShown;

      // Sort ascending so we pick the first location per window
      final sorted = List.of(locations)
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      for (final location in sorted) {
        if (!_isInRange(location.timestamp, rangeStart, rangeEnd)) {
          continue;
        }

        final isSpecialType = location.type == 'check_in' ||
            location.type == 'check_out' ||
            location.type == 'visit';

        if (!isSpecialType) {
          // Thin: skip if too close to the last shown location
          if (lastLocationShown != null &&
              location.timestamp.difference(lastLocationShown).abs() <
                  _locationDisplayInterval) {
            continue;
          }
          lastLocationShown = location.timestamp;
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
