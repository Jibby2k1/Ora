import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app.dart';
import '../../../core/voice/stt.dart';
import '../../../data/db/db.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../screens/shell/app_shell_controller.dart';
import '../glass/glass_card.dart';

enum _OrbInputType { camera, upload, mic, text }

enum _OrbDestination { training, diet, appearance, leaderboard, settings }

class OraOrb extends StatefulWidget {
  const OraOrb({super.key});

  @override
  State<OraOrb> createState() => _OraOrbState();
}

class _OraOrbState extends State<OraOrb> with TickerProviderStateMixin {
  static const double _orbSize = 56;
  static const double _dockWidth = 84;
  static const double _dockHeight = 84;
  static const double _edgePadding = 12;
  static const double _dragOverscroll = 24;

  final SettingsRepo _settingsRepo = SettingsRepo(AppDatabase.instance);
  final SpeechToTextEngine _stt = SpeechToTextEngine.instance;

  late final AnimationController _floatController;
  late final AnimationController _snapController;
  late final AnimationController _waveController;
  late final AnimationController _driftController;
  Animation<Offset>? _snapAnimation;
  Animation<Offset>? _driftAnimation;
  late final Ticker _momentumTicker;
  Offset _momentumVelocity = Offset.zero;
  Duration _lastTick = Duration.zero;

  Size? _layoutSize;
  bool _positionReady = false;
  bool _showDockTarget = false;
  bool _dragging = false;
  bool _expanded = false;
  bool _hidden = false;
  bool _recording = false;
  bool _routing = false;
  bool _docked = true;
  String? _partialTranscript;
  _OrbDestination? _lastDestination;

  Offset _position = Offset.zero;
  Offset _driftOffset = Offset.zero;
  Offset _dragVelocity = Offset.zero;
  int _lastDragTs = 0;
  Offset _dragTarget = Offset.zero;
  bool _dragTickerActive = false;
  double _toolbarHeight = kToolbarHeight;
  double? _savedPosX;
  double? _savedPosY;

  Timer? _recordTimeout;
  Timer? _driftTimer;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _snapController.addListener(() {
      if (_snapAnimation == null) return;
      setState(() {
        _position = _snapAnimation!.value;
      });
    });
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _driftController.addListener(() {
      if (_driftAnimation == null) return;
      setState(() {
        _driftOffset = _driftAnimation!.value;
      });
    });
    AppShellController.instance.orbHidden.addListener(_handleHiddenChange);
    _momentumTicker = createTicker(_onMomentumTickSafe);
    _loadSettings();
    _startDriftLoop();
    _momentumTicker.start();
  }

  @override
  void dispose() {
    AppShellController.instance.orbHidden.removeListener(_handleHiddenChange);
    _floatController.dispose();
    _snapController.dispose();
    _waveController.dispose();
    _driftController.dispose();
    _momentumTicker.dispose();
    _recordTimeout?.cancel();
    _driftTimer?.cancel();
    if (_recording) {
      _stt.stopListening();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final hidden = await _settingsRepo.getOrbHidden();
    final docked = await _settingsRepo.getOrbDocked();
    final posX = await _settingsRepo.getOrbPosX();
    final posY = await _settingsRepo.getOrbPosY();
    if (!mounted) return;
    setState(() {
      _hidden = hidden;
      _docked = docked;
      _savedPosX = posX;
      _savedPosY = posY;
    });
    AppShellController.instance.setOrbHidden(hidden);
  }

  void _handleHiddenChange() {
    if (!mounted) return;
    final value = AppShellController.instance.orbHidden.value;
    if (_hidden == value) return;
    setState(() => _hidden = value);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final padding = MediaQuery.of(context).padding;
        _toolbarHeight = Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight;
        _ensurePosition(size, padding);
        final dockRect = _dockRect(size, padding);
        final orbOffset = _position + _driftOffset;
        final deckOffset = _deckOffset(size, padding, orbOffset);

        return Stack(
          children: [
            // Dock target intentionally hidden for a clean top-right slot.
            if (_expanded && !_hidden)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _expanded = false),
                  child: Container(color: Colors.transparent),
                ),
              ),
            if (!_hidden)
              Positioned(
                left: orbOffset.dx,
                top: orbOffset.dy,
                child: _buildOrb(),
              ),
            if (_expanded && !_hidden)
              Positioned(
                left: deckOffset.dx,
                top: deckOffset.dy,
                child: _buildDeck(),
              ),
            if (_hidden)
              Positioned(
                right: 0,
                top: math.max(padding.top + 80, size.height * 0.35),
                child: _HiddenTab(onTap: _showOrb),
              ),
            if (_routing && !_hidden)
              Positioned(
                left: orbOffset.dx - 6,
                top: orbOffset.dy - 44,
                child: _RoutingChip(),
              ),
            if (_recording && !_hidden && _partialTranscript != null)
              Positioned(
                left: math.max(8, orbOffset.dx - 12),
                top: math.max(8, orbOffset.dy - 64),
                child: _PartialBubble(text: _partialTranscript!),
              ),
          ],
        );
      },
    );
  }

  Widget _buildOrb() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bob = math.sin(_floatController.value * math.pi) * 3;
    final showWave = _recording;

    return GestureDetector(
      onTap: () {
        if (_recording) {
          _stopRecording();
          return;
        }
        setState(() => _expanded = !_expanded);
      },
      onLongPress: () => _hideOrb(),
      onPanStart: (_) => _startDrag(),
      onPanUpdate: (details) => _drag(details.delta),
      onPanEnd: (details) => _endDrag(
        velocity: details.velocity.pixelsPerSecond * 0.6,
      ),
      child: Transform.translate(
        offset: Offset(0, bob),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (showWave)
              SizedBox(
                width: _orbSize + 28,
                height: _orbSize + 28,
                child: AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _WaveRingPainter(
                        color: scheme.primary.withOpacity(0.8),
                        phase: _waveController.value,
                      ),
                    );
                  },
                ),
              ),
            Container(
              width: _orbSize,
              height: _orbSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    scheme.primary.withOpacity(0.95),
                    scheme.secondary.withOpacity(0.75),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withOpacity(0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                _recording ? Icons.stop_rounded : Icons.auto_awesome,
                color: scheme.onPrimary,
                size: 26,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeck() {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      radius: 20,
      child: SizedBox(
        width: 220,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _OrbActionButton(
                  icon: Icons.photo_camera,
                  label: 'Camera',
                  onTap: () => _handleInput(_OrbInputType.camera),
                ),
                _OrbActionButton(
                  icon: Icons.upload_file,
                  label: 'Upload',
                  onTap: () => _handleInput(_OrbInputType.upload),
                ),
                _OrbActionButton(
                  icon: Icons.mic,
                  label: _recording ? 'Stop' : 'Mic',
                  onTap: _handleMicTap,
                ),
                _OrbActionButton(
                  icon: Icons.edit_note,
                  label: 'Text',
                  onTap: _showTextSheet,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _hideOrb,
                  icon: const Icon(Icons.visibility_off, size: 18),
                  label: const Text('Hide'),
                ),
                const Spacer(),
                const Text(
                  'Drag to move',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _startDrag() {
    _stopMomentum();
    setState(() {
      _dragging = true;
      _showDockTarget = true;
      _expanded = false;
      _driftOffset = Offset.zero;
    });
    _dragVelocity = Offset.zero;
    _lastDragTs = DateTime.now().millisecondsSinceEpoch;
    _dragTarget = _position;
    _dragTickerActive = true;
  }

  void _drag(Offset delta) {
    if (_layoutSize == null) return;
    final padding = MediaQuery.of(context).padding;
    final now = DateTime.now().millisecondsSinceEpoch;
    final dt = (now - _lastDragTs) / 1000.0;
    if (dt > 0) {
      final instant = delta / dt;
      _dragVelocity = _dragVelocity * 0.6 + instant * 0.4;
      _lastDragTs = now;
    }
    _dragTarget = _applyDragResistance(_dragTarget + delta, _layoutSize!, padding);
  }

  void _endDrag({Offset? velocity}) {
    if (_layoutSize == null) return;
    final padding = MediaQuery.of(context).padding;
    final dockRect = _dockRect(_layoutSize!, padding);
    final shouldDock = _isInDockZone(dockRect, _position);
    final releaseVelocity = velocity ?? _dragVelocity;

    setState(() {
      _dragging = false;
      _showDockTarget = false;
      _docked = shouldDock;
      _driftOffset = Offset.zero;
    });
    _dragTickerActive = false;

    if (shouldDock) {
      _animateTo(_dockPosition(_layoutSize!, padding));
    } else {
      if (releaseVelocity.distance > 80) {
        _startMomentum(releaseVelocity);
      } else {
        _persistPosition();
      }
    }

    _settingsRepo.setOrbDocked(shouldDock);
  }

  void _animateTo(Offset target) {
    _snapController.stop();
    _snapAnimation = Tween<Offset>(begin: _position, end: target).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );
    _snapController
      ..reset()
      ..forward();
  }

  void _startMomentum(Offset velocity) {
    if (_layoutSize == null) return;
    _driftOffset = Offset.zero;
    _momentumVelocity = velocity;
    _lastTick = Duration.zero;
  }

  void _stopMomentum() {
    _momentumVelocity = Offset.zero;
  }

  void _onMomentumTick(Duration elapsed) {
    if (_layoutSize == null) return;
    if (_dragging || _expanded || _recording || _hidden || _docked) {
      _stopMomentum();
      return;
    }
    if (_momentumVelocity.distance == 0) {
      return;
    }
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMilliseconds / 1000.0;
    _lastTick = elapsed;
    if (dt <= 0) return;

    final friction = math.pow(0.94, dt * 60).toDouble();
    _momentumVelocity = _momentumVelocity * friction;

    final padding = MediaQuery.of(context).padding;
    final bounds = Rect.fromLTWH(
      _edgePadding,
      padding.top + _edgePadding,
      _layoutSize!.width - _orbSize - _edgePadding * 2,
      _layoutSize!.height - _orbSize - _edgePadding * 2,
    );

    final next = _position + _momentumVelocity * dt;
    double dx = next.dx;
    double dy = next.dy;
    double vx = _momentumVelocity.dx;
    double vy = _momentumVelocity.dy;

    if (dx < bounds.left) {
      dx = bounds.left;
      vx = -vx * 0.75;
    } else if (dx > bounds.right) {
      dx = bounds.right;
      vx = -vx * 0.75;
    }

    if (dy < bounds.top) {
      dy = bounds.top;
      vy = -vy * 0.75;
    } else if (dy > bounds.bottom) {
      dy = bounds.bottom;
      vy = -vy * 0.75;
    }

    setState(() {
      _position = Offset(dx, dy);
      _momentumVelocity = Offset(vx, vy);
    });

    if (_momentumVelocity.distance < 20) {
      _stopMomentum();
      _persistPosition();
    }
  }

  void _onMomentumTickSafe(Duration elapsed) {
    _onMomentumTick(elapsed);
    _updateDragFollow(elapsed);
  }

  void _updateDragFollow(Duration elapsed) {
    if (!_dragging || !_dragTickerActive || _layoutSize == null) return;
    final padding = MediaQuery.of(context).padding;
    final target = _clamp(_dragTarget, _layoutSize!, padding);
    // Spring-like follow (lag behind finger for a floaty feel).
    final toTarget = target - _position;
    final follow = toTarget * 0.14;
    setState(() {
      _position = _clamp(_position + follow, _layoutSize!, padding);
    });
  }

  void _hideOrb() {
    setState(() {
      _hidden = true;
      _expanded = false;
    });
    _settingsRepo.setOrbHidden(true);
    AppShellController.instance.setOrbHidden(true);
  }

  void _showOrb() {
    setState(() {
      _hidden = false;
    });
    _settingsRepo.setOrbHidden(false);
    AppShellController.instance.setOrbHidden(false);
  }

  void _ensurePosition(Size size, EdgeInsets padding) {
    _layoutSize ??= size;

    if (!_positionReady) {
      final dock = _dockPosition(size, padding);
      if (_docked) {
        _position = dock;
      } else if (_savedPosX != null && _savedPosY != null) {
        _position = Offset(
          (size.width - _orbSize) * _savedPosX!,
          (size.height - _orbSize) * _savedPosY!,
        );
        _position = _clamp(_position, size, padding);
      } else {
        _position = dock;
      }
      _positionReady = true;
      return;
    }

    if (_layoutSize != size) {
      _layoutSize = size;
      if (_docked) {
        _position = _dockPosition(size, padding);
      } else {
        _position = _clamp(_position, size, padding);
      }
    }
  }

  void _startDriftLoop() {
    _driftTimer?.cancel();
    _driftTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      if (_dragging || _expanded || _recording || _hidden) return;
      if (_momentumTicker.isActive) return;
      final rand = math.Random();
      final dx = (rand.nextDouble() * 2 - 1) * 6;
      final dy = (rand.nextDouble() * 2 - 1) * 6;
      _driftAnimation = Tween<Offset>(
        begin: _driftOffset,
        end: Offset(dx, dy),
      ).animate(CurvedAnimation(parent: _driftController, curve: Curves.easeOutSine));
      _driftController
        ..reset()
        ..forward();
    });
  }

  Offset _dockPosition(Size size, EdgeInsets padding) {
    final minY = padding.top + (_toolbarHeight - _orbSize) / 2 + 2;
    final maxY = size.height - _orbSize - _edgePadding;
    final y = minY.clamp(minY, maxY);
    final x = size.width - _orbSize - _edgePadding;
    return Offset(x, y);
  }

  Rect _dockRect(Size size, EdgeInsets padding) {
    final dock = _dockPosition(size, padding);
    return Rect.fromLTWH(
      dock.dx - (_dockWidth - _orbSize) / 2,
      dock.dy - (_dockHeight - _orbSize) / 2,
      _dockWidth,
      _dockHeight,
    );
  }

  bool _isInDockZone(Rect dockRect, Offset pos) {
    final center = Offset(pos.dx + _orbSize / 2, pos.dy + _orbSize / 2);
    return dockRect.contains(center);
  }

  Offset _clamp(Offset pos, Size size, EdgeInsets padding) {
    final minX = _edgePadding;
    final minY = padding.top + _edgePadding;
    final maxX = size.width - _orbSize - _edgePadding;
    final maxY = size.height - _orbSize - _edgePadding;
    return Offset(
      pos.dx.clamp(minX, maxX),
      pos.dy.clamp(minY, maxY),
    );
  }

  Offset _applyDragResistance(Offset pos, Size size, EdgeInsets padding) {
    final minX = _edgePadding;
    final minY = padding.top + _edgePadding;
    final maxX = size.width - _orbSize - _edgePadding;
    final maxY = size.height - _orbSize - _edgePadding;

    double dx = pos.dx;
    double dy = pos.dy;

    if (dx < minX) {
      dx = minX - (minX - dx) * 0.35;
    } else if (dx > maxX) {
      dx = maxX + (dx - maxX) * 0.35;
    }

    if (dy < minY) {
      dy = minY - (minY - dy) * 0.35;
    } else if (dy > maxY) {
      dy = maxY + (dy - maxY) * 0.35;
    }

    dx = dx.clamp(minX - _dragOverscroll, maxX + _dragOverscroll);
    dy = dy.clamp(minY - _dragOverscroll, maxY + _dragOverscroll);

    return Offset(dx, dy);
  }

  Offset _deckOffset(Size size, EdgeInsets padding, Offset orbOffset) {
    const deckWidth = 220.0;
    const deckHeight = 170.0;
    final isRightSide = orbOffset.dx > size.width * 0.55;
    final dx = isRightSide
        ? (orbOffset.dx - deckWidth - 12)
        : (orbOffset.dx + _orbSize + 12);
    final rawDy = orbOffset.dy + _orbSize / 2 - deckHeight / 2;
    final dy = rawDy
        .clamp(padding.top + 12, size.height - deckHeight - _edgePadding);
    return Offset(dx.clamp(12, size.width - deckWidth - 12), dy);
  }

  void _handleInput(_OrbInputType type) {
    setState(() => _expanded = false);
    final destination = _classify('', type);
    _routeTo(destination);
  }

  Future<void> _handleMicTap() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    setState(() {
      _expanded = false;
      _recording = true;
      _partialTranscript = null;
    });
    _waveController.repeat();

    try {
      await _stt.startListening(
        onPartial: (text) {
          if (!mounted) return;
          setState(() => _partialTranscript = text);
        },
        onResult: (text) async {
          await _stopRecording();
          if (!mounted) return;
          if (text.trim().isEmpty) {
            _showSnack('No speech detected.');
            return;
          }
          _routeTo(_classify(text, _OrbInputType.mic), transcript: text);
        },
        onError: (error) async {
          await _stopRecording();
          _showSnack('Mic error: $error');
        },
      );
      _recordTimeout?.cancel();
      _recordTimeout = Timer(const Duration(seconds: 9), () async {
        if (!_recording) return;
        await _stopRecording();
        _showSnack('Recording timed out.');
      });
    } catch (error) {
      await _stopRecording();
      _showSnack('Mic unavailable.');
    }
  }

  Future<void> _stopRecording() async {
    _recordTimeout?.cancel();
    _recordTimeout = null;
    if (_recording) {
      await _stt.stopListening();
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _partialTranscript = null;
    });
    _waveController.stop();
  }

  Future<void> _showTextSheet() async {
    setState(() => _expanded = false);
    final controller = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 24,
          ),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quick input'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: null,
                  decoration: const InputDecoration(
                    hintText: 'Type a few sentences... ',
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(controller.text.trim()),
                    icon: const Icon(Icons.send),
                    label: const Text('Send'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (text == null || text.trim().isEmpty) return;
    _routeTo(_classify(text, _OrbInputType.text), transcript: text);
  }

  _OrbDestination _classify(String text, _OrbInputType type) {
    final normalized = text.toLowerCase();
    final scores = <_OrbDestination, double>{
      _OrbDestination.training: 0,
      _OrbDestination.diet: 0,
      _OrbDestination.appearance: 0,
      _OrbDestination.leaderboard: 0,
      _OrbDestination.settings: 0,
    };

    void bump(_OrbDestination dest, double value) {
      scores[dest] = (scores[dest] ?? 0) + value;
    }

    if (normalized.contains('leaderboard') || normalized.contains('rank')) {
      bump(_OrbDestination.leaderboard, 3);
    }
    if (normalized.contains('setting') || normalized.contains('preference')) {
      bump(_OrbDestination.settings, 3);
    }

    for (final word in [
      'set',
      'reps',
      'rep',
      'workout',
      'session',
      'bench',
      'squat',
      'deadlift',
      'press',
      'curl',
      'row',
      'rest',
      'warmup',
      'pr',
    ]) {
      if (normalized.contains(word)) bump(_OrbDestination.training, 1.6);
    }

    for (final word in [
      'calorie',
      'meal',
      'protein',
      'carb',
      'fat',
      'fiber',
      'sodium',
      'breakfast',
      'lunch',
      'dinner',
      'snack',
      'macro',
    ]) {
      if (normalized.contains(word)) bump(_OrbDestination.diet, 1.6);
    }

    for (final word in [
      'appearance',
      'physique',
      'style',
      'outfit',
      'face',
      'progress',
      'waist',
      'hips',
      'chest',
      'confidence',
      'fit',
      'photo',
    ]) {
      if (normalized.contains(word)) bump(_OrbDestination.appearance, 1.6);
    }

    if (type == _OrbInputType.camera) {
      bump(_OrbDestination.appearance, 1.2);
    } else if (type == _OrbInputType.upload) {
      bump(_OrbDestination.diet, 1.0);
    }

    _OrbDestination best = _OrbDestination.training;
    double bestScore = -1;
    scores.forEach((dest, score) {
      if (score > bestScore) {
        bestScore = score;
        best = dest;
      }
    });

    if (bestScore <= 0 && _lastDestination != null) {
      return _lastDestination!;
    }

    return best;
  }

  Future<void> _routeTo(_OrbDestination destination, {String? transcript}) async {
    setState(() => _routing = true);
    await Future.delayed(const Duration(milliseconds: 420));
    if (!mounted) return;
    setState(() => _routing = false);

    final appearanceEnabled = AppShellController.instance.appearanceEnabled.value;
    if (destination == _OrbDestination.appearance && !appearanceEnabled) {
      _showSnack('Appearance is disabled.');
      _selectTab(_OrbDestination.settings);
      return;
    }

    _selectTab(destination);
    _lastDestination = destination;
    _showRouteSnackbar(destination, transcript: transcript);
  }

  void _selectTab(_OrbDestination destination) {
    final appearanceEnabled = AppShellController.instance.appearanceEnabled.value;
    final index = switch (destination) {
      _OrbDestination.training => 0,
      _OrbDestination.diet => 1,
      _OrbDestination.appearance => appearanceEnabled ? 2 : 0,
      _OrbDestination.leaderboard => appearanceEnabled ? 3 : 2,
      _OrbDestination.settings => appearanceEnabled ? 4 : 3,
    };
    AppShellController.instance.selectTab(index);
  }

  void _showRouteSnackbar(_OrbDestination dest, {String? transcript}) {
    final messenger = OraApp.messengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Routed to ${_labelFor(dest)}'),
        action: SnackBarAction(
          label: 'Change',
          onPressed: () => _showDestinationPicker(),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _showDestinationPicker() async {
    final choice = await showModalBottomSheet<_OrbDestination>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Send input to'),
                const SizedBox(height: 12),
                _DestinationTile(label: 'Training', value: _OrbDestination.training),
                _DestinationTile(label: 'Diet', value: _OrbDestination.diet),
                _DestinationTile(label: 'Appearance', value: _OrbDestination.appearance),
                _DestinationTile(label: 'Leaderboard', value: _OrbDestination.leaderboard),
                _DestinationTile(label: 'Settings', value: _OrbDestination.settings),
              ],
            ),
          ),
        );
      },
    );

    if (choice == null) return;
    _routeTo(choice);
  }

  void _persistPosition() {
    if (_layoutSize == null) return;
    final size = _layoutSize!;
    final x = (_position.dx / (size.width - _orbSize)).clamp(0.0, 1.0);
    final y = (_position.dy / (size.height - _orbSize)).clamp(0.0, 1.0);
    _settingsRepo.setOrbPosition(x: x, y: y);
  }

  void _showSnack(String message) {
    OraApp.messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _labelFor(_OrbDestination dest) {
    return switch (dest) {
      _OrbDestination.training => 'Training',
      _OrbDestination.diet => 'Diet',
      _OrbDestination.appearance => 'Appearance',
      _OrbDestination.leaderboard => 'Leaderboard',
      _OrbDestination.settings => 'Settings',
    };
  }
}

class _OrbActionButton extends StatelessWidget {
  const _OrbActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: scheme.surface.withOpacity(0.55),
          border: Border.all(color: scheme.outline.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _DockTarget extends StatelessWidget {
  const _DockTarget({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: scheme.surface.withOpacity(active ? 0.6 : 0.4),
        border: Border.all(
          color: scheme.primary.withOpacity(active ? 0.6 : 0.25),
          width: active ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withOpacity(active ? 0.25 : 0.12),
            blurRadius: active ? 20 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: scheme.primary.withOpacity(active ? 0.7 : 0.35),
              width: active ? 2 : 1,
            ),
            color: scheme.surface.withOpacity(active ? 0.5 : 0.2),
          ),
          child: Icon(
            Icons.circle_outlined,
            color: scheme.primary.withOpacity(active ? 0.6 : 0.3),
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _HiddenTab extends StatelessWidget {
  const _HiddenTab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 18,
        height: 70,
        decoration: BoxDecoration(
          color: scheme.primary.withOpacity(0.7),
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
        ),
        child: const Icon(Icons.chevron_left, size: 18, color: Colors.white),
      ),
    );
  }
}

class _RoutingChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline.withOpacity(0.2)),
      ),
      child: const Text('Classifying...', style: TextStyle(fontSize: 12)),
    );
  }
}

class _PartialBubble extends StatelessWidget {
  const _PartialBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.white70),
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({required this.label, required this.value});

  final String label;
  final _OrbDestination value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

class _WaveRingPainter extends CustomPainter {
  _WaveRingPainter({required this.color, required this.phase});

  final Color color;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2 - 6;
    final amplitude = 4.0;
    final path = Path();
    for (int i = 0; i <= 64; i++) {
      final t = i / 64 * math.pi * 2;
      final wave = math.sin(t * 6 + phase * math.pi * 2) * amplitude;
      final r = baseRadius + wave;
      final point = Offset(
        center.dx + math.cos(t) * r,
        center.dy + math.sin(t) * r,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WaveRingPainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.color != color;
  }
}
