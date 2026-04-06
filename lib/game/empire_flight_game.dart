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

  static const double _missionDistance = 5200;
  static const double _baseSpeed = 215;

  double distance = 0;
  int hull = 100;
  double damageFlash = 0;
  double collisionCooldown = 0;

  // HACKABLE NOTE:
  // shipX = lateral offset from trench center
  // shipY = altitude feeling, 0 = low, 1 = high
  double shipX = 0.0;
  double shipY = 0.56;
  double shipVX = 0.0;
  double shipVY = 0.0;

  bool leftPressed = false;
  bool rightPressed = false;
  bool upPressed = false;
  bool downPressed = false;

  final List<_SnowParticle> particles = [];
  final Random rng = Random();

  Size playSize = const Size(1000, 700);

  @override
  void initState() {
    super.initState();

    for (int i = 0; i < 120; i++) {
      particles.add(
        _SnowParticle(
          x: rng.nextDouble(),
          y: rng.nextDouble(),
          speed: 0.35 + rng.nextDouble() * 1.1,
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

  double get worldSpeed => _baseSpeed * (1.0 + progress * 0.08);

  void _resetRun() {
    phase = _GamePhase.briefing;
    distance = 0;
    hull = 100;
    damageFlash = 0;
    collisionCooldown = 0;

    shipX = 0.0;
    shipY = 0.56;
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
      p.y += p.speed * dt * 0.40;
      if (p.y > 1.04) {
        p.y = -0.03;
        p.x = rng.nextDouble();
      }
    }
  }

  void _updateShip(double dt) {
    // HACKABLE NOTE:
    // Tune these four values first for flight feel.
    const accelX = 3.0;
    const accelY = 2.4;
    const damping = 0.90;
    const maxVX = 1.20;
    const maxVY = 0.90;

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

    shipX = shipX.clamp(-1.0, 1.0);
    shipY = shipY.clamp(0.18, 0.90);

    if (shipX <= -1.0 || shipX >= 1.0) shipVX *= -0.12;
    if (shipY <= 0.18 || shipY >= 0.90) shipVY *= -0.10;
  }

  // ---------------------------------------------------------------------------
  // Terrain model
  // ---------------------------------------------------------------------------

  double _pathCenter(double d) {
    return sin(d / 520.0) * 0.34 +
        sin(d / 1150.0 + 0.8) * 0.18 +
        sin(d / 260.0 + 1.2) * 0.03;
  }

  double _pathHalfWidth(double d) {
    final base = 0.54 + sin(d / 820.0 + 0.7) * 0.03;
    final narrow1 = _bump(d, 1800, 380, -0.08);
    final narrow2 = _bump(d, 3450, 340, -0.10);
    final narrow3 = _bump(d, 4650, 260, -0.06);
    return (base + narrow1 + narrow2 + narrow3).clamp(0.36, 0.60);
  }

  double _groundHeight(double d) {
    final base = 0.18;
    final waves = sin(d / 340.0 + 0.4) * 0.035 + sin(d / 110.0) * 0.010;
    final hill1 = _bump(d, 1200, 320, 0.10);
    final hill2 = _bump(d, 2550, 260, 0.12);
    final hill3 = _bump(d, 4250, 300, 0.09);
    return (base + waves + hill1 + hill2 + hill3).clamp(0.10, 0.52);
  }

  double _ceilingHeight(double d) {
    final base = 0.94;
    final dip1 = _bump(d, 2150, 320, -0.05);
    final dip2 = _bump(d, 3950, 260, -0.05);
    return (base + dip1 + dip2).clamp(0.80, 0.96);
  }

  double _bump(double x, double center, double width, double amplitude) {
    final t = (x - center) / width;
    return amplitude * exp(-t * t);
  }

  void _checkTerrainCollision() {
    final sampleD = distance + 80;

    final center = _pathCenter(sampleD);
    final halfWidth = _pathHalfWidth(sampleD);
    final floor = _groundHeight(sampleD);
    final ceiling = _ceilingHeight(sampleD);

    final hitWall = (shipX - center).abs() > halfWidth * 1.02;
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

    shipVX += dx * 2.8;
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

  String _overlayTitle() {
    switch (phase) {
      case _GamePhase.briefing:
        return 'DEPTH FLIGHT TEST';
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
        return 'Follow the bright trench.\nThis version is focused on forward motion and route readability.';
      case _GamePhase.paused:
        return 'Pause and take a breath.';
      case _GamePhase.victory:
        return 'You completed the flight test.';
      case _GamePhase.crashed:
        return 'You drifted out of the canyon line.';
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
                      painter: _DepthFlightPainter(
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
                      child: Container(color: Colors.red.withOpacity(0.10)),
                    ),

                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: SafeArea(
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0x55000000),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0x22FFFFFF)),
                              ),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Hoth Flight',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.7,
                                      ),
                                    ),
                                  ),
                                  const Text('Hull'),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: isCompact ? 82 : 120,
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
                                  const SizedBox(width: 10),
                                  SizedBox(
                                    width: isCompact ? 82 : 130,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 10,
                                        backgroundColor: const Color(0x33222222),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${distance.floor()}m'),
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
                            constraints: const BoxConstraints(maxWidth: 560),
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
                                      letterSpacing: 1.2,
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
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

class _DepthFlightPainter extends CustomPainter {
  _DepthFlightPainter({
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
    _paintFarBackground(canvas, size);
    _paintDepthTrench(canvas, size);
    _paintParticles(canvas, size);
    _paintCockpitWindow(canvas, size);
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

  void _paintFarBackground(Canvas canvas, Size size) {
    final horizonY = size.height * 0.43;

    final farSnow = Rect.fromLTWH(0, horizonY, size.width, size.height - horizonY);
    canvas.drawRect(
      farSnow,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFBEDAEB), Color(0xFFF0FAFF)],
        ).createShader(farSnow),
    );

    final mountainPath = Path()..moveTo(0, horizonY);

    final peaks = [
      Offset(size.width * 0.00, horizonY - 18),
      Offset(size.width * 0.08, horizonY - 40),
      Offset(size.width * 0.17, horizonY - 10),
      Offset(size.width * 0.30, horizonY - 55),
      Offset(size.width * 0.44, horizonY - 18),
      Offset(size.width * 0.57, horizonY - 60),
      Offset(size.width * 0.73, horizonY - 14),
      Offset(size.width * 0.89, horizonY - 42),
      Offset(size.width, horizonY - 20),
    ];

    for (final p in peaks) {
      mountainPath.lineTo(p.dx, p.dy);
    }
    mountainPath.lineTo(size.width, horizonY);
    mountainPath.close();

    canvas.drawPath(
      mountainPath,
      Paint()..color = const Color(0x66F3FBFF),
    );
  }

  void _paintDepthTrench(Canvas canvas, Size size) {
    final horizonY = size.height * 0.43;
    final bottomY = size.height * 0.96;

    final leftOuter = <Offset>[];
    final leftInner = <Offset>[];
    final rightInner = <Offset>[];
    final rightOuter = <Offset>[];
    final centerPoints = <Offset>[];
    final stripeLeft = <Offset>[];
    final stripeRight = <Offset>[];

    const samples = 48;
    const lookAhead = 1100.0;

    for (int i = 0; i < samples; i++) {
      final t = i / (samples - 1);
      final d = distance + t * lookAhead;

      final scale = lerpDouble(0.05, 1.0, pow(t, 1.36).toDouble())!;
      final center = pathCenterFn(d);
      final halfWidth = pathHalfWidthFn(d);
      final ground = groundHeightFn(d);
      final ceiling = ceilingHeightFn(d);

      final screenCenterX =
          size.width * (0.5 + (center - playerX) * 0.34 * scale);

      final leftInnerX =
          size.width * (0.5 + ((center - halfWidth) - playerX) * 0.34 * scale);
      final rightInnerX =
          size.width * (0.5 + ((center + halfWidth) - playerX) * 0.34 * scale);

      final leftOuterX = size.width *
          (0.5 + ((center - halfWidth - 0.40) - playerX) * 0.34 * scale);
      final rightOuterX = size.width *
          (0.5 + ((center + halfWidth + 0.40) - playerX) * 0.34 * scale);

      final floorBaseY = lerpDouble(horizonY + 10, bottomY, scale)!;
      final floorY = floorBaseY + (ground - playerY) * size.height * 0.46 * scale;

      final cliffLift = max(0.0, (ceiling - playerY) * 60 * scale);
      final wallY = floorY - 20 - cliffLift;

      leftOuter.add(Offset(leftOuterX, floorY));
      leftInner.add(Offset(leftInnerX, wallY));
      rightInner.add(Offset(rightInnerX, wallY));
      rightOuter.add(Offset(rightOuterX, floorY));

      centerPoints.add(Offset(screenCenterX, floorY - 6));
      stripeLeft.add(Offset(leftInnerX, floorY - 4));
      stripeRight.add(Offset(rightInnerX, floorY - 4));
    }

    final leftWall = Path()..moveTo(leftOuter.first.dx, leftOuter.first.dy);
    for (final p in leftOuter) {
      leftWall.lineTo(p.dx, p.dy);
    }
    for (final p in leftInner.reversed) {
      leftWall.lineTo(p.dx, p.dy);
    }
    leftWall.close();

    final rightWall = Path()..moveTo(rightInner.first.dx, rightInner.first.dy);
    for (final p in rightInner) {
      rightWall.lineTo(p.dx, p.dy);
    }
    for (final p in rightOuter.reversed) {
      rightWall.lineTo(p.dx, p.dy);
    }
    rightWall.close();

    final floor = Path()..moveTo(leftInner.first.dx, leftInner.first.dy);
    for (final p in leftInner) {
      floor.lineTo(p.dx, p.dy);
    }
    for (final p in rightInner.reversed) {
      floor.lineTo(p.dx, p.dy);
    }
    floor.close();

    canvas.drawPath(leftWall, Paint()..color = const Color(0x995D8BB5));
    canvas.drawPath(rightWall, Paint()..color = const Color(0x995D8BB5));

    canvas.drawPath(
      floor,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFEAFBFF),
            Color(0xFFFDFEFF),
          ],
        ).createShader(Rect.fromLTWH(0, horizonY, size.width, size.height)),
    );

    final edgeGlow = Paint()
      ..color = Colors.white.withOpacity(0.34)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final leftEdgePath = Path()..moveTo(leftInner.first.dx, leftInner.first.dy);
    for (final p in leftInner.skip(1)) {
      leftEdgePath.lineTo(p.dx, p.dy);
    }

    final rightEdgePath = Path()..moveTo(rightInner.first.dx, rightInner.first.dy);
    for (final p in rightInner.skip(1)) {
      rightEdgePath.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(leftEdgePath, edgeGlow);
    canvas.drawPath(rightEdgePath, edgeGlow);

    final centerGlow = Paint()
      ..color = accent.withOpacity(0.22)
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final centerCore = Paint()
      ..color = accent.withOpacity(0.54)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final centerPath = Path()..moveTo(centerPoints.first.dx, centerPoints.first.dy);
    for (final p in centerPoints.skip(1)) {
      centerPath.lineTo(p.dx, p.dy);
    }

    canvas.drawPath(centerPath, centerGlow);
    canvas.drawPath(centerPath, centerCore);

    final stripePaint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..strokeWidth = 1.4;

    for (int i = 6; i < centerPoints.length; i += 4) {
      final c = centerPoints[i];
      final l = stripeLeft[i];
      final r = stripeRight[i];

      final t = i / (centerPoints.length - 1);
      final half = lerpDouble(8.0, 54.0, t)!;

      final dx = r.dx - l.dx;
      final dy = r.dy - l.dy;
      final len = sqrt(dx * dx + dy * dy);
      if (len < 0.001) continue;

      final nx = dx / len;
      final ny = dy / len;

      canvas.drawLine(
        Offset(c.dx - nx * half, c.dy - ny * half),
        Offset(c.dx + nx * half, c.dy + ny * half),
        stripePaint,
      );
    }
  }

  void _paintParticles(Canvas canvas, Size size) {
    for (final p in particles) {
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.size,
        Paint()..color = Colors.white.withOpacity(0.16),
      );
    }
  }

  void _paintCockpitWindow(Canvas canvas, Size size) {
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
    final darkPanel = Paint()..color = const Color(0xE0081018);
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

    final sideShade = Paint()..color = const Color(0x88081118);
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
  bool shouldRepaint(covariant _DepthFlightPainter oldDelegate) => true;
}
