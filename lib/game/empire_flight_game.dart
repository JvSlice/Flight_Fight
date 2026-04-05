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

  static const double _missionDistance = 5600;
  static const double _baseSpeed = 220;

  double distance = 0;
  int hull = 100;
  double damageFlash = 0;
  double collisionCooldown = 0;

  // HACKABLE NOTE:
  // shipX = lateral offset from canyon center
  // shipY = altitude feeling, 0 low / 1 high
  double shipX = 0.0;
  double shipY = 0.52;
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
          speed: 0.35 + rng.nextDouble() * 1.1,
          size: 0.8 + rng.nextDouble() * 1.9,
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

  double get worldSpeed => _baseSpeed * (1.0 + progress * 0.08);

  void _resetRun() {
    phase = _GamePhase.briefing;
    distance = 0;
    hull = 100;
    damageFlash = 0;
    collisionCooldown = 0;

    shipX = 0.0;
    shipY = 0.52;
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

    if (collisionCooldown > 0) {
      collisionCooldown -= dt;
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
      p.y += p.speed * dt * 0.42;
      if (p.y > 1.05) {
        p.y = -0.03;
      }
    }
  }

  void _updateShip(double dt) {
    // HACKABLE NOTE:
    // Tune these first for flight feel.
    const accelX = 3.2;
    const accelY = 2.5;
    const damping = 0.89;
    const maxVX = 1.30;
    const maxVY = 0.95;

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

    shipX = shipX.clamp(-1.1, 1.1);
    shipY = shipY.clamp(0.14, 0.90);

    if (shipX <= -1.1 || shipX >= 1.1) shipVX *= -0.10;
    if (shipY <= 0.14 || shipY >= 0.90) shipVY *= -0.10;
  }

  // ---------------------------------------------------------------------------
  // Terrain model
  // ---------------------------------------------------------------------------

  double _pathCenter(double d) {
    return sin(d / 520.0) * 0.34 +
        sin(d / 1100.0 + 0.8) * 0.16 +
        sin(d / 260.0 + 1.6) * 0.03;
  }

  double _pathHalfWidth(double d) {
    final base = 0.52 + sin(d / 700.0 + 0.6) * 0.04;

    final narrow1 = _bump(d, 1800, 360, -0.08);
    final narrow2 = _bump(d, 3600, 340, -0.10);
    final narrow3 = _bump(d, 5000, 260, -0.06);

    return (base + narrow1 + narrow2 + narrow3).clamp(0.34, 0.58);
  }

  double _groundHeight(double d) {
    final base = 0.20;
    final waves = sin(d / 340.0 + 0.5) * 0.04 + sin(d / 115.0) * 0.010;

    final hill1 = _bump(d, 1200, 320, 0.10);
    final hill2 = _bump(d, 2650, 260, 0.12);
    final hill3 = _bump(d, 4300, 320, 0.10);

    return (base + waves + hill1 + hill2 + hill3).clamp(0.10, 0.52);
  }

  double _ceilingHeight(double d) {
    final base = 0.92;
    final dip1 = _bump(d, 2000, 320, -0.05);
    final dip2 = _bump(d, 3900, 260, -0.05);

    return (base + dip1 + dip2).clamp(0.78, 0.94);
  }

  double _bump(double x, double center, double width, double amplitude) {
    final t = (x - center) / width;
    return amplitude * exp(-t * t);
  }

  void _checkTerrainCollision() {
    final sampleD = distance + 90;

    final center = _pathCenter(sampleD);
    final halfWidth = _pathHalfWidth(sampleD);
    final floor = _groundHeight(sampleD);
    final ceiling = _ceilingHeight(sampleD);

    final lateralError = (shipX - center).abs();
    final hitWall = lateralError > halfWidth * 1.04;
    final hitGround = shipY < floor + 0.015;
    final hitCeiling = shipY > ceiling - 0.02;

    if ((hitWall || hitGround || hitCeiling) && collisionCooldown <= 0) {
      hull -= 6;
      damageFlash = 0.10;
      collisionCooldown = 0.20;
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

    shipVX += dx * 3.0;
    shipVY += (-dy) * 2.4;
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
        return 'READABLE CANYON TEST';
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
        return 'This version is about route readability.\nFollow the bright trench through the Hoth canyon.';
      case _GamePhase.paused:
        return 'Pause and take a breath.';
      case _GamePhase.victory:
        return 'You completed the full canyon flight test.';
      case _GamePhase.crashed:
        return 'You lost the canyon line.';
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
                      painter: _ReadableCanyonPainter(
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
                                          ? 'Hoth Canyon Flight'
                                          : 'Readable Canyon Prototype',
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

class _ReadableCanyonPainter extends CustomPainter {
  _ReadableCanyonPainter({
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
    _paintReadableCanyon(canvas, size);
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

  void _paintReadableCanyon(Canvas canvas, Size size) {
    final horizonY = size.height * 0.43;
    final bottomY = size.height * 0.95;

    final leftWallOuter = <Offset>[];
    final leftWallInner = <Offset>[];
    final rightWallInner = <Offset>[];
    final rightWallOuter = <Offset>[];
    final floorLeft = <Offset>[];
    final floorRight = <Offset>[];
    final centerLine = <Offset>[];
    final leftEdge = <Offset>[];
    final rightEdge = <Offset>[];

    const samples = 44;
    const lookAhead = 1000.0;

    for (int i = 0; i < samples; i++) {
      final t = i / (samples - 1);
      final d = distance + t * lookAhead;

      final scale = lerpDouble(0.06, 1.0, pow(t, 1.42).toDouble())!;
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
          (0.5 + ((worldCenter - worldHalf - 0.34) - playerX) * 0.34 * scale);
      final rightOuterX = size.width *
          (0.5 + ((worldCenter + worldHalf + 0.34) - playerX) * 0.34 * scale);

      final baseFloorY = lerpDouble(horizonY + 18, bottomY, scale)!;
      final floorY =
          baseFloorY + (floorH - playerY) * size.height * 0.42 * scale;

      final ceilingBaseY = lerpDouble(horizonY - 6, size.height * 0.70, scale)!;
      final ceilingY =
          ceilingBaseY + (ceilingH - playerY) * size.height * 0.18 * scale;

      leftWallOuter.add(Offset(leftOuterX, floorY));
      leftWallInner.add(Offset(leftInnerX, floorY));
      rightWallInner.add(Offset(rightInnerX, floorY));
      rightWallOuter.add(Offset(rightOuterX, floorY));

      floorLeft.add(Offset(leftInnerX, floorY));
      floorRight.add(Offset(rightInnerX, floorY));

      leftEdge.add(Offset(leftInnerX, floorY));
      rightEdge.add(Offset(rightInnerX, floorY));

      // Brighter center guidance so the route is obvious.
      final centerY = lerpDouble(floorY - 10, ceilingY + 26, 0.10)!;
      centerLine.add(Offset(screenCenterX, centerY));
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
      Paint()..color = const Color(0x99D4F4FF),
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
      Paint()..color = const Color(0x99D4F4FF),
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
            Color(0xBBE7FBFF),
            Color(0xFFF8FDFF),
          ],
        ).createShader(Rect.fromLTWH(0, horizonY, size.width, size.height)),
    );

    // Strong readable canyon edges
    final edgePaint = Paint()
      ..color = Colors.white.withOpacity(0.40)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final leftEdgePath = Path()..moveTo(leftEdge.first.dx, leftEdge.first.dy);
    for (final p in leftEdge.skip(1)) {
      leftEdgePath.lineTo(p.dx, p.dy);
    }

    final rightEdgePath = Path()..moveTo(rightEdge.first.dx, rightEdge.first.dy);
    for (final p in rightEdge.skip(1)) {
      rightEdgePath.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(leftEdgePath, edgePaint);
    canvas.drawPath(rightEdgePath, edgePaint);

    // Center trench glow / guide
    final centerGlow = Paint()
      ..color = accent.withOpacity(0.18)
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final centerCore = Paint()
      ..color = accent.withOpacity(0.46)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final centerPath = Path()..moveTo(centerLine.first.dx, centerLine.first.dy);
    for (final p in centerLine.skip(1)) {
      centerPath.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(centerPath, centerGlow);
    canvas.drawPath(centerPath, centerCore);

    // Light terrain stripes to help forward-motion reading
    final stripePaint = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..strokeWidth = 1.2;

    for (int i = 6; i < centerLine.length; i += 4) {
      final c = centerLine[i];
      final l = leftEdge[i];
      final r = rightEdge[i];

      final t = i / (centerLine.length - 1);
      final half = lerpDouble(8.0, 44.0, t)!;

      final dirX = (r.dx - l.dx);
      final dirY = (r.dy - l.dy);
      final len = sqrt(dirX * dirX + dirY * dirY);
      if (len <= 0.0001) continue;

      final nx = dirX / len;
      final ny = dirY / len;

      canvas.drawLine(
        Offset(c.dx - nx * half, c.dy - ny * half),
        Offset(c.dx + nx * half, c.dy + ny * half),
        stripePaint,
      );
    }
  }

  void _paintParticles(Canvas canvas, Size size) {
    for (final p in particles) {
      final x = p.x * size.width;
      final y = p.y * size.height;
      canvas.drawCircle(
        Offset(x, y),
        p.size,
        Paint()..color = Colors.white.withOpacity(0.15),
      );
    }
  }

  void _paintCockpitGlassLines(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = accent.withOpacity(0.24)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final frame = Path()
      ..moveTo(size.width * 0.16, size.height * 0.92)
      ..lineTo(size.width * 0.12, size.height * 0.58)
      ..lineTo(size.width * 0.20, size.height * 0.18)
      ..lineTo(size.width * 0.80, size.height * 0.18)
      ..lineTo(size.width * 0.88, size.height * 0.58)
      ..lineTo(size.width * 0.84, size.height * 0.92);

    canvas.drawPath(frame, linePaint);

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

    final dashPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width * 0.14, size.height * 0.84)
      ..lineTo(size.width * 0.34, size.height * 0.78)
      ..lineTo(size.width * 0.66, size.height * 0.78)
      ..lineTo(size.width * 0.86, size.height * 0.84)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(dashPath, darkPanel);

    final nosePath = Path()
      ..moveTo(size.width * 0.42, size.height)
      ..lineTo(size.width * 0.46, size.height * 0.86)
      ..lineTo(size.width * 0.54, size.height * 0.86)
      ..lineTo(size.width * 0.58, size.height)
      ..close();

    canvas.drawPath(nosePath, midPanel);

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
  bool shouldRepaint(covariant _ReadableCanyonPainter oldDelegate) => true;
}
