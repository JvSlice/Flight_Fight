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

enum _HazardKind {
  iceSpire,
  iceWall,
  turret,
  drone,
}

class _Hazard {
  _Hazard({
    required this.kind,
    required this.x,
    required this.z,
    required this.width,
    required this.height,
    this.hp = 1,
    this.active = true,
  });

  _HazardKind kind;

  /// World horizontal offset. Negative = left, positive = right.
  double x;

  /// Depth: 0 = far/horizon, 1 = near cockpit.
  double z;

  /// Relative world size.
  double width;
  double height;

  int hp;
  bool active;

  bool get isShootable => kind == _HazardKind.turret || kind == _HazardKind.drone;

  bool get isSolid => kind == _HazardKind.iceSpire || kind == _HazardKind.iceWall;
}

class _LaserBolt {
  _LaserBolt({
    required this.start,
    required this.end,
    this.t = 0,
    this.active = true,
  });

  Offset start;
  Offset end;
  double t;
  bool active;
}

class _Explosion {
  _Explosion({
    required this.x,
    required this.z,
    this.large = false,
    this.t = 0,
    this.active = true,
  });

  double x;
  double z;
  bool large;
  double t;
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

  // Mission stats
  int score = 0;
  int hull = 100;
  double distance = 0;

  static const double _missionDistance = 5200;
  static const double _baseSpeed = 220;

  // Ship state: screen-space cinematic model, not lane model.
  double shipX = 0.0;
  double shipY = 0.0;
  double shipVX = 0.0;
  double shipVY = 0.0;

  // Input state
  bool leftPressed = false;
  bool rightPressed = false;
  bool upPressed = false;
  bool downPressed = false;
  bool firePressed = false;

  double fireCooldown = 0.0;
  double damageFlash = 0.0;

  final List<_Hazard> hazards = [];
  final List<_LaserBolt> bolts = [];
  final List<_Explosion> explosions = [];
  final List<_Star> stars = [];

  // Track which scripted groups have already spawned.
  final Set<int> _spawnedGroups = <int>{};

  Size playSize = const Size(1000, 700);

  @override
  void initState() {
    super.initState();

    for (int i = 0; i < 80; i++) {
      stars.add(
        _Star(
          x: _rng.nextDouble(),
          y: _rng.nextDouble() * 0.56,
          speed: 0.25 + _rng.nextDouble() * 0.9,
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

  double get worldSpeed {
    // HACKABLE NOTE:
    // Keep this flatter than before. The run should build pressure,
    // but not turn into chaos.
    return _baseSpeed * (1.0 + progress * 0.18);
  }

  Offset _shipScreenCenter(Size size) {
    return Offset(
      size.width * (0.5 + shipX * 0.22),
      size.height * (0.78 + shipY * 0.10),
    );
  }

  void _resetRun() {
    phase = _GamePhase.briefing;
    score = 0;
    hull = 100;
    distance = 0;

    shipX = 0.0;
    shipY = 0.0;
    shipVX = 0.0;
    shipVY = 0.0;

    leftPressed = false;
    rightPressed = false;
    upPressed = false;
    downPressed = false;
    firePressed = false;

    fireCooldown = 0.0;
    damageFlash = 0.0;

    hazards.clear();
    bolts.clear();
    explosions.clear();
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
    _updateEffects(dt);

    if (phase != _GamePhase.playing) {
      setState(() {});
      return;
    }

    _updateShip(dt);
    _spawnScriptedGroups();
    _updateHazards(dt);
    _handleShooting(dt);
    _handleCollisions();
    _cleanup();

    distance += worldSpeed * dt;

    if (hull <= 0) {
      hull = 0;
      phase = _GamePhase.gameOver;
    } else if (distance >= _missionDistance) {
      score += 1500;
      phase = _GamePhase.victory;
    }

    setState(() {});
  }

  void _updateStars(double dt) {
    final drift = 0.05 + progress * 0.02;
    for (final s in stars) {
      s.y += s.speed * drift * dt * 10;
      if (s.y > 0.58) {
        s.y = 0;
        s.x = _rng.nextDouble();
      }
    }
  }

  void _updateEffects(double dt) {
    if (damageFlash > 0) {
      damageFlash -= dt;
    }

    if (fireCooldown > 0) {
      fireCooldown -= dt;
    }

    for (final b in bolts) {
      b.t += dt * 6.0;
      if (b.t >= 1.0) {
        b.active = false;
      }
    }
    bolts.removeWhere((b) => !b.active);

    for (final e in explosions) {
      e.t += dt * 1.9;
      if (e.t >= 1.0) {
        e.active = false;
      }
    }
    explosions.removeWhere((e) => !e.active);
  }

  void _updateShip(double dt) {
    // HACKABLE NOTE:
    // This is the feel core.
    // Bigger acceleration = snappier.
    // Bigger damping = more stable.
    const accelX = 3.0;
    const accelY = 2.1;
    const damping = 0.86;
    const maxVX = 1.15;
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

    // HACKABLE NOTE:
    // Broad playable sweep. This should feel wider than the old lane game.
    shipX = shipX.clamp(-0.95, 0.95);
    shipY = shipY.clamp(-0.22, 0.22);

    // Soft edge bounce/settle.
    if (shipX <= -0.95 || shipX >= 0.95) shipVX *= -0.15;
    if (shipY <= -0.22 || shipY >= 0.22) shipVY *= -0.15;
  }

  void _spawnScriptedGroups() {
    // HACKABLE NOTE:
    // This is the new foundation: hand-authored distance groups,
    // not random soup.
    _spawnAt(
      180,
      1,
      () => _spawnTurretPair(centerGapLeft: true),
    );
    _spawnAt(
      520,
      2,
      () => _spawnSpireSlalom(leftFirst: true),
    );
    _spawnAt(
      880,
      3,
      () => _spawnWideGateWithTurret(openLeft: false),
    );
    _spawnAt(
      1250,
      4,
      () => _spawnDroneSweep(leftToRight: true),
    );
    _spawnAt(
      1650,
      5,
      () => _spawnSpireSlalom(leftFirst: false),
    );
    _spawnAt(
      2050,
      6,
      () => _spawnWideGateWithTurret(openLeft: true),
    );
    _spawnAt(
      2450,
      7,
      () => _spawnNarrowIcePass(openCenter: true),
    );
    _spawnAt(
      2850,
      8,
      () => _spawnDroneSweep(leftToRight: false),
    );
    _spawnAt(
      3300,
      9,
      () => _spawnTurretRun(),
    );
    _spawnAt(
      3820,
      10,
      () => _spawnNarrowIcePass(openCenter: false),
    );
    _spawnAt(
      4300,
      11,
      () => _spawnFinalPush(),
    );
  }

  void _spawnAt(double distanceMark, int id, VoidCallback spawn) {
    if (_spawnedGroups.contains(id)) return;
    if (distance >= distanceMark) return;

    // Spawn when the run is approaching this section.
    if (distanceMark - distance <= 420) {
      _spawnedGroups.add(id);
      spawn();
    }
  }

  void _spawnTurretPair({required bool centerGapLeft}) {
    hazards.addAll([
      _Hazard(
        kind: _HazardKind.turret,
        x: centerGapLeft ? 0.36 : -0.36,
        z: 0.12,
        width: 0.10,
        height: 0.18,
        hp: 2,
      ),
      _Hazard(
        kind: _HazardKind.turret,
        x: centerGapLeft ? 0.70 : -0.70,
        z: 0.08,
        width: 0.10,
        height: 0.18,
        hp: 2,
      ),
    ]);
  }

  void _spawnSpireSlalom({required bool leftFirst}) {
    final xs = leftFirst
        ? [-0.62, 0.20, -0.18]
        : [0.62, -0.20, 0.18];

    for (int i = 0; i < xs.length; i++) {
      hazards.add(
        _Hazard(
          kind: _HazardKind.iceSpire,
          x: xs[i],
          z: 0.05 + i * 0.03,
          width: 0.11,
          height: 0.25,
          hp: 999,
        ),
      );
    }
  }

  void _spawnWideGateWithTurret({required bool openLeft}) {
    if (openLeft) {
      hazards.addAll([
        _Hazard(
          kind: _HazardKind.iceWall,
          x: 0.28,
          z: 0.05,
          width: 0.22,
          height: 0.18,
          hp: 999,
        ),
        _Hazard(
          kind: _HazardKind.iceSpire,
          x: 0.68,
          z: 0.05,
          width: 0.12,
          height: 0.24,
          hp: 999,
        ),
        _Hazard(
          kind: _HazardKind.turret,
          x: -0.20,
          z: 0.12,
          width: 0.10,
          height: 0.18,
          hp: 2,
        ),
      ]);
    } else {
      hazards.addAll([
        _Hazard(
          kind: _HazardKind.iceWall,
          x: -0.28,
          z: 0.05,
          width: 0.22,
          height: 0.18,
          hp: 999,
        ),
        _Hazard(
          kind: _HazardKind.iceSpire,
          x: -0.68,
          z: 0.05,
          width: 0.12,
          height: 0.24,
          hp: 999,
        ),
        _Hazard(
          kind: _HazardKind.turret,
          x: 0.20,
          z: 0.12,
          width: 0.10,
          height: 0.18,
          hp: 2,
        ),
      ]);
    }
  }

  void _spawnDroneSweep({required bool leftToRight}) {
    final xs = leftToRight
        ? [-0.62, -0.24, 0.16]
        : [0.62, 0.24, -0.16];

    for (int i = 0; i < xs.length; i++) {
      hazards.add(
        _Hazard(
          kind: _HazardKind.drone,
          x: xs[i],
          z: 0.10 + i * 0.025,
          width: 0.10,
          height: 0.09,
          hp: 2,
        ),
      );
    }
  }

  void _spawnNarrowIcePass({required bool openCenter}) {
    if (openCenter) {
      hazards.addAll([
        _Hazard(
          kind: _HazardKind.iceWall,
          x: -0.56,
          z: 0.05,
          width: 0.18,
          height: 0.18,
          hp: 999,
        ),
        _Hazard(
          kind: _HazardKind.iceWall,
          x: 0.56,
          z: 0.05,
          width: 0.18,
          height: 0.18,
          hp: 999,
        ),
      ]);
    } else {
      hazards.addAll([
        _Hazard(
          kind: _HazardKind.iceSpire,
          x: -0.18,
          z: 0.05,
          width: 0.12,
          height: 0.25,
          hp: 999,
        ),
        _Hazard(
          kind: _HazardKind.iceSpire,
          x: 0.18,
          z: 0.08,
          width: 0.12,
          height: 0.25,
          hp: 999,
        ),
      ]);
    }
  }

  void _spawnTurretRun() {
    hazards.addAll([
      _Hazard(
        kind: _HazardKind.turret,
        x: -0.58,
        z: 0.08,
        width: 0.10,
        height: 0.18,
        hp: 2,
      ),
      _Hazard(
        kind: _HazardKind.turret,
        x: 0.00,
        z: 0.11,
        width: 0.10,
        height: 0.18,
        hp: 2,
      ),
      _Hazard(
        kind: _HazardKind.turret,
        x: 0.58,
        z: 0.14,
        width: 0.10,
        height: 0.18,
        hp: 2,
      ),
    ]);
  }

  void _spawnFinalPush() {
    hazards.addAll([
      _Hazard(
        kind: _HazardKind.iceWall,
        x: -0.52,
        z: 0.05,
        width: 0.18,
        height: 0.18,
        hp: 999,
      ),
      _Hazard(
        kind: _HazardKind.iceWall,
        x: 0.52,
        z: 0.05,
        width: 0.18,
        height: 0.18,
        hp: 999,
      ),
      _Hazard(
        kind: _HazardKind.turret,
        x: -0.18,
        z: 0.11,
        width: 0.10,
        height: 0.18,
        hp: 2,
      ),
      _Hazard(
        kind: _HazardKind.turret,
        x: 0.18,
        z: 0.14,
        width: 0.10,
        height: 0.18,
        hp: 2,
      ),
      _Hazard(
        kind: _HazardKind.drone,
        x: 0.00,
        z: 0.17,
        width: 0.10,
        height: 0.09,
        hp: 2,
      ),
    ]);
  }

  void _updateHazards(double dt) {
    final advance = dt * (0.30 + worldSpeed / 860.0);

    for (final h in hazards) {
      h.z += advance * (h.kind == _HazardKind.drone ? 1.10 : 1.0);
    }
  }

  void _handleShooting(double dt) {
    if (!firePressed) return;
    if (fireCooldown > 0) return;
    if (phase != _GamePhase.playing) return;

    fireCooldown = 0.18;

    final target = _chooseSoftAimTarget();

    final start = _shipScreenCenter(playSize);
    final end = target != null
        ? _project(playSize, target.x, target.z, shipX, shipY)
        : Offset(
            playSize.width * (0.5 + shipX * 0.14),
            playSize.height * 0.50,
          );

    bolts.add(_LaserBolt(start: start, end: end));

    if (target != null) {
      target.hp -= 1;
      if (target.hp <= 0) {
        target.active = false;
        score += target.kind == _HazardKind.drone ? 170 : 95;
        explosions.add(
          _Explosion(
            x: target.x,
            z: target.z,
            large: target.kind == _HazardKind.turret,
          ),
        );
      }
    }
  }

  _Hazard? _chooseSoftAimTarget() {
    _Hazard? best;
    double bestScore = double.infinity;

    for (final h in hazards) {
      if (!h.active || !h.isShootable) continue;

      // HACKABLE NOTE:
      // This is the new soft target model.
      // It favors targets somewhat near the ship and in a good forward depth band.
      final xDist = (h.x - shipX).abs();

      if (xDist > 0.42) continue;
      if (h.z < 0.10 || h.z > 0.72) continue;

      final depthBias = (h.z - 0.34).abs();
      final score = xDist * 1.0 + depthBias * 0.7;

      if (score < bestScore) {
        bestScore = score;
        best = h;
      }
    }

    return best;
  }

  void _handleCollisions() {
    for (final h in hazards) {
      if (!h.active) continue;

      if (h.z > 0.88) {
        // HACKABLE NOTE:
        // Bigger, friendlier cinematic ship contact space.
        final xThreshold = h.kind == _HazardKind.iceWall
            ? h.width * 1.18
            : h.width * 1.08;

        if ((h.x - shipX).abs() < xThreshold) {
          h.active = false;
          hull -= h.isShootable ? 15 : 24;
          damageFlash = 0.15;

          explosions.add(
            _Explosion(
              x: h.x,
              z: 0.90,
              large: h.kind != _HazardKind.drone,
            ),
          );
        }
      }

      if (h.active && h.z > 1.10) {
        h.active = false;
      }
    }
  }

  void _cleanup() {
    hazards.removeWhere((h) => !h.active);
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

    // Direct momentum push for touch.
    shipVX += dx * 2.5;
    shipVY += dy * 1.5;
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
      if (isDown) firePressed = true;
      if (isUp) firePressed = false;
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
        return 'Fly the run.\nThread the ice. Snap turrets and drones when they line up.';
      case _GamePhase.paused:
        return 'Take a breath and resume when ready.';
      case _GamePhase.victory:
        return 'Ice Run cleared.\nFinal score: $score';
      case _GamePhase.gameOver:
        return 'Your run ended in wreckage.\nFinal score: $score';
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
                        playerX: shipX,
                        playerY: shipY,
                        hazards: hazards,
                        bolts: bolts,
                        stars: stars,
                        explosions: explosions,
                        accent: const Color(0xFFD9F3FF),
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
                                            value: (_missionDistance == 0)
                                                ? 0
                                                : (distance / _missionDistance).clamp(0.0, 1.0),
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
                                        ? 'Touch: drag to fly • hold FIRE'
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
                          onPointerDown: (_) => setState(() => firePressed = true),
                          onPointerUp: (_) => setState(() => firePressed = false),
                          onPointerCancel: (_) => setState(() => firePressed = false),
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
    required this.hazards,
    required this.bolts,
    required this.stars,
    required this.explosions,
    required this.accent,
  });

  final double playerX;
  final double playerY;
  final List<_Hazard> hazards;
  final List<_LaserBolt> bolts;
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

    final sorted = [...hazards]..sort((a, b) => a.z.compareTo(b.z));
    for (final h in sorted) {
      _paintHazard(canvas, size, h);
    }

    for (final bolt in bolts) {
      _paintBolt(canvas, bolt);
    }

    for (final e in explosions) {
      _paintExplosion(canvas, size, e);
    }

    _paintReticle(canvas, size);
    _paintShipBody(canvas, size);
    _paintCockpit(canvas, size);
  }

  void _paintSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0E1A33), Color(0xFF79B7E6)],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
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

  void _paintHazard(Canvas canvas, Size size, _Hazard h) {
    final pos = _project(size, h.x, h.z, playerX, playerY);
    final scale = _scaleForZ(h.z);
    final w = size.width * h.width * scale;
    final ht = size.height * h.height * scale;

    switch (h.kind) {
      case _HazardKind.iceWall:
        final rect = Rect.fromCenter(
          center: Offset(pos.dx, pos.dy - ht * 0.5),
          width: w,
          height: ht,
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

      case _HazardKind.iceSpire:
        final path = Path()
          ..moveTo(pos.dx - w * 0.45, pos.dy)
          ..lineTo(pos.dx - w * 0.20, pos.dy - ht * 0.45)
          ..lineTo(pos.dx - w * 0.04, pos.dy - ht * 0.98)
          ..lineTo(pos.dx + w * 0.10, pos.dy - ht * 0.64)
          ..lineTo(pos.dx + w * 0.32, pos.dy - ht * 0.84)
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

      case _HazardKind.turret:
        final base = Rect.fromCenter(
          center: Offset(pos.dx, pos.dy - ht * 0.34),
          width: w * 0.72,
          height: ht * 0.54,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(base, const Radius.circular(5)),
          Paint()..color = const Color(0xFFDFE8EF),
        );

        final barrel = Path()
          ..moveTo(pos.dx + w * 0.04, pos.dy - ht * 0.60)
          ..lineTo(pos.dx + w * 0.60, pos.dy - ht * 0.80)
          ..lineTo(pos.dx + w * 0.54, pos.dy - ht * 0.92)
          ..lineTo(pos.dx - w * 0.02, pos.dy - ht * 0.70)
          ..close();
        canvas.drawPath(barrel, Paint()..color = const Color(0xFFE16A6A));

        final cap = Rect.fromCenter(
          center: Offset(pos.dx, pos.dy - ht * 0.16),
          width: w * 0.24,
          height: ht * 0.10,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(cap, const Radius.circular(4)),
          Paint()..color = const Color(0xFFE16A6A),
        );
        break;

      case _HazardKind.drone:
        final bodyPaint = Paint()..color = const Color(0xFFE16A6A);
        final wingPaint = Paint()..color = const Color(0xFFB84D4D);
        final glass = Paint()..color = const Color(0xFFA7EEFF);

        final body = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(pos.dx, pos.dy - ht * 0.42),
            width: w * 0.42,
            height: ht * 0.34,
          ),
          const Radius.circular(8),
        );
        canvas.drawRRect(body, bodyPaint);

        final leftWing = Path()
          ..moveTo(pos.dx - w * 0.15, pos.dy - ht * 0.42)
          ..lineTo(pos.dx - w * 0.90, pos.dy - ht * 0.18)
          ..lineTo(pos.dx - w * 0.32, pos.dy - ht * 0.04)
          ..close();
        final rightWing = Path()
          ..moveTo(pos.dx + w * 0.15, pos.dy - ht * 0.42)
          ..lineTo(pos.dx + w * 0.90, pos.dy - ht * 0.18)
          ..lineTo(pos.dx + w * 0.32, pos.dy - ht * 0.04)
          ..close();

        canvas.drawPath(leftWing, wingPaint);
        canvas.drawPath(rightWing, wingPaint);

        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(pos.dx, pos.dy - ht * 0.46),
            width: w * 0.14,
            height: ht * 0.12,
          ),
          glass,
        );
        break;
    }
  }

  void _paintBolt(Canvas canvas, _LaserBolt bolt) {
    final alpha = (1.0 - bolt.t).clamp(0.0, 1.0);

    final core = Paint()
      ..color = accent.withOpacity(alpha)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final glow = Paint()
      ..color = accent.withOpacity(alpha * 0.25)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(bolt.start, bolt.end, glow);
    canvas.drawLine(bolt.start, bolt.end, core);
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

    // Canopy side struts for stronger cockpit feel.
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
    final scale = _scaleForZ(z);

    final screenX = size.width * (0.5 + (x - playerX * 0.50) * 0.30 * scale);
    final screenY = lerpDouble(horizonY, bottomY, scale)!;

    return Offset(screenX, screenY);
  }

  double _scaleForZ(double z) => z.clamp(0.06, 1.0);

  @override
  bool shouldRepaint(covariant _MissionOnePainter oldDelegate) => true;
}
