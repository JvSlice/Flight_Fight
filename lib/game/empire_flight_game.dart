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
  gameOver,
}

enum _ObstacleKind {
  iceSpire,
  iceWall,
}

class _Obstacle {
  _Obstacle({
    required this.kind,
    required this.x,
    required this.z,
    required this.width,
    required this.height,
    this.active = true,
  });

  _ObstacleKind kind;
  double x;
  double z;
  double width;
  double height;
  bool active;
}

class _Star {
  _Star({
    required this.x,
    required this.y,
    required this.speed,
  });

  double x;
  double y;
  double speed;
}

class _EmpireFlightGameState extends State<EmpireFlightGame> {
  final FocusNode _keyboardFocus = FocusNode();
  final Random _rng = Random();

  Timer? _loop;
  DateTime? _lastTick;

  _GamePhase phase = _GamePhase.briefing;

  static const double _missionDistance = 4200;
  static const double _baseSpeed = 210;

  double distance = 0;
  int hull = 100;
  double damageFlash = 0;

  // HACKABLE NOTE:
  // This is the actual flying model.
  // shipX / shipY are position.
  // shipVX / shipVY are momentum.
  double shipX = 0;
  double shipY = 0;
  double shipVX = 0;
  double shipVY = 0;

  bool leftPressed = false;
  bool rightPressed = false;
  bool upPressed = false;
  bool downPressed = false;

  final List<_Obstacle> obstacles = [];
  final List<_Star> stars = [];
  final Set<int> _spawnedGroups = {};

  Size playSize = const Size(1000, 700);

  @override
  void initState() {
    super.initState();

    for (int i = 0; i < 90; i++) {
      stars.add(
        _Star(
          x: _rng.nextDouble(),
          y: _rng.nextDouble() * 0.58,
          speed: 0.25 + _rng.nextDouble() * 0.95,
        ),
      );
    }

    _resetRun();
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

  double get worldSpeed => _baseSpeed * (1.0 + progress * 0.14);

  void _resetRun() {
    phase = _GamePhase.briefing;
    distance = 0;
    hull = 100;
    damageFlash = 0;

    shipX = 0;
    shipY = 0;
    shipVX = 0;
    shipVY = 0;

    leftPressed = false;
    rightPressed = false;
    upPressed = false;
    downPressed = false;

    obstacles.clear();
    _spawnedGroups.clear();
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

    _updateStars(dt);

    if (damageFlash > 0) {
      damageFlash -= dt;
    }

    if (phase != _GamePhase.playing) {
      setState(() {});
      return;
    }

    _updateShip(dt);
    _spawnScriptedGroups();
    _updateObstacles(dt);
    _handleCollisions();
    _cleanup();

    distance += worldSpeed * dt;

    if (hull <= 0) {
      hull = 0;
      phase = _GamePhase.gameOver;
    } else if (distance >= _missionDistance) {
      phase = _GamePhase.victory;
    }

    setState(() {});
  }

  void _updateStars(double dt) {
    final drift = 0.05 + progress * 0.018;
    for (final s in stars) {
      s.y += s.speed * drift * dt * 10;
      if (s.y > 0.58) {
        s.y = 0;
        s.x = _rng.nextDouble();
      }
    }
  }

  void _updateShip(double dt) {
    // HACKABLE NOTE:
    // Tune these first if the flight feel is wrong.
    const accelX = 3.2;
    const accelY = 2.0;
    const damping = 0.88;
    const maxVX = 1.25;
    const maxVY = 0.85;

    if (leftPressed) shipVX -= accelX * dt;
    if (rightPressed) shipVX += accelX * dt;
    if (upPressed) shipVY -= accelY * dt;
    if (downPressed) shipVY += accelY * dt;

    shipVX *= pow(damping, dt * 60).toDouble();
    shipVY *= pow(damping, dt * 60).toDouble();

    shipVX = shipVX.clamp(-maxVX, maxVX);
    shipVY = shipVY.clamp(-maxVY, maxVY);

    shipX += shipVX * dt;
    shipY += shipVY * dt;

    // Broad play area.
    shipX = shipX.clamp(-0.95, 0.95);
    shipY = shipY.clamp(-0.24, 0.20);

    if (shipX <= -0.95 || shipX >= 0.95) shipVX *= -0.18;
    if (shipY <= -0.24 || shipY >= 0.20) shipVY *= -0.18;
  }

  void _spawnScriptedGroups() {
    _spawnAt(180, 1, () => _spawnWideGate(openLeft: true));
    _spawnAt(520, 2, () => _spawnSlalom(leftFirst: true));
    _spawnAt(860, 3, () => _spawnWideGate(openLeft: false));
    _spawnAt(1200, 4, () => _spawnCenterPass());
    _spawnAt(1550, 5, () => _spawnSlalom(leftFirst: false));
    _spawnAt(1920, 6, () => _spawnWideGate(openLeft: true));
    _spawnAt(2280, 7, () => _spawnTightPass());
    _spawnAt(2670, 8, () => _spawnSlalom(leftFirst: true));
    _spawnAt(3080, 9, () => _spawnWideGate(openLeft: false));
    _spawnAt(3480, 10, () => _spawnCenterPass());
    _spawnAt(3860, 11, () => _spawnFinalGauntlet());
  }

  void _spawnAt(double distanceMark, int id, VoidCallback spawn) {
    if (_spawnedGroups.contains(id)) return;
    if (distance >= distanceMark) return;

    if (distanceMark - distance <= 420) {
      _spawnedGroups.add(id);
      spawn();
    }
  }

  void _spawnWideGate({required bool openLeft}) {
    if (openLeft) {
      obstacles.addAll([
        _Obstacle(
          kind: _ObstacleKind.iceWall,
          x: 0.28,
          z: 0.05,
          width: 0.22,
          height: 0.18,
        ),
        _Obstacle(
          kind: _ObstacleKind.iceSpire,
          x: 0.68,
          z: 0.05,
          width: 0.12,
          height: 0.25,
        ),
      ]);
    } else {
      obstacles.addAll([
        _Obstacle(
          kind: _ObstacleKind.iceWall,
          x: -0.28,
          z: 0.05,
          width: 0.22,
          height: 0.18,
        ),
        _Obstacle(
          kind: _ObstacleKind.iceSpire,
          x: -0.68,
          z: 0.05,
          width: 0.12,
          height: 0.25,
        ),
      ]);
    }
  }

  void _spawnSlalom({required bool leftFirst}) {
    final xs = leftFirst ? [-0.60, 0.10, -0.18] : [0.60, -0.10, 0.18];

    for (int i = 0; i < xs.length; i++) {
      obstacles.add(
        _Obstacle(
          kind: _ObstacleKind.iceSpire,
          x: xs[i],
          z: 0.05 + i * 0.03,
          width: 0.12,
          height: 0.25,
        ),
      );
    }
  }

  void _spawnCenterPass() {
    obstacles.addAll([
      _Obstacle(
        kind: _ObstacleKind.iceWall,
        x: -0.56,
        z: 0.05,
        width: 0.18,
        height: 0.18,
      ),
      _Obstacle(
        kind: _ObstacleKind.iceWall,
        x: 0.56,
        z: 0.05,
        width: 0.18,
        height: 0.18,
      ),
    ]);
  }

  void _spawnTightPass() {
    obstacles.addAll([
      _Obstacle(
        kind: _ObstacleKind.iceSpire,
        x: -0.22,
        z: 0.05,
        width: 0.12,
        height: 0.25,
      ),
      _Obstacle(
        kind: _ObstacleKind.iceSpire,
        x: 0.22,
        z: 0.08,
        width: 0.12,
        height: 0.25,
      ),
    ]);
  }

  void _spawnFinalGauntlet() {
    obstacles.addAll([
      _Obstacle(
        kind: _ObstacleKind.iceWall,
        x: -0.54,
        z: 0.05,
        width: 0.18,
        height: 0.18,
      ),
      _Obstacle(
        kind: _ObstacleKind.iceWall,
        x: 0.54,
        z: 0.05,
        width: 0.18,
        height: 0.18,
      ),
      _Obstacle(
        kind: _ObstacleKind.iceSpire,
        x: -0.12,
        z: 0.09,
        width: 0.12,
        height: 0.25,
      ),
      _Obstacle(
        kind: _ObstacleKind.iceSpire,
        x: 0.18,
        z: 0.13,
        width: 0.12,
        height: 0.25,
      ),
    ]);
  }

  void _updateObstacles(double dt) {
    final advance = dt * (0.30 + worldSpeed / 860.0);

    for (final o in obstacles) {
      o.z += advance;
    }
  }

  void _handleCollisions() {
    for (final o in obstacles) {
      if (!o.active) continue;

      if (o.z > 0.88) {
        // HACKABLE NOTE:
        // This is the ship contact size.
        final xThreshold =
            o.kind == _ObstacleKind.iceWall ? o.width * 1.16 : o.width * 1.06;

        if ((o.x - shipX).abs() < xThreshold) {
          o.active = false;
          hull -= 24;
          damageFlash = 0.16;
        }
      }

      if (o.active && o.z > 1.10) {
        o.active = false;
      }
    }
  }

  void _cleanup() {
    obstacles.removeWhere((o) => !o.active);
  }

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
    shipVY += dy * 1.6;
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
        case _GamePhase.gameOver:
          _restartRun();
          break;
        case _GamePhase.playing:
          break;
      }
      return KeyEventResult.handled;
    }

    if (isDown && key == LogicalKeyboardKey.keyR) {
      if (phase == _GamePhase.victory || phase == _GamePhase.gameOver) {
        _restartRun();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _overlayTitle() {
    switch (phase) {
      case _GamePhase.briefing:
        return 'FLIGHT PROTOTYPE';
      case _GamePhase.paused:
        return 'PAUSED';
      case _GamePhase.victory:
        return 'RUN COMPLETE';
      case _GamePhase.gameOver:
        return 'CRASHED';
      case _GamePhase.playing:
        return '';
    }
  }

  String _overlaySubtitle() {
    switch (phase) {
      case _GamePhase.briefing:
        return 'No shooting. No enemies.\nJust fly the ice run and see if the movement feels right.';
      case _GamePhase.paused:
        return 'Take a breath and resume when ready.';
      case _GamePhase.victory:
        return 'You made it through the full ice run.';
      case _GamePhase.gameOver:
        return 'The prototype failed the run.';
      case _GamePhase.playing:
        return '';
    }
  }

  String _overlayButtonText() {
    switch (phase) {
      case _GamePhase.briefing:
        return 'Start Flight Test';
      case _GamePhase.paused:
        return 'Resume';
      case _GamePhase.victory:
      case _GamePhase.gameOver:
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
                } else if (phase == _GamePhase.victory || phase == _GamePhase.gameOver) {
                  _restartRun();
                }
              },
              onPanUpdate: phase == _GamePhase.playing ? _handleDrag : null,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FlightPrototypePainter(
                        playerX: shipX,
                        playerY: shipY,
                        obstacles: obstacles,
                        stars: stars,
                        accent: const Color(0xFFD9F3FF),
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
                                          ? 'Ice Flight Test'
                                          : 'Flight Prototype',
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
                                        case _GamePhase.gameOver:
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

class _FlightPrototypePainter extends CustomPainter {
  _FlightPrototypePainter({
    required this.playerX,
    required this.playerY,
    required this.obstacles,
    required this.stars,
    required this.accent,
  });

  final double playerX;
  final double playerY;
  final List<_Obstacle> obstacles;
  final List<_Star> stars;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    _paintStars(canvas, size);
    _paintGround(canvas, size);
    _paintMountains(canvas, size);
    _paintTrackLines(canvas, size);

    final sorted = [...obstacles]..sort((a, b) => a.z.compareTo(b.z));
    for (final o in sorted) {
      _paintObstacle(canvas, size, o);
    }

    _paintShipBody(canvas, size);
    _paintCockpit(canvas, size);
  }

  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0E1A33), Color(0xFF79B7E6)],
      ).createShader(rect);
    canvas.drawRect(rect, p);
  }

  void _paintStars(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.75);
    for (final s in stars) {
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        1.0 + s.speed * 0.4,
        p,
      );
    }
  }

  void _paintGround(Canvas canvas, Size size) {
    final horizonY = size.height * 0.42;
    final rect = Rect.fromLTWH(0, horizonY, size.width, size.height - horizonY);

    final p = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF9CC6E3), Color(0xFFDFF5FF)],
      ).createShader(rect);

    canvas.drawRect(rect, p);
  }

  void _paintMountains(Canvas canvas, Size size) {
    final horizonY = size.height * 0.42;
    final path = Path()..moveTo(0, horizonY);

    final peaks = [
      Offset(size.width * 0.05, horizonY - 34),
      Offset(size.width * 0.14, horizonY - 10),
      Offset(size.width * 0.27, horizonY - 50),
      Offset(size.width * 0.44, horizonY - 16),
      Offset(size.width * 0.62, horizonY - 46),
      Offset(size.width * 0.78, horizonY - 14),
      Offset(size.width, horizonY - 34),
    ];

    for (final p in peaks) {
      path.lineTo(p.dx, p.dy);
    }
    path.lineTo(size.width, horizonY);
    path.close();

    canvas.drawPath(path, Paint()..color = const Color(0x66E2F4FF));
  }

  void _paintTrackLines(Canvas canvas, Size size) {
    final horizonY = size.height * 0.42;
    final centerX = size.width / 2 + playerX * size.width * 0.07;

    final p = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(centerX - size.width * 0.28, size.height),
      Offset(centerX - size.width * 0.08, horizonY),
      p,
    );
    canvas.drawLine(
      Offset(centerX + size.width * 0.28, size.height),
      Offset(centerX + size.width * 0.08, horizonY),
      p,
    );

    for (int i = 0; i < 8; i++) {
      final t = i / 7;
      final y = lerpDouble(
        horizonY + 18,
        size.height - 28,
        pow(t, 1.45).toDouble(),
      )!;
      final halfW = lerpDouble(size.width * 0.03, size.width * 0.24, t)!;
      canvas.drawLine(
        Offset(centerX - halfW, y),
        Offset(centerX + halfW, y),
        p,
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(0, horizonY - 2, size.width, 4),
      Paint()..color = Colors.white.withOpacity(0.10),
    );
  }

  void _paintObstacle(Canvas canvas, Size size, _Obstacle o) {
    final pos = _project(size, o.x, o.z, playerX, playerY);
    final scale = o.z.clamp(0.06, 1.0);
    final w = size.width * o.width * scale;
    final h = size.height * o.height * scale;

    switch (o.kind) {
      case _ObstacleKind.iceWall:
        final rect = Rect.fromCenter(
          center: Offset(pos.dx, pos.dy - h * 0.5),
          width: w,
          height: h,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(max(4, w * 0.08))),
          Paint()..color = const Color(0xFFDFF7FF),
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(max(4, w * 0.08))),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.0, w * 0.03)
            ..color = const Color(0x88AEE2FF),
        );
        break;

      case _ObstacleKind.iceSpire:
        final path = Path()
          ..moveTo(pos.dx - w * 0.45, pos.dy)
          ..lineTo(pos.dx - w * 0.20, pos.dy - h * 0.45)
          ..lineTo(pos.dx - w * 0.04, pos.dy - h * 0.98)
          ..lineTo(pos.dx + w * 0.10, pos.dy - h * 0.64)
          ..lineTo(pos.dx + w * 0.32, pos.dy - h * 0.84)
          ..lineTo(pos.dx + w * 0.45, pos.dy)
          ..close();

        canvas.drawPath(path, Paint()..color = const Color(0xFFDDF6FF));
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.0, w * 0.035)
            ..color = const Color(0x889EDCFF),
        );
        break;
    }
  }

  void _paintShipBody(Canvas canvas, Size size) {
    final center = Offset(
      size.width * (0.5 + playerX * 0.12),
      size.height * (0.80 + playerY * 0.03),
    );

    final fillPaint = Paint()
      ..color = accent.withOpacity(0.18)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = accent.withOpacity(0.56)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final hull = Path()
      ..moveTo(center.dx, center.dy - 18)
      ..lineTo(center.dx - 24, center.dy + 10)
      ..lineTo(center.dx - 10, center.dy + 4)
      ..lineTo(center.dx, center.dy + 15)
      ..lineTo(center.dx + 10, center.dy + 4)
      ..lineTo(center.dx + 24, center.dy + 10)
      ..close();

    canvas.drawPath(hull, fillPaint);
    canvas.drawPath(hull, linePaint);

    final leftWing = Path()
      ..moveTo(center.dx - 16, center.dy + 2)
      ..lineTo(center.dx - 34, center.dy + 15)
      ..lineTo(center.dx - 12, center.dy + 10);

    final rightWing = Path()
      ..moveTo(center.dx + 16, center.dy + 2)
      ..lineTo(center.dx + 34, center.dy + 15)
      ..lineTo(center.dx + 12, center.dy + 10);

    canvas.drawPath(leftWing, linePaint);
    canvas.drawPath(rightWing, linePaint);
  }

  void _paintCockpit(Canvas canvas, Size size) {
    final framePaint = Paint()..color = const Color(0x77081118);
    final sidePaint = Paint()..color = const Color(0x33081118);
    final linePaint = Paint()
      ..color = accent.withOpacity(0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 112, size.width, 112),
      framePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 34, size.height),
      sidePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width - 34, 0, 34, size.height),
      sidePaint,
    );

    canvas.drawLine(
      Offset(size.width * 0.18, size.height),
      Offset(size.width * 0.08, size.height * 0.58),
      linePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.82, size.height),
      Offset(size.width * 0.92, size.height * 0.58),
      linePaint,
    );

    canvas.drawLine(
      Offset(0, size.height - 112),
      Offset(size.width, size.height - 112),
      linePaint,
    );
  }

  Offset _project(Size size, double x, double z, double playerX, double playerY) {
    final horizonY = size.height * 0.42;
    final bottomY = size.height * (0.86 + playerY * 0.025);
    final scale = z.clamp(0.06, 1.0);

    final screenX = size.width * (0.5 + (x - playerX * 0.50) * 0.30 * scale);
    final screenY = lerpDouble(horizonY, bottomY, scale)!;

    return Offset(screenX, screenY);
  }

  @override
  bool shouldRepaint(covariant _FlightPrototypePainter oldDelegate) => true;
}
