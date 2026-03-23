import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_models.dart';
import 'game_painter.dart';
import 'touch_controls.dart';

class EmpireFlightGame extends StatefulWidget {
  const EmpireFlightGame({super.key});

  @override
  State<EmpireFlightGame> createState() => _EmpireFlightGameState();
}

class _EmpireFlightGameState extends State<EmpireFlightGame> {
  late final List<MissionConfig> missions;
  late PlayerShip player;

  final List<Obstacle> obstacles = [];
  final List<Bullet> bullets = [];
  final List<StarPoint> stars = [];
  final List<Explosion> explosions = [];

  GamePhase phase = GamePhase.title;
  int missionIndex = 0;
  int score = 0;
  double missionDistance = 0;
  double spawnTimer = 0;
  double droneTimer = 0;
  double flashTimer = 0;

  bool leftPressed = false;
  bool rightPressed = false;
  bool upPressed = false;
  bool downPressed = false;
  bool firePressed = false;
  bool touchMode = false;

  Timer? loop;
  DateTime? lastTick;

  @override
  void initState() {
    super.initState();

    missions = [
      const MissionConfig(
        name: 'Mission 1: Ice Run',
        subtitle: 'Skim the frozen world and survive the defense line.',
        biome: MissionBiome.ice,
        skyTop: Color(0xFF13253F),
        skyBottom: Color(0xFF7FB7E8),
        groundNear: Color(0xFFD7EEF9),
        groundFar: Color(0xFF8FB8D6),
        targetDistance: 3200,
        baseSpeed: 240,
        spawnRate: 0.95,
        droneRate: 2.0,
        bonusForCompletion: 1200,
      ),
      const MissionConfig(
        name: 'Mission 2: Forest Canyon',
        subtitle: 'Thread the giant trees and break through patrol drones.',
        biome: MissionBiome.forest,
        skyTop: Color(0xFF102118),
        skyBottom: Color(0xFF3A6B4A),
        groundNear: Color(0xFF2D4A2F),
        groundFar: Color(0xFF1A2D1D),
        targetDistance: 3800,
        baseSpeed: 270,
        spawnRate: 0.85,
        droneRate: 1.7,
        bonusForCompletion: 1800,
      ),
      const MissionConfig(
        name: 'Mission 3: Desert Gauntlet',
        subtitle: 'Fly low through heat and stone to finish the campaign.',
        biome: MissionBiome.desert,
        skyTop: Color(0xFF412113),
        skyBottom: Color(0xFFE39B54),
        groundNear: Color(0xFFC98D46),
        groundFar: Color(0xFF8E6235),
        targetDistance: 4500,
        baseSpeed: 300,
        spawnRate: 0.75,
        droneRate: 1.45,
        bonusForCompletion: 2500,
      ),
    ];

    _newCampaign();
    _startLoop();
  }

  @override
  void dispose() {
    loop?.cancel();
    super.dispose();
  }

  MissionConfig get mission => missions[missionIndex];

  void _newCampaign() {
    missionIndex = 0;
    score = 0;
    _loadMission(resetHealth: true);
    phase = GamePhase.title;
  }

  void _loadMission({bool resetHealth = false}) {
    player = PlayerShip(
      x: 0,
      y: 0.75,
      health: resetHealth ? 100 : min(player.health + 18, 100),
      fireCooldown: 0,
      alive: true,
    );

    obstacles.clear();
    bullets.clear();
    explosions.clear();

    stars
      ..clear()
      ..addAll(List.generate(
        55,
        (_) => StarPoint(
          x: GameMath.rng.nextDouble(),
          y: GameMath.rng.nextDouble(),
          speed: 0.2 + GameMath.rng.nextDouble() * 0.8,
        ),
      ));

    missionDistance = 0;
    spawnTimer = 0;
    droneTimer = 0;
    flashTimer = 0;
    leftPressed = false;
    rightPressed = false;
    upPressed = false;
    downPressed = false;
    firePressed = false;
  }

  void _startLoop() {
    loop?.cancel();
    lastTick = null;

    loop = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now();

      // HACKABLE NOTE:
      // First tick just establishes time so web startup is safer.
      if (lastTick == null) {
        lastTick = now;
        return;
      }

      final dt = (now.difference(lastTick!).inMicroseconds / 1000000.0)
          .clamp(0.0, 0.033);

      lastTick = now;
      _update(dt);
    });
  }

  void _update(double dt) {
    if (!mounted) return;

    if (flashTimer > 0) {
      flashTimer -= dt;
    }

    if (phase != GamePhase.playing) {
      _updateStars(dt, idle: true);
      setState(() {});
      return;
    }

    _handleInput(dt);
    _updateStars(dt);
    _updatePlayer(dt);
    _spawnContent(dt);
    _updateObstacles(dt);
    _updateBullets(dt);
    _handleCollisions();
    _cleanupObjects();
    _checkMissionState();

    setState(() {});
  }

  void _handleInput(double dt) {
    const xSpeed = 1.65;
    const ySpeed = 1.1;

    if (leftPressed) player.x -= xSpeed * dt;
    if (rightPressed) player.x += xSpeed * dt;
    if (upPressed) player.y -= ySpeed * dt;
    if (downPressed) player.y += ySpeed * dt;

    player.x = GameMath.clamp(player.x, -1.18, 1.18);
    player.y = GameMath.clamp(player.y, 0.60, 0.84);

    if (firePressed) {
      _fire();
    }
  }

  void _updatePlayer(double dt) {
    if (player.fireCooldown > 0) {
      player.fireCooldown -= dt;
    }
  }

  void _updateStars(double dt, {bool idle = false}) {
    final speed = idle ? 0.03 : (0.08 + difficulty * 0.02);

    for (final s in stars) {
      s.y += s.speed * speed * dt * 9;
      if (s.y > 1.0) {
        s.y = 0;
        s.x = GameMath.rng.nextDouble();
      }
    }
  }

  double get difficulty =>
      1.0 + (missionDistance / mission.targetDistance) * 0.9;

  double get currentSpeed => mission.baseSpeed * difficulty;

  void _spawnContent(double dt) {
    spawnTimer += dt;
    droneTimer += dt;

    final obstacleDelay = max(0.30, mission.spawnRate / difficulty);
    final droneDelay = max(0.85, mission.droneRate / difficulty);

    if (spawnTimer >= obstacleDelay) {
      spawnTimer = 0;
      _spawnObstacle();
    }

    if (droneTimer >= droneDelay) {
      droneTimer = 0;
      _spawnDroneMaybe();
    }

    if (GameMath.rng.nextDouble() < 0.008 * difficulty * dt * 60) {
      _spawnGateRarely();
    }
  }

  void _spawnObstacle() {
    final lanes = [-0.95, -0.6, -0.25, 0.25, 0.6, 0.95];
    final lane = lanes[GameMath.rng.nextInt(lanes.length)];

    late ObstacleType type;

    switch (mission.biome) {
      case MissionBiome.ice:
        type = ObstacleType.pillar;
        break;
      case MissionBiome.forest:
        type = ObstacleType.tree;
        break;
      case MissionBiome.desert:
        type = ObstacleType.rock;
        break;
    }

    obstacles.add(
      Obstacle(
        type: type,
        laneX: lane,
        z: 0.02,
        width: 0.08 + GameMath.rng.nextDouble() * 0.05,
        height: 0.18 + GameMath.rng.nextDouble() * 0.14,
      ),
    );
  }

  void _spawnDroneMaybe() {
    if (GameMath.rng.nextDouble() < 0.78) {
      obstacles.add(
        Obstacle(
          type: ObstacleType.drone,
          laneX: -0.9 + GameMath.rng.nextDouble() * 1.8,
          z: 0.05,
          width: 0.10,
          height: 0.12,
          speedFactor: 1.18 + GameMath.rng.nextDouble() * 0.35,
          hp: 2,
        ),
      );
    }
  }

  void _spawnGateRarely() {
    if (obstacles.any((o) => o.type == ObstacleType.gate)) return;

    obstacles.add(
      Obstacle(
        type: ObstacleType.gate,
        laneX: 0,
        z: 0.04,
        width: 0.32,
        height: 0.24,
        speedFactor: 1.0,
        hp: 999,
      ),
    );
  }

  void _updateObstacles(double dt) {
    for (final o in obstacles) {
      o.z += dt * (0.34 + currentSpeed / 700) * o.speedFactor;

      if (!o.passed && o.z > 0.92) {
        o.passed = true;
        if (o.type == ObstacleType.drone) {
          score += 15;
        } else {
          score += 6;
        }
      }
    }

    missionDistance += currentSpeed * dt;
  }

  void _updateBullets(double dt) {
    for (final b in bullets) {
      b.z -= dt * 1.55;
      if (b.z < 0.0) {
        b.active = false;
      }
    }
  }

  void _handleCollisions() {
    for (final o in obstacles) {
      if (!o.active) continue;

      // HACKABLE NOTE:
      // Bullet hit tuning:
      // - z tolerance changes how forgiving shots feel
      // - width multiplier changes horizontal hitbox feel
      for (final b in bullets) {
        if (!b.active) continue;

        if ((b.z - o.z).abs() < 0.07 &&
            (b.x - o.laneX).abs() < (o.width * 1.4)) {
          b.active = false;

          if (o.type == ObstacleType.drone) {
            o.hp -= 1;
            if (o.hp <= 0) {
              _destroyObstacle(o, 120);
            }
          } else if (o.type == ObstacleType.gate) {
            score += 20;
          } else {
            _destroyObstacle(o, 35);
          }
        }
      }

      if (o.z > 0.86 && o.z < 1.03) {
        final xHit = (player.x - o.laneX).abs() < (o.width * 1.55);

        if (xHit) {
          if (o.type == ObstacleType.gate) {
            score += 40;
            o.active = false;
          } else {
            _hitPlayer(o.type == ObstacleType.drone ? 18 : 24);
            o.active = false;
            explosions.add(
              Explosion(x: o.laneX, y: player.y - 0.02),
            );
          }
        }
      }
    }
  }

  void _destroyObstacle(Obstacle o, int points) {
    o.active = false;
    score += points;
    explosions.add(Explosion(x: o.laneX, y: 0.63));
  }

  void _hitPlayer(double damage) {
    player.health -= damage;
    flashTimer = 0.14;

    if (player.health <= 0) {
      player.health = 0;
      player.alive = false;
      phase = GamePhase.gameOver;
    }
  }

  void _cleanupObjects() {
    obstacles.removeWhere((o) => !o.active || o.z > 1.12);
    bullets.removeWhere((b) => !b.active);

    for (final e in explosions) {
      e.t += 0.035;
      if (e.t >= 1.0) {
        e.active = false;
      }
    }

    explosions.removeWhere((e) => !e.active);
  }

  void _checkMissionState() {
    if (phase != GamePhase.playing) return;

    if (missionDistance >= mission.targetDistance) {
      score += mission.bonusForCompletion;

      if (missionIndex >= missions.length - 1) {
        phase = GamePhase.victory;
      } else {
        phase = GamePhase.missionComplete;
      }
    }
  }

  void _fire() {
    if (phase != GamePhase.playing) return;
    if (player.fireCooldown > 0) return;

    bullets.add(
      Bullet(
        x: player.x,
        y: player.y - 0.10,
        z: 0.92,
      ),
    );

    player.fireCooldown = 0.16;
  }

  void _startGameFromTitle() {
    phase = GamePhase.briefing;
  }

  void _startMission() {
    phase = GamePhase.playing;
  }

  void _nextMission() {
    missionIndex += 1;
    _loadMission();
    phase = GamePhase.briefing;
  }

  void _restartCampaign() {
    _newCampaign();
  }

  void _onDragUpdate(DragUpdateDetails details, BoxConstraints c) {
    touchMode = true;

    final dx = details.localPosition.dx / c.maxWidth;
    final dy = details.localPosition.dy / c.maxHeight;

    player.x = ((dx - 0.5) / 0.33).clamp(-1.18, 1.18);
    player.y = dy.clamp(0.60, 0.84);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isDown = event is KeyDownEvent;
    final isUp = event is KeyUpEvent;
    final key = event.logicalKey;

    void setKey(void Function(bool v) setter) {
      if (isDown) setter(true);
      if (isUp) setter(false);
    }

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.keyA) {
      setKey((v) => leftPressed = v);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyD) {
      setKey((v) => rightPressed = v);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.keyW) {
      setKey((v) => upPressed = v);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.keyS) {
      setKey((v) => downPressed = v);
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
      if (phase == GamePhase.gameOver || phase == GamePhase.victory) {
        _restartCampaign();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _handlePrimaryAction() {
    switch (phase) {
      case GamePhase.title:
        _startGameFromTitle();
        break;
      case GamePhase.briefing:
        _startMission();
        break;
      case GamePhase.missionComplete:
        _nextMission();
        break;
      case GamePhase.gameOver:
      case GamePhase.victory:
        _restartCampaign();
        break;
      case GamePhase.playing:
        break;
    }
  }

  HudSnapshot get hud => HudSnapshot(
        score: score,
        missionIndex: missionIndex + 1,
        totalMissions: missions.length,
        distance: missionDistance.floor(),
        targetDistance: mission.targetDistance,
        health: player.health,
        phase: phase,
        phaseText: _phaseText(),
      );

  String _phaseText() {
    switch (phase) {
      case GamePhase.title:
        return 'Tap or press Enter to begin';
      case GamePhase.briefing:
        return mission.subtitle;
      case GamePhase.playing:
        return 'Fly low. Dodge. Fire. Survive.';
      case GamePhase.missionComplete:
        return 'Mission complete';
      case GamePhase.gameOver:
        return 'Mission failed';
      case GamePhase.victory:
        return 'Campaign complete';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobileLayout = constraints.maxWidth < 900;

          return Focus(
            autofocus: true,
            onKeyEvent: _onKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (phase != GamePhase.playing) {
                  _handlePrimaryAction();
                }
              },
              onTapDown: (_) => touchMode = true,
              onPanUpdate: phase == GamePhase.playing
                  ? (details) => _onDragUpdate(details, constraints)
                  : null,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: GamePainter(
                        mission: mission,
                        player: player,
                        obstacles: obstacles,
                        bullets: bullets,
                        stars: stars,
                        explosions: explosions,
                        worldSpeed: currentSpeed,
                        difficulty: difficulty,
                        showAimLines: true,
                      ),
                    ),
                  ),

                  if (flashTimer > 0)
                    Positioned.fill(
                      child: Container(
                        color: Colors.red.withOpacity(0.12),
                      ),
                    ),

                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: _HudBar(
                        hud: hud,
                        missionName: mission.name,
                      ),
                    ),
                  ),

                  if (phase != GamePhase.playing)
                    Positioned.fill(
                      child: _OverlayCard(
                        title: _overlayTitle(),
                        subtitle: _overlaySubtitle(),
                        primaryLabel: _overlayButtonText(),
                        onPrimary: _handlePrimaryAction,
                        secondaryLabel:
                            _showRestartButton() ? 'Restart Campaign' : null,
                        onSecondary:
                            _showRestartButton() ? _restartCampaign : null,
                        footer: _overlayFooterText(isMobileLayout),
                      ),
                    ),

                  TouchControls(
                    visible: phase == GamePhase.playing && isMobileLayout,
                    onLeftDown: () {
                      touchMode = true;
                      leftPressed = true;
                    },
                    onLeftUp: () => leftPressed = false,
                    onRightDown: () {
                      touchMode = true;
                      rightPressed = true;
                    },
                    onRightUp: () => rightPressed = false,
                    onUpDown: () {
                      touchMode = true;
                      upPressed = true;
                    },
                    onUpUp: () => upPressed = false,
                    onDownDown: () {
                      touchMode = true;
                      downPressed = true;
                    },
                    onDownUp: () => downPressed = false,
                    onFire: () {
                      touchMode = true;
                      _fire();
                    },
                  ),

                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x66000000),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: const Color(0x22FFFFFF)),
                          ),
                          child: Text(
                            isMobileLayout
                                ? 'Drag ship • Use FIRE button • Tap overlay buttons'
                                : 'Move: WASD / Arrows • Fire: Space • Confirm: Enter • Restart: R',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _overlayTitle() {
    switch (phase) {
      case GamePhase.title:
        return 'EMPIRE FLIGHT';
      case GamePhase.briefing:
        return mission.name;
      case GamePhase.missionComplete:
        return 'MISSION COMPLETE';
      case GamePhase.gameOver:
        return 'GAME OVER';
      case GamePhase.victory:
        return 'VICTORY';
      case GamePhase.playing:
        return '';
    }
  }

  String _overlaySubtitle() {
    switch (phase) {
      case GamePhase.title:
        return 'Arcade-style low-altitude strike run across three hostile worlds.';
      case GamePhase.briefing:
        return mission.subtitle;
      case GamePhase.missionComplete:
        return 'Bonus awarded: ${mission.bonusForCompletion}';
      case GamePhase.gameOver:
        return 'Final Score: $score';
      case GamePhase.victory:
        return 'You survived all three missions.\nFinal Score: $score';
      case GamePhase.playing:
        return '';
    }
  }

  String _overlayButtonText() {
    switch (phase) {
      case GamePhase.title:
        return 'Start Campaign';
      case GamePhase.briefing:
        return 'Launch Mission';
      case GamePhase.missionComplete:
        return 'Next Mission';
      case GamePhase.gameOver:
        return 'Retry';
      case GamePhase.victory:
        return 'Play Again';
      case GamePhase.playing:
        return '';
    }
  }

  bool _showRestartButton() {
    return phase == GamePhase.briefing ||
        phase == GamePhase.missionComplete ||
        phase == GamePhase.gameOver ||
        phase == GamePhase.victory;
  }

  String _overlayFooterText(bool mobile) {
    if (phase == GamePhase.title) {
      return mobile
          ? 'Touch: drag + fire button'
          : 'Keyboard + touch supported';
    }
    if (phase == GamePhase.briefing) {
      return 'Win condition: reach ${mission.targetDistance}m with health remaining';
    }
    if (phase == GamePhase.missionComplete) {
      return 'Prepare for the next biome';
    }
    if (phase == GamePhase.gameOver) {
      return 'Dodge obstacles and shoot drones earlier';
    }
    if (phase == GamePhase.victory) {
      return 'Great base version for future upgrades';
    }
    return '';
  }
}

class _HudBar extends StatelessWidget {
  final HudSnapshot hud;
  final String missionName;

  const _HudBar({
    required this.hud,
    required this.missionName,
  });

  @override
  Widget build(BuildContext context) {
    final progress =
        hud.targetDistance == 0 ? 0.0 : hud.distance / hud.targetDistance;

    return Padding(
      padding: const EdgeInsets.all(12),
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
                    missionName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Text('Score ${hud.score}'),
                const SizedBox(width: 14),
                Text('Mission ${hud.missionIndex}/${hud.totalMissions}'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Hull'),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: hud.health / 100,
                      minHeight: 10,
                      backgroundColor: const Color(0x33222222),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        hud.health > 50
                            ? const Color(0xFF7FDBFF)
                            : hud.health > 25
                                ? const Color(0xFFFFC857)
                                : const Color(0xFFFF6B6B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 150,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: const Color(0x33222222),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${hud.distance}/${hud.targetDistance}m'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String footer;

  const _OverlayCard({
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              boxShadow: const [
                BoxShadow(
                  blurRadius: 20,
                  color: Color(0x44000000),
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: onPrimary,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        child: Text(primaryLabel),
                      ),
                    ),
                    if (secondaryLabel != null && onSecondary != null)
                      OutlinedButton(
                        onPressed: onSecondary,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          child: Text(secondaryLabel!),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  footer,
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
    );
  }
}
