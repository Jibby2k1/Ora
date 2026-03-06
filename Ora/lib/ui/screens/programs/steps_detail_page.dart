import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/manual_treadmill_entry.dart';
import '../../../domain/services/steps_service.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import '../../widgets/steps/steps_progress_ring.dart';

class StepsDetailPage extends StatefulWidget {
  const StepsDetailPage({
    super.key,
    required this.stepsService,
  });

  final StepsService stepsService;

  @override
  State<StepsDetailPage> createState() => _StepsDetailPageState();
}

class _StepsDetailPageState extends State<StepsDetailPage> {
  static const int _pageAnchor = 10000;
  static const double _ringNavButtonWidth = 44;

  final NumberFormat _countFormatter = NumberFormat.decimalPattern();
  late final PageController _pageController;
  late final DateTime _today;
  late DateTime _selectedDay;
  int _currentPageIndex = _pageAnchor;
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    _today = _normalizeDay(DateTime.now());
    _selectedDay = _today;
    _pageController = PageController(initialPage: _pageAnchor);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _normalizeDay(DateTime day) {
    return DateTime(day.year, day.month, day.day);
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  DateTime _dayForPage(int pageIndex) {
    final daysBack = _pageAnchor - pageIndex;
    return _today.subtract(Duration(days: daysBack));
  }

  int _pageForDay(DateTime day) {
    final normalizedDay = _normalizeDay(day);
    final daysBack = _today.difference(normalizedDay).inDays;
    return (_pageAnchor - daysBack).clamp(0, _pageAnchor);
  }

  void _handlePageChanged(int pageIndex) {
    final nextDay = _dayForPage(pageIndex);
    setState(() {
      _currentPageIndex = pageIndex;
      _selectedDay = nextDay;
    });
    unawaited(HapticFeedback.selectionClick());
  }

  Future<void> _goToPreviousDay() async {
    if (!_pageController.hasClients || _currentPageIndex <= 0) return;
    await _pageController.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _goToNextDay() async {
    if (!_pageController.hasClients || _currentPageIndex >= _pageAnchor) return;
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2000),
      lastDate: _today,
    );
    if (!mounted || picked == null) return;
    final normalizedPicked = _normalizeDay(picked);
    if (_isSameDay(normalizedPicked, _selectedDay)) return;
    final targetPage = _pageForDay(normalizedPicked);
    final currentPage = _pageController.hasClients
        ? (_pageController.page?.round() ?? _pageAnchor)
        : _pageAnchor;
    if ((currentPage - targetPage).abs() > 7) {
      _pageController.jumpToPage(targetPage);
    } else {
      await _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _showEntrySheet(
    DateTime day, {
    ManualTreadmillEntry? entry,
  }) async {
    if (!mounted) return;
    final pendingEntry = await showGeneralDialog<_PendingTreadmillEntry>(
      context: context,
      barrierLabel: 'Treadmill Entry',
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      pageBuilder: (_, __, ___) => _AddTreadmillEntrySheet(entry: entry),
    );

    if (!mounted || pendingEntry == null) return;
    if (entry == null) {
      await widget.stepsService.saveManualEntry(
        steps: pendingEntry.steps,
        inclineDegrees: pendingEntry.inclineDegrees,
        speedMph: pendingEntry.speedMph,
        durationMinutes: pendingEntry.durationMinutes,
        day: day,
      );
    } else {
      final updated = await widget.stepsService.updateManualEntry(
        entry,
        inclineDegrees: pendingEntry.inclineDegrees,
        speedMph: pendingEntry.speedMph,
        durationMinutes: pendingEntry.durationMinutes,
      );
      if (!updated) return;
    }
    if (!mounted) return;
    setState(() {
      _refreshTick++;
    });
    _showMessage(
      entry == null
          ? 'Manual treadmill entry saved.'
          : 'Manual treadmill entry updated.',
    );
  }

  Future<void> _deleteEntry(ManualTreadmillEntry entry) async {
    final removedIndex = await widget.stepsService.deleteManualEntry(entry);
    if (!mounted || removedIndex == null) return;
    setState(() {
      _refreshTick++;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: const Text('Manual treadmill entry removed.'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            unawaited(() async {
              await widget.stepsService.restoreManualEntry(
                entry,
                atIndex: removedIndex,
              );
              if (!mounted) return;
              setState(() {
                _refreshTick++;
              });
            }());
          },
        ),
      ),
    );
    var isClosed = false;
    unawaited(
      controller.closed.then((_) {
        isClosed = true;
      }),
    );
    unawaited(
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (!mounted || isClosed) return;
        controller.close();
      }),
    );
  }

  Future<void> _editEntry(DateTime day, ManualTreadmillEntry entry) async {
    await _showEntrySheet(day, entry: entry);
  }

  Future<void> _editGoalSteps() async {
    final nextValue = await showDialog<int>(
      context: context,
      builder: (_) => _EditGoalStepsDialog(
        initialGoalSteps: widget.stepsService.goalSteps,
      ),
    );
    if (!mounted || nextValue == null) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await widget.stepsService.setGoalSteps(nextValue);
    if (!mounted) return;
    setState(() {
      _refreshTick++;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> _handleMenuAction(String value) async {
    if (value == 'edit_goal') {
      await _editGoalSteps();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Steps'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(
              width: 44,
              height: 44,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_horiz),
                onSelected: (value) {
                  unawaited(_handleMenuAction(value));
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'edit_goal',
                    child: Text('Edit Goals'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          if (!widget.stepsService.isPermissionGranted)
            const SizedBox.shrink()
          else
            PageView.builder(
              controller: _pageController,
              itemCount: _pageAnchor + 1,
              onPageChanged: _handlePageChanged,
              itemBuilder: (context, index) {
                final day = _dayForPage(index);
                return _StepsDayContent(
                  key: ValueKey('${day.toIso8601String()}-$_refreshTick'),
                  day: day,
                  today: _today,
                  stepsService: widget.stepsService,
                  countFormatter: _countFormatter,
                  refreshToken: _refreshTick,
                  onPickDate: _pickDate,
                  onGoToPreviousDay: _goToPreviousDay,
                  onGoToNextDay: _goToNextDay,
                  onAddEntry: () => _showEntrySheet(day),
                  onEditEntry: (entry) => _editEntry(day, entry),
                  onDeleteEntry: _deleteEntry,
                );
              },
            ),
        ],
      ),
    );
  }
}

class _StepsDayContent extends StatefulWidget {
  const _StepsDayContent({
    super.key,
    required this.day,
    required this.today,
    required this.stepsService,
    required this.countFormatter,
    required this.refreshToken,
    required this.onPickDate,
    required this.onGoToPreviousDay,
    required this.onGoToNextDay,
    required this.onAddEntry,
    required this.onEditEntry,
    required this.onDeleteEntry,
  });

  final DateTime day;
  final DateTime today;
  final StepsService stepsService;
  final NumberFormat countFormatter;
  final int refreshToken;
  final Future<void> Function() onPickDate;
  final Future<void> Function() onGoToPreviousDay;
  final Future<void> Function() onGoToNextDay;
  final Future<void> Function() onAddEntry;
  final Future<void> Function(ManualTreadmillEntry entry) onEditEntry;
  final Future<void> Function(ManualTreadmillEntry entry) onDeleteEntry;

  @override
  State<_StepsDayContent> createState() => _StepsDayContentState();
}

class _StepsDayContentState extends State<_StepsDayContent> {
  late Future<StepsDayView> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.stepsService.loadDay(widget.day);
  }

  @override
  void didUpdateWidget(covariant _StepsDayContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameDay(oldWidget.day, widget.day) ||
        oldWidget.refreshToken != widget.refreshToken) {
      _future = widget.stepsService.loadDay(widget.day);
    }
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _formatCount(num value) {
    return widget.countFormatter.format(value.round());
  }

  String _formatDouble(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  String _formatDistanceNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    final oneDecimal = double.parse(value.toStringAsFixed(1));
    if (oneDecimal == value) {
      return oneDecimal.toStringAsFixed(1);
    }
    return value.toStringAsFixed(2);
  }

  String _formatDistanceValue(double distanceKm) {
    final miles = distanceKm / 1.609344;
    final milesRounded = double.parse(miles.toStringAsFixed(2));
    final kmRounded = double.parse(distanceKm.toStringAsFixed(2));
    final mileLabel = milesRounded == 1 || milesRounded < 1 ? 'mile' : 'miles';
    return '${_formatDistanceNumber(milesRounded)} $mileLabel '
        '(${_formatDistanceNumber(kmRounded)} km)';
  }

  String _formatDurationValue(double totalMinutes) {
    final roundedMinutes = totalMinutes.round();
    final hours = roundedMinutes ~/ 60;
    final minutes = roundedMinutes % 60;
    if (hours <= 0) {
      final minuteLabel = minutes == 1 ? 'min' : 'min';
      return '$minutes $minuteLabel';
    }
    if (minutes == 0) {
      final hourLabel = hours == 1 ? 'hr' : 'hr';
      return '$hours $hourLabel';
    }
    return '$hours hr $minutes min';
  }

  String _entryTitle(ManualTreadmillEntry entry) {
    final bonusSteps = widget.stepsService.equivalentStepsForEntry(entry);
    return '${_formatCount(entry.steps)} Treadmill Steps '
        '→ ${_formatCount(bonusSteps)} Bonus Steps '
        '(${entry.estimatedCalories.toStringAsFixed(0)} kcal)';
  }

  String _entrySubtitle(ManualTreadmillEntry entry) {
    final durationLabel = entry.durationMinutes == null
        ? 'Duration estimated'
        : '${entry.durationMinutes} min';
    return '${_formatDouble(entry.speedMph)} mph • '
        '${_formatDouble(entry.inclineDegrees)}° incline • '
        '$durationLabel';
  }

  String? _relativeDayLabel() {
    if (_isSameDay(widget.day, widget.today)) {
      return 'Today';
    }
    if (_isSameDay(
      widget.day,
      widget.today.subtract(const Duration(days: 1)),
    )) {
      return 'Yesterday';
    }
    return null;
  }

  String _dateLabel() {
    final relative = _relativeDayLabel();
    if (relative != null) {
      return DateFormat.yMMMd().format(widget.day);
    }
    return DateFormat('EEE, MMM d, y').format(widget.day);
  }

  Color _treadmillTint(BuildContext context) {
    final theme = Theme.of(context);
    return Color.lerp(
          theme.colorScheme.primary,
          theme.colorScheme.surface,
          0.32,
        ) ??
        theme.colorScheme.primary.withValues(alpha: 0.72);
  }

  Widget _buildContent(BuildContext context, StepsDayView data) {
    final displayEntries = data.manualEntries.reversed.toList(growable: false);
    final theme = Theme.of(context);
    final ringSize =
        (MediaQuery.of(context).size.width * 0.62).clamp(220.0, 280.0);
    final relativeLabel = _relativeDayLabel();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: InkWell(
            onTap: widget.onPickDate,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (relativeLabel != null)
                        Text(
                          relativeLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.64),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _dateLabel(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_drop_down_rounded,
                            size: 28,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: _StepsDetailPageState._ringNavButtonWidth,
                    child: _RingNavButton(
                      icon: Icons.chevron_left,
                      onTap: widget.onGoToPreviousDay,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: StepsProgressRing(
                        progress: data.trackedProgressSegment,
                        secondaryProgress: data.manualProgressSegment,
                        size: ringSize,
                        strokeWidth: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Text(
                                _formatCount(data.totalSteps),
                                key: ValueKey(data.totalSteps),
                                style: theme.textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'out of ${_formatCount(data.goalSteps)} Steps',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.68,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _StepsDetailPageState._ringNavButtonWidth,
                    child: _isSameDay(widget.day, widget.today)
                        ? const SizedBox.shrink()
                        : _RingNavButton(
                            icon: Icons.chevron_right,
                            onTap: widget.onGoToNextDay,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${(data.progress * 100).round()}% Complete',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  _LegendPill(
                    color: theme.colorScheme.primary,
                    label: 'Flat Steps',
                  ),
                  _LegendPill(
                    color: _treadmillTint(context),
                    label: 'Bonus Steps',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Flat Steps: ${_formatCount(data.flatSteps)} • '
                'Bonus Steps: ${_formatCount(data.bonusSteps)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              _StepsMetricRow(
                label: 'Distance (Estimated)',
                value: _formatDistanceValue(data.distanceKm),
                subtitle: 'Based on flat + bonus steps for this day',
              ),
              const Divider(height: 1),
              _StepsMetricRow(
                label: 'Duration',
                value: _formatDurationValue(data.totalDurationMinutes),
                subtitle:
                    'Flat Steps: ${_formatDurationValue(data.flatStepsDurationMinutes)} + '
                    'Bonus Steps: ${_formatDurationValue(data.bonusStepsDurationMinutes)}',
              ),
              const Divider(height: 1),
              _StepsMetricRow(
                label: 'Energy Burned (Estimated)',
                value: '${data.totalEstimatedCalories.toStringAsFixed(1)} kcal',
                subtitle:
                    'Flat Steps Energy: ${data.flatStepsEstimatedCalories.toStringAsFixed(1)} kcal + '
                    'Bonus Steps Energy: ${data.bonusStepsEstimatedCalories.toStringAsFixed(1)} kcal',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manual Treadmill Entry',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Entries shown here are saved for the selected day only.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                ),
              ),
              const SizedBox(height: 16),
              if (displayEntries.isEmpty)
                Text(
                  'No treadmill entries saved for this day.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var index = 0;
                            index < displayEntries.length;
                            index++) ...[
                          _EntryListTile(
                            title: _entryTitle(displayEntries[index]),
                            subtitle: _entrySubtitle(displayEntries[index]),
                            onEdit: () => widget.onEditEntry(
                              displayEntries[index],
                            ),
                            onDelete: () => widget.onDeleteEntry(
                              displayEntries[index],
                            ),
                          ),
                          if (index < displayEntries.length - 1)
                            const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: widget.onAddEntry,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.16),
                    foregroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Add Entry',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isSameDay(widget.day, widget.today)) {
      return AnimatedBuilder(
        animation: widget.stepsService,
        builder: (context, _) => _buildContent(
          context,
          widget.stepsService.todayView,
        ),
      );
    }

    return FutureBuilder<StepsDayView>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) {
          return const Center(child: Text('Unable to load steps.'));
        }
        return _buildContent(context, snapshot.data!);
      },
    );
  }
}

class _StepsMetricRow extends StatelessWidget {
  const _StepsMetricRow({
    required this.label,
    required this.value,
    this.subtitle,
  });

  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 188),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    textAlign: TextAlign.start,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.start,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StepsNumberPadMode {
  integer,
  decimal,
  timer,
}

Future<String?> _showStepsNumberPad({
  required BuildContext context,
  required String title,
  required String initialValue,
  required _StepsNumberPadMode mode,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StepsNumberPadSheet(
      title: title,
      initialValue: initialValue,
      mode: mode,
    ),
  );
}

String _formatTimerDigits(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return '';
  }
  final secondsText = digits.length <= 2
      ? digits.padLeft(2, '0')
      : digits.substring(digits.length - 2);
  final minutesText =
      digits.length <= 2 ? '0' : digits.substring(0, digits.length - 2);
  final minutes = int.tryParse(minutesText) ?? 0;
  return '$minutes:$secondsText';
}

int? _timerDigitsToRoundedMinutes(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return null;
  }
  final seconds = int.tryParse(
        digits.length <= 2 ? digits : digits.substring(digits.length - 2),
      ) ??
      0;
  final minutes = int.tryParse(
        digits.length <= 2 ? '0' : digits.substring(0, digits.length - 2),
      ) ??
      0;
  final totalSeconds = (minutes * 60) + seconds;
  if (totalSeconds <= 0) {
    return null;
  }
  return ((totalSeconds + 59) ~/ 60);
}

class _EntryInputField extends StatelessWidget {
  const _EntryInputField({
    required this.value,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final String value;
  final String label;
  final String hint;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () {
            unawaited(onTap());
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.14),
              ),
            ),
            child: Text(
              hasValue ? value : hint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: hasValue
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.42),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepsNumberPadSheet extends StatefulWidget {
  const _StepsNumberPadSheet({
    required this.title,
    required this.initialValue,
    required this.mode,
  });

  final String title;
  final String initialValue;
  final _StepsNumberPadMode mode;

  @override
  State<_StepsNumberPadSheet> createState() => _StepsNumberPadSheetState();
}

class _StepsNumberPadSheetState extends State<_StepsNumberPadSheet> {
  late String _rawValue;

  @override
  void initState() {
    super.initState();
    _rawValue = widget.initialValue;
  }

  void _append(String char) {
    setState(() {
      if (widget.mode == _StepsNumberPadMode.timer) {
        if (RegExp(r'[0-9]').hasMatch(char)) {
          _rawValue += char;
        }
        return;
      }
      if (char == '.') {
        if (widget.mode != _StepsNumberPadMode.decimal ||
            _rawValue.contains('.')) {
          return;
        }
        _rawValue = _rawValue.isEmpty ? '0.' : '$_rawValue.';
        return;
      }
      _rawValue += char;
    });
  }

  void _backspace() {
    if (_rawValue.isEmpty) return;
    setState(() {
      _rawValue = _rawValue.substring(0, _rawValue.length - 1);
    });
  }

  void _clear() {
    setState(() {
      _rawValue = '';
    });
  }

  Widget _keyButton(
    BuildContext context,
    String label, {
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor:
                  theme.colorScheme.surface.withValues(alpha: 0.22),
              foregroundColor: theme.colorScheme.onSurface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supportsDecimal = widget.mode == _StepsNumberPadMode.decimal;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _keyButton(context, '1', onPressed: () => _append('1')),
                  _keyButton(context, '2', onPressed: () => _append('2')),
                  _keyButton(context, '3', onPressed: () => _append('3')),
                ],
              ),
              Row(
                children: [
                  _keyButton(context, '4', onPressed: () => _append('4')),
                  _keyButton(context, '5', onPressed: () => _append('5')),
                  _keyButton(context, '6', onPressed: () => _append('6')),
                ],
              ),
              Row(
                children: [
                  _keyButton(context, '7', onPressed: () => _append('7')),
                  _keyButton(context, '8', onPressed: () => _append('8')),
                  _keyButton(context, '9', onPressed: () => _append('9')),
                ],
              ),
              Row(
                children: [
                  _keyButton(
                    context,
                    supportsDecimal ? '.' : 'C',
                    onPressed: supportsDecimal ? () => _append('.') : _clear,
                  ),
                  _keyButton(context, '0', onPressed: () => _append('0')),
                  _keyButton(context, '⌫', onPressed: _backspace),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(_rawValue),
                      child: const Text('OK'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTreadmillEntrySheet extends StatefulWidget {
  const _AddTreadmillEntrySheet({
    this.entry,
  });

  final ManualTreadmillEntry? entry;

  @override
  State<_AddTreadmillEntrySheet> createState() =>
      _AddTreadmillEntrySheetState();
}

class _AddTreadmillEntrySheetState extends State<_AddTreadmillEntrySheet> {
  static const double _numberPadLiftHeight = 354;

  final ScrollController _scrollController = ScrollController();
  final Object _numberPadTapGroup = Object();
  final TextEditingController _inlineEditDisplayController =
      TextEditingController();
  final FocusNode _inlineEditDisplayFocusNode = FocusNode();

  String? _activeNumberPadFieldKey;
  String _activeNumberPadTitle = '';
  bool _activeNumberPadAllowDecimal = false;
  bool _activeNumberPadIsTimer = false;
  bool _numberPadReplacePending = false;
  String _durationRaw = '';
  String _inclineRaw = '';
  String _speedRaw = '';

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    if (entry == null) return;
    final durationMinutes = entry.durationMinutes;
    if (durationMinutes != null && durationMinutes > 0) {
      _durationRaw = '${durationMinutes}00';
    }
    _inclineRaw = _formatEditableDouble(entry.inclineDegrees);
    _speedRaw = _formatEditableDouble(entry.speedMph);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inlineEditDisplayFocusNode.dispose();
    _inlineEditDisplayController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  String _rawValueForField(String fieldKey) {
    switch (fieldKey) {
      case 'duration':
        return _durationRaw;
      case 'incline':
        return _inclineRaw;
      case 'speed':
        return _speedRaw;
      default:
        return '';
    }
  }

  String _displayValueForField(String fieldKey) {
    final rawValue = _rawValueForField(fieldKey);
    if (fieldKey == 'duration') {
      return _formatTimerDigits(rawValue);
    }
    return rawValue;
  }

  void _applyRawValueForField(String fieldKey, String rawValue) {
    switch (fieldKey) {
      case 'duration':
        _durationRaw = rawValue;
        break;
      case 'incline':
        _inclineRaw = rawValue;
        break;
      case 'speed':
        _speedRaw = rawValue;
        break;
    }
  }

  Future<void> _bringFieldIntoView(BuildContext fieldContext) async {
    if (Scrollable.maybeOf(fieldContext) == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!fieldContext.mounted) return;
    try {
      await Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.14,
      );
    } catch (_) {
      // Ignore detached contexts.
    }
  }

  void _syncInlineEditDisplayState() {
    final fieldKey = _activeNumberPadFieldKey;
    if (fieldKey == null) {
      if (_inlineEditDisplayController.text.isNotEmpty ||
          _inlineEditDisplayController.selection.baseOffset != 0 ||
          _inlineEditDisplayController.selection.extentOffset != 0) {
        _inlineEditDisplayController.value = const TextEditingValue();
      }
      if (_inlineEditDisplayFocusNode.hasFocus) {
        _inlineEditDisplayFocusNode.unfocus();
      }
      return;
    }
    final value = _displayValueForField(fieldKey);
    final nextValue = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    if (_inlineEditDisplayController.value != nextValue) {
      _inlineEditDisplayController.value = nextValue;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeNumberPadFieldKey != fieldKey) return;
      if (!_inlineEditDisplayFocusNode.hasFocus) {
        _inlineEditDisplayFocusNode.requestFocus();
      }
    });
  }

  void _closeNumberPad() {
    if (_activeNumberPadFieldKey == null) return;
    setState(() {
      _activeNumberPadFieldKey = null;
      _activeNumberPadTitle = '';
      _activeNumberPadAllowDecimal = false;
      _activeNumberPadIsTimer = false;
      _numberPadReplacePending = false;
    });
    _syncInlineEditDisplayState();
  }

  void _activateNumberPad({
    required String title,
    required String fieldKey,
    required BuildContext fieldContext,
    bool allowDecimal = false,
    bool isTimer = false,
  }) {
    final rawValue = _rawValueForField(fieldKey);
    if (_activeNumberPadFieldKey == fieldKey) {
      setState(() {
        _numberPadReplacePending = false;
      });
      _syncInlineEditDisplayState();
      unawaited(_bringFieldIntoView(fieldContext));
      return;
    }
    setState(() {
      _activeNumberPadFieldKey = fieldKey;
      _activeNumberPadTitle = title;
      _activeNumberPadAllowDecimal = allowDecimal;
      _activeNumberPadIsTimer = isTimer;
      _numberPadReplacePending = rawValue.isNotEmpty;
    });
    _syncInlineEditDisplayState();
    unawaited(_bringFieldIntoView(fieldContext));
  }

  void _appendNumberPadChar(String value) {
    final fieldKey = _activeNumberPadFieldKey;
    if (fieldKey == null) return;
    var nextRaw = _numberPadReplacePending ? '' : _rawValueForField(fieldKey);
    if (_activeNumberPadIsTimer) {
      if (RegExp(r'[0-9]').hasMatch(value)) {
        nextRaw = '$nextRaw$value';
      } else {
        return;
      }
    } else if (_activeNumberPadAllowDecimal && value == '.') {
      if (nextRaw.contains('.')) return;
      nextRaw = nextRaw.isEmpty ? '0.' : '$nextRaw.';
    } else {
      nextRaw = '$nextRaw$value';
    }
    setState(() {
      _numberPadReplacePending = false;
      _applyRawValueForField(fieldKey, nextRaw);
    });
    _syncInlineEditDisplayState();
  }

  void _backspaceNumberPad() {
    final fieldKey = _activeNumberPadFieldKey;
    if (fieldKey == null) return;
    var nextRaw = _rawValueForField(fieldKey);
    if (_numberPadReplacePending) {
      nextRaw = '';
    } else if (nextRaw.isNotEmpty) {
      nextRaw = nextRaw.substring(0, nextRaw.length - 1);
    } else {
      return;
    }
    setState(() {
      _numberPadReplacePending = false;
      _applyRawValueForField(fieldKey, nextRaw);
    });
    _syncInlineEditDisplayState();
  }

  void _clearNumberPad() {
    final fieldKey = _activeNumberPadFieldKey;
    if (fieldKey == null) return;
    setState(() {
      _numberPadReplacePending = false;
      _applyRawValueForField(fieldKey, '');
    });
    _syncInlineEditDisplayState();
  }

  void _confirmNumberPad() {
    _closeNumberPad();
  }

  Widget _buildInlineEditingField({
    required TextStyle? style,
    required Color cursorColor,
  }) {
    return IgnorePointer(
      child: EditableText(
        controller: _inlineEditDisplayController,
        focusNode: _inlineEditDisplayFocusNode,
        readOnly: true,
        showCursor: true,
        backgroundCursorColor: Colors.transparent,
        selectionColor: Colors.transparent,
        selectionControls: null,
        rendererIgnoresPointer: true,
        maxLines: 1,
        textAlign: TextAlign.left,
        style: style ?? const TextStyle(),
        cursorColor: cursorColor,
        keyboardType: TextInputType.none,
      ),
    );
  }

  Widget _buildSelectedInlineLabel({
    required String value,
    required TextStyle? style,
    required Color textColor,
    required Color highlightColor,
  }) {
    return Text(
      value.isEmpty ? ' ' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style?.copyWith(
        color: textColor,
        backgroundColor: highlightColor,
      ),
    );
  }

  Widget _buildTapFieldText({
    required BuildContext context,
    required String fieldKey,
    required String value,
    required String hintText,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final hasValue = value.isNotEmpty;
    final isActive = _activeNumberPadFieldKey == fieldKey;
    final isSelected = isActive && _numberPadReplacePending && hasValue;
    final baseStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: hasValue
              ? scheme.onSurface
              : scheme.onSurface.withValues(alpha: 0.42),
        );

    if (isSelected) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _buildSelectedInlineLabel(
          value: value,
          style: baseStyle,
          textColor: scheme.onSurface,
          highlightColor: scheme.primary.withValues(alpha: 0.2),
        ),
      );
    }

    if (isActive) {
      return Align(
        alignment: Alignment.centerLeft,
        child: _buildInlineEditingField(
          style: baseStyle?.copyWith(color: scheme.onSurface),
          cursorColor: scheme.primary,
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        hasValue ? value : hintText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      ),
    );
  }

  BoxDecoration _tapFieldDecoration(BuildContext context, String fieldKey) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = _activeNumberPadFieldKey == fieldKey;
    return BoxDecoration(
      color: scheme.surface.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: isActive
            ? scheme.primary.withValues(alpha: 0.7)
            : scheme.outline.withValues(alpha: 0.14),
      ),
    );
  }

  Widget _buildEditableField({
    required BuildContext context,
    required String fieldKey,
    required String label,
    required String hintText,
    required String value,
    required String title,
    bool allowDecimal = false,
    bool isTimer = false,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Builder(
          builder: (fieldContext) => TapRegion(
            groupId: _numberPadTapGroup,
            child: InkWell(
              onTap: () => _activateNumberPad(
                title: title,
                fieldKey: fieldKey,
                fieldContext: fieldContext,
                allowDecimal: allowDecimal,
                isTimer: isTimer,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: _tapFieldDecoration(context, fieldKey),
                child: _buildTapFieldText(
                  context: context,
                  fieldKey: fieldKey,
                  value: value,
                  hintText: hintText,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineNumberPad() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final supportsDecimal = _activeNumberPadAllowDecimal;
    final keypadPanelTopColor = scheme.surface.withValues(alpha: 0.66);
    final keypadPanelBottomColor =
        scheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final keypadPanelBorderColor = scheme.outline.withValues(alpha: 0.18);
    final keypadKeyColor = scheme.surface.withValues(alpha: 0.74);
    final keypadKeyBorderColor = scheme.onSurface.withValues(alpha: 0.12);

    Widget keyButton(
      String label, {
      required VoidCallback onPressed,
      Color? backgroundColor,
      Color? foregroundColor,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: backgroundColor ?? keypadKeyColor,
                foregroundColor: foregroundColor ?? scheme.onSurface,
                shadowColor: Colors.transparent,
                side: BorderSide(color: keypadKeyBorderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: label == '⌫'
                  ? const Icon(Icons.backspace_outlined, size: 20)
                  : Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(28),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                keypadPanelTopColor,
                keypadPanelBottomColor,
              ],
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
            border: Border.all(color: keypadPanelBorderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _activeNumberPadTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  keyButton('1', onPressed: () => _appendNumberPadChar('1')),
                  keyButton('2', onPressed: () => _appendNumberPadChar('2')),
                  keyButton('3', onPressed: () => _appendNumberPadChar('3')),
                ],
              ),
              Row(
                children: [
                  keyButton('4', onPressed: () => _appendNumberPadChar('4')),
                  keyButton('5', onPressed: () => _appendNumberPadChar('5')),
                  keyButton('6', onPressed: () => _appendNumberPadChar('6')),
                ],
              ),
              Row(
                children: [
                  keyButton('7', onPressed: () => _appendNumberPadChar('7')),
                  keyButton('8', onPressed: () => _appendNumberPadChar('8')),
                  keyButton('9', onPressed: () => _appendNumberPadChar('9')),
                ],
              ),
              Row(
                children: [
                  keyButton(
                    supportsDecimal ? '.' : 'C',
                    onPressed: supportsDecimal
                        ? () => _appendNumberPadChar('.')
                        : _clearNumberPad,
                  ),
                  keyButton('0', onPressed: () => _appendNumberPadChar('0')),
                  keyButton('⌫', onPressed: _backspaceNumberPad),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  keyButton(
                    'Cancel',
                    onPressed: _closeNumberPad,
                  ),
                  keyButton(
                    'OK',
                    onPressed: _confirmNumberPad,
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.surface,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final incline = double.tryParse(_inclineRaw.trim());
    final speed = double.tryParse(_speedRaw.trim());
    final duration = _timerDigitsToRoundedMinutes(_durationRaw);

    if (duration == null || duration <= 0) {
      _showMessage('Enter a valid duration.');
      return;
    }
    if (incline == null || incline < 0 || incline > 30) {
      _showMessage('Incline must be between 0 and 30 degrees.');
      return;
    }
    if (speed == null || speed <= 0) {
      _showMessage('Enter a valid speed in mph.');
      return;
    }

    Navigator.of(context).pop(
      _PendingTreadmillEntry(
        steps: null,
        inclineDegrees: incline,
        speedMph: speed,
        durationMinutes: duration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEditing = widget.entry != null;
    final formCard = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEditing ? 'Edit Treadmill Entry' : 'Add Treadmill Entry',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter a duration, incline, and speed. Steps are estimated from your speed.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 16),
          _buildEditableField(
            context: context,
            fieldKey: 'duration',
            label: 'Duration',
            hintText: '00:00',
            value: _formatTimerDigits(_durationRaw),
            title: 'Duration',
            isTimer: true,
          ),
          const SizedBox(height: 12),
          _buildEditableField(
            context: context,
            fieldKey: 'incline',
            label: 'Incline (degrees)',
            hintText: '0 to 30',
            value: _inclineRaw,
            title: 'Incline (degrees)',
            allowDecimal: true,
          ),
          const SizedBox(height: 12),
          _buildEditableField(
            context: context,
            fieldKey: 'speed',
            label: 'Speed (mph)',
            hintText: 'e.g. 3.0',
            value: _speedRaw,
            title: 'Speed (mph)',
            allowDecimal: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _submit,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );

    return TapRegionSurface(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_activeNumberPadFieldKey != null) {
                    _closeNumberPad();
                    return;
                  }
                  Navigator.of(context).pop();
                },
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 +
                      (_activeNumberPadFieldKey != null
                          ? _numberPadLiftHeight
                          : 0),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: formCard,
                  ),
                ),
              ),
            ),
            if (_activeNumberPadFieldKey != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: TapRegion(
                  groupId: _numberPadTapGroup,
                  child: _buildInlineNumberPad(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EntryListTile extends StatelessWidget {
  const _EntryListTile({
    required this.title,
    required this.subtitle,
    required this.onEdit,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 4,
        ),
        title: Text(
          title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit entry',
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete entry',
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendPill extends StatelessWidget {
  const _LegendPill({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingNavButton extends StatelessWidget {
  const _RingNavButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _StepsDetailPageState._ringNavButtonWidth,
      height: _StepsDetailPageState._ringNavButtonWidth,
      child: IconButton(
        onPressed: () {
          unawaited(onTap());
        },
        padding: EdgeInsets.zero,
        icon: Icon(
          icon,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
        ),
      ),
    );
  }
}

class _EditGoalStepsDialog extends StatefulWidget {
  const _EditGoalStepsDialog({
    required this.initialGoalSteps,
  });

  final int initialGoalSteps;

  @override
  State<_EditGoalStepsDialog> createState() => _EditGoalStepsDialogState();
}

class _EditGoalStepsDialogState extends State<_EditGoalStepsDialog> {
  late String _goalRaw;

  @override
  void initState() {
    super.initState();
    _goalRaw = widget.initialGoalSteps.toString();
  }

  void _save() {
    final parsed = int.tryParse(_goalRaw.trim());
    if (parsed == null || parsed <= 0) return;
    Navigator.of(context).pop(parsed);
  }

  Future<void> _editGoal() async {
    final next = await _showStepsNumberPad(
      context: context,
      title: 'Goal Steps',
      initialValue: _goalRaw,
      mode: _StepsNumberPadMode.integer,
    );
    if (!mounted || next == null) return;
    setState(() {
      _goalRaw = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Goal Steps'),
      content: _EntryInputField(
        value: _goalRaw,
        label: 'Goal Steps',
        hint: 'e.g. 10000',
        onTap: _editGoal,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PendingTreadmillEntry {
  const _PendingTreadmillEntry({
    required this.steps,
    required this.inclineDegrees,
    required this.speedMph,
    required this.durationMinutes,
  });

  final int? steps;
  final double inclineDegrees;
  final double speedMph;
  final int? durationMinutes;
}

String _formatEditableDouble(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}
