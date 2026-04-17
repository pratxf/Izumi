import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:izumi/core/ui/app_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_shadows.dart';
import '../../core/constants/app_typography.dart';
import '../../models/daily_summary_model.dart';
import '../../models/session_model.dart';
import '../../models/session_location_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/session_provider.dart';
import '../../repositories/daily_summary_repository.dart';
import '../../repositories/session_repository.dart';
import '../../services/realtime_db_service.dart';
import '../../services/unified_data_layer.dart';
import '../../widgets/glass/gradient_background.dart';
import '../../widgets/navigation/app_header.dart';

/// History Screen - Redesigned per reference
/// Shows monthly summary and daily session logs with timeline
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DailySummaryRepository _summaryRepo = DailySummaryRepository();
  final SessionRepository _sessionRepo = SessionRepository();
  final RealtimeDbService _rtdb = RealtimeDbService();

  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  int? _selectedDate; // null = show all days in month
  int? _expandedDay;
  bool _isLoading = true;
  bool? _wasSessionActive;

  Map<String, dynamic> _monthSummary = {};
  List<DailySummaryModel> _dailySummaries = [];
  // Cache: day index -> session models (for per-session distance)
  final Map<int, List<SessionModel>> _sessionCache = {};
  // Cache: day index -> per-session locations (parallel to _sessionCache)
  final Map<int, List<List<SessionLocationModel>>> _locationCache = {};
  // Which session within an expanded day is expanded (day index -> session index)
  int? _expandedSessionIndex;

  // Live RTDB activeStats for the current user's own in-progress session.
  // Used to add live distance/photos/tasks to today's card while the session
  // is running (before a dailySummary exists).
  StreamSubscription<DatabaseEvent>? _activeStatsSubscription;
  Map<String, dynamic>? _liveActiveStats;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String get _selectedMonthLabel =>
      '${_monthNames[_selectedMonth - 1]} $_selectedYear';

  List<DailySummaryModel> get _filteredSummaries {
    if (_selectedDate == null) return _dailySummaries;
    return _dailySummaries
        .where((s) => s.date.day == _selectedDate)
        .toList();
  }

  SessionProvider? _sessionProvider;

  // ─── Distance helpers ─────────────────────────────────────────────────
  // Match the pattern used by AnalyticsProvider so completed-day distance
  // reads from dailySummaries (server-corrected) and active-today adds live
  // RTDB activeStats on top. Values are sanitized so legacy meter-valued
  // rows don't inflate the monthly total.

  /// Server-style fallback for sessions without a dailySummary: sum
  /// Haversine segments, rejecting > 10 km jumps and > 90 km/h speeds —
  /// same thresholds as `on_session_complete.ts`.
  static const double _maxSegmentKm = 10.0;
  static const double _maxSpeedKmh = 90.0;

  static double _haversineKm(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _filteredDistanceKm(List<SessionLocationModel> locations) {
    if (locations.length < 2) return 0.0;
    double total = 0.0;
    for (var i = 1; i < locations.length; i++) {
      final prev = locations[i - 1];
      final curr = locations[i];
      final seg = _haversineKm(
          prev.latitude, prev.longitude, curr.latitude, curr.longitude);
      if (seg > _maxSegmentKm) continue;
      final dtSec = curr.timestamp.difference(prev.timestamp).inSeconds;
      if (dtSec > 0) {
        final speedKmh = seg / (dtSec / 3600.0);
        if (speedKmh > _maxSpeedKmh) continue;
      }
      total += seg;
    }
    return total;
  }

  double get _liveDistanceKm => UnifiedDataLayer.sanitizeKm(
      ((_liveActiveStats?['distance'] as num?)?.toDouble() ?? 0.0));

  /// Distance to display for a given day card. Uses the dailySummary
  /// total (server-authoritative), plus live RTDB activeStats when today's
  /// session is still running.
  double _distanceForDay(DailySummaryModel summary, {required bool isToday}) {
    double km = UnifiedDataLayer.sanitizeKm(summary.totalDistance);
    if (isToday && (_sessionProvider?.isSessionActive ?? false)) {
      km += _liveDistanceKm;
    }
    return km;
  }

  /// Distance for the expanded per-session row. Prefers the server-corrected
  /// session.totalDistance (written by `on_session_complete`); for active
  /// sessions shows live RTDB distance; falls back to filtered Haversine
  /// when a completed session never got the Cloud Function correction.
  double _distanceForSession(
    SessionModel session,
    List<SessionLocationModel> locations, {
    required bool daySummaryExists,
  }) {
    if (session.isActive) {
      return _liveDistanceKm;
    }
    if (!daySummaryExists && locations.length >= 2) {
      return _filteredDistanceKm(locations);
    }
    return UnifiedDataLayer.sanitizeKm(session.totalDistance);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sessionProvider = context.read<SessionProvider>();
      _wasSessionActive = _sessionProvider!.isSessionActive;
      _sessionProvider!.addListener(_onSessionChanged);
      _startActiveStatsStream();
      _loadData();
    });
  }

  void _startActiveStatsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    String enterpriseId = '';
    try {
      enterpriseId = context.read<AuthProvider>().enterpriseId ?? '';
    } catch (_) {
      enterpriseId = '';
    }
    if (enterpriseId.isEmpty) return;

    _activeStatsSubscription?.cancel();
    _activeStatsSubscription =
        _rtdb.streamUserActiveStats(enterpriseId, user.uid).listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      setState(() {
        _liveActiveStats =
            data is Map ? Map<String, dynamic>.from(data) : null;
      });
    }, onError: (e) {
      debugPrint('[HistoryScreen] activeStats stream error: $e');
    });
  }

  void _onSessionChanged() {
    final isActive = _sessionProvider?.isSessionActive ?? false;
    if (_wasSessionActive == true && !isActive) {
      // Session just ended — reload after short delay for client-side
      // Firestore write to complete
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _loadData();
      });
    }
    _wasSessionActive = isActive;
  }

  @override
  void dispose() {
    _sessionProvider?.removeListener(_onSessionChanged);
    _activeStatsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isEmpty) return;

    setState(() => _isLoading = true);
    _locationCache.clear();
    _sessionCache.clear();

    try {
      final startDate = DateTime(_selectedYear, _selectedMonth, 1);
      final endDate = DateTime(_selectedYear, _selectedMonth + 1, 0, 23, 59, 59);

      final results = await Future.wait([
        _summaryRepo.getMonthlySummary(userId, _selectedYear, _selectedMonth),
        _summaryRepo.getDailySummaries(
          userId,
          startDate: startDate,
          endDate: endDate,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _monthSummary = results[0] as Map<String, dynamic>;
        _dailySummaries = results[1] as List<DailySummaryModel>;
        _isLoading = false;
        // Auto-expand today's card if present
        _expandedDay = _dailySummaries.indexWhere((s) => s.isToday);
        if (_expandedDay == -1) _expandedDay = null;
      });

      // Load locations for today's expanded card
      if (_expandedDay != null) {
        _loadLocationsForDay(_expandedDay!);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      debugPrint('[HistoryScreen] loadData error: $e');
    }
  }

  Future<void> _loadLocationsForDay(int index) async {
    if (_sessionCache.containsKey(index)) return;
    final summary = _dailySummaries[index];
    if (summary.sessionIds.isEmpty) return;

    try {
      final sessions = <SessionModel>[];
      final perSessionLocations = <List<SessionLocationModel>>[];
      for (final sessionId in summary.sessionIds) {
        final locationsFuture = _sessionRepo.getSessionLocations(sessionId);
        final sessionFuture = _sessionRepo.getSession(sessionId);
        final results = await Future.wait([locationsFuture, sessionFuture]);
        final locs = results[0] as List<SessionLocationModel>;
        locs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final session = results[1] as SessionModel?;
        if (session != null) {
          sessions.add(session);
          perSessionLocations.add(locs);
        }
      }
      // Sort sessions (and their locations) by start time
      final indices = List.generate(sessions.length, (i) => i);
      indices.sort((a, b) => sessions[a].startTime.compareTo(sessions[b].startTime));
      final sortedSessions = indices.map((i) => sessions[i]).toList();
      final sortedLocations = indices.map((i) => perSessionLocations[i]).toList();

      if (mounted) {
        setState(() {
          _sessionCache[index] = sortedSessions;
          _locationCache[index] = sortedLocations;
        });
      }
    } catch (e) {
      debugPrint('[HistoryScreen] loadLocations error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionProvider = context.watch<SessionProvider>();
    final isSessionActive = sessionProvider.isSessionActive;

    return GradientBackground(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppHeader(
              title: 'History',
              type: AppHeaderType.primary,
              showAvatar: false,
              showLeading: false,
            ),

            // Filter Selector - Month or Date
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(child: _buildFilterSelector()),
            ),

            // Scrollable Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.only(
                        left: 20,
                        right: 20,
                        bottom: 120,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Monthly Summary
                          _buildMonthlySummary(),
                          const SizedBox(height: 24),

                          // Daily Logs Header
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Daily Logs',
                                  style: AppTypography.h3.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox.shrink(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Daily Log Cards
                          if (_filteredSummaries.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 32),
                              child: Center(
                                child: Text(
                                  _selectedDate != null
                                      ? 'No activity on this date'
                                      : 'No activity this month',
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            )
                          else
                            ...List.generate(_filteredSummaries.length, (index) {
                              final summary = _filteredSummaries[index];
                              // Use the original index for location cache
                              final originalIndex = _dailySummaries.indexOf(summary);
                              return _buildDayCard(summary, originalIndex, isSessionActive);
                            }),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String get _filterLabel {
    if (_selectedDate != null) {
      final d = DateTime(_selectedYear, _selectedMonth, _selectedDate!);
      const dayAbbr = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${dayAbbr[d.weekday - 1]}, $_selectedDate ${_monthNames[_selectedMonth - 1].substring(0, 3)} $_selectedYear';
    }
    return _selectedMonthLabel;
  }

  Widget _buildFilterSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Main date/month selector
        GestureDetector(
          onTap: _showDatePicker,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.glassPrimary,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.glassBorder),
                  boxShadow: AppShadows.glass,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppIcons.calendar_1,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _filterLabel,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      AppIcons.arrow_down_1,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Clear date filter (show only when a specific date is selected)
        if (_selectedDate != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() => _selectedDate = null);
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.glassPrimary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Icon(
                AppIcons.close_circle,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showDatePicker() async {
    final now = DateTime.now();
    final earliest = DateTime(2026, 3, 1);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate != null
          ? DateTime(_selectedYear, _selectedMonth, _selectedDate!)
          : DateTime(
              _selectedYear,
              _selectedMonth,
              now.year == _selectedYear && now.month == _selectedMonth
                  ? now.day
                  : 1,
            ),
      firstDate: earliest,
      lastDate: now,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.glassNav,
              onSurface: AppColors.textPrimary,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: AppColors.glassNav,
              headerBackgroundColor: AppColors.glassPrimary,
              headerForegroundColor: AppColors.textPrimary,
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                if (states.contains(WidgetState.disabled)) {
                  return AppColors.textSecondary.withValues(alpha: 0.3);
                }
                return AppColors.textPrimary;
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.primary;
                }
                return null;
              }),
              todayForegroundColor: WidgetStateProperty.all(AppColors.primary),
              todayBackgroundColor: WidgetStateProperty.all(
                AppColors.primary.withValues(alpha: 0.1),
              ),
              todayBorder: BorderSide(color: AppColors.primary),
              yearForegroundColor: WidgetStateProperty.all(AppColors.textPrimary),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && mounted) {
      final newYear = picked.year;
      final newMonth = picked.month;
      final newDay = picked.day;
      final monthChanged =
          newYear != _selectedYear || newMonth != _selectedMonth;

      setState(() {
        _selectedYear = newYear;
        _selectedMonth = newMonth;
        _selectedDate = newDay;
      });

      if (monthChanged) {
        _loadData();
      }
    }
  }

  Widget _buildMonthlySummary() {
    // Use dailySummaries as the source of truth (server-corrected by
    // onSessionComplete), not the pre-aggregated repo total — the repo
    // doesn't sanitize legacy meter values. Add live RTDB activeStats when
    // the current user's session is running today and today falls in the
    // selected month.
    double distance = 0.0;
    for (final s in _dailySummaries) {
      if (!s.isOffDuty) {
        distance += UnifiedDataLayer.sanitizeKm(s.totalDistance);
      }
    }
    final now = DateTime.now();
    final todayInRange =
        now.year == _selectedYear && now.month == _selectedMonth;
    if (todayInRange && (_sessionProvider?.isSessionActive ?? false)) {
      distance += _liveDistanceKm;
    }
    final hours = _monthSummary['hours'] ?? 0;
    final minutes = _monthSummary['minutes'] ?? 0;
    final activeDays = _monthSummary['activeDays'] ?? 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: AppColors.glassPanelGradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: AppShadows.glass,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(AppIcons.chart, size: 22, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Monthly Summary',
                    style: AppTypography.headline.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Stats Grid - 3 items
              Row(
                children: [
                  _buildStatCard(
                    icon: AppIcons.location,
                    iconBgColor: AppColors.success.withValues(alpha: 0.2),
                    iconColor: AppColors.success,
                    label: 'Distance',
                    value: distance.toStringAsFixed(1),
                    unit: 'km',
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: AppIcons.timer_1,
                    iconBgColor: AppColors.warning.withValues(alpha: 0.2),
                    iconColor: AppColors.warning,
                    label: 'Time',
                    value: '${hours}h ${minutes}m',
                    unit: null,
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    icon: AppIcons.calendar_tick,
                    iconBgColor: AppColors.primary.withValues(alpha: 0.2),
                    iconColor: AppColors.primary,
                    label: 'Active',
                    value: '$activeDays',
                    unit: 'days',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String label,
    required String value,
    String? unit,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.glassPrimary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                style: AppTypography.overline.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: RichText(
                maxLines: 1,
                text: TextSpan(
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  children: [
                    TextSpan(text: value),
                    if (unit != null)
                      TextSpan(
                        text: ' $unit',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCard(DailySummaryModel summary, int index, bool isSessionActive) {
    final isExpanded = _expandedDay == index;
    final isToday = summary.isToday;
    final isOffDuty = summary.isOffDuty;
    final dayNum = summary.date.day.toString().padLeft(2, '0');
    final sessions = _sessionCache[index] ?? [];
    final perSessionLocations = _locationCache[index] ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: isToday
                  ? AppColors.glassStrong
                  : AppColors.glassPrimary,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isToday
                    ? AppColors.primary.withValues(alpha: 0.5)
                    : AppColors.glassBorder,
              ),
            ),
            child: Column(
              children: [
                // Card Header
                GestureDetector(
                  onTap: isOffDuty
                      ? null
                      : () {
                          setState(() {
                            _expandedDay = isExpanded ? null : index;
                            _expandedSessionIndex = null;
                          });
                          if (!isExpanded) {
                            _loadLocationsForDay(index);
                          }
                        },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.all(isExpanded ? 20 : 16),
                    child: Row(
                      children: [
                        // Day Number Box
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isToday
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : AppColors.glassStrong,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.glassBorder,
                            ),
                          ),
                          child: Center(
                            child: isToday
                                ? Icon(
                                    AppIcons.calendar,
                                    size: 24,
                                    color: AppColors.primary,
                                  )
                                : Text(
                                    dayNum,
                                    style: AppTypography.h3.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Day Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isToday
                                    ? '$dayNum ${_monthNames[summary.date.month - 1].substring(0, 3)}'
                                    : summary.dayName,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: isToday ? 18 : 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              if (isToday && isSessionActive)
                                Text(
                                  'Today • Active',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                )
                              else if (isOffDuty)
                                Text(
                                  'Off Duty',
                                  style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    Icon(
                                      AppIcons.timer_1,
                                      size: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      summary.formattedDuration,
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Icon(
                                      AppIcons.location,
                                      size: 14,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${_distanceForDay(summary, isToday: isToday).toStringAsFixed(1)}km',
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),

                        // Expand/Collapse Icon
                        if (!isOffDuty)
                          AnimatedRotation(
                            duration: const Duration(milliseconds: 200),
                            turns: isExpanded ? 0.5 : 0,
                            child: Icon(
                              AppIcons.arrow_down_1,
                              color: AppColors.textSecondary,
                              size: 24,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // Per-session expandable cards with timeline
                if (isExpanded && !isOffDuty) ...[
                  if (sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Text(
                        'Loading sessions...',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        children: sessions.asMap().entries.map((entry) {
                          final sIdx = entry.key;
                          final s = entry.value;
                          final isSessionExpanded = _expandedSessionIndex == sIdx;
                          final label = sessions.length > 1
                              ? 'Session ${sIdx + 1}'
                              : 'Session';
                          final dur = Duration(seconds: s.totalDuration);
                          final h = dur.inHours;
                          final m = dur.inMinutes.remainder(60);
                          final durText = h > 0 ? '${h}h ${m}m' : '${m}m';
                          final sessionLocs = sIdx < perSessionLocations.length
                              ? perSessionLocations[sIdx]
                              : <SessionLocationModel>[];
                          // A summary exists for this day if the sessionId
                          // is covered by summary.sessionIds — that's the
                          // server-corrected path. Otherwise fall back to
                          // Haversine + filter computation.
                          final daySummaryExists =
                              summary.sessionIds.contains(s.id);
                          final sessionDistanceKm = _distanceForSession(
                            s,
                            sessionLocs,
                            daySummaryExists: daySummaryExists,
                          );

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.glassPrimary,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.glassBorder),
                              ),
                              child: Column(
                                children: [
                                  // Session header (tappable)
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      setState(() {
                                        _expandedSessionIndex =
                                            isSessionExpanded ? null : sIdx;
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            AppIcons.routing_2,
                                            size: 16,
                                            color: AppColors.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              label,
                                              style: AppTypography.caption.copyWith(
                                                color: AppColors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${sessionDistanceKm.toStringAsFixed(1)} km',
                                            style: AppTypography.caption.copyWith(
                                              color: AppColors.success,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Icon(
                                            AppIcons.timer_1,
                                            size: 14,
                                            color: AppColors.textSecondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            durText,
                                            style: AppTypography.caption.copyWith(
                                              color: AppColors.textSecondary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          AnimatedRotation(
                                            duration: const Duration(milliseconds: 200),
                                            turns: isSessionExpanded ? 0.5 : 0,
                                            child: Icon(
                                              AppIcons.arrow_down_1,
                                              color: AppColors.textSecondary,
                                              size: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // Session timeline (expandable)
                                  if (isSessionExpanded && sessionLocs.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(36, 0, 14, 12),
                                      child: Column(
                                        children: List.generate(sessionLocs.length, (i) {
                                          final loc = sessionLocs[i];
                                          String type;
                                          if (loc.isCheckIn) {
                                            type = 'start';
                                          } else if (loc.isCheckOut || loc.isAutoEnd) {
                                            type = 'end';
                                          } else if (loc.isLocationUpdate) {
                                            type = 'location_update';
                                          } else {
                                            type = 'visit';
                                          }
                                          return _buildTimelineItem(
                                            time: loc.formattedTime,
                                            title: loc.title.isNotEmpty
                                                ? loc.title
                                                : loc.address,
                                            subtitle: loc.address,
                                            type: type,
                                            isLast: i == sessionLocs.length - 1,
                                            latitude: loc.latitude,
                                            longitude: loc.longitude,
                                          );
                                        }),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMaps(double latitude, double longitude) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _buildTimelineItem({
    required String time,
    required String title,
    required String subtitle,
    required String type,
    bool isLast = false,
    double latitude = 0.0,
    double longitude = 0.0,
  }) {
    Color dotColor;
    switch (type) {
      case 'start':
        dotColor = AppColors.success;
        break;
      case 'end':
        dotColor = AppColors.critical;
        break;
      case 'location_update':
        dotColor = AppColors.warning;
        break;
      default:
        dotColor = AppColors.primary;
    }

    final hasCords = latitude != 0.0 || longitude != 0.0;

    return GestureDetector(
      onTap: hasCords ? () => _openMaps(latitude, longitude) : null,
      child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline column: dot centered on vertical line
          SizedBox(
            width: 14,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: AppColors.glassBorder, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.3),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: AppColors.glassBorder,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.glassPrimary,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.glassPrimary),
                    ),
                    child: Text(
                      time,
                      style: AppTypography.overline.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }
}
