import 'dart:math';
import 'dart:ui';

enum GamePhase {
  title,
  briefing,
  playing,
  missionComplete,
  gameOver,
  victory,
}

enum MissionBiome {
  ice,
  forest,
  desert,
}

enum ObstacleType {
  pillar,
  tree,
  rock,
  drone,
  gate,
}

class MissionConfig {
  final String name;
  final String subtitle;
  final MissionBiome biome;
  final Color skyTop;
  final Color skyBottom;
  final Color groundNear;
  final Color groundFar;
  final int targetDistance;
  final double baseSpeed;
  final double spawnRate;
  final double droneRate;
  final int bonusForCompletion;

  const MissionConfig({
    required this.name,
    required this.subtitle,
    required this.biome,
    required this.skyTop,
    required this.skyBottom,
    required this.groundNear,
    required this.groundFar,
    required this.targetDistance,
    required this.baseSpeed,
    required this.spawnRate,
    required this.droneRate,
    required this.bonusForCompletion,
  });
}

class PlayerShip {
  double x;
  double y;
  double health;
  double fireCooldown;
  bool alive;

  PlayerShip({
    this.x = 0,
    this.y = 0.72,
    this.health = 100,
    this.fireCooldown = 0,
    this.alive = true,
  });
}

class Obstacle {
  ObstacleType type;
  double laneX;
  double z;
  double width;
  double height;
  double speedFactor;
  bool active;
  bool passed;
  int hp;

  Obstacle({
    required this.type,
    required this.laneX,
    required this.z,
    required this.width,
    required this.height,
    this.speedFactor = 1.0,
    this.active = true,
    this.passed = false,
    this.hp = 1,
  });
}

class Bullet {
  double x;
  double y;
  double z;
  bool active;

  Bullet({
    required this.x,
    required this.y,
    required this.z,
    this.active = true,
  });
}

class StarPoint {
  double x;
  double y;
  double speed;

  StarPoint({
    required this.x,
    required this.y,
    required this.speed,
  });
}

class Explosion {
  double x;
  double y;
  double t;
  bool active;

  Explosion({
    required this.x,
    required this.y,
    this.t = 0,
    this.active = true,
  });
}

class HudSnapshot {
  final int score;
  final int missionIndex;
  final int totalMissions;
  final int distance;
  final int targetDistance;
  final double health;
  final GamePhase phase;
  final String phaseText;

  const HudSnapshot({
    required this.score,
    required this.missionIndex,
    required this.totalMissions,
    required this.distance,
    required this.targetDistance,
    required this.health,
    required this.phase,
    required this.phaseText,
  });
}

class GameMath {
  static double clamp(double v, double min, double max) {
    if (v < min) return min;
    if (v > max) return max;
    return v;
  }

  static double lerp(double a, double b, double t) => a + (b - a) * t;

  static final Random rng = Random();
}
