import '../models/photo_model.dart';
import '../models/session_model.dart';

/// Lightweight in-memory cache for Firestore query results.
///
/// Prevents duplicate reads when multiple providers/screens request the
/// same sessions or photos within a short window (e.g. analytics screen
/// loads sessions, then employee history loads the same sessions again).
///
/// Entries expire after [ttl] (default 2 minutes) so stale data doesn't
/// persist across user actions.
class QueryCache {
  QueryCache._();
  static final instance = QueryCache._();

  static const Duration ttl = Duration(minutes: 2);

  final Map<String, _CacheEntry<List<SessionModel>>> _sessions = {};
  final Map<String, _CacheEntry<List<PhotoModel>>> _photos = {};

  // ── Sessions ──

  String _sessionKey(String enterpriseId, DateTime start, DateTime end) =>
      'sessions:$enterpriseId:${start.millisecondsSinceEpoch}:${end.millisecondsSinceEpoch}';

  List<SessionModel>? getSessions(
    String enterpriseId,
    DateTime start,
    DateTime end,
  ) {
    final entry = _sessions[_sessionKey(enterpriseId, start, end)];
    if (entry == null || entry.isExpired) return null;
    return entry.data;
  }

  void putSessions(
    String enterpriseId,
    DateTime start,
    DateTime end,
    List<SessionModel> data,
  ) {
    _sessions[_sessionKey(enterpriseId, start, end)] = _CacheEntry(data);
  }

  // ── Photos ──

  String _photoKey(String enterpriseId, DateTime start, DateTime end) =>
      'photos:$enterpriseId:${start.millisecondsSinceEpoch}:${end.millisecondsSinceEpoch}';

  List<PhotoModel>? getPhotos(
    String enterpriseId,
    DateTime start,
    DateTime end,
  ) {
    final entry = _photos[_photoKey(enterpriseId, start, end)];
    if (entry == null || entry.isExpired) return null;
    return entry.data;
  }

  void putPhotos(
    String enterpriseId,
    DateTime start,
    DateTime end,
    List<PhotoModel> data,
  ) {
    _photos[_photoKey(enterpriseId, start, end)] = _CacheEntry(data);
  }

  /// Clear all cached data (e.g. on logout or period change).
  void clear() {
    _sessions.clear();
    _photos.clear();
  }
}

class _CacheEntry<T> {
  _CacheEntry(this.data) : createdAt = DateTime.now();
  final T data;
  final DateTime createdAt;
  bool get isExpired => DateTime.now().difference(createdAt) > QueryCache.ttl;
}
