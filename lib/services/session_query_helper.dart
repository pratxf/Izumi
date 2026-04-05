import 'package:flutter/foundation.dart';

import '../models/session_model.dart';
import '../repositories/daily_summary_repository.dart';
import '../repositories/session_repository.dart';
import 'query_cache.dart';

/// Consolidated session loading with multi-layer fallback.
///
/// Both [AnalyticsProvider] and [AdminActivityFeedService] need the same
/// fallback chain when loading sessions. This helper centralises that logic
/// so it is maintained in one place.
class SessionQueryHelper {
  SessionQueryHelper({
    SessionRepository? sessionRepo,
    DailySummaryRepository? summaryRepo,
  })  : _sessionRepo = sessionRepo ?? SessionRepository(),
        _summaryRepo = summaryRepo ?? DailySummaryRepository();

  final SessionRepository _sessionRepo;
  final DailySummaryRepository _summaryRepo;

  /// Load sessions for the given date range with up to 4 fallback layers.
  ///
  /// When [employeeIds] is provided, queries are scoped to those employees.
  /// Otherwise falls back to enterprise-wide queries.
  /// Results are cached via [QueryCache] so repeated calls are free.
  Future<List<SessionModel>> loadSessions({
    required String enterpriseId,
    required DateTime startDate,
    required DateTime endDate,
    List<String>? employeeIds,
    int limit = 1000,
  }) async {
    // Check cache first
    final cache = QueryCache.instance;
    final cached = cache.getSessions(enterpriseId, startDate, endDate);
    if (cached != null && cached.isNotEmpty) {
      if (employeeIds != null) {
        final idSet = employeeIds.toSet();
        return cached.where((s) => idSet.contains(s.employeeId)).toList();
      }
      return cached;
    }

    var sessions = <SessionModel>[];

    // Layer 1: Employee-scoped query with date range
    if (employeeIds != null && employeeIds.isNotEmpty && sessions.isEmpty) {
      try {
        sessions = await _sessionRepo.getSessionHistoryByEmployeeIds(
          employeeIds,
          startDate: startDate,
          endDate: endDate,
          limit: limit,
        );
      } catch (e) {
        debugPrint('[SessionQueryHelper] layer 1 (employee+date) failed: $e');
      }
    }

    // Layer 2: Employee-scoped unfiltered, filter in memory
    if (employeeIds != null && employeeIds.isNotEmpty && sessions.isEmpty) {
      try {
        sessions = (await _sessionRepo.getSessionHistoryByEmployeeIdsUnfiltered(
          employeeIds,
          limit: limit,
        ))
            .where((s) =>
                !s.startTime.isAfter(endDate) &&
                !(s.endTime ?? s.startTime).isBefore(startDate))
            .toList();
        if (sessions.isNotEmpty) {
          debugPrint(
            '[SessionQueryHelper] layer 2 (employee unfiltered): ${sessions.length}',
          );
        }
      } catch (e) {
        debugPrint('[SessionQueryHelper] layer 2 failed: $e');
      }
    }

    // Layer 3: Enterprise-wide query with date range
    if (sessions.isEmpty) {
      try {
        sessions = await _sessionRepo.getSessionsByEnterprise(
          enterpriseId,
          startDate: startDate,
          endDate: endDate,
          limit: limit,
        );
        if (employeeIds != null) {
          final idSet = employeeIds.toSet();
          sessions =
              sessions.where((s) => idSet.contains(s.employeeId)).toList();
        }
      } catch (e) {
        debugPrint('[SessionQueryHelper] layer 3 (enterprise+date) failed: $e');
      }
    }

    // Layer 4: Enterprise-wide unfiltered, filter in memory
    if (sessions.isEmpty) {
      try {
        sessions = (await _sessionRepo.getSessionsByEnterprise(
          enterpriseId,
          limit: limit,
        ))
            .where((s) =>
                !s.startTime.isBefore(startDate) &&
                !s.startTime.isAfter(endDate))
            .toList();
        if (employeeIds != null) {
          final idSet = employeeIds.toSet();
          sessions =
              sessions.where((s) => idSet.contains(s.employeeId)).toList();
        }
        if (sessions.isNotEmpty) {
          debugPrint(
            '[SessionQueryHelper] layer 4 (enterprise unfiltered): ${sessions.length}',
          );
        }
      } catch (e) {
        debugPrint('[SessionQueryHelper] layer 4 failed: $e');
      }
    }

    // Layer 5: DailySummary-based session discovery (last resort)
    if (sessions.isEmpty && employeeIds != null) {
      try {
        final summarySessionIds = <String>{};
        for (final empId in employeeIds) {
          final summaries = await _summaryRepo.getDailySummaries(
            empId,
            startDate: startDate,
            endDate: endDate,
          );
          for (final s in summaries) {
            summarySessionIds.addAll(s.sessionIds);
          }
        }
        if (summarySessionIds.isNotEmpty) {
          final loaded = <SessionModel>[];
          for (final sid in summarySessionIds) {
            final session = await _sessionRepo.getSession(sid);
            if (session != null) loaded.add(session);
          }
          sessions = loaded;
          debugPrint(
            '[SessionQueryHelper] layer 5 (daily summary): ${sessions.length}',
          );
        }
      } catch (e) {
        debugPrint('[SessionQueryHelper] layer 5 failed: $e');
      }
    }

    // Cache the enterprise-wide result for other callers
    if (sessions.isNotEmpty) {
      cache.putSessions(enterpriseId, startDate, endDate, sessions);
    }

    return sessions;
  }
}
