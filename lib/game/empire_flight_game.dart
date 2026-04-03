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

enum _ObjectKind {
  iceWall,
  iceSpire,
  turret,
  drone,
}

class _WorldObject {
  _WorldObject({
    required this.kind,
    required this.x,
    required this.z,
    required this.width,
    required this.height,
    required this.hp,
    this.active = true,
  });

  _ObjectKind kind;

  /// horizontal world offset. Negative = left, positive = right.
  double x;

  /// depth: 0 = horizon / far, 1 = near cockpit
  double z;

  /// relative width/height in projected world terms
  double width;
  double height;

  int hp;
  bool active;

  bool get isShootable => kind == _ObjectKind.turret || kind == _ObjectKind.drone;
  bool get isSolid => kind == _ObjectKind.iceWall || kind == _ObjectKind.iceSpire;
}

class _Shot {
  _Shot({
    required this.x,
    required this.z,
    required this.yBias,
    this.active = true,
  });

  double x;
  double z;
  double yBias;
  bool active;
}

class _Explosion {
  _Explosion({
    required this.x,
    required this.z,
    this.t = 0,
    this.active = true,
    this.large = false,
  });

  double x;
  double z;
  double t;
  bool active;
  bool large;
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

  int score = 0;
  int hull = 100;
  double distance = 0;

  // HACKABLE NOTE:
  // These values are the heart of the feel.
  static const double _missionDistance = 5200;
  static const double _baseSpeed = 210;
  static const double _maxDifficultyBonus = 0.28;

  // Player steering state.
  double playerX = 0.0;
  double targetPlayerX = 0.0;
  double playerY = 0.0;
  double targetPlayerY = 0.0;

  bool leftPressed = false;
  bool rightPressed = false;
  bool upPressed = false;
  bool downPressed = false;
  bool firePressed = false;

  double fireCooldown = 0.0;
  double spawnTimer = 0.0;
  double damageFlash = 0.0;

  final List<_WorldObject> objects = [];
  final List<_Shot> shots = [];
  final List<_Explosion> explosions = [];
  final List<_Star> stars = [];

  Size playSize = const Size(1000, 700);

  @override
  void initState() {
    super.initState();

    for (int i = 0; i < 70; i++) {
      stars.add(
        _Star(
          x: _rng.nextDouble(),
          y: _rng.nextDouble() * 0.56,
          speed: 0.25 + _rng.nextDouble() * 0.85,
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

  double get difficultyScale {
    final pct = (distance / _missionDistance).clamp(0.0, 1.0);
    return 1.0 + pct * _maxDifficultyBonus;
  }

  double get worldSpeed => _baseSpeed * difficultyScale;

  void _resetRun() {
    phase = _GamePhase.briefing;
    score = 0;
    hull = 100;
    distance = 0;
    fireCooldown = 0;
    spawnTimer = 0;
    damageFlash = 0;

    playerX = 0;
    targetPlayerX = 0;
    playerY = 0;
    targetPlayerY = 0;

    leftPressed = false;
    rightPressed = false;
    upPressed = false;
    downPressed = false;
    firePressed = false;

    objects.clear();
    shots.clear();
    explosions.clear();
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
    _updateExplosions(dt);

    if (damageFlash > 0) {
      damageFlash -= dt;
    }

    if (fireCooldown > 0) {
      fireCooldown -= dt;
    }

    if (phase != _GamePhase.playing) {
      setState(() {});
      return;
    }

    _handleInput(dt);
    _spawnPatterns(dt);
    _updateObjects(dt);
    _updateShots(dt);
    _handleCollisions();
    _cleanup();

    distance += worldSpeed * dt;

    if (hull <= 0) {
      hull = 0;
      phase = _GamePhase.gameOver;
    } else if (distance >= _missionDistance) {
      phase = _GamePhase.victory;
      score += 1500;
    }

    setState(() {});
  }

  void _updateStars(double dt) {
    final drift = 0.06 + difficultyScale * 0.015;
    for (final s in stars) {
      s.y += s.speed * drift * dt * 10;
      if (s.y > 0.58) {
        s.y = 0;
        s.x = _rng.nextDouble();
      }
    }
  }

  void _updateExplosions(double dt) {
    for (final e in explosions) {
      e.t += dt * 1.9;
      if (e.t >= 1.0) {
        e.active = false;
      }
    }
    explosions.removeWhere((e) => !e.active);
  }

  void _handleInput(double dt) {
    // HACKABLE NOTE:
    // The goal is slightly weighty but still responsive, not slippery.
    const lateralSpeed = 1.75;
    const verticalSpeed = 0.95;
    const followSpeed = 8.8;

    if (leftPressed) targetPlayerX -= lateralSpeed * dt;
    if (rightPressed) targetPlayerX += lateralSpeed * dt;
    if (upPressed) targetPlayerY -= verticalSpeed * dt;
    if (downPressed) targetPlayerY += verticalSpeed * dt;

    targetPlayerX = targetPlayerX.clamp(-0.92, 0.92);
    targetPlayerY = targetPlayerY.clamp(-0.22, 0.22);

    final follow = min(1.0, dt * followSpeed);
    playerX = lerpDouble(playerX, targetPlayerX, follow)!;
    playerY = lerpDouble(playerY, targetPlayerY, follow)!;

    if (firePressed) {
      _fire();
    }
  }

  void _spawnPatterns(double dt) {
    spawnTimer += dt;

    // HACKABLE NOTE:
    // Pattern pacing. Lower = denser attack run.
    final delay = max(0.34, 1.05 / difficultyScale);
    if (spawnTimer < delay) return;
    spawnTimer = 0;

    final roll = _rng.nextDouble();

    // Weighted pattern mix:
    // single turret / drone
    if (roll < 0.20) {
      _spawnDroneBurst();
      return;
    }

    // single obstacle
    if (roll < 0.45) {
      _spawnSingleIceObstacle();
      return;
    }

    // readable gate
    if (roll < 0.82) {
      _spawnGatePattern();
      return;
    }

    // mixed gate with target
    _spawnGateWithTarget();
  }

  void _spawnDroneBurst() {
    final center = (_rng.nextDouble() * 1.4) - 0.7;
    final offsets = [-0.18, 0.0, 0.18];

    for (final offset in offsets) {
      final x = (center + offset).clamp(-0.88, 0.88);
      objects.add(
        _WorldObject(
          kind: _ObjectKind.drone,
          x: x,
          z: 0.10 + _rng.nextDouble() * 0.03,
          width: 0.10,
          height: 0.09,
          hp: 2,
        ),
      );
    }
  }

  void _spawnSingleIceObstacle() {
    final avoidPlayer = playerX;
    double x = ((_rng.nextDouble() * 2.0) - 1.0) * 0.82;

    if ((x - avoidPlayer).abs() < 0.22) {
      x += x < 0 ? -0.22 : 0.22;
    }
    x = x.clamp(-0.88, 0.88);

    final kind = _rng.nextBool() ? _ObjectKind.iceSpire : _ObjectKind.iceWall;

    objects.add(
      _WorldObject(
        kind: kind,
        x: x,
        z: 0.05,
        width: kind == _ObjectKind.iceWall ? 0.16 : 0.11,
        height: kind == _ObjectKind.iceWall ? 0.18 : 0.25,
        hp: 999,
      ),
    );
  }

  void _spawnGatePattern() {
    // HACKABLE NOTE:
    // Keep one broad clear side. This should feel fair and readable.
    final openLeft = _rng.nextBool();

    if (openLeft) {
      objects.addAll([
        _WorldObject(
          kind: _ObjectKind.iceWall,
          x: 0.18,
          z: 0.05,
          width: 0.20,
          height: 0.18,
          hp: 999,
        ),
        _WorldObject(
          kind: _ObjectKind.iceSpire,
          x: 0.58,
          z: 0.05,
          width: 0.12,
          height: 0.25,
          hp: 999,
        ),
      ]);
    } else {
      objects.addAll([
        _WorldObject(
          kind: _ObjectKind.iceWall,
          x: -0.18,
          z: 0.05,
          width: 0.20,
          height: 0.18,
          hp: 999,
        ),
        _WorldObject(
          kind: _ObjectKind.iceSpire,
          x: -0.58,
          z: 0.05,
          width: 0.12,
          height: 0.25,
          hp: 999,
        ),
      ]);
    }
  }

  void _spawnGateWithTarget() {
    final openLeft = _rng.nextBool();

    if (openLeft) {
      objects.addAll([
        _WorldObject(
          kind: _ObjectKind.iceWall,
          x: 0.24,
          z: 0.05,
          width: 0.20,
          height: 0.18,
          hp: 999,
        ),
        _WorldObject(
          kind: _ObjectKind.iceSpire,
          x: 0.62,
          z: 0.05,
          width: 0.12,
          height: 0.25,
          hp: 999,
        ),
        _WorldObject(
          kind: _ObjectKind.turret,
          x: -0.22,
          z: 0.11,
          width: 0.09,
          height: 0.17,
          hp: 2,
        ),
      ]);
    } else {
      objects.addAll([
        _WorldObject(
          kind: _ObjectKind.iceWall,
          x: -0.24,
          z: 0.05,
          width: 0.20,
          height: 0.18,
          hp: 999,
        ),
        _WorldObject(
          kind: _ObjectKind.iceSpire,
          x: -0.62,
          z: 0.05,
          width: 0.12,
          height: 0.25,
          hp: 999,
        ),
        _WorldObject(
          kind: _ObjectKind.turret,
          x: 0.22,
          z: 0.11,
          width: 0.09,
          height: 0.17,
          hp: 2,
        ),
      ]);
    }
  }

  void _updateObjects(double dt) {
    final advance = dt * (0.30 + worldSpeed / 860.0);

    for (final o in objects) {
      o.z += advance * (o.kind == _ObjectKind.drone ? 1.12 : 1.0);
    }
  }

  void _updateShots(double dt) {
    for (final s in shots) {
      s.z -= dt * 1.75;
      if (s.z < 0) {
        s.active = false;
      }
    }
  }

  void _handleCollisions() {
    for (final o in objects) {
      if (!o.active) continue;

      // HACKABLE NOTE:
      // Bigger contact envelope for the ship. This is intentionally forgiving
      // visually but slightly larger physically, per your feedback.
      if (o.z > 0.89) {
        final hitWidth = o.kind == _ObjectKind.iceWall
            ? o.width * 1.12
            : o.width * 1.04;

        final xHit = (o.x - playerX).abs() < hitWidth;

        if (xHit) {
          o.active = false;
          hull -= o.isShootable ? 15 : 24;
          damageFlash = 0.15;
          explosions.add(
            _Explosion(
              x: o.x,
              z: 0.88,
              large: o.kind != _ObjectKind.drone,
            ),
          );
        }
      }

      for (final s in shots) {
        if (!s.active || !o.active) continue;
        if (!o.isShootable) continue;

        // HACKABLE NOTE:
        // More generous than before.
        final zHit = (s.z - o.z).abs() < 0.085;
        final xHit = (s.x - o.x).abs() < (o.width * 1.10);
        final yHit = s.yBias.abs() < 0.30 || o.kind != _ObjectKind.drone;

        if (zHit && xHit && yHit) {
          s.active = false;
          o.hp -= 1;

          if (o.hp <= 0) {
            o.active = false;
            score += switch (o.kind) {
              _ObjectKind.drone => 170,
              _ObjectKind.turret => 95,
              _ => 50,
            };
            explosions.add(
              _Explosion(
                x: o.x,
                z: o.z,
                large: o.kind == _ObjectKind.turret,
              ),
            );
          }
        }
      }

      if (o.active && o.z > 1.08) {
        o.active = false;
      }
    }
  }

  void _cleanup() {
    objects.removeWhere((o) => !o.active);
    shots.removeWhere((s) => !s.active);
  }

  void _fire() {
    if (phase != _GamePhase.playing) return;
    if (fireCooldown > 0) return;
    if (shots.length > 7) return;

    shots.add(
      _Shot(
        x: playerX,
        z: 0.92,
        yBias: playerY,
      ),
    );

    fireCooldown = 0.15;
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

    setState(() {
      targetPlayerX = (targetPlayerX + dx * 2.8).clamp(-0.92, 0.92);
      targetPlayerY = (targetPlayerY + dy * 2.0).clamp(-0.22, 0.22);
    });
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

    if (key == LogicalKeyboardKey.space) {
      if (isDown) {
        firePressed = true;
        _fire();
      }
      if (isUp) {
        firePressed = false;
      }
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
        case _GamePhase.missionComplete:
          break;
      }
      return KeyEventResult.handled;
    }

    if (isDown && key == LogicalKeyboardKey.keyR) {
      if (phase == _GamePhase.gameOver || phase == _GamePhase.victory) {
        _restartRun();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String _overlayTitle() {
    switch (phase) {
      case _GamePhase.briefing:
        return 'MISSION 1: ICE RUN';
      case _GamePhase.paused:
        return 'PAUSED';
      case _GamePhase.victory:
        return 'MISSION COMPLETE';
      case _GamePhase.gameOver:
        return 'GAME OVER';
      case _GamePhase.playing:
        return '';
    }
  }

  String _overlaySubtitle() {
    switch (phase) {
      case _GamePhase.briefing:
        return 'Break the defense line.\nDodge ice formations. Destroy turrets and drones.';
      case _GamePhase.paused:
        return 'Take a breath and resume when ready.';
      case _GamePhase.victory:
        return 'Ice Run cleared.\nFinal score: $score';
      case _GamePhase.gameOver:
        return 'Your snow run ended in wreckage.\nFinal score: $score';
      case _GamePhase.playing:
        return '';
    }
  }

  String _overlayButtonText() {
    switch (phase) {
      case _GamePhase.briefing:
        return 'Launch Run';
      case _GamePhase.paused:
        return 'Resume';
      case _GamePhase.victory:
      case _GamePhase.gameOver:
        return 'Restart Run';
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
                      painter: _MissionOnePainter(
                        playerX: playerX,
                        playerY: playerY,
                        objects: objects,
                        shots: shots,
                        stars: stars,
                        explosions: explosions,
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
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      const Expanded(
                                        child: Text(
                                          'Mission 1: Ice Run',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ),
                                      Text('Score $score'),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Text('Hull'),
                                      const SizedBox(width: 8),
                                      Expanded(
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
                                            value: (distance / _missionDistance).clamp(0.0, 1.0),
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
                                        ? 'Touch: drag to steer • hold FIRE'
                                        : 'Move: WASD / Arrows • Hold Space to fire • P pause • R restart after end',
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

                  if (isCompact && phase == _GamePhase.playing)
                    Positioned(
                      right: 20,
                      bottom: 20,
                      child: SafeArea(
                        child: Listener(
                          onPointerDown: (_) {
                            setState(() => firePressed = true);
                            _fire();
                          },
                          onPointerUp: (_) {
                            setState(() => firePressed = false);
                          },
                          onPointerCancel: (_) {
                            setState(() => firePressed = false);
                          },
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: firePressed
                                  ? const Color(0x66FFC857)
                                  : const Color(0x33FFC857),
                              border: Border.all(
                                color: const Color(0xAAFFC857),
                                width: 2,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'FIRE',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
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

class _MissionOnePainter extends CustomPainter {
  _MissionOnePainter({
    required this.playerX,
    required this.playerY,
    required this.objects,
    required this.shots,
    required this.stars,
    required this.explosions,
    required this.accent,
  });

  final double playerX;
  final double playerY;
  final List<_WorldObject> objects;
  final List<_Shot> shots;
  final List<_Star> stars;
  final List<_Explosion> explosions;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    _paintStars(canvas, size);
    _paintGround(canvas, size);
    _paintMountains(canvas, size);
    _paintTrackLines(canvas, size);

    final sorted = [...objects]..sort((a, b) => a.z.compareTo(b.z));
    for (final o in sorted) {
      _paintObject(canvas, size, o);
    }

    for (final s in shots) {
      _paintShot(canvas, size, s);
    }

    for (final e in explosions) {
      _paintExplosion(canvas, size, e);
    }

    _paintReticle(canvas, size);
    _paintShipGuide(canvas, size);
    _paintCockpit(canvas, size);
  }

  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0E1A33),
          Color(0xFF79B7E6),
        ],
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
    final groundRect = Rect.fromLTWH(0, horizonY, size.width, size.height - horizonY);

    final p = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF9CC6E3),
          Color(0xFFDFF5FF),
        ],
      ).createShader(groundRect);

    canvas.drawRect(groundRect, p);
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
      final y = lerpDouble(horizonY + 18, size.height - 28, pow(t, 1.45).toDouble())!;
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

  void _paintObject(Canvas canvas, Size size, _WorldObject o) {
    final pos = _project(size, o.x, o.z, playerX, playerY);
    final scale = _scaleForZ(o.z);
    final w = size.width * o.width * scale;
    final h = size.height * o.height * scale;

    switch (o.kind) {
      case _ObjectKind.iceWall:
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

      case _ObjectKind.iceSpire:
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

      case _ObjectKind.turret:
        final base = Rect.fromCenter(
          center: Offset(pos.dx, pos.dy - h * 0.34),
          width: w * 0.72,
          height: h * 0.54,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(base, const Radius.circular(5)),
          Paint()..color = const Color(0xFFDFE8EF),
        );

        final barrel = Path()
          ..moveTo(pos.dx + w * 0.04, pos.dy - h * 0.60)
          ..lineTo(pos.dx + w * 0.60, pos.dy - h * 0.80)
          ..lineTo(pos.dx + w * 0.54, pos.dy - h * 0.92)
          ..lineTo(pos.dx - w * 0.02, pos.dy - h * 0.70)
          ..close();
        canvas.drawPath(barrel, Paint()..color = const Color(0xFFE16A6A));

        final cap = Rect.fromCenter(
          center: Offset(pos.dx, pos.dy - h * 0.16),
          width: w * 0.24,
          height: h * 0.10,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(cap, const Radius.circular(4)),
          Paint()..color = const Color(0xFFE16A6A),
        );
        break;

      case _ObjectKind.drone:
        final bodyPaint = Paint()..color = const Color(0xFFE16A6A);
        final wingPaint = Paint()..color = const Color(0xFFB84D4D);
        final glass = Paint()..color = const Color(0xFFA7EEFF);

        final body = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(pos.dx, pos.dy - h * 0.42),
            width: w * 0.42,
            height: h * 0.34,
          ),
          const Radius.circular(8),
        );
        canvas.drawRRect(body, bodyPaint);

        final leftWing = Path()
          ..moveTo(pos.dx - w * 0.15, pos.dy - h * 0.42)
          ..lineTo(pos.dx - w * 0.90, pos.dy - h * 0.18)
          ..lineTo(pos.dx - w * 0.32, pos.dy - h * 0.04)
          ..close();
        final rightWing = Path()
          ..moveTo(pos.dx + w * 0.15, pos.dy - h * 0.42)
          ..lineTo(pos.dx + w * 0.90, pos.dy - h * 0.18)
          ..lineTo(pos.dx + w * 0.32, pos.dy - h * 0.04)
          ..close();

        canvas.drawPath(leftWing, wingPaint);
        canvas.drawPath(rightWing, wingPaint);

        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(pos.dx, pos.dy - h * 0.46),
            width: w * 0.14,
            height: h * 0.12,
          ),
          glass,
        );
        break;

      case _ObjectKind.tree:
      case _ObjectKind.rock:
        break;
    }
  }

  void _paintShot(Canvas canvas, Size size, _Shot s) {
    final pos = _project(size, s.x, s.z, playerX, playerY);
    final scale = _scaleForShotZ(s.z);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: pos,
          width: size.width * 0.006 * scale + 3,
          height: size.height * 0.024 * scale + 5,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = accent,
    );
  }

  void _paintExplosion(Canvas canvas, Size size, _Explosion e) {
    final pos = _project(size, e.x, e.z, playerX, playerY);
    final baseRadius = e.large ? 14.0 : 8.0;
    final growth = e.large ? 50.0 : 36.0;
    final r = baseRadius + e.t * growth;
    final a = (1.0 - e.t).clamp(0.0, 1.0);

    canvas.drawCircle(
      pos,
      r,
      Paint()..color = Colors.orange.withOpacity(a * 0.45),
    );
    canvas.drawCircle(
      pos,
      r * 0.55,
      Paint()..color = Colors.yellow.withOpacity(a * 0.82),
    );
  }

  void _paintReticle(Canvas canvas, Size size) {
    final center = Offset(
      size.width * (0.5 + playerX * 0.13),
      size.height * (0.56 + playerY * 0.10),
    );

    final p = Paint()
      ..color = accent.withOpacity(0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, 18, p);
    canvas.drawLine(Offset(center.dx - 28, center.dy), Offset(center.dx - 8, center.dy), p);
    canvas.drawLine(Offset(center.dx + 8, center.dy), Offset(center.dx + 28, center.dy), p);
    canvas.drawLine(Offset(center.dx, center.dy - 28), Offset(center.dx, center.dy - 8), p);
    canvas.drawLine(Offset(center.dx, center.dy + 8), Offset(center.dx, center.dy + 28), p);
  }

  void _paintShipGuide(Canvas canvas, Size size) {
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
      Rect.fromLTWH(0, 0, 32, size.height),
      sidePaint,
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width - 32, 0, 32, size.height),
      sidePaint,
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
    final scale = _scaleForZ(z);

    final screenX = size.width * (0.5 + (x - playerX * 0.52) * 0.28 * scale);
    final screenY = lerpDouble(horizonY, bottomY, scale)!;

    return Offset(screenX, screenY);
  }

  double _scaleForZ(double z) => z.clamp(0.06, 1.0);

  double _scaleForShotZ(double z) => z.clamp(0.06, 1.0);

  @override
  bool shouldRepaint(covariant _MissionOnePainter oldDelegate) => true;
}
