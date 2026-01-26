import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../../app.dart';
import '../../../core/voice/stt.dart';
import '../../../core/input/input_router.dart';
import '../../../core/utils/image_downscaler.dart';
import '../../../data/db/db.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../screens/shell/app_shell_controller.dart';
import '../../screens/uploads/uploads_screen.dart';
import '../glass/glass_card.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';


class OraOrb extends StatefulWidget {
  const OraOrb({super.key});

  @override
  State<OraOrb> createState() => _OraOrbState();
}

class _OraOrbState extends State<OraOrb> with TickerProviderStateMixin {
  static const double _orbSize = 84;
  static const double _dockWidth = 126;
  static const double _dockHeight = 126;
  static const double _edgePadding = 12;
  static const double _dragOverscroll = 24;
  static const double _dockNavHeight = 68;
  static const double _deckWidth = 220;
  static const double _deckGap = 12;
  static const double _deckFallbackHeight = 292;
  static const String _orbAsset = 'assets/branding/ora.png';

  final SettingsRepo _settingsRepo = SettingsRepo(AppDatabase.instance);
  final SpeechToTextEngine _stt = SpeechToTextEngine.instance;
  final InputRouter _inputRouter = InputRouter(AppDatabase.instance);
  final ImagePicker _imagePicker = ImagePicker();

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

  Offset _position = Offset.zero;
  Offset _driftOffset = Offset.zero;
  Offset _dragVelocity = Offset.zero;
  int _lastDragTs = 0;
  Offset _dragTarget = Offset.zero;
  bool _dragTickerActive = false;
  double _toolbarHeight = kToolbarHeight;
  double? _savedPosX;
  double? _savedPosY;
  Size? _deckSize;

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
        _toggleExpanded();
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
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  _orbAsset,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleExpanded() {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }

    if (_layoutSize != null) {
      final padding = MediaQuery.of(context).padding;
      final adjusted = _clampOrbForDeck(_layoutSize!, padding, _position);
      if (adjusted != _position) {
        _position = adjusted;
        _persistPosition();
      }
    }

    setState(() {
      _expanded = true;
      _driftOffset = Offset.zero;
    });
  }

  Widget _buildDeck() {
    return _MeasureSize(
      onChange: (size) {
        if (_deckSize == size) return;
        setState(() => _deckSize = size);
      },
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        radius: 20,
        child: SizedBox(
          width: _deckWidth,
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
                    onTap: _handleCameraTap,
                  ),
                  _OrbActionButton(
                    icon: Icons.upload_file,
                    label: 'Upload',
                    onTap: _handleUploadTap,
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
                  TextButton.icon(
                    onPressed: _openUploads,
                    icon: const Icon(Icons.cloud_upload, size: 18),
                    label: const Text('Uploads'),
                  ),
                ],
              ),
            ],
          ),
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

    if (_expanded) {
      _position = _clampOrbForDeck(size, padding, _position);
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
    final maxY = _maxY(size, padding);
    final y = (size.height - padding.bottom - _dockNavHeight - _orbSize * 0.35)
        .clamp(padding.top + _edgePadding, maxY);
    final x = (size.width - _orbSize) / 2;
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
    final maxY = _maxY(size, padding);
    return Offset(
      pos.dx.clamp(minX, maxX),
      pos.dy.clamp(minY, maxY),
    );
  }

  Offset _applyDragResistance(Offset pos, Size size, EdgeInsets padding) {
    final minX = _edgePadding;
    final minY = padding.top + _edgePadding;
    final maxX = size.width - _orbSize - _edgePadding;
    final maxY = _maxY(size, padding);

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

  double _maxY(Size size, EdgeInsets padding) {
    return size.height - padding.bottom - _orbSize + 6;
  }

  Size _currentDeckSize() {
    final height = _deckSize?.height ?? _deckFallbackHeight;
    return Size(_deckWidth, height);
  }

  Offset _clampOrbForDeck(Size size, EdgeInsets padding, Offset orbOffset) {
    final deckHeight = _currentDeckSize().height;
    final minX = _edgePadding;
    final maxX = size.width - _orbSize - _edgePadding;
    final minYOrb = padding.top + _edgePadding;
    final maxYOrb = _maxY(size, padding);
    final minYDeck = padding.top + _edgePadding;
    final maxYDeck = size.height - padding.bottom - _dockNavHeight - deckHeight - _edgePadding;

    final aboveMin = minYDeck + deckHeight + _deckGap;
    final aboveMax = maxYDeck + deckHeight + _deckGap;
    final belowMin = minYDeck - _orbSize - _deckGap;
    final belowMax = maxYDeck - deckHeight - _orbSize - _deckGap;

    final orbMin = minYOrb;
    final orbMax = maxYOrb;

    double dy = orbOffset.dy;
    final aboveLow = math.max(orbMin, aboveMin);
    final aboveHigh = math.min(orbMax, aboveMax);
    final belowLow = math.max(orbMin, belowMin);
    final belowHigh = math.min(orbMax, belowMax);

    if (aboveLow <= aboveHigh) {
      dy = dy.clamp(aboveLow, aboveHigh);
    } else if (belowLow <= belowHigh) {
      dy = dy.clamp(belowLow, belowHigh);
    } else {
      dy = dy.clamp(orbMin, orbMax);
    }

    final dx = orbOffset.dx.clamp(minX, maxX);
    return Offset(dx, dy);
  }

  Offset _deckOffset(Size size, EdgeInsets padding, Offset orbOffset) {
    final deckSize = _currentDeckSize();
    final deckWidth = deckSize.width;
    final deckHeight = deckSize.height;
    final minX = _edgePadding;
    final maxX = size.width - deckWidth - _edgePadding;
    final minY = padding.top + _edgePadding;
    final maxY = size.height - padding.bottom - _dockNavHeight - deckHeight - _edgePadding;
    final safeMaxY = math.max(minY, maxY);
    final centerX = orbOffset.dx + _orbSize / 2;
    final left = (centerX - deckWidth / 2).clamp(minX, maxX);
    final aboveTop = orbOffset.dy - deckHeight - _deckGap;
    final belowTop = orbOffset.dy + _orbSize + _deckGap;
    final above = Rect.fromLTWH(left, aboveTop, deckWidth, deckHeight);
    final below = Rect.fromLTWH(left, belowTop, deckWidth, deckHeight);

    final aboveFits = above.top >= minY && above.bottom <= safeMaxY;
    final belowFits = below.top >= minY && below.bottom <= safeMaxY;

    Rect chosen;
    String reason;
    if (aboveFits) {
      chosen = above;
      reason = 'above';
    } else if (belowFits) {
      chosen = below;
      reason = 'below';
    } else {
      final clampedTop = aboveTop.clamp(minY, safeMaxY);
      chosen = Rect.fromLTWH(left, clampedTop, deckWidth, deckHeight);
      reason = 'clamped-above';
      final orbRect = Rect.fromLTWH(orbOffset.dx, orbOffset.dy, _orbSize, _orbSize);
      if (chosen.overlaps(orbRect)) {
        final clampedBelow = Rect.fromLTWH(left, belowTop.clamp(minY, safeMaxY), deckWidth, deckHeight);
        if (!clampedBelow.overlaps(orbRect)) {
          chosen = clampedBelow;
          reason = 'clamped-below';
        }
      }
    }

    assert(() {
      if (kDebugMode) {
        final orbRect = Rect.fromLTWH(orbOffset.dx, orbOffset.dy, _orbSize, _orbSize);
        debugPrint('[OrbMenu][$reason] orb=$orbRect deck=$chosen size=$size padding=$padding');
      }
      return true;
    }());

    return chosen.topLeft;
  }

  Future<void> _handleCameraTap() async {
    setState(() => _expanded = false);
    try {
      final file = await _imagePicker.pickImage(source: ImageSource.camera);
      if (file == null) return;
      final optimized = await ImageDownscaler.downscaleImageIfNeeded(File(file.path));
      await _routeInput(
        InputEvent(
          source: InputSource.camera,
          file: optimized,
          fileName: optimized.uri.pathSegments.last,
          mimeType: _guessMimeType(optimized.path),
        ),
      );
    } on PlatformException catch (error) {
      final message = error.code.contains('camera')
          ? 'Camera access is disabled. Enable it in Settings > Ora.'
          : 'Camera unavailable: ${error.message ?? error.code}.';
      _showSnack(message);
    } catch (_) {
      _showSnack('Camera unavailable. Check permissions in Settings > Ora.');
    }
  }

  Future<void> _handleUploadTap() async {
    setState(() => _expanded = false);
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'heic', 'pdf', 'csv', 'xlsx', 'txt'],
      withData: false,
    );
    if (selection == null || selection.files.isEmpty) return;
    final file = selection.files.first;
    if (file.path == null) return;
    final original = File(file.path!);
    final optimized = await ImageDownscaler.downscaleImageIfNeeded(original);
    await _routeInput(
      InputEvent(
        source: InputSource.upload,
        file: optimized,
        fileName: optimized.uri.pathSegments.last,
      ),
    );
  }

  Future<void> _routeInput(InputEvent event) async {
    setState(() => _routing = true);
    await _inputRouter.routeAndHandle(context, event);
    if (!mounted) return;
    setState(() => _routing = false);
  }


  void _openUploads() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UploadsScreen()),
    );
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
          await _routeInput(
            InputEvent(source: InputSource.mic, text: text),
          );
        },
        onError: (error) async {
          await _stopRecording();
          final text = error.toString();
          if (text.contains('Microphone permission denied')) {
            _showSnack('Microphone access is disabled. Enable it in Settings > Ora.');
          } else {
            _showSnack('Mic error: $error');
          }
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
    await _routeInput(InputEvent(source: InputSource.text, text: text));
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

  String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
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

class _MeasureSize extends StatefulWidget {
  const _MeasureSize({required this.onChange, required this.child});

  final ValueChanged<Size> onChange;
  final Widget child;

  @override
  State<_MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<_MeasureSize> {
  Size? _oldSize;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final size = context.size;
      if (size == null || size == _oldSize) return;
      _oldSize = size;
      widget.onChange(size);
    });
    return widget.child;
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
