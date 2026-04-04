import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EmpireFlightGame extends StatefulWidget {
  const EmpireFlightGame({super.key});

  @override
  State<EmpireFlightGame> createState() => _EmpireFlightGameState();
}

enum _GamePhase {
  briefing,
  playing,
  paused,
  victory,
  crashed,
}

class _SnowParticle {
  _SnowParticle({
    required this.x,
    required this.y,
    required this.speed,
    required this.size,
  });

  double x;
  double y;
  double speed;
  double size;
}

class _EmpireFlightGameState extends State<EmpireFlightGame> {
  final FocusNode _keyboardFocus = FocusNode();
  Timer? _loop;
  DateTime? _lastTick;

  _GamePhase phase = _GamePhase.briefing;

  // HACKABLE NOTE:
  // This is a pure flight prototype.
  // Distance is how far along the run you are.
  static const double _missionDistance = 5600;
  static const double _baseSpeed = 245;

  double distance = 0;
  int hull = 100;
  double damageFlash = 0;

  // HACKABLE NOTE:
  // shipX = lateral position relative to the canyon center.
  // shipY = altitude feeling. Higher = climbing.
  double shipX = 0.0;
  double shipY = 0.48;
  double shipVX = 0.0;
  double shipVY = 0.0;

  bool leftPressed = false;
  bool rightPressed = false;
  bool upPressed = false;
  bool downPressed = false;

  final List<_SnowParticle> particles = [];

  Size playSize = const Size(1000, 700);

  @override
  void initState() {
    super.initState();

    final rng = Random();
    for (int i = 0; i < 120; i++) {
      particles.add(
        _SnowParticle(
          x: rng.nextDouble(),
          y: rng.nextDouble(),
          speed: 0.3 + rng.nextDouble() * 1.2,
          size: 0.8 + rng.nextDouble() * 1.8,
        ),
      );
    }

    _startLoop();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _loop?.cancel();
    _keyboardFocus.dispose();
    super.dispose();
  }

  double get progress => (distance / _missionDistance).clamp(0.0, 1.0);

  double get worldSpeed {
    // HACKABLE NOTE:
    // A slight speed build keeps the run from feeling dead,
    // but this is still mainly about flight feel, not difficulty spikes.
    return _baseSpeed * (1.0 + progress * 0.12);
  }

  void _resetRun() {
    phase = _GamePhase.briefing;
    distance = 0;
    hull = 100;
    damageFlash = 0;

    shipX = 0.0;
    shipY = 0.48;
    shipVX = 0.0;
    shipVY = 0.0;

    leftPressed = false;
    rightPressed = false;
    upPressed = false;
    downPressed = false;
  }

  void _startLoop() {
    _loop?.cancel();
    _lastTick = null;

    _loop = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now();

      if (_lastTick == null) {
        _lastTick = now;
        return;
      }

      final dt = (now.difference(_lastTick!).inMicroseconds / 1000000.0)
          .clamp(0.0, 0.033);

      _lastTick = now;
      _update(dt);
    });
  }

  void _update(double dt) {
    if (!mounted) return;

    _updateParticles(dt);

    if (damageFlash > 0) {
      damageFlash -= dt;
    }

    if (phase != _GamePhase.playing) {
      setState(() {});
      return;
    }

    _updateShip(dt);
    _checkTerrainCollision();

    distance += worldSpeed * dt;

    if (hull <= 0) {
      hull = 0;
      phase = _GamePhase.crashed;
    } else if (distance >= _missionDistance) {
      phase = _GamePhase.victory;
    }

    setState(() {});
  }

  void _updateParticles(double dt) {
    for (final p in particles) {
      p.y += p.speed * dt * 0.35;
      if (p.y > 1.05) {
        p.y = -0.02;
      }
    }
  }

  void _updateShip(double dt) {
    // HACKABLE NOTE:
    // These values are the heart of the feel.
    const accelX = 3.4;
    const accelY = 2.6;
    const damping = 0.885;
    const maxVX = 1.35;
    const maxVY = 1.0;

    if (leftPressed) shipVX -= accelX * dt;
    if (rightPressed) shipVX += accelX * dt;
    if (upPressed) shipVY += accelY * dt;
    if (downPressed) shipVY -= accelY * dt;

    shipVX *= pow(damping, dt * 60).toDouble();
    shipVY *= pow(damping, dt * 60).toDouble();

    shipVX = shipVX.clamp(-maxVX, maxVX);
    shipVY = shipVY.clamp(-maxVY, maxVY);

    shipX += shipVX * dt;
    shipY += shipVY * dt;

    // HACKABLE NOTE:
    // Broad flight box. This should feel wider than a lane runner.
    shipX = shipX.clamp(-1.1, 1.1);
    shipY = shipY.clamp(0.10, 0.92);

    if (shipX <= -1.1 || shipX >= 1.1) shipVX *= -0.12;
    if (shipY <= 0.10 || shipY >= 0.92) shipVY *= -0.10;
  }

  // ---------------------------------------------------------------------------
  // Terrain model
  // ---------------------------------------------------------------------------

  double _pathCenter(double d) {
    // HACKABLE NOTE:
    // This is the main broad turn feel.
    // Lower frequency / larger amplitude = more sweeping canyon.
    return sin(d / 430.0) * 0.42 +
        sin(d / 980.0 + 0.8) * 0.22 +
        sin(d / 210.0 + 1.6) * 0.05;
  }

  double _pathHalfWidth(double d) {
    // HACKABLE NOTE:
    // This controls how wide the safe lateral space feels.
    final base = 0.44 + sin(d / 650.0 + 0.7) * 0.05;

    final narrow1 = _bump(d, 1500, 260, -0.10);
    final narrow2 = _bump(d, 3150, 240, -0.12);
    final narrow3 = _bump(d, 4700, 240, -0.10);

    return (base + narrow1 + narrow2 + narrow3).clamp(0.24, 0.56);
  }

  double _groundHeight(double d) {
    // HACKABLE NOTE:
    // This is what gives the feel of climbing and dipping over terrain.
    final base = 0.18;
    final waves = sin(d / 260.0 + 0.4) * 0.05 + sin(d / 95.0) * 0.015;

    final hill1 = _bump(d, 900, 260, 0.16);
    final hill2 = _bump(d, 2350, 220, 0.13);
    final hill3 = _bump(d, 3980, 280, 0.18);

    return (base + waves + hill1 + hill2 + hill3).clamp(0.08, 0.62);
  }

  double _ceilingHeight(double d) {
    // HACKABLE NOTE:
    // Keeps the prototype feeling like a canyon/window flight,
    // and lets some sections feel lower/tighter overhead.
    final base = 0.90;
    final dips = _bump(d, 1700, 240, -0.10) +
        _bump(d, 3400, 220, -0.08) +
        _bump(d, 5000, 220, -0.12);

    return (base + dips).clamp(0.66, 0.94);
  }

  double _bump(double x, double center, double width, double amplitude) {
    final t = ((x - center) / width);
    return amplitude * exp(-t * t);
  }

  void _checkTerrainCollision() {
    // HACKABLE NOTE:
    // Use a near-future sample so contact feels like flying into terrain,
    // not being hit by a sprite at the last instant.
    final sampleD = distance + 70;

    final center = _pathCenter(sampleD);
    final halfWidth = _pathHalfWidth(sampleD);
    final floor = _groundHeight(sampleD);
    final ceiling = _ceilingHeight(sampleD);

    final lateralError = (shipX - center).abs();
    final hitWall = lateralError > halfWidth * 0.98;
    final hitGround = shipY < floor + 0.05;
    final hitCeiling = shipY > ceiling - 0.04;

    if (hitWall || hitGround || hitCeiling) {
      hull -= 2;
      damageFlash = 0.08;
    }
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  void _startMission() {
    phase = _GamePhase.playing;
    _keyboardFocus.requestFocus();
  }

  void _restartRun() {
    _resetRun();
    _keyboardFocus.requestFocus();
  }

  void _togglePause() {
    if (phase == _GamePhase.playing) {
      setState(() => phase = _GamePhase.paused);
    } else if (phase == _GamePhase.paused) {
      setState(() => phase = _GamePhase.playing);
      _keyboardFocus.requestFocus();
    }
  }

  void _handleDrag(DragUpdateDetails details) {
    final dx = details.delta.dx / max(1, playSize.width);
    final dy = details.delta.dy / max(1, playSize.height);

    // HACKABLE NOTE:
    // Touch directly adds momentum.
    shipVX += dx * 3.0;
    shipVY += (-dy) * 2.3;
  }

  KeyEventResult _onKeyEvent(KeyEvent event) {
    final isDown = event is KeyDownEvent;
    final isUp = event is KeyUpEvent;
    final key = event.logicalKey;

    void updateKey(void Function(bool v) setter) {
      if (isDown) setter(true);
      if (isUp) setter(false);
    }

    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyA) {
      updateKey((v) => leftPressed = v);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.keyD) {
      updateKey((v) => rightPressed = v);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      updateKey((v) => upPressed = v);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.keyS) {
      updateKey((v) => downPressed = v);
      return KeyEventResult.handled;
    }

    if (isDown && key == LogicalKeyboardKey.keyP) {
      _togglePause();
      return KeyEventResult.handled;
    }

    if (isDown && key == LogicalKeyboardKey.enter) {
      switch (phase) {
        case _GamePhase.briefing:
          _startMission();
          break;
        case _GamePhase.paused:
          _togglePause();
          break;
        case _GamePhase.victory:
        case _GamePhase.crashed:
          _restartRun();
          break;
        case _GamePhase.playing:
          break;
      }
      return KeyEventResult.handled;
    }

    if (isDown && key == LogicalKeyboardKey.keyR) {
      if (phase == _GamePhase.victory || phase == _GamePhase.crashed) {
        _restartRun();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // UI text
  // ---------------------------------------------------------------------------

  String _overlayTitle() {
    switch (phase) {
      case _GamePhase.briefing:
        return 'HOTH FLIGHT TEST';
      case _GamePhase.paused:
        return 'PAUSED';
      case _GamePhase.victory:
        return 'RUN COMPLETE';
      case _GamePhase.crashed:
        return 'CRASHED';
      case _GamePhase.playing:
        return '';
    }
  }

  String _overlaySubtitle() {
    switch (phase) {
      case _GamePhase.briefing:
        return 'No weapons yet.\nJust feel the cockpit, terrain, turns, climbs, and dips.';
      case _GamePhase.paused:
        return 'Pause and take a breath.';
      case _GamePhase.victory:
        return 'You completed the full Hoth flight test.';
      case _GamePhase.crashed:
        return 'The terrain won this run.';
      case _GamePhase.playing:
        return '';
    }
  }

  String _overlayButtonText() {
    switch (phase) {
      case _GamePhase.briefing:
        return 'Start Flight';
      case _GamePhase.paused:
        return 'Resume';
      case _GamePhase.victory:
      case _GamePhase.crashed:
        return 'Restart Test';
      case _GamePhase.playing:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        playSize = Size(
          max(320, constraints.maxWidth),
          max(480, constraints.maxHeight),
        );

        final isCompact = playSize.width < 850;

        return KeyboardListener(
          focusNode: _keyboardFocus,
          autofocus: true,
          onKeyEvent: _onKeyEvent,
          child: Scaffold(
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (phase == _GamePhase.playing) {
                  _keyboardFocus.requestFocus();
                } else if (phase == _GamePhase.briefing) {
                  _startMission();
                } else if (phase == _GamePhase.paused) {
                  _togglePause();
                } else if (phase == _GamePhase.victory || phase == _GamePhase.crashed) {
                  _restartRun();
                }
              },
              onPanUpdate: phase == _GamePhase.playing ? _handleDrag : null,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CockpitFlightPainter(
                        playerX: shipX,
                        playerY: shipY,
                        distance: distance,
                        particles: particles,
                        accent: const Color(0xFFD9F3FF),
                        pathCenterFn: _pathCenter,
                        pathHalfWidthFn: _pathHalfWidth,
                        groundHeightFn: _groundHeight,
                        ceilingHeightFn: _ceilingHeight,
                      ),
                    ),
                  ),

                  if (damageFlash > 0)
                    Positioned.fill(
                      child: Container(
                        color: Colors.red.withOpacity(0.10),
                      ),
                    ),

                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: SafeArea(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0x55000000),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0x22FFFFFF)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      phase == _GamePhase.playing
                                          ? 'Snow Speeder Flight'
                                          : 'Hoth Flight Prototype',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text('Hull'),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: isCompact ? 90 : 130,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: hull / 100,
                                        minHeight: 10,
                                        backgroundColor: const Color(0x33222222),
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          hull > 50
                                              ? const Color(0xFF7FDBFF)
                                              : hull > 25
                                                  ? const Color(0xFFFFC857)
                                                  : const Color(0xFFFF6B6B),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: isCompact ? 90 : 150,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 10,
                                        backgroundColor: const Color(0x33222222),
                                        valueColor: const AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${distance.floor()}/${_missionDistance.toInt()}m'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (phase == _GamePhase.playing || phase == _GamePhase.paused)
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0x55000000),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0x22FFFFFF)),
                              ),
                              child: IconButton(
                                onPressed: _togglePause,
                                icon: Icon(
                                  phase == _GamePhase.paused ? Icons.play_arrow : Icons.pause,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  if (phase != _GamePhase.playing)
                    Positioned.fill(
                      child: Container(
                        color: const Color(0x88000000),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 580),
                            child: Container(
                              margin: const EdgeInsets.all(20),
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0E1320),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0x3388AAFF),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _overlayTitle(),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _overlaySubtitle(),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  ElevatedButton(
                                    onPressed: () {
                                      switch (phase) {
                                        case _GamePhase.briefing:
                                          _startMission();
                                          break;
                                        case _GamePhase.paused:
                                          _togglePause();
                                          break;
                                        case _GamePhase.victory:
                                        case _GamePhase.crashed:
                                          _restartRun();
                                          break;
                                        case _GamePhase.playing:
                                          break;
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      child: Text(_overlayButtonText()),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    isCompact
                                        ? 'Touch: drag to fly'
                                        : 'Move: WASD / Arrows • P pause • R restart after end',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CockpitFlightPainter extends CustomPainter {
  _CockpitFlightPainter({
    required this.playerX,
    required this.playerY,
    required this.distance,
    required this.particles,
    required this.accent,
    required this.pathCenterFn,
    required this.pathHalfWidthFn,
    required this.groundHeightFn,
    required this.ceilingHeightFn,
  });

  final double playerX;
  final double playerY;
  final double distance;
  final List<_SnowParticle> particles;
  final Color accent;

  final double Function(double d) pathCenterFn;
  final double Function(double d) pathHalfWidthFn;
  final double Function(double d) groundHeightFn;
  final double Function(double d) ceilingHeightFn;

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    _paintFarSnow(canvas, size);
    _paintMountains(canvas, size);
    _paintWorldRibbon(canvas, size);
    _paintParticles(canvas, size);
    _paintCockpitGlassLines(canvas, size);
    _paintCockpitInterior(canvas, size);
  }

  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0D1730),
          Color(0xFF4D85B7),
          Color(0xFF8FC3E8),
        ],
      ).createShader(rect);

    canvas.drawRect(rect, paint);
  }

  void _paintFarSnow(Canvas canvas, Size size) {
    final horizonY = size.height * 0.43;
    final rect = Rect.fromLTWH(0, horizonY, size.width, size.height - horizonY);

    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFB8D4E8),
          Color(0xFFEAF7FF),
        ],
      ).createShader(rect);

    canvas.drawRect(rect, paint);
  }

  void _paintMountains(Canvas canvas, Size size) {
    final horizonY = size.height * 0.43;
    final mountainPath = Path()..moveTo(0, horizonY);

    final peaks = [
      Offset(size.width * 0.00, horizonY - 20),
      Offset(size.width * 0.08, horizonY - 42),
      Offset(size.width * 0.16, horizonY - 12),
      Offset(size.width * 0.30, horizonY - 58),
      Offset(size.width * 0.42, horizonY - 20),
      Offset(size.width * 0.56, horizonY - 64),
      Offset(size.width * 0.72, horizonY - 18),
      Offset(size.width * 0.88, horizonY - 46),
      Offset(size.width, horizonY - 20),
    ];

    for (final p in peaks) {
      mountainPath.lineTo(p.dx, p.dy);
    }
    mountainPath.lineTo(size.width, horizonY);
    mountainPath.close();

    canvas.drawPath(
      mountainPath,
      Paint()..color = const Color(0x66F1FBFF),
    );
  }

  void _paintWorldRibbon(Canvas canvas, Size size) {
    final horizonY = size.height * 0.43;
    final bottomY = size.height * 0.94;

    final leftWallOuter = <Offset>[];
    final leftWallInner = <Offset>[];
    final rightWallInner = <Offset>[];
    final rightWallOuter = <Offset>[];
    final floorLeft = <Offset>[];
    final floorRight = <Offset>[];
    final ceilingLeft = <Offset>[];
    final ceilingRight = <Offset>[];

    const samples = 40;
    const lookAhead = 900.0;

    for (int i = 0; i < samples; i++) {
      final t = i / (samples - 1);
      final d = distance + t * lookAhead;

      final scale = lerpDouble(0.06, 1.0, pow(t, 1.55).toDouble())!;
      final worldCenter = pathCenterFn(d);
      final worldHalf = pathHalfWidthFn(d);
      final floorH = groundHeightFn(d);
      final ceilingH = ceilingHeightFn(d);

      final screenCenterX =
          size.width * (0.5 + (worldCenter - playerX) * 0.34 * scale);

      final leftInnerX = size.width *
          (0.5 + ((worldCenter - worldHalf) - playerX) * 0.34 * scale);
      final rightInnerX = size.width *
          (0.5 + ((worldCenter + worldHalf) - playerX) * 0.34 * scale);

      final leftOuterX = size.width *
          (0.5 + ((worldCenter - worldHalf - 0.30) - playerX) * 0.34 * scale);
      final rightOuterX = size.width *
          (0.5 + ((worldCenter + worldHalf + 0.30) - playerX) * 0.34 * scale);

      final baseFloorY = lerpDouble(horizonY + 18, bottomY, scale)!;
      final floorY = baseFloorY + (floorH - playerY) * size.height * 0.42 * scale;

      final ceilingBaseY = lerpDouble(horizonY - 10, size.height * 0.70, scale)!;
      final ceilingY = ceilingBaseY + (ceilingH - playerY) * size.height * 0.22 * scale;

      leftWallOuter.add(Offset(leftOuterX, floorY));
      leftWallInner.add(Offset(leftInnerX, floorY));
      rightWallInner.add(Offset(rightInnerX, floorY));
      rightWallOuter.add(Offset(rightOuterX, floorY));

      floorLeft.add(Offset(leftInnerX, floorY));
      floorRight.add(Offset(rightInnerX, floorY));

      // keep a light sense of overhead shaping
      final ceilingHalf = max(worldHalf * 0.78, 0.18);
      final ceilLeftX = size.width *
          (0.5 + ((worldCenter - ceilingHalf) - playerX) * 0.34 * scale);
      final ceilRightX = size.width *
          (0.5 + ((worldCenter + ceilingHalf) - playerX) * 0.34 * scale);

      ceilingLeft.add(Offset(ceilLeftX, ceilingY));
      ceilingRight.add(Offset(ceilRightX, ceilingY));

      // Center guide streaks for speed / path feel
      if (i < samples - 1 && i.isEven) {
        canvas.drawCircle(
          Offset(screenCenterX, floorY - 6),
          max(0.8, 1.2 * scale),
          Paint()..color = Colors.white.withOpacity(0.10),
        );
      }
    }

    // Left wall
    final leftWallPath = Path()
      ..moveTo(leftWallOuter.first.dx, leftWallOuter.first.dy);
    for (final p in leftWallOuter) {
      leftWallPath.lineTo(p.dx, p.dy);
    }
    for (final p in leftWallInner.reversed) {
      leftWallPath.lineTo(p.dx, p.dy);
    }
    leftWallPath.close();

    canvas.drawPath(
      leftWallPath,
      Paint()..color = const Color(0x88D4F4FF),
    );

    // Right wall
    final rightWallPath = Path()
      ..moveTo(rightWallInner.first.dx, rightWallInner.first.dy);
    for (final p in rightWallInner) {
      rightWallPath.lineTo(p.dx, p.dy);
    }
    for (final p in rightWallOuter.reversed) {
      rightWallPath.lineTo(p.dx, p.dy);
    }
    rightWallPath.close();

    canvas.drawPath(
      rightWallPath,
      Paint()..color = const Color(0x88D4F4FF),
    );

    // Floor ribbon
    final floorPath = Path()..moveTo(floorLeft.first.dx, floorLeft.first.dy);
    for (final p in floorLeft) {
      floorPath.lineTo(p.dx, p.dy);
    }
    for (final p in floorRight.reversed) {
      floorPath.lineTo(p.dx, p.dy);
    }
    floorPath.close();

    canvas.drawPath(
      floorPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x99E7FBFF),
            Color(0xFFF4FDFF),
          ],
        ).createShader(Rect.fromLTWH(0, horizonY, size.width, size.height)),
    );

    // Floor edge lines
    final edgePaint = Paint()
      ..color = Colors.white.withOpacity(0.28)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final leftEdge = Path()..moveTo(floorLeft.first.dx, floorLeft.first.dy);
    for (final p in floorLeft.skip(1)) {
      leftEdge.lineTo(p.dx, p.dy);
    }
    final rightEdge = Path()..moveTo(floorRight.first.dx, floorRight.first.dy);
    for (final p in floorRight.skip(1)) {
      rightEdge.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(leftEdge, edgePaint);
    canvas.drawPath(rightEdge, edgePaint);

    // Ceiling guide
    final ceilPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final ceilLeftPath = Path()
      ..moveTo(ceilingLeft.first.dx, ceilingLeft.first.dy);
    for (final p in ceilingLeft.skip(1)) {
      ceilLeftPath.lineTo(p.dx, p.dy);
    }

    final ceilRightPath = Path()
      ..moveTo(ceilingRight.first.dx, ceilingRight.first.dy);
    for (final p in ceilingRight.skip(1)) {
      ceilRightPath.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(ceilLeftPath, ceilPaint);
    canvas.drawPath(ceilRightPath, ceilPaint);
  }

  void _paintParticles(Canvas canvas, Size size) {
    for (final p in particles) {
      final x = p.x * size.width;
      final y = p.y * size.height;
      canvas.drawCircle(
        Offset(x, y),
        p.size,
        Paint()..color = Colors.white.withOpacity(0.16),
      );
    }
  }

  void _paintCockpitGlassLines(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = accent.withOpacity(0.22)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Main window outline
    final frame = Path()
      ..moveTo(size.width * 0.16, size.height * 0.92)
      ..lineTo(size.width * 0.12, size.height * 0.58)
      ..lineTo(size.width * 0.20, size.height * 0.18)
      ..lineTo(size.width * 0.80, size.height * 0.18)
      ..lineTo(size.width * 0.88, size.height * 0.58)
      ..lineTo(size.width * 0.84, size.height * 0.92);

    canvas.drawPath(frame, linePaint);

    // Windshield segmentation / canopy lines
    canvas.drawLine(
      Offset(size.width * 0.50, size.height * 0.16),
      Offset(size.width * 0.50, size.height * 0.40),
      linePaint,
    );

    canvas.drawLine(
      Offset(size.width * 0.30, size.height * 0.20),
      Offset(size.width * 0.24, size.height * 0.40),
      linePaint,
    );

    canvas.drawLine(
      Offset(size.width * 0.70, size.height * 0.20),
      Offset(size.width * 0.76, size.height * 0.40),
      linePaint,
    );

    // Small windshield detail lines
    final detailPaint = Paint()
      ..color = accent.withOpacity(0.12)
      ..strokeWidth = 1.2;

    canvas.drawLine(
      Offset(size.width * 0.42, size.height * 0.18),
      Offset(size.width * 0.38, size.height * 0.30),
      detailPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.58, size.height * 0.18),
      Offset(size.width * 0.62, size.height * 0.30),
      detailPaint,
    );
  }

  void _paintCockpitInterior(Canvas canvas, Size size) {
    final darkPanel = Paint()..color = const Color(0xCC0A1018);
    final midPanel = Paint()..color = const Color(0xFF131D28);
    final bezel = Paint()
      ..color = accent.withOpacity(0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Main lower dash
    final dashPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * 0.14, size.height * 0.84)
      ..lineTo(size.width * 0.34, size.height * 0.78)
      ..lineTo(size.width * 0.66, size.height * 0.78)
      ..lineTo(size.width * 0.86, size.height * 0.84)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(dashPath, darkPanel);

    // Nose / center housing
    final nosePath = Path()
      ..moveTo(size.width * 0.42, size.height)
      ..lineTo(size.width * 0.46, size.height * 0.86)
      ..lineTo(size.width * 0.54, size.height * 0.86)
      ..lineTo(size.width * 0.58, size.height)
      ..close();

    canvas.drawPath(nosePath, midPanel);

    // Left mini screen cluster
    _drawPanelScreen(
      canvas,
      Rect.fromLTWH(size.width * 0.10, size.height * 0.84, size.width * 0.11, size.height * 0.055),
      accent,
      bezel,
    );
    _drawPanelScreen(
      canvas,
      Rect.fromLTWH(size.width * 0.23, size.height * 0.82, size.width * 0.09, size.height * 0.05),
      accent,
      bezel,
    );

    // Right mini screen cluster
    _drawPanelScreen(
      canvas,
      Rect.fromLTWH(size.width * 0.79, size.height * 0.84, size.width * 0.11, size.height * 0.055),
      accent,
      bezel,
    );
    _drawPanelScreen(
      canvas,
      Rect.fromLTWH(size.width * 0.68, size.height * 0.82, size.width * 0.09, size.height * 0.05),
      accent,
      bezel,
    );

    // Small buttons / toggles
    final buttonPaint = Paint()..color = accent.withOpacity(0.32);
    for (int i = 0; i < 4; i++) {
      canvas.drawCircle(
        Offset(size.width * (0.17 + i * 0.022), size.height * 0.915),
        3.2,
        buttonPaint,
      );
      canvas.drawCircle(
        Offset(size.width * (0.75 + i * 0.022), size.height * 0.915),
        3.2,
        buttonPaint,
      );
    }

    // Cockpit edge shading
    final sideShade = Paint()..color = const Color(0x66081118);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * 0.06, size.height), sideShade);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.94, 0, size.width * 0.06, size.height),
      sideShade,
    );
  }

  void _drawPanelScreen(
    Canvas canvas,
    Rect rect,
    Color accent,
    Paint bezel,
  ) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = const Color(0xFF071018),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      bezel,
    );

    final linePaint = Paint()
      ..color = accent.withOpacity(0.45)
      ..strokeWidth = 1.3;

    final y1 = rect.top + rect.height * 0.30;
    final y2 = rect.top + rect.height * 0.55;
    final y3 = rect.top + rect.height * 0.78;

    canvas.drawLine(
      Offset(rect.left + rect.width * 0.12, y1),
      Offset(rect.right - rect.width * 0.18, y1),
      linePaint,
    );
    canvas.drawLine(
      Offset(rect.left + rect.width * 0.12, y2),
      Offset(rect.right - rect.width * 0.30, y2),
      linePaint,
    );
    canvas.drawLine(
      Offset(rect.left + rect.width * 0.12, y3),
      Offset(rect.right - rect.width * 0.42, y3),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CockpitFlightPainter oldDelegate) => true;
}
