import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/db/db.dart';
import '../../data/repositories/profile_repo.dart';
import '../../diagnostics/diagnostics_log.dart';
import '../models/manual_treadmill_entry.dart';
import 'treadmill_calorie_estimator.dart';

enum StepsAccessState {
  loading,
  available,
  needsPermission,
  denied,
  unavailable,
}

class StepsDayView {
  const StepsDayView({
    required this.day,
    required this.goalSteps,
    required this.trackedSteps,
    required this.trackedCalories,
    required this.manualEntries,
    required this.manualRawSteps,
    required this.manualEquivalentSteps,
    required this.allocatedTrackedTreadmillSteps,
    required this.flatSteps,
    required this.bonusSteps,
    required this.rawTotalSteps,
    required this.totalSteps,
    required this.totalEstimatedCalories,
    required this.flatStepsEstimatedCalories,
    required this.bonusStepsEstimatedCalories,
    required this.flatStepsDurationMinutes,
    required this.bonusStepsDurationMinutes,
    required this.totalDurationMinutes,
    required this.distanceKm,
  });

  final DateTime day;
  final int goalSteps;
  final int trackedSteps;
  final double? trackedCalories;
  final List<ManualTreadmillEntry> manualEntries;
  final int manualRawSteps;
  final int manualEquivalentSteps;
  final int allocatedTrackedTreadmillSteps;
  final int flatSteps;
  final int bonusSteps;
  final int rawTotalSteps;
  final int totalSteps;
  final double totalEstimatedCalories;
  final double flatStepsEstimatedCalories;
  final double bonusStepsEstimatedCalories;
  final double flatStepsDurationMinutes;
  final double bonusStepsDurationMinutes;
  final double totalDurationMinutes;
  final double distanceKm;

  double get progress {
    if (goalSteps <= 0) return 0;
    return (totalSteps / goalSteps).clamp(0.0, 1.0);
  }

  double get trackedProgressSegment {
    if (totalSteps <= 0) return 0;
    return (progress * (flatSteps / totalSteps)).clamp(0.0, 1.0);
  }

  double get manualProgressSegment {
    if (totalSteps <= 0 || bonusSteps <= 0) return 0;
    return (progress * (bonusSteps / totalSteps)).clamp(0.0, 1.0);
  }
}

class _TrackedHealthDayData {
  const _TrackedHealthDayData({
    required this.steps,
    required this.calories,
  });

  final int steps;
  final double? calories;
}

class StepsService extends ChangeNotifier {
  StepsService(AppDatabase db)
      : _profileRepo = ProfileRepo(db),
        _health = Health(),
        _estimator = TreadmillCalorieEstimator();

  static const int _defaultGoalSteps = 10000;
  static const String _manualEntriesKey = 'steps.manual_treadmill_entries.v2';
  static const String _legacyManualEntryKey = 'steps.manual_treadmill_entry.v1';
  static const String _goalStepsKey = 'steps.goal_steps.v1';
  static const String _hasAskedPermissionKey =
      'steps.has_asked_for_permission.v1';
  static const String _liveBaselineBootStepsKey =
      'steps.live_baseline_boot_steps.v1';
  static const String _liveBaselineDayKey = 'steps.live_baseline_day.v1';
  static const String _liveLatestBootStepsKey =
      'steps.live_latest_boot_steps.v1';
  static const String _liveLatestTrackedStepsKey =
      'steps.live_latest_tracked_steps.v1';
  static const int _reconcileBackwardToleranceSteps = 50;
  static const int _bootCounterResetToleranceSteps = 200;
  static const int _unrealisticJumpThresholdSteps = 2000;
  static const int _unrealisticJumpWindowMs = 1000;
  static const Duration _bootSampleFreshnessWindow = Duration(seconds: 5);

  final ProfileRepo _profileRepo;
  final Health _health;
  final TreadmillCalorieEstimator _estimator;

  SharedPreferences? _prefs;
  StepsAccessState _accessState = StepsAccessState.loading;
  List<ManualTreadmillEntry> _manualEntries = const [];
  bool _initialized = false;
  bool _isLoading = false;
  bool _isRequestingAccess = false;
  bool _hasAskedForPermission = false;
  bool _shouldShowFirstRunPrompt = false;
  int _trackedStepsToday = 0;
  int? _liveTrackedStepsToday;
  int? _baselineBootSteps;
  int? _latestBootSteps;
  DateTime? _latestBootSampleAt;
  String? _liveBaselineDayStamp;
  StreamSubscription<StepCount>? _pedometerSub;
  Timer? _liveHealthRefreshTimer;
  DateTime? _lastLiveNotifyAt;
  bool _liveTrackingActive = false;
  bool _liveTrackingUnavailable = false;
  bool _hasRequestedLiveMotionAccess = false;
  bool _healthConfigured = false;
  int _goalSteps = _defaultGoalSteps;
  double? _trackedCaloriesToday;
  String? _statusMessage;
  DateTime? _lastDisplayedStepsAt;
  int? _lastDisplayedStepsTotal;

  StepsAccessState get accessState => _accessState;
  bool get isLoading => _isLoading;
  bool get isRequestingAccess => _isRequestingAccess;
  bool get isInitialized => _initialized;
  bool get isPermissionGranted => _accessState == StepsAccessState.available;
  bool get hasHealthAccess => isPermissionGranted;
  bool get showPermissionCta => !isPermissionGranted;
  bool get shouldShowFirstRunPrompt => _shouldShowFirstRunPrompt;
  String? get statusMessage => _statusMessage;
  int get healthTrackedStepsToday => _trackedStepsToday;
  int? get liveTrackedStepsToday => _liveTrackedStepsToday;
  int get effectiveTrackedStepsToday =>
      _liveTrackedStepsToday ?? _trackedStepsToday;
  int get trackedStepsToday => effectiveTrackedStepsToday;
  int get goalSteps => _goalSteps;
  double? get trackedCaloriesFromHealth =>
      isPermissionGranted ? _trackedCaloriesToday : null;
  bool get isLiveTrackingActive => _liveTrackingActive;
  bool get isLiveTrackingAvailable =>
      _liveTrackingActive && !_liveTrackingUnavailable;
  List<ManualTreadmillEntry> get manualEntriesToday =>
      getManualEntriesForDay(DateTime.now());

  int get manualRawStepsToday => manualEntriesToday.fold<int>(
        0,
        (total, entry) => total + entry.steps,
      );

  int get manualStepsToday => manualEntriesToday.fold<int>(
        0,
        (total, entry) => total + equivalentStepsForEntry(entry),
      );

  int get allocatedTrackedTreadmillStepsToday =>
      manualRawStepsToday > effectiveTrackedStepsToday
          ? effectiveTrackedStepsToday
          : manualRawStepsToday;

  int get flatStepsToday =>
      effectiveTrackedStepsToday - allocatedTrackedTreadmillStepsToday;

  int get treadmillBonusStepsToday => manualStepsToday;

  double get manualEstimatedCaloriesToday => manualEntriesToday.fold<double>(
        0,
        (total, entry) => total + entry.estimatedCalories,
      );

  double get flatStepsEstimatedCaloriesToday =>
      _estimateFlatStepCalories(flatStepsToday);

  double get bonusStepsEstimatedCaloriesToday => manualEstimatedCaloriesToday;

  int get rawTotalStepsToday => effectiveTrackedStepsToday;
  int get totalStepsToday => effectiveTrackedStepsToday + manualStepsToday;

  double get progress {
    if (_goalSteps <= 0) return 0;
    return (totalStepsToday / _goalSteps).clamp(0.0, 1.0);
  }

  double get trackedProgressSegment {
    if (totalStepsToday <= 0) return 0;
    return (progress * (effectiveTrackedStepsToday / totalStepsToday)).clamp(
      0.0,
      1.0,
    );
  }

  double get manualProgressSegment {
    if (totalStepsToday <= 0 || manualStepsToday <= 0) return 0;
    return (progress * (manualStepsToday / totalStepsToday)).clamp(
      0.0,
      1.0,
    );
  }

  double get totalEstimatedCalories =>
      flatStepsEstimatedCaloriesToday + bonusStepsEstimatedCaloriesToday;
  double get flatStepsDurationMinutesToday =>
      _estimateFlatStepDurationMinutes(flatStepsToday);
  double get bonusStepsDurationMinutesToday => manualEntriesToday.fold<double>(
        0,
        (total, entry) => total + _estimateEntryDurationMinutes(entry),
      );
  double get totalDurationMinutesToday =>
      flatStepsDurationMinutesToday + bonusStepsDurationMinutesToday;
  double get estimatedDistanceKm =>
      _estimator.estimateDistanceKm(totalStepsToday);
  double get caloriesToday => totalEstimatedCalories;
  double get distanceToday => estimatedDistanceKm / 1.609344;
  int get durationTodayMinutes => totalDurationMinutesToday.round();
  double get goalEstimatedCalories => _estimateFlatStepCalories(_goalSteps);
  double get goalDistanceToday => _estimator.estimateDistanceKm(_goalSteps) / 1.609344;
  int get goalDurationTodayMinutes =>
      _estimateFlatStepDurationMinutes(_goalSteps).round();

  List<ManualTreadmillEntry> getManualEntriesForDay(DateTime day) {
    final normalizedDay = _normalizeDay(day);
    final entries = _manualEntries
        .where((entry) => _isSameDay(entry.createdAt, normalizedDay))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(entries);
  }

  Future<int> getTrackedStepsForDay(DateTime day) async {
    if (!_isMobilePlatform || !isPermissionGranted) return 0;
    try {
      await _ensureHealthConfigured();
      final tracked = await _loadTrackedHealthDataForDay(day);
      return tracked.steps;
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'getTrackedStepsForDay(${_normalizeDay(day).toIso8601String()}) failed',
      );
      return 0;
    }
  }

  Future<double?> getTrackedCaloriesForDay(DateTime day) async {
    if (!_isMobilePlatform || !isPermissionGranted) return null;
    try {
      await _ensureHealthConfigured();
      final tracked = await _loadTrackedHealthDataForDay(day);
      return tracked.calories;
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context:
            'getTrackedCaloriesForDay(${_normalizeDay(day).toIso8601String()}) failed',
      );
      return null;
    }
  }

  StepsDayView get todayView => _buildDayView(
        day: DateTime.now(),
        trackedSteps: effectiveTrackedStepsToday,
        trackedCalories: trackedCaloriesFromHealth,
        manualEntries: manualEntriesToday,
      );

  Future<StepsDayView> loadDay(DateTime day) async {
    final normalizedDay = _normalizeDay(day);
    final manualEntries = getManualEntriesForDay(normalizedDay);
    if (_isSameDay(normalizedDay, DateTime.now())) {
      return _buildDayView(
        day: normalizedDay,
        trackedSteps: effectiveTrackedStepsToday,
        trackedCalories: trackedCaloriesFromHealth,
        manualEntries: manualEntries,
      );
    }
    if (!_isMobilePlatform || !isPermissionGranted) {
      return _buildDayView(
        day: normalizedDay,
        trackedSteps: 0,
        trackedCalories: null,
        manualEntries: manualEntries,
      );
    }

    try {
      await _ensureHealthConfigured();
      final tracked = await _loadTrackedHealthDataForDay(normalizedDay);
      return _buildDayView(
        day: normalizedDay,
        trackedSteps: tracked.steps,
        trackedCalories: tracked.calories,
        manualEntries: manualEntries,
      );
    } catch (_) {
      return _buildDayView(
        day: normalizedDay,
        trackedSteps: 0,
        trackedCalories: null,
        manualEntries: manualEntries,
      );
    }
  }

  String get accessPrompt => switch (_accessState) {
        StepsAccessState.unavailable => 'Enable step access',
        StepsAccessState.denied => 'Enable step access',
        StepsAccessState.needsPermission => 'Enable step access',
        StepsAccessState.loading => 'Loading steps',
        StepsAccessState.available => 'Step access enabled',
      };

  Future<void> initialize() async {
    if (_initialized) return;
    _isLoading = true;
    notifyListeners();
    try {
      DiagnosticsLog.instance.record('StepsService.initialize() begin');
      _prefs = await SharedPreferences.getInstance();
      _goalSteps = _prefs?.getInt(_goalStepsKey) ?? _defaultGoalSteps;
      _hasAskedForPermission = _prefs?.getBool(_hasAskedPermissionKey) ?? false;
      _manualEntries = _loadManualEntries();
      _restorePersistedLiveBaseline();
      _initialized = true;
      await refresh();
      _shouldShowFirstRunPrompt =
          _isMobilePlatform && !_hasAskedForPermission && !isPermissionGranted;
      DiagnosticsLog.instance.record(
        'StepsService.initialize() complete; accessState=$_accessState',
      );
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'StepsService.initialize() failed',
      );
      _initialized = true;
      _setLockedState(
        state: StepsAccessState.unavailable,
        message: 'Steps are not available on this device.',
      );
      _shouldShowFirstRunPrompt = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> consumeFirstRunPrompt() async {
    if (!_shouldShowFirstRunPrompt) return false;
    _shouldShowFirstRunPrompt = false;
    _hasAskedForPermission = true;
    await _prefs?.setBool(_hasAskedPermissionKey, true);
    notifyListeners();
    return true;
  }

  Future<void> refresh() async {
    if (!_initialized && _prefs == null) return;
    if (!_isMobilePlatform) {
      _setLockedState(
        state: StepsAccessState.unavailable,
        message: 'Steps are not available on this platform.',
      );
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();
    try {
      DiagnosticsLog.instance.record('StepsService.refresh() begin');
      if (_isAndroid) {
        await _ensureHealthConfigured();
        final isAvailable = await _health.isHealthConnectAvailable();
        if (!isAvailable) {
          _setLockedState(
            state: StepsAccessState.unavailable,
            message: 'Install Health Connect to enable steps.',
          );
          return;
        }
        final hasPermissions = await _health.hasPermissions(
          _healthTypes,
          permissions: _healthPermissions,
        );
        if (hasPermissions != true) {
          _setLockedState(
            state: _hasAskedForPermission
                ? StepsAccessState.denied
                : StepsAccessState.needsPermission,
            message: 'Allow step access to unlock this section.',
          );
          return;
        }
      } else if (_isIOS && !_hasAskedForPermission) {
        _setLockedState(
          state: StepsAccessState.needsPermission,
          message: 'Allow step access to unlock this section.',
        );
        return;
      } else {
        await _ensureHealthConfigured();
      }

      await _loadTrackedHealthData();
      _syncLiveTrackedFloorToHealth(source: 'refresh');
      unawaited(startLiveTrackingIfAllowed());
      _reconcileBaselineWithHealth(
        healthSteps: _trackedStepsToday,
        source: 'refresh',
      );
      _logLiveSnapshot('onResume', checkJump: true);
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'StepsService.refresh() failed',
      );
      _handleHealthFailure(
        error,
        whileRequestingAccess: false,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshHealthTotalsForToday() async {
    if (!_initialized || !isPermissionGranted) {
      return;
    }
    _isLoading = true;
    notifyListeners();
    try {
      await _ensureHealthConfigured();
      await _loadTrackedHealthData();
      _syncLiveTrackedFloorToHealth(source: 'refreshHealthTotalsForToday');
      unawaited(startLiveTrackingIfAllowed());
      _reconcileBaselineWithHealth(
        healthSteps: _trackedStepsToday,
        source: 'refreshHealthTotalsForToday',
      );
      _logLiveSnapshot('onHealthRefresh', checkJump: true);
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'StepsService.refreshHealthTotalsForToday() failed',
      );
      _trackedStepsToday = 0;
      _trackedCaloriesToday = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> requestAccess() async {
    if (!_isMobilePlatform) {
      _setLockedState(
        state: StepsAccessState.unavailable,
        message: 'Steps are not available on this platform.',
      );
      notifyListeners();
      return false;
    }
    if (_isRequestingAccess) return isPermissionGranted;

    _isRequestingAccess = true;
    _hasAskedForPermission = true;
    _shouldShowFirstRunPrompt = false;
    notifyListeners();
    try {
      await _prefs?.setBool(_hasAskedPermissionKey, true);
      await _ensureHealthConfigured();
      if (_isAndroid) {
        final isAvailable = await _health.isHealthConnectAvailable();
        if (!isAvailable) {
          await _health.installHealthConnect();
          _setLockedState(
            state: StepsAccessState.unavailable,
            message: 'Install Health Connect, then tap Enable again.',
          );
          return false;
        }
      }

      final granted = await _health.requestAuthorization(
        _healthTypes,
        permissions: _healthPermissions,
      );
      if (!granted) {
        _setLockedState(
          state: StepsAccessState.denied,
          message: 'Step access is currently disabled.',
        );
        return false;
      }

      await _loadTrackedHealthData();
      _syncLiveTrackedFloorToHealth(source: 'requestAccess');
      unawaited(startLiveTrackingIfAllowed());
      _reconcileBaselineWithHealth(
        healthSteps: _trackedStepsToday,
        source: 'requestAccess',
      );
      _logLiveSnapshot('requestAccess', checkJump: true);
      notifyListeners();
      return true;
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'StepsService.requestAccess() failed',
      );
      _handleHealthFailure(
        error,
        whileRequestingAccess: true,
      );
      notifyListeners();
      return false;
    } finally {
      _isRequestingAccess = false;
      notifyListeners();
    }
  }

  Future<void> startLiveTrackingIfAllowed() async {
    if (!_isMobilePlatform || !isPermissionGranted) {
      stopLiveTracking();
      return;
    }
    _ensureLiveBaselineDay();
    if (_pedometerSub != null) {
      return;
    }
    if (_isAndroid) {
      final hasMotionPermission = await _ensureActivityRecognitionPermission();
      if (!hasMotionPermission) {
        _liveTrackingUnavailable = true;
        _liveTrackedStepsToday = null;
        notifyListeners();
        return;
      }
    }

    try {
      DiagnosticsLog.instance.record('Starting pedometer live tracking');
      _pedometerSub = Pedometer.stepCountStream.listen(
        _handleStepCountEvent,
        onError: _handlePedometerError,
        cancelOnError: false,
      );
      _liveTrackingActive = true;
      _liveTrackingUnavailable = false;
      _liveHealthRefreshTimer?.cancel();
      _liveHealthRefreshTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => unawaited(_refreshLiveAlignment(reason: 'periodic')),
      );
      _reconcileBaselineWithHealth(
        healthSteps: _trackedStepsToday,
        source: 'startLiveTracking',
      );
      _logLiveSnapshot('startLiveTracking', checkJump: true);
      notifyListeners();
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'Failed to start pedometer live tracking',
      );
      _liveTrackingUnavailable = true;
      _liveTrackedStepsToday = null;
      _liveTrackingActive = false;
      notifyListeners();
    }
  }

  void pauseLiveTracking() {
    _pedometerSub?.cancel();
    _pedometerSub = null;
    _liveHealthRefreshTimer?.cancel();
    _liveHealthRefreshTimer = null;
    _latestBootSampleAt = null;
    _liveTrackingActive = false;
    _logLiveSnapshot('onPause', checkJump: true);
  }

  void stopLiveTracking() {
    pauseLiveTracking();
    _baselineBootSteps = null;
    _latestBootSteps = null;
    _latestBootSampleAt = null;
    _liveBaselineDayStamp = null;
    _liveTrackedStepsToday = null;
    _lastLiveNotifyAt = null;
    _liveTrackingUnavailable = false;
    unawaited(_clearPersistedLiveBaseline());
  }

  Future<void> setGoalSteps(int steps) async {
    final normalized = steps.clamp(100, 100000);
    _goalSteps = normalized;
    await _prefs?.setInt(_goalStepsKey, normalized);
    notifyListeners();
  }

  Future<bool> _ensureActivityRecognitionPermission() async {
    try {
      final status = await Permission.activityRecognition.status;
      if (status.isGranted) {
        return true;
      }
      if (_hasRequestedLiveMotionAccess) {
        return false;
      }
      _hasRequestedLiveMotionAccess = true;
      final requested = await Permission.activityRecognition.request();
      return requested.isGranted;
    } catch (_) {
      return false;
    }
  }

  void _handleStepCountEvent(StepCount event) {
    _ensureLiveBaselineDay();
    if (_didPedometerCounterReset(event.steps)) {
      DiagnosticsLog.instance.record(
        'Detected pedometer counter reset; reinitializing live baseline.',
        level: 'WARN',
      );
      _baselineBootSteps = null;
      _liveTrackedStepsToday = null;
      _lastLiveNotifyAt = null;
    }
    _latestBootSteps = event.steps;
    _latestBootSampleAt = DateTime.now();
    _liveTrackingUnavailable = false;
    final previousLive = _liveTrackedStepsToday ?? _trackedStepsToday;
    if (_baselineBootSteps == null) {
      _reconcileBaselineWithHealth(
        healthSteps: _trackedStepsToday,
        source: 'pedometer-first-event',
        forceInitialize: true,
      );
      if (_baselineBootSteps == null) {
        return;
      }
    } else {
      final computedLive = _computeLiveSteps(
        bootSteps: event.steps,
        baseline: _baselineBootSteps!,
      );
      if (computedLive + _reconcileBackwardToleranceSteps < previousLive) {
        _baselineBootSteps = event.steps - previousLive;
        _liveTrackedStepsToday = previousLive;
        DiagnosticsLog.instance.record(
          'Live pedometer update kept monotonic: '
          'boot=${event.steps} baseline=$_baselineBootSteps '
          'previousLive=$previousLive computedLive=$computedLive',
          level: 'WARN',
        );
      } else {
        _liveTrackedStepsToday = computedLive;
      }
    }
    final now = DateTime.now();
    final shouldNotify = _lastLiveNotifyAt == null ||
        now.difference(_lastLiveNotifyAt!) >= const Duration(milliseconds: 400);
    final currentLive = _liveTrackedStepsToday ?? _trackedStepsToday;
    if (shouldNotify || previousLive != currentLive) {
      _lastLiveNotifyAt = now;
      notifyListeners();
    }
    unawaited(_persistLiveBaseline());
    _logLiveSnapshot(
      'onPedometerEvent',
      checkJump: true,
    );
  }

  void _handlePedometerError(Object error) {
    DiagnosticsLog.instance.record(
      'Pedometer stream error: $error',
      level: 'WARN',
    );
    _liveTrackingUnavailable = true;
    _liveTrackedStepsToday = null;
    _pedometerSub?.cancel();
    _pedometerSub = null;
    _liveHealthRefreshTimer?.cancel();
    _liveHealthRefreshTimer = null;
    _baselineBootSteps = null;
    _latestBootSteps = null;
    _latestBootSampleAt = null;
    _liveTrackingActive = false;
    _liveBaselineDayStamp = null;
    unawaited(_clearPersistedLiveBaseline());
    _logLiveSnapshot('pedometerError');
    notifyListeners();
  }

  bool _reconcileBaselineWithHealth({
    required int healthSteps,
    required String source,
    bool forceInitialize = false,
  }) {
    final latestBootSteps = _latestBootSteps;
    if (latestBootSteps == null) {
      return false;
    }
    if (!forceInitialize && !_hasRecentBootSample) {
      DiagnosticsLog.instance.record(
        'Baseline reconcile deferred [$source]: waiting for a fresh boot sample.',
      );
      return false;
    }
    final previousLive = _liveTrackedStepsToday ?? _trackedStepsToday;
    final candidateBaseline = latestBootSteps - healthSteps;
    final candidateLive = _computeLiveSteps(
      bootSteps: latestBootSteps,
      baseline: candidateBaseline,
    );

    if (_baselineBootSteps == null || forceInitialize) {
      var seededLive = candidateLive;
      if (seededLive + _reconcileBackwardToleranceSteps < previousLive) {
        seededLive = previousLive;
      }
      _baselineBootSteps = latestBootSteps - seededLive;
      _liveTrackedStepsToday = seededLive;
      unawaited(_persistLiveBaseline());
      DiagnosticsLog.instance.record(
        'Baseline initialized [$source]: boot=$latestBootSteps baseline=$_baselineBootSteps '
        'health=$healthSteps candidateLive=$candidateLive live=$_liveTrackedStepsToday',
      );
      return _liveTrackedStepsToday != previousLive;
    }

    final delta = candidateLive - previousLive;
    final allowRebaseline =
        delta >= 0 || delta.abs() <= _reconcileBackwardToleranceSteps;
    if (!allowRebaseline) {
      final preservedBaseline = _baselineBootSteps!;
      final preservedLive = _computeLiveSteps(
        bootSteps: latestBootSteps,
        baseline: preservedBaseline,
      );
      if (preservedLive < previousLive) {
        _baselineBootSteps = latestBootSteps - previousLive;
        _liveTrackedStepsToday = previousLive;
        unawaited(_persistLiveBaseline());
      } else {
        _liveTrackedStepsToday = preservedLive;
      }
      DiagnosticsLog.instance.record(
        'Baseline reconcile skipped [$source]: boot=$latestBootSteps '
        'baseline=$_baselineBootSteps candidateBaseline=$candidateBaseline '
        'health=$healthSteps previousLive=$previousLive candidateLive=$candidateLive '
        'delta=$delta',
        level: 'WARN',
      );
      return _liveTrackedStepsToday != previousLive;
    }

    _baselineBootSteps = candidateBaseline;
    _liveTrackedStepsToday = candidateLive;
    unawaited(_persistLiveBaseline());
    DiagnosticsLog.instance.record(
      'Baseline reconciled [$source]: boot=$latestBootSteps baseline=$_baselineBootSteps health=$healthSteps live=$_liveTrackedStepsToday',
    );
    return _liveTrackedStepsToday != previousLive;
  }

  void _logLiveSnapshot(
    String event, {
    bool checkJump = false,
  }) {
    final tracked = effectiveTrackedStepsToday;
    final manual = manualStepsToday;
    final totalDisplayed = tracked + manual;
    DiagnosticsLog.instance.record(
      '[steps][$event] boot=${_latestBootSteps ?? -1} '
      'baseline=${_baselineBootSteps ?? -1} '
      'computedLive=${_liveTrackedStepsToday ?? -1} '
      'health=$_trackedStepsToday manual=$manual '
      'totalDisplayed=$totalDisplayed liveActive=$_liveTrackingActive',
    );
    if (checkJump) {
      _warnOnUnrealisticJump(totalDisplayed, event: event);
    }
  }

  void _warnOnUnrealisticJump(
    int totalDisplayed, {
    required String event,
  }) {
    final now = DateTime.now();
    final lastAt = _lastDisplayedStepsAt;
    final lastValue = _lastDisplayedStepsTotal;
    if (lastAt != null && lastValue != null) {
      final deltaMs = now.difference(lastAt).inMilliseconds;
      final deltaSteps = totalDisplayed - lastValue;
      if (deltaMs > 0 &&
          deltaMs <= _unrealisticJumpWindowMs &&
          deltaSteps.abs() > _unrealisticJumpThresholdSteps) {
        DiagnosticsLog.instance.record(
          'Unrealistic step jump detected [$event]: '
          'deltaSteps=$deltaSteps deltaMs=$deltaMs '
          'previous=$lastValue current=$totalDisplayed',
          level: 'WARN',
        );
      }
    }
    _lastDisplayedStepsAt = now;
    _lastDisplayedStepsTotal = totalDisplayed;
  }

  void _ensureLiveBaselineDay() {
    final todayStamp = _todayStamp();
    if (_liveBaselineDayStamp == todayStamp) {
      return;
    }
    final didChangeDay =
        _liveBaselineDayStamp != null && _liveBaselineDayStamp != todayStamp;
    _baselineBootSteps = null;
    _liveTrackedStepsToday = null;
    _latestBootSteps = null;
    _latestBootSampleAt = null;
    _lastLiveNotifyAt = null;
    if (didChangeDay) {
      _trackedStepsToday = 0;
      _trackedCaloriesToday = null;
    }
    _liveBaselineDayStamp = todayStamp;
    unawaited(_persistLiveBaseline());
  }

  String _todayStamp() => _normalizeDay(DateTime.now()).toIso8601String();

  bool get _hasRecentBootSample {
    final sampledAt = _latestBootSampleAt;
    if (sampledAt == null) return false;
    return DateTime.now().difference(sampledAt) <= _bootSampleFreshnessWindow;
  }

  int _computeLiveSteps({
    required int bootSteps,
    required int baseline,
  }) {
    final computed = bootSteps - baseline;
    if (computed <= 0) return 0;
    return computed;
  }

  bool _didPedometerCounterReset(int nextBootSteps) {
    final previousBoot = _latestBootSteps;
    if (previousBoot == null) return false;
    return nextBootSteps + _bootCounterResetToleranceSteps < previousBoot;
  }

  void _syncLiveTrackedFloorToHealth({
    required String source,
  }) {
    final liveSteps = _liveTrackedStepsToday;
    if (liveSteps == null) return;
    if (_trackedStepsToday <= liveSteps) return;
    _liveTrackedStepsToday = _trackedStepsToday;
    DiagnosticsLog.instance.record(
      'Live tracked steps advanced from health [$source]: '
      'live=$liveSteps health=$_trackedStepsToday',
    );
    unawaited(_persistLiveBaseline());
  }

  Future<void> _refreshLiveAlignment({
    String reason = 'periodic',
  }) async {
    if (!isPermissionGranted) {
      return;
    }
    try {
      final tracked = await _loadTrackedHealthDataForDay(DateTime.now());
      final healthChanged = tracked.steps != _trackedStepsToday ||
          tracked.calories != _trackedCaloriesToday;
      _trackedStepsToday = tracked.steps;
      _trackedCaloriesToday = tracked.calories;
      _syncLiveTrackedFloorToHealth(source: 'health-refresh:$reason');
      final baselineChanged = _reconcileBaselineWithHealth(
        healthSteps: _trackedStepsToday,
        source: 'health-refresh:$reason',
      );
      if (healthChanged || baselineChanged) {
        notifyListeners();
      }
      _logLiveSnapshot('onHealthRefresh:$reason', checkJump: true);
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'Live health alignment refresh failed ($reason)',
      );
    }
  }

  Future<void> saveManualEntry({
    int? steps,
    required double inclineDegrees,
    required double speedMph,
    int? durationMinutes,
    DateTime? day,
  }) async {
    final resolvedSteps = (steps != null && steps > 0)
        ? steps
        : (durationMinutes != null && durationMinutes > 0
            ? _estimator.estimateSteps(
                durationMinutes: durationMinutes,
                speedMph: speedMph,
              )
            : 0);
    if (resolvedSteps <= 0) {
      throw ArgumentError(
        'A manual treadmill entry requires steps or duration minutes.',
      );
    }

    final profile = await _profileRepo.getProfile();
    final estimatedCalories = _estimator.estimateCalories(
      steps: resolvedSteps,
      inclineDegrees: inclineDegrees,
      speedMph: speedMph,
      durationMinutes: durationMinutes,
      weightKg: profile?.weightKg,
    );
    final next = ManualTreadmillEntry(
      steps: resolvedSteps,
      inclineDegrees: inclineDegrees,
      speedMph: speedMph,
      durationMinutes: durationMinutes,
      createdAt: _entryTimestampForDay(day),
      estimatedCalories: estimatedCalories,
    );
    _manualEntries = [..._manualEntries, next];
    await _persistManualEntries();
    notifyListeners();
  }

  Future<bool> updateManualEntry(
    ManualTreadmillEntry existing, {
    required double inclineDegrees,
    required double speedMph,
    int? durationMinutes,
  }) async {
    final index = _manualEntries.indexWhere(
      (candidate) => _matchesEntry(candidate, existing),
    );
    if (index < 0) {
      return false;
    }

    final resolvedSteps = (durationMinutes != null && durationMinutes > 0)
        ? _estimator.estimateSteps(
            durationMinutes: durationMinutes,
            speedMph: speedMph,
          )
        : 0;
    if (resolvedSteps <= 0) {
      throw ArgumentError(
        'A manual treadmill entry requires a valid duration.',
      );
    }

    final profile = await _profileRepo.getProfile();
    final estimatedCalories = _estimator.estimateCalories(
      steps: resolvedSteps,
      inclineDegrees: inclineDegrees,
      speedMph: speedMph,
      durationMinutes: durationMinutes,
      weightKg: profile?.weightKg,
    );

    final updated = ManualTreadmillEntry(
      steps: resolvedSteps,
      inclineDegrees: inclineDegrees,
      speedMph: speedMph,
      durationMinutes: durationMinutes,
      createdAt: existing.createdAt,
      estimatedCalories: estimatedCalories,
    );
    final next = [..._manualEntries];
    next[index] = updated;
    _manualEntries = next;
    await _persistManualEntries();
    notifyListeners();
    return true;
  }

  int equivalentStepsForEntry(ManualTreadmillEntry entry) {
    return _estimator.estimateEquivalentFlatSteps(
      steps: entry.steps,
      inclineDegrees: entry.inclineDegrees,
      speedMph: entry.speedMph,
    );
  }

  Future<int?> deleteManualEntry(ManualTreadmillEntry entry) async {
    final index = _manualEntries.indexWhere(
      (candidate) => _matchesEntry(candidate, entry),
    );
    if (index < 0) return null;
    final next = [..._manualEntries]..removeAt(index);
    _manualEntries = next;
    await _persistManualEntries();
    notifyListeners();
    return index;
  }

  Future<void> restoreManualEntry(
    ManualTreadmillEntry entry, {
    int? atIndex,
  }) async {
    final next = [..._manualEntries];
    final safeIndex =
        atIndex == null ? next.length : atIndex.clamp(0, next.length);
    next.insert(safeIndex, entry);
    _manualEntries = next;
    await _persistManualEntries();
    notifyListeners();
  }

  Future<void> _loadTrackedHealthData() async {
    final tracked = await _loadTrackedHealthDataForDay(DateTime.now());
    _trackedStepsToday = tracked.steps;
    _trackedCaloriesToday = tracked.calories;
    _accessState = StepsAccessState.available;
    _statusMessage = null;
  }

  Future<_TrackedHealthDayData> _loadTrackedHealthDataForDay(
      DateTime day) async {
    final normalizedDay = _normalizeDay(day);
    final start = normalizedDay;
    final end = _isSameDay(normalizedDay, DateTime.now())
        ? DateTime.now()
        : normalizedDay.add(const Duration(days: 1));

    try {
      final steps = await _health.getTotalStepsInInterval(
            start,
            end,
            includeManualEntry: false,
          ) ??
          0;

      final caloriesPoints = await _health.getHealthDataFromTypes(
        types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
        startTime: start,
        endTime: end,
      );

      double calories = 0;
      for (final point in caloriesPoints) {
        final value = point.value;
        if (value is NumericHealthValue) {
          calories += value.numericValue.toDouble();
        }
      }

      return _TrackedHealthDayData(
        steps: steps,
        calories: caloriesPoints.isEmpty
            ? null
            : double.parse(calories.toStringAsFixed(1)),
      );
    } on PlatformException catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'Health read failed for ${normalizedDay.toIso8601String()}',
      );
      if (_isHealthConfigurationError(error)) {
        rethrow;
      }
      return const _TrackedHealthDayData(steps: 0, calories: null);
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'Health read failed for ${normalizedDay.toIso8601String()}',
      );
      return const _TrackedHealthDayData(steps: 0, calories: null);
    }
  }

  StepsDayView _buildDayView({
    required DateTime day,
    required int trackedSteps,
    required double? trackedCalories,
    required List<ManualTreadmillEntry> manualEntries,
  }) {
    final manualRawSteps = manualEntries.fold<int>(
      0,
      (total, entry) => total + entry.steps,
    );
    final manualEquivalentSteps = manualEntries.fold<int>(
      0,
      (total, entry) => total + equivalentStepsForEntry(entry),
    );
    final allocatedTrackedTreadmillSteps =
        manualRawSteps > trackedSteps ? trackedSteps : manualRawSteps;
    final flatSteps = trackedSteps - allocatedTrackedTreadmillSteps;
    final bonusSteps = manualEquivalentSteps;
    final bonusStepsEstimatedCalories = manualEntries.fold<double>(
      0,
      (total, entry) => total + entry.estimatedCalories,
    );
    final flatStepsEstimatedCalories = _estimateFlatStepCalories(flatSteps);
    final flatStepsDurationMinutes =
        _estimateFlatStepDurationMinutes(flatSteps);
    final bonusStepsDurationMinutes = manualEntries.fold<double>(
      0,
      (total, entry) => total + _estimateEntryDurationMinutes(entry),
    );
    final totalEstimatedCalories =
        flatStepsEstimatedCalories + bonusStepsEstimatedCalories;
    final totalDurationMinutes =
        flatStepsDurationMinutes + bonusStepsDurationMinutes;
    final totalSteps = flatSteps + bonusSteps;
    return StepsDayView(
      day: _normalizeDay(day),
      goalSteps: _goalSteps,
      trackedSteps: trackedSteps,
      trackedCalories: trackedCalories,
      manualEntries: manualEntries,
      manualRawSteps: manualRawSteps,
      manualEquivalentSteps: manualEquivalentSteps,
      allocatedTrackedTreadmillSteps: allocatedTrackedTreadmillSteps,
      flatSteps: flatSteps,
      bonusSteps: bonusSteps,
      rawTotalSteps: trackedSteps,
      totalSteps: totalSteps,
      totalEstimatedCalories: totalEstimatedCalories,
      flatStepsEstimatedCalories: flatStepsEstimatedCalories,
      bonusStepsEstimatedCalories: bonusStepsEstimatedCalories,
      flatStepsDurationMinutes: flatStepsDurationMinutes,
      bonusStepsDurationMinutes: bonusStepsDurationMinutes,
      totalDurationMinutes: totalDurationMinutes,
      distanceKm: _estimator.estimateDistanceKm(totalSteps),
    );
  }

  double _estimateFlatStepCalories(int steps) {
    if (steps <= 0) return 0;
    return _estimator.estimateCalories(
      steps: steps,
      inclineDegrees: 0,
      speedMph: 3.0,
    );
  }

  double _estimateFlatStepDurationMinutes(int steps) {
    if (steps <= 0) return 0;
    return _estimator.estimateDurationMinutes(
      steps: steps,
      speedMph: 3.0,
    );
  }

  double _estimateEntryDurationMinutes(ManualTreadmillEntry entry) {
    final durationMinutes = entry.durationMinutes;
    if (durationMinutes != null && durationMinutes > 0) {
      return durationMinutes.toDouble();
    }
    return _estimator.estimateDurationMinutes(
      steps: entry.steps,
      speedMph: entry.speedMph,
    );
  }

  List<ManualTreadmillEntry> _loadManualEntries() {
    final raw = _prefs?.getString(_manualEntriesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        return ManualTreadmillEntry.decodeList(raw);
      } catch (_) {}
    }

    final legacyRaw = _prefs?.getString(_legacyManualEntryKey);
    if (legacyRaw != null && legacyRaw.isNotEmpty) {
      try {
        return [ManualTreadmillEntry.fromJsonString(legacyRaw)];
      } catch (_) {}
    }
    return const [];
  }

  Future<void> _persistManualEntries() async {
    await _prefs?.setString(
      _manualEntriesKey,
      ManualTreadmillEntry.encodeList(_manualEntries),
    );
    if (_prefs?.containsKey(_legacyManualEntryKey) ?? false) {
      await _prefs?.remove(_legacyManualEntryKey);
    }
  }

  void _restorePersistedLiveBaseline() {
    final baseline = _prefs?.getInt(_liveBaselineBootStepsKey);
    final dayStamp = _prefs?.getString(_liveBaselineDayKey);
    final latestBoot = _prefs?.getInt(_liveLatestBootStepsKey);
    final latestLive = _prefs?.getInt(_liveLatestTrackedStepsKey);
    if (baseline == null || dayStamp == null) {
      _baselineBootSteps = null;
      _liveBaselineDayStamp = null;
      _latestBootSteps = null;
      _latestBootSampleAt = null;
      _liveTrackedStepsToday = null;
      return;
    }
    final todayStamp = _todayStamp();
    if (dayStamp != todayStamp) {
      _baselineBootSteps = null;
      _liveBaselineDayStamp = null;
      _latestBootSteps = null;
      _latestBootSampleAt = null;
      _liveTrackedStepsToday = null;
      unawaited(_clearPersistedLiveBaseline());
      return;
    }
    _baselineBootSteps = baseline;
    _liveBaselineDayStamp = dayStamp;
    _latestBootSteps = latestBoot;
    _latestBootSampleAt = null;
    _liveTrackedStepsToday = latestLive;
  }

  Future<void> _persistLiveBaseline() async {
    final baseline = _baselineBootSteps;
    if (baseline == null) {
      await _clearPersistedLiveBaseline();
      return;
    }
    final todayStamp = _todayStamp();
    _liveBaselineDayStamp = todayStamp;
    await _prefs?.setInt(_liveBaselineBootStepsKey, baseline);
    await _prefs?.setString(_liveBaselineDayKey, todayStamp);
    if (_latestBootSteps != null) {
      await _prefs?.setInt(_liveLatestBootStepsKey, _latestBootSteps!);
    } else {
      await _prefs?.remove(_liveLatestBootStepsKey);
    }
    if (_liveTrackedStepsToday != null) {
      await _prefs?.setInt(_liveLatestTrackedStepsKey, _liveTrackedStepsToday!);
    } else {
      await _prefs?.remove(_liveLatestTrackedStepsKey);
    }
  }

  Future<void> _clearPersistedLiveBaseline() async {
    await _prefs?.remove(_liveBaselineBootStepsKey);
    await _prefs?.remove(_liveBaselineDayKey);
    await _prefs?.remove(_liveLatestBootStepsKey);
    await _prefs?.remove(_liveLatestTrackedStepsKey);
  }

  Future<void> _ensureHealthConfigured() async {
    if (_healthConfigured || !_isMobilePlatform) return;
    await _health.configure();
    _healthConfigured = true;
  }

  void _handleHealthFailure(
    Object error, {
    required bool whileRequestingAccess,
  }) {
    if (_isHealthConfigurationError(error)) {
      _setLockedState(
        state: StepsAccessState.unavailable,
        message:
            'Health access is unavailable in this build. Enable HealthKit in the iOS Runner target.',
      );
      return;
    }

    if (_isHealthDataTemporarilyUnavailable(error)) {
      stopLiveTracking();
      _trackedStepsToday = 0;
      _trackedCaloriesToday = null;
      _accessState = StepsAccessState.available;
      _statusMessage =
          'Health data is temporarily unavailable. Unlock the device and try again.';
      return;
    }

    final message = _isHealthDataTemporarilyUnavailable(error)
        ? 'Health data is temporarily unavailable. Unlock the device and try again.'
        : whileRequestingAccess
              ? 'Step access is currently disabled.'
              : 'Allow step access to unlock this section.';
    _setLockedState(
      state: whileRequestingAccess || _hasAskedForPermission
          ? StepsAccessState.denied
          : StepsAccessState.needsPermission,
      message: message,
    );
  }

  bool _isHealthConfigurationError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('healthkit entitlement') ||
        message.contains('nshealthshareusagedescription') ||
        message.contains('nshealthupdateusagedescription');
  }

  bool _isHealthDataTemporarilyUnavailable(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('protected health data is inaccessible') ||
        message.contains('data is inaccessible') ||
        message.contains('device is locked') ||
        message.contains('temporarily unavailable');
  }

  void _setLockedState({
    required StepsAccessState state,
    String? message,
  }) {
    stopLiveTracking();
    _trackedStepsToday = 0;
    _trackedCaloriesToday = null;
    _accessState = state;
    _statusMessage = message;
  }

  bool _matchesEntry(
    ManualTreadmillEntry left,
    ManualTreadmillEntry right,
  ) {
    return left.createdAt.isAtSameMomentAs(right.createdAt) &&
        left.steps == right.steps &&
        left.inclineDegrees == right.inclineDegrees &&
        left.speedMph == right.speedMph &&
        left.durationMinutes == right.durationMinutes &&
        left.estimatedCalories == right.estimatedCalories;
  }

  DateTime _normalizeDay(DateTime day) {
    return DateTime(day.year, day.month, day.day);
  }

  DateTime _entryTimestampForDay(DateTime? day) {
    if (day == null) return DateTime.now();
    final normalizedDay = _normalizeDay(day);
    final now = DateTime.now();
    if (_isSameDay(normalizedDay, now)) {
      return now;
    }
    return DateTime(
      normalizedDay.year,
      normalizedDay.month,
      normalizedDay.day,
      12,
    );
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  bool get _isMobilePlatform {
    if (kIsWeb) return false;
    return _isAndroid || _isIOS;
  }

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  List<HealthDataType> get _healthTypes => const [
        HealthDataType.STEPS,
        HealthDataType.ACTIVE_ENERGY_BURNED,
      ];

  List<HealthDataAccess> get _healthPermissions => const [
        HealthDataAccess.READ,
        HealthDataAccess.READ,
      ];

  @override
  void dispose() {
    stopLiveTracking();
    super.dispose();
  }
}
