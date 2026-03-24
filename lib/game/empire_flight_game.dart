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
  missionComplete,
  gameOver,
  victory,
}

enum _ObjectKind {
  tower,
  tree,
  rock,
  drone,
  battery,
}

class _MissionData {
  final String name;
  final String subtitle;
  final Color skyTop;
  final Color skyBottom;
  final Color groundNear;
  final Color groundFar;
  final Color accent;
  final int goalDistance;
  final double baseSpeed;
  final double spawnRate;
  final double droneChance;

  const _MissionData({
    required this.name,
    required this.subtitle,
    required this.skyTop,
    required this.skyBottom,
    required this.groundNear,
    required this.groundFar,
    required this.accent,
    required this.goalDistance,
    required this.baseSpeed,
    required this.spawnRate,
    required this.droneChance,
  });
}

class _WorldObject {
  _ObjectKind kind;
  double laneX;

  /// 0.0 = horizon / far away
  /// 1.0 = near player / foreground
  double z;

  double width;
  double height;
  bool active;
  int hp;

  _WorldObject({
    required this.kind,
    required this.laneX,
    required this.z,
    required this.width,
    required this.height,
    required this.hp,
    this.active = true,
  });
}

class _Shot {
  double laneX;
  double aimY;

  /// starts near player and travels toward horizon
  double z;
  bool active;

  _Shot({
    required this.laneX,
    required this.aimY,
    required this.z,
    this.active = true,
  });
}

class _Star {
  double x;
  double y;
  double speed;

  _Star({
    required this.x,
    required this.y,
    required this.speed,
  });
}

class _Explosion {
  double laneX;
  double y;
  double t;
  bool active;

  _Explosion({
    required this.laneX,
    required this.y,
    this.t = 0,
    this.active = true,
  });
}

class _EmpireFlightGameState extends State<EmpireFlightGame> {
  final Random rng = Random();
  final FocusNode _keyboardFocus = FocusNode();

  late final List<_MissionData> missions;

  Timer? _loop;
  DateTime? _lastTick;

  _GamePhase phase = _GamePhase.briefing;
  int missionIndex = 0;
  int score = 0;
  int hull = 100;
  double distance = 0;
  double spawnTimer = 0;
  double fireCooldown = 0;
  double damageFlash = 0;

  // HACKABLE NOTE:
  // targetPlayerX/Y are what the controls want.
  // playerX/Y ease toward them for better arcade flight feel.
  double playerX = 0;
  double playerY = 0;
  double targetPlayerX = 0;
  double targetPlayerY = 0;

  bool leftPressed = false;
  bool rightPressed = false;
  bool upPressed = false;
  bool downPressed = false;
  bool firePressed = false;

  final List<_WorldObject> objects = [];
  final List<_Shot> shots = [];
  final List<_Star> stars = [];
  final List<_Explosion> explosions = [];

  Size playSize = const Size(1000, 700);

  @override
  void initState() {
    super.initState();

    missions = const [
      _MissionData(
        name: 'Mission 1: Ice Run',
        subtitle: 'Skim the frozen world and destroy the defense line.',
        skyTop: Color(0xFF0E1A33),
        skyBottom: Color(0xFF79B7E6),
        groundNear: Color(0xFFDFF5FF),
        groundFar: Color(0xFF9CC6E3),
        accent: Color(0xFFD9F3FF),
        goalDistance: 5400,
        baseSpeed: 210,
        spawnRate: 0.95,
        droneChance: 0.28,
      ),
      _MissionData(
        name: 'Mission 2: Forest Run',
        subtitle: 'Thread the giant trunks and break through patrol craft.',
        skyTop: Color(0xFF112015),
        skyBottom: Color(0xFF4D7857),
        groundNear: Color(0xFF243E27),
        groundFar: Color(0xFF1A2E1D),
        accent: Color(0xFFB6F5A0),
        goalDistance: 6400,
        baseSpeed: 225,
        spawnRate: 0.86,
        droneChance: 0.34,
      ),
      _MissionData(
        name: 'Mission 3: Desert Run',
        subtitle: 'Push through rock spires, guns, and attack drones.',
        skyTop: Color(0xFF3A1C12),
        skyBottom: Color(0xFFE0A05D),
        groundNear: Color(0xFFC98B4A),
        groundFar: Color(0xFF966235),
        accent: Color(0xFFFFD27A),
        goalDistance: 7600,
        baseSpeed: 240,
        spawnRate: 0.78,
        droneChance: 0.38,
      ),
    ];

    for (int i = 0; i < 65; i++) {
      stars.add(
        _Star(
          x: rng.nextDouble(),
          y: rng.nextDouble() * 0.55,
          speed: 0.2 + rng.nextDouble() * 0.8,
        ),
      );
    }

    _resetMission(fullReset: true);
    _startLoop();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _loop?.cancel();
    _keyboardFocus.dispose();
    super.dispose();
  }

  _MissionData get mission => missions[missionIndex];

  double get difficultyScale {
    final pct = distance / mission.goalDistance;
    return 1.0 + pct.clamp(0.0, 1.0) * 0.45;
  }

  double get worldSpeed => mission.baseSpeed * difficultyScale;

  double get reticleX => playerX;
  double get reticleY => playerY;

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

  void _resetMission({bool fullReset = false}) {
    if (fullReset) {
      missionIndex = 0;
      score = 0;
      phase = _GamePhase.briefing;
      hull = 100;
    } else {
      hull = min(100, hull + 20);
      phase = _GamePhase.briefing;
    }

    distance = 0;
    spawnTimer = 0;
    fireCooldown = 0;
    damageFlash = 0;

    playerX = 0;
    playerY = 0;
    targetPlayerX = 0;
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

  void _update(double dt) {
    if (!mounted) return;

    _updateStars(dt);

    if (damageFlash > 0) {
      damageFlash -= dt;
    }

    if (fireCooldown > 0) {
      fireCooldown -= dt;
    }

    for (final e in explosions) {
      e.t += dt * 1.8;
      if (e.t >= 1.0) {
        e.active = false;
      }
    }
    explosions.removeWhere((e) => !e.active);

    if (phase != _GamePhase.playing) {
      setState(() {});
      return;
    }

    _handleInput(dt);
    _spawnWorld(dt);
    _updateObjects(dt);
    _updateShots(dt);
    _handleCollisions();
    _cleanupObjects();

    distance += worldSpeed * dt;

    if (distance >= mission.goalDistance) {
      score += 1400 + missionIndex * 600;
      if (missionIndex >= missions.length - 1) {
        phase = _GamePhase.victory;
      } else {
        phase = _GamePhase.missionComplete;
      }
    }

    if (hull <= 0) {
      hull = 0;
      phase = _GamePhase.gameOver;
    }

    setState(() {});
  }

  void _updateStars(double dt) {
    final speed = 0.06 + difficultyScale * 0.015;
    for (final s in stars) {
      s.y += s.speed * speed * dt * 10;
      if (s.y > 0.58) {
        s.y = 0.0;
        s.x = rng.nextDouble();
      }
    }
  }

  void _handleInput(double dt) {
    const lateralSpeed = 1.7;
    const verticalSpeed = 0.95;

    if (leftPressed) targetPlayerX -= lateralSpeed * dt;
    if (rightPressed) targetPlayerX += lateralSpeed * dt;
    if (upPressed) targetPlayerY -= verticalSpeed * dt;
    if (downPressed) targetPlayerY += verticalSpeed * dt;

    // HACKABLE NOTE:
    // Narrower corridor = more attack-run feel.
    targetPlayerX = targetPlayerX.clamp(-0.95, 0.95);
    targetPlayerY = targetPlayerY.clamp(-0.26, 0.26);

    // Smooth follow so the ship feels like it has a little weight.
    final follow = min(1.0, dt * 8.5);
    playerX = lerpDouble(playerX, targetPlayerX, follow)!;
    playerY = lerpDouble(playerY, targetPlayerY, follow)!;

    if (firePressed) {
      _fire();
    }
  }

  void _spawnWorld(double dt) {
    spawnTimer += dt;

    final delay = max(0.26, mission.spawnRate / difficultyScale);
    if (spawnTimer < delay) return;
    spawnTimer = 0;

    final spawnDrone = rng.nextDouble() < mission.droneChance;
    final lane = [-0.9, -0.6, -0.3, 0.0, 0.3, 0.6, 0.9][rng.nextInt(7)];

    if (spawnDrone) {
      objects.add(
        _WorldObject(
          kind: _ObjectKind.drone,
          laneX: lane,
          z: 0.06,
          width: 0.10,
          height: 0.09,
          hp: 2,
        ),
      );
      return;
    }

    switch (missionIndex) {
      case 0:
        objects.add(
          _WorldObject(
            kind: rng.nextBool() ? _ObjectKind.tower : _ObjectKind.battery,
            laneX: lane,
            z: 0.05,
            width: 0.09,
            height: 0.19,
            hp: 1,
          ),
        );
        break;
      case 1:
        objects.add(
          _WorldObject(
            kind: _ObjectKind.tree,
            laneX: lane,
            z: 0.05,
            width: 0.11,
            height: 0.25,
            hp: 1,
          ),
        );
        break;
      case 2:
        objects.add(
          _WorldObject(
            kind: rng.nextBool() ? _ObjectKind.rock : _ObjectKind.battery,
            laneX: lane,
            z: 0.05,
            width: 0.11,
            height: 0.21,
            hp: 1,
          ),
        );
        break;
    }
  }

  void _updateObjects(double dt) {
    final advance = dt * (0.30 + worldSpeed / 850.0);

    for (final o in objects) {
      o.z += advance * (o.kind == _ObjectKind.drone ? 1.10 : 1.0);
    }
  }

  void _updateShots(double dt) {
    for (final s in shots) {
      s.z -= dt * 1.9;
      if (s.z < 0.0) {
        s.active = false;
      }
    }
  }

  void _handleCollisions() {
    for (final o in objects) {
      if (!o.active) continue;

      // HACKABLE NOTE:
      // This is the player collision width.
      // Lower value = tighter / fairer dodging.
      if (o.z > 0.90) {
        final xHit = (o.laneX - playerX).abs() < (o.width * 0.92);
        if (xHit) {
          o.active = false;
          hull -= (o.kind == _ObjectKind.drone) ? 15 : 22;
          damageFlash = 0.15;
          explosions.add(
            _Explosion(
              laneX: o.laneX,
              y: 0.78 + playerY * 0.06,
            ),
          );
        }
      }

      for (final s in shots) {
        if (!s.active || !o.active) continue;

        final zHit = (s.z - o.z).abs() < 0.06;

        // HACKABLE NOTE:
        // This is the shot hit width.
        // Lower value = more precise aiming.
        final xHit = (s.laneX - o.laneX).abs() < (o.width * 0.78);

        final yBias = (s.aimY.abs() < 0.24) || o.kind != _ObjectKind.drone;

        if (zHit && xHit && yBias) {
          s.active = false;
          o.hp -= 1;
          if (o.hp <= 0) {
            o.active = false;
            score += (o.kind == _ObjectKind.drone) ? 160 : 55;
            explosions.add(
              _Explosion(
                laneX: o.laneX,
                y: 0.58,
              ),
            );
          }
        }
      }

      if (o.active && o.z > 1.08) {
        o.active = false;
        score += 4;
      }
    }
  }

  void _cleanupObjects() {
    objects.removeWhere((o) => !o.active);
    shots.removeWhere((s) => !s.active);
  }

  void _fire() {
    // HACKABLE NOTE:
    // Lower cooldown = faster fire rate.
    if (phase != _GamePhase.playing) return;
    if (fireCooldown > 0) return;
    if (shots.length > 12) return;

    shots.add(
      _Shot(
        laneX: reticleX,
        aimY: reticleY,
        z: 0.92,
      ),
    );

    shots.add(
      _Shot(
        laneX: (reticleX - 0.025).clamp(-1.0, 1.0),
        aimY: reticleY,
        z: 0.90,
      ),
    );

    shots.add(
      _Shot(
        laneX: (reticleX + 0.025).clamp(-1.0, 1.0),
        aimY: reticleY,
        z: 0.90,
      ),
    );

    fireCooldown = 0.09;
  }

  void _startMission() {
    phase = _GamePhase.playing;
    _keyboardFocus.requestFocus();
  }

  void _nextMission() {
    missionIndex += 1;
    _resetMission(fullReset: false);
    _keyboardFocus.requestFocus();
  }

  void _restartCampaign() {
    _resetMission(fullReset: true);
    _keyboardFocus.requestFocus();
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

    if (isDown && key == LogicalKeyboardKey.enter) {
      _handlePrimaryAction();
      return KeyEventResult.handled;
    }

    if (isDown && key == LogicalKeyboardKey.keyR) {
      if (phase == _GamePhase.gameOver || phase == _GamePhase.victory) {
        _restartCampaign();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _handlePrimaryAction() {
    switch (phase) {
      case _GamePhase.briefing:
        _startMission();
        break;
      case _GamePhase.missionComplete:
        _nextMission();
        break;
      case _GamePhase.gameOver:
      case _GamePhase.victory:
        _restartCampaign();
        break;
      case _GamePhase.playing:
        break;
    }
  }

  void _handleDrag(DragUpdateDetails details) {
    final dx = details.delta.dx / max(1, playSize.width);
    final dy = details.delta.dy / max(1, playSize.height);

    setState(() {
      targetPlayerX = (targetPlayerX + dx * 2.6).clamp(-0.95, 0.95);
      targetPlayerY = (targetPlayerY + dy * 2.0).clamp(-0.26, 0.26);
    });
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
                if (phase != _GamePhase.playing) {
                  _handlePrimaryAction();
                } else {
                  _keyboardFocus.requestFocus();
                }
              },
              onPanUpdate: phase == _GamePhase.playing ? _handleDrag : null,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ForwardRunPainter(
                        mission: mission,
                        playerX: playerX,
                        playerY: playerY,
                        objects: objects,
                        shots: shots,
                        stars: stars,
                        explosions: explosions,
                        accent: mission.accent,
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
                                Expanded(
                                  child: Text(
                                    mission.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                Text('Score $score'),
                                const SizedBox(width: 12),
                                Text('Mission ${missionIndex + 1}/${missions.length}'),
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
                                      value: (distance / mission.goalDistance).clamp(0.0, 1.0),
                                      minHeight: 10,
                                      backgroundColor: const Color(0x33222222),
                                      valueColor: const AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('${distance.floor()}/${mission.goalDistance}m'),
                              ],
                            ),
                          ],
                        ),
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
                                    onPressed: _handlePrimaryAction,
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
                                        : 'Move: WASD / Arrows • Hold Space to fire • Enter to continue • R to restart',
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

  String _overlayTitle() {
    switch (phase) {
      case _GamePhase.briefing:
        return mission.name;
      case _GamePhase.missionComplete:
        return 'MISSION COMPLETE';
      case _GamePhase.gameOver:
        return 'GAME OVER';
      case _GamePhase.victory:
        return 'VICTORY';
      case _GamePhase.playing:
        return '';
    }
  }

  String _overlaySubtitle() {
    switch (phase) {
      case _GamePhase.briefing:
        return mission.subtitle;
      case _GamePhase.missionComplete:
        return 'Prepare for the next run.\nScore: $score';
      case _GamePhase.gameOver:
        return 'Your ship was destroyed.\nFinal score: $score';
      case _GamePhase.victory:
        return 'All three worlds cleared.\nFinal score: $score';
      case _GamePhase.playing:
        return '';
    }
  }

  String _overlayButtonText() {
    switch (phase) {
      case _GamePhase.briefing:
        return 'Launch Mission';
      case _GamePhase.missionComplete:
        return 'Next Mission';
      case _GamePhase.gameOver:
        return 'Retry Campaign';
      case _GamePhase.victory:
        return 'Play Again';
      case _GamePhase.playing:
        return '';
    }
  }
}

class _ForwardRunPainter extends CustomPainter {
  final _MissionData mission;
  final double playerX;
  final double playerY;
  final List<_WorldObject> objects;
  final List<_Shot> shots;
  final List<_Star> stars;
  final List<_Explosion> explosions;
  final Color accent;

  _ForwardRunPainter({
    required this.mission,
    required this.playerX,
    required this.playerY,
    required this.objects,
    required this.shots,
    required this.stars,
    required this.explosions,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintSky(canvas, size);
    _paintStars(canvas, size);
    _paintGround(canvas, size);
    _paintHorizonBand(canvas, size);
    _paintDistantScenery(canvas, size);

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
    _paintCockpit(canvas, size);
  }

  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [mission.skyTop, mission.skyBottom],
      ).createShader(rect);
    canvas.drawRect(rect, p);
  }

  void _paintStars(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.7);
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

    final path = Path()
      ..moveTo(0, horizonY)
      ..lineTo(size.width, horizonY)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final p = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [mission.groundFar, mission.groundNear],
      ).createShader(Rect.fromLTWH(0, horizonY, size.width, size.height - horizonY));

    canvas.drawPath(path, p);

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 2;

    final centerX = size.width / 2 + playerX * size.width * 0.07;

    canvas.drawLine(
      Offset(centerX - size.width * 0.28, size.height),
      Offset(centerX - size.width * 0.08, horizonY),
      gridPaint,
    );
    canvas.drawLine(
      Offset(centerX + size.width * 0.28, size.height),
      Offset(centerX + size.width * 0.08, horizonY),
      gridPaint,
    );

    for (int i = 0; i < 8; i++) {
      final t = i / 7;
      final y = lerpDouble(horizonY + 16, size.height - 28, pow(t, 1.45).toDouble())!;
      final halfW = lerpDouble(size.width * 0.03, size.width * 0.24, t)!;
      canvas.drawLine(
        Offset(centerX - halfW, y),
        Offset(centerX + halfW, y),
        gridPaint,
      );
    }
  }

  void _paintHorizonBand(Canvas canvas, Size size) {
    final y = size.height * 0.42;
    canvas.drawRect(
      Rect.fromLTWH(0, y - 2, size.width, 4),
      Paint()..color = Colors.white.withOpacity(0.10),
    );
  }

  void _paintDistantScenery(Canvas canvas, Size size) {
    final horizonY = size.height * 0.42;

    switch (mission.name) {
      case 'Mission 1: Ice Run':
        final path = Path()..moveTo(0, horizonY);
        final peaks = [
          Offset(size.width * 0.06, horizonY - 38),
          Offset(size.width * 0.16, horizonY - 8),
          Offset(size.width * 0.28, horizonY - 52),
          Offset(size.width * 0.46, horizonY - 12),
          Offset(size.width * 0.62, horizonY - 48),
          Offset(size.width * 0.80, horizonY - 15),
          Offset(size.width, horizonY - 38),
        ];
        for (final p in peaks) {
          path.lineTo(p.dx, p.dy);
        }
        path.lineTo(size.width, horizonY);
        path.close();
        canvas.drawPath(path, Paint()..color = const Color(0x66E2F4FF));
        break;

      case 'Mission 2: Forest Run':
        final p = Paint()..color = const Color(0x66273929);
        for (int i = 0; i < 18; i++) {
          final x = i / 17 * size.width;
          final h = 24 + (i % 5) * 12.0;
          final tri = Path()
            ..moveTo(x - 12, horizonY)
            ..lineTo(x, horizonY - h)
            ..lineTo(x + 12, horizonY)
            ..close();
          canvas.drawPath(tri, p);
        }
        break;

      case 'Mission 3: Desert Run':
        final path = Path()..moveTo(0, horizonY);
        for (int i = 0; i <= 8; i++) {
          final x = i / 8 * size.width;
          final y = horizonY - (sin(i * 0.9) * 10 + 8);
          path.lineTo(x, y);
        }
        path.lineTo(size.width, horizonY);
        path.close();
        canvas.drawPath(path, Paint()..color = const Color(0x55FFD089));
        break;
    }
  }

  void _paintObject(Canvas canvas, Size size, _WorldObject o) {
    final pos = _project(size, o.laneX, o.z, playerX, playerY);
    final scale = _scaleForZ(o.z);
    final w = size.width * o.width * scale;
    final h = size.height * o.height * scale;

    switch (o.kind) {
      case _ObjectKind.tower:
        final rect = Rect.fromCenter(
          center: Offset(pos.dx, pos.dy - h * 0.5),
          width: w,
          height: h,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = const Color(0xFFE6F7FF),
        );
        canvas.drawRect(
          Rect.fromLTWH(rect.left + w * 0.18, rect.top + h * 0.08, w * 0.16, h * 0.82),
          Paint()..color = Colors.white.withOpacity(0.22),
        );
        break;

      case _ObjectKind.tree:
        final trunk = Rect.fromCenter(
          center: Offset(pos.dx, pos.dy - h * 0.30),
          width: w * 0.22,
          height: h * 0.58,
        );
        canvas.drawRect(trunk, Paint()..color = const Color(0xFF654321));
        final crown = Path()
          ..moveTo(pos.dx, pos.dy - h)
          ..lineTo(pos.dx - w * 0.72, pos.dy - h * 0.28)
          ..lineTo(pos.dx + w * 0.72, pos.dy - h * 0.28)
          ..close();
        canvas.drawPath(crown, Paint()..color = const Color(0xFF2D8A4D));
        break;

      case _ObjectKind.rock:
        final path = Path()
          ..moveTo(pos.dx - w * 0.55, pos.dy)
          ..lineTo(pos.dx - w * 0.32, pos.dy - h * 0.66)
          ..lineTo(pos.dx + w * 0.10, pos.dy - h * 0.88)
          ..lineTo(pos.dx + w * 0.52, pos.dy - h * 0.30)
          ..lineTo(pos.dx + w * 0.42, pos.dy)
          ..close();
        canvas.drawPath(path, Paint()..color = const Color(0xFFC18A58));
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
          ..lineTo(pos.dx - w * 0.9, pos.dy - h * 0.18)
          ..lineTo(pos.dx - w * 0.32, pos.dy - h * 0.04)
          ..close();
        final rightWing = Path()
          ..moveTo(pos.dx + w * 0.15, pos.dy - h * 0.42)
          ..lineTo(pos.dx + w * 0.9, pos.dy - h * 0.18)
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

      case _ObjectKind.battery:
        final base = Rect.fromCenter(
          center: Offset(pos.dx, pos.dy - h * 0.36),
          width: w * 0.70,
          height: h * 0.52,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(base, const Radius.circular(5)),
          Paint()..color = const Color(0xFF7D7D7D),
        );

        final barrel = Path()
          ..moveTo(pos.dx + w * 0.06, pos.dy - h * 0.62)
          ..lineTo(pos.dx + w * 0.60, pos.dy - h * 0.80)
          ..lineTo(pos.dx + w * 0.54, pos.dy - h * 0.90)
          ..lineTo(pos.dx, pos.dy - h * 0.70)
          ..close();
        canvas.drawPath(barrel, Paint()..color = const Color(0xFFBDBDBD));
        break;
    }
  }

  void _paintShot(Canvas canvas, Size size, _Shot s) {
    final pos = _project(size, s.laneX, s.z, playerX, playerY);
    final scale = _scaleForShotZ(s.z);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: pos,
          width: size.width * 0.007 * scale + 3,
          height: size.height * 0.026 * scale + 5,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = accent,
    );
  }

  void _paintExplosion(Canvas canvas, Size size, _Explosion e) {
    final pos = _project(size, e.laneX, 0.82, playerX, playerY);
    final r = 8 + e.t * 36;
    final a = (1.0 - e.t).clamp(0.0, 1.0);
    canvas.drawCircle(
      Offset(pos.dx, lerpDouble(pos.dy, size.height * e.y, 0.65)!),
      r,
      Paint()..color = Colors.orange.withOpacity(a * 0.45),
    );
    canvas.drawCircle(
      Offset(pos.dx, lerpDouble(pos.dy, size.height * e.y, 0.65)!),
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
      ..color = accent.withOpacity(0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(center, 18, p);
    canvas.drawLine(Offset(center.dx - 28, center.dy), Offset(center.dx - 8, center.dy), p);
    canvas.drawLine(Offset(center.dx + 8, center.dy), Offset(center.dx + 28, center.dy), p);
    canvas.drawLine(Offset(center.dx, center.dy - 28), Offset(center.dx, center.dy - 8), p);
    canvas.drawLine(Offset(center.dx, center.dy + 8), Offset(center.dx, center.dy + 28), p);
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

    final circleCenter = Offset(size.width * 0.5, size.height - 128);
    canvas.drawCircle(circleCenter, 54, linePaint);
    canvas.drawLine(
      Offset(circleCenter.dx - 18, circleCenter.dy),
      Offset(circleCenter.dx + 18, circleCenter.dy),
      linePaint,
    );
    canvas.drawLine(
      Offset(circleCenter.dx, circleCenter.dy - 18),
      Offset(circleCenter.dx, circleCenter.dy + 18),
      linePaint,
    );
  }

  Offset _project(Size size, double laneX, double z, double playerX, double playerY) {
    final horizonY = size.height * 0.42;
    final bottomY = size.height * (0.86 + playerY * 0.025);
    final scale = _scaleForZ(z);

    final screenX = size.width * (0.5 + (laneX - playerX * 0.52) * 0.28 * scale);
    final screenY = lerpDouble(horizonY, bottomY, scale)!;

    return Offset(screenX, screenY);
  }

  double _scaleForZ(double z) {
    return z.clamp(0.06, 1.0);
  }

  double _scaleForShotZ(double z) {
    return z.clamp(0.06, 1.0);
  }

  @override
  bool shouldRepaint(covariant _ForwardRunPainter oldDelegate) => true;
}
