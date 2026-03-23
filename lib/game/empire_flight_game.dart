import 'dart:async';
import 'dart:math';
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

class _MissionData {
  final String name;
  final String subtitle;
  final Color bgTop;
  final Color bgBottom;
  final Color accent;
  final List<Color> terrainColors;
  final int goalDistance;
  final double baseSpeed;
  final double spawnRate;

  const _MissionData({
    required this.name,
    required this.subtitle,
    required this.bgTop,
    required this.bgBottom,
    required this.accent,
    required this.terrainColors,
    required this.goalDistance,
    required this.baseSpeed,
    required this.spawnRate,
  });
}

class _Obstacle {
  double x;
  double y;
  double w;
  double h;
  Color color;
  bool isEnemy;
  bool active;
  int hp;

  _Obstacle({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.color,
    required this.isEnemy,
    this.active = true,
    this.hp = 1,
  });

  Rect get rect => Rect.fromLTWH(x, y, w, h);
}

class _Bullet {
  double x;
  double y;
  double w;
  double h;
  bool active;

  _Bullet({
    required this.x,
    required this.y,
    this.w = 18,
    this.h = 4,
    this.active = true,
  });

  Rect get rect => Rect.fromLTWH(x, y, w, h);
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

class _EmpireFlightGameState extends State<EmpireFlightGame> {
  final Random rng = Random();
  final FocusNode _keyboardFocus = FocusNode();

  late final List<_MissionData> missions;

  Timer? _loop;
  DateTime? _lastTick;

  _GamePhase phase = _GamePhase.briefing;
  int missionIndex = 0;
  int score = 0;
  int health = 100;
  double distance = 0;
  double spawnTimer = 0;
  double fireCooldown = 0;

  double playerX = 80;
  double playerY = 250;
  final double playerW = 64;
  final double playerH = 34;

  bool leftPressed = false;
  bool rightPressed = false;
  bool upPressed = false;
  bool downPressed = false;
  bool firePressed = false;

  final List<_Obstacle> obstacles = [];
  final List<_Bullet> bullets = [];
  final List<_Star> stars = [];

  Size _playSize = const Size(1000, 600);

  @override
  void initState() {
    super.initState();

    missions = const [
      _MissionData(
        name: 'Mission 1: Ice Run',
        subtitle: 'Fly low over the frozen world and survive the defense line.',
        bgTop: Color(0xFF0E1F39),
        bgBottom: Color(0xFF7DB8E8),
        accent: Color(0xFFD9F3FF),
        terrainColors: [
          Color(0xFFB7D9F3),
          Color(0xFFDFF5FF),
        ],
        goalDistance: 5000,
        baseSpeed: 220,
        spawnRate: 0.92,
      ),
      _MissionData(
        name: 'Mission 2: Forest Run',
        subtitle: 'Thread between giant trunks and hostile patrol craft.',
        bgTop: Color(0xFF0E2012),
        bgBottom: Color(0xFF4A7A56),
        accent: Color(0xFF9BE58A),
        terrainColors: [
          Color(0xFF29452C),
          Color(0xFF1D341F),
        ],
        goalDistance: 6200,
        baseSpeed: 240,
        spawnRate: 0.82,
      ),
      _MissionData(
        name: 'Mission 3: Desert Run',
        subtitle: 'Push through heat, rock spires, and attack drones.',
        bgTop: Color(0xFF422013),
        bgBottom: Color(0xFFE6A45D),
        accent: Color(0xFFFFD27A),
        terrainColors: [
          Color(0xFFC78A4B),
          Color(0xFF9A6536),
        ],
        goalDistance: 7400,
        baseSpeed: 260,
        spawnRate: 0.72,
      ),
    ];

    for (int i = 0; i < 60; i++) {
      stars.add(
        _Star(
          x: rng.nextDouble() * 1000,
          y: rng.nextDouble() * 600,
          speed: 20 + rng.nextDouble() * 80,
        ),
      );
    }

    _resetMission(fullReset: true);
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

  _MissionData get mission => missions[missionIndex];

  double get difficultyScale {
    final pct = distance / mission.goalDistance;
    return 1.0 + pct.clamp(0.0, 1.0) * 0.45;
  }

  double get worldSpeed => mission.baseSpeed * difficultyScale;

  Rect get playerRect => Rect.fromLTWH(playerX, playerY, playerW, playerH);

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
      health = 100;
      phase = _GamePhase.briefing;
    } else {
      health = min(100, health + 20);
      phase = _GamePhase.briefing;
    }

    distance = 0;
    spawnTimer = 0;
    fireCooldown = 0;
    obstacles.clear();
    bullets.clear();

    playerX = 80;
    playerY = 250;
    leftPressed = false;
    rightPressed = false;
    upPressed = false;
    downPressed = false;
    firePressed = false;
  }

  void _update(double dt) {
    if (!mounted) return;

    _updateStars(dt);

    if (fireCooldown > 0) {
      fireCooldown -= dt;
    }

    if (phase != _GamePhase.playing) {
      setState(() {});
      return;
    }

    _handleInput(dt);
    _spawnObstacles(dt);
    _updateObstacles(dt);
    _updateBullets(dt);
    _handleCollisions();
    _cleanup();

    distance += worldSpeed * dt;

    if (distance >= mission.goalDistance) {
      score += 1200 + missionIndex * 500;
      if (missionIndex >= missions.length - 1) {
        phase = _GamePhase.victory;
      } else {
        phase = _GamePhase.missionComplete;
      }
    }

    if (health <= 0) {
      phase = _GamePhase.gameOver;
    }

    setState(() {});
  }

  void _updateStars(double dt) {
    for (final s in stars) {
      s.x -= s.speed * dt;
      if (s.x < -4) {
        s.x = _playSize.width + rng.nextDouble() * 40;
        s.y = rng.nextDouble() * (_playSize.height * 0.68);
      }
    }
  }

  void _handleInput(double dt) {
    const moveSpeed = 300.0;

    if (leftPressed) playerX -= moveSpeed * dt;
    if (rightPressed) playerX += moveSpeed * dt;
    if (upPressed) playerY -= moveSpeed * dt;
    if (downPressed) playerY += moveSpeed * dt;

    if (firePressed) {
      _fire();
    }

    final minX = 20.0;
    final maxX = max(20.0, _playSize.width - playerW - 20.0);
    final minY = 70.0;
    final maxY = max(70.0, _playSize.height - playerH - 110.0);

    playerX = playerX.clamp(minX, maxX);
    playerY = playerY.clamp(minY, maxY);
  }

  void _spawnObstacles(double dt) {
    spawnTimer += dt;
    final delay = max(0.28, mission.spawnRate / difficultyScale);

    if (spawnTimer < delay) return;
    spawnTimer = 0;

    final isEnemy = rng.nextDouble() < 0.5;
    final laneY = 90 + rng.nextDouble() * max(120.0, _playSize.height - 220.0);

    if (isEnemy) {
      obstacles.add(
        _Obstacle(
          x: _playSize.width + 40,
          y: laneY,
          w: 46,
          h: 28,
          color: const Color(0xFFE16A6A),
          isEnemy: true,
          hp: 2,
        ),
      );
    } else {
      switch (missionIndex) {
        case 0:
          obstacles.add(
            _Obstacle(
              x: _playSize.width + 40,
              y: laneY - 35,
              w: 28,
              h: 130,
              color: const Color(0xFFD7F2FF),
              isEnemy: false,
            ),
          );
          break;
        case 1:
          obstacles.add(
            _Obstacle(
              x: _playSize.width + 40,
              y: laneY - 48,
              w: 38,
              h: 160,
              color: const Color(0xFF5F3C22),
              isEnemy: false,
            ),
          );
          break;
        case 2:
          obstacles.add(
            _Obstacle(
              x: _playSize.width + 40,
              y: laneY - 40,
              w: 42,
              h: 125,
              color: const Color(0xFFB97B47),
              isEnemy: false,
            ),
          );
          break;
      }
    }
  }

  void _updateObstacles(double dt) {
    for (final o in obstacles) {
      o.x -= worldSpeed * dt * (o.isEnemy ? 1.08 : 1.0);
    }
  }

  void _updateBullets(double dt) {
    for (final b in bullets) {
      b.x += 700 * dt;
      if (b.x > _playSize.width + 40) {
        b.active = false;
      }
    }
  }

  void _handleCollisions() {
    final pRect = playerRect;

    for (final o in obstacles) {
      if (!o.active) continue;

      if (o.rect.overlaps(pRect)) {
        o.active = false;
        health -= o.isEnemy ? 16 : 24;
      }

      for (final b in bullets) {
        if (!b.active || !o.active) continue;

        if (b.rect.overlaps(o.rect)) {
          b.active = false;

          if (o.isEnemy) {
            o.hp -= 1;
            if (o.hp <= 0) {
              o.active = false;
              score += 130;
            }
          } else {
            o.active = false;
            score += 40;
          }
        }
      }

      if (o.active && o.x + o.w < 0) {
        o.active = false;
        score += 5;
      }
    }
  }

  void _cleanup() {
    obstacles.removeWhere((o) => !o.active);
    bullets.removeWhere((b) => !b.active);
  }

  void _fire() {
    // HACKABLE NOTE:
    // Lower cooldown for more shooting.
    // Raise bullet cap for heavier laser spam.
    if (fireCooldown > 0) return;
    if (bullets.length > 12) return;

    bullets.add(
      _Bullet(
        x: playerX + playerW - 2,
        y: playerY + playerH * 0.35,
      ),
    );
    bullets.add(
      _Bullet(
        x: playerX + playerW - 2,
        y: playerY + playerH * 0.65 - 4,
      ),
    );

    fireCooldown = 0.10;
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _playSize = Size(
          max(320, constraints.maxWidth),
          max(480, constraints.maxHeight),
        );

        final isCompact = _playSize.width < 850;

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
              onPanUpdate: phase == _GamePhase.playing
                  ? (details) {
                      setState(() {
                        playerX += details.delta.dx;
                        playerY += details.delta.dy;
                      });
                    }
                  : null,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            mission.bgTop,
                            mission.bgBottom,
                          ],
                        ),
                      ),
                    ),
                  ),

                  ...stars.map(
                    (s) => Positioned(
                      left: s.x,
                      top: s.y,
                      child: Container(
                        width: 2,
                        height: 2,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 145,
                    child: Container(color: mission.terrainColors[0]),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 82,
                    child: Container(color: mission.terrainColors[1]),
                  ),

                  ...obstacles.map((o) {
                    return Positioned(
                      left: o.x,
                      top: o.y,
                      child: o.isEnemy
                          ? _EnemyWidget(width: o.w, height: o.h, color: o.color)
                          : _ObstacleWidget(width: o.w, height: o.h, color: o.color),
                    );
                  }),

                  ...bullets.map(
                    (b) => Positioned(
                      left: b.x,
                      top: b.y,
                      child: Container(
                        width: b.w,
                        height: b.h,
                        decoration: BoxDecoration(
                          color: mission.accent,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 8,
                              color: mission.accent.withOpacity(0.7),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: playerX,
                    top: playerY,
                    child: _ShipWidget(
                      width: playerW,
                      height: playerH,
                      accent: mission.accent,
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
                                      value: health / 100,
                                      minHeight: 10,
                                      backgroundColor: const Color(0x33222222),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        health > 50
                                            ? const Color(0xFF7FDBFF)
                                            : health > 25
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
                                        Color(0xFFFFFFFF),
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

                  // Simple cockpit overlay
                  IgnorePointer(
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 110,
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0x66081118),
                              border: Border(
                                top: BorderSide(
                                  color: mission.accent.withOpacity(0.25),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 32,
                          child: Container(color: const Color(0x33081118)),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          width: 32,
                          child: Container(color: const Color(0x33081118)),
                        ),
                      ],
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
                                        ? 'Touch: drag to move • hold FIRE'
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
                            setState(() {
                              firePressed = true;
                            });
                            _fire();
                          },
                          onPointerUp: (_) {
                            setState(() {
                              firePressed = false;
                            });
                          },
                          onPointerCancel: (_) {
                            setState(() {
                              firePressed = false;
                            });
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
        return 'Prepare for the next mission.\nScore: $score';
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

class _ShipWidget extends StatelessWidget {
  final double width;
  final double height;
  final Color accent;

  const _ShipWidget({
    required this.width,
    required this.height,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _ShipPainter(accent: accent),
      ),
    );
  }
}

class _ShipPainter extends CustomPainter {
  final Color accent;

  _ShipPainter({required this.accent});

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = const Color(0xFFE7EEF7);
    final wing = Paint()..color = const Color(0xFF98AFC7);
    final glass = Paint()..color = const Color(0xFF9EE7FF);
    final glow = Paint()..color = accent.withOpacity(0.6);

    final bodyPath = Path()
      ..moveTo(size.width * 0.08, size.height * 0.5)
      ..lineTo(size.width * 0.55, size.height * 0.18)
      ..lineTo(size.width * 0.92, size.height * 0.5)
      ..lineTo(size.width * 0.55, size.height * 0.82)
      ..close();

    final wingTop = Path()
      ..moveTo(size.width * 0.18, size.height * 0.34)
      ..lineTo(size.width * 0.02, size.height * 0.05)
      ..lineTo(size.width * 0.36, size.height * 0.26)
      ..close();

    final wingBottom = Path()
      ..moveTo(size.width * 0.18, size.height * 0.66)
      ..lineTo(size.width * 0.02, size.height * 0.95)
      ..lineTo(size.width * 0.36, size.height * 0.74)
      ..close();

    canvas.drawPath(wingTop, wing);
    canvas.drawPath(wingBottom, wing);
    canvas.drawPath(bodyPath, body);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.52, size.height * 0.5),
        width: size.width * 0.18,
        height: size.height * 0.24,
      ),
      glass,
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.04, size.height * 0.5),
        width: size.width * 0.10,
        height: size.height * 0.18,
      ),
      glow,
    );
  }

  @override
  bool shouldRepaint(covariant _ShipPainter oldDelegate) {
    return oldDelegate.accent != accent;
  }
}

class _EnemyWidget extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _EnemyWidget({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _EnemyPainter(color: color),
    );
  }
}

class _EnemyPainter extends CustomPainter {
  final Color color;

  _EnemyPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final body = Paint()..color = color;
    final detail = Paint()..color = const Color(0xFF2B1D1D);

    final p = Path()
      ..moveTo(size.width * 0.1, size.height * 0.5)
      ..lineTo(size.width * 0.42, size.height * 0.18)
      ..lineTo(size.width * 0.9, size.height * 0.5)
      ..lineTo(size.width * 0.42, size.height * 0.82)
      ..close();

    canvas.drawPath(p, body);
    canvas.drawCircle(
      Offset(size.width * 0.44, size.height * 0.5),
      size.height * 0.12,
      detail,
    );
  }

  @override
  bool shouldRepaint(covariant _EnemyPainter oldDelegate) => false;
}

class _ObstacleWidget extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _ObstacleWidget({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            blurRadius: 6,
            color: Color(0x22000000),
            offset: Offset(2, 3),
          ),
        ],
      ),
    );
  }
}
