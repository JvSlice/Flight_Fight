import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'game_models.dart';

class GamePainter extends CustomPainter {
  final MissionConfig mission;
  final PlayerShip player;
  final List<Obstacle> obstacles;
  final List<Bullet> bullets;
  final List<StarPoint> stars;
  final List<Explosion> explosions;
  final double worldSpeed;
  final double difficulty;
  final bool showAimLines;

  GamePainter({
    required this.mission,
    required this.player,
    required this.obstacles,
    required this.bullets,
    required this.stars,
    required this.explosions,
    required this.worldSpeed,
    required this.difficulty,
    required this.showAimLines,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    _paintStars(canvas, size);
    _paintHorizon(canvas, size);
    _paintRunwayGuides(canvas, size);

    final sorted = [...obstacles]..sort((a, b) => b.z.compareTo(a.z));
    for (final obstacle in sorted) {
      _paintObstacle(canvas, size, obstacle);
    }

    for (final bullet in bullets) {
      _paintBullet(canvas, size, bullet);
    }

    for (final explosion in explosions) {
      _paintExplosion(canvas, size, explosion);
    }

    _paintPlayer(canvas, size);

    if (showAimLines) {
      _paintAimAssist(canvas, size);
    }
  }

  void _paintBackground(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sky = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, 0),
        Offset(0, size.height * 0.65),
        [mission.skyTop, mission.skyBottom],
      );
    canvas.drawRect(rect, sky);

    final groundRect = Rect.fromLTWH(
      0,
      size.height * 0.55,
      size.width,
      size.height * 0.45,
    );
    final ground = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, size.height * 0.55),
        Offset(0, size.height),
        [mission.groundFar, mission.groundNear],
      );
    canvas.drawRect(groundRect, ground);
  }

  void _paintStars(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.7);
    for (final s in stars) {
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height * 0.55),
        1.2 + s.speed * 0.6,
        paint,
      );
    }
  }

  void _paintHorizon(Canvas canvas, Size size) {
    final y = size.height * 0.55;
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);

    switch (mission.biome) {
      case MissionBiome.ice:
        _paintIceMountains(canvas, size);
        break;
      case MissionBiome.forest:
        _paintForestSilhouette(canvas, size);
        break;
      case MissionBiome.desert:
        _paintDesertDunes(canvas, size);
        break;
    }
  }

  void _paintIceMountains(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, size.height * 0.55);
    final peaks = [
      Offset(size.width * 0.08, size.height * 0.42),
      Offset(size.width * 0.18, size.height * 0.50),
      Offset(size.width * 0.32, size.height * 0.38),
      Offset(size.width * 0.46, size.height * 0.49),
      Offset(size.width * 0.62, size.height * 0.40),
      Offset(size.width * 0.82, size.height * 0.48),
      Offset(size.width, size.height * 0.44),
    ];
    for (final p in peaks) {
      path.lineTo(p.dx, p.dy);
    }
    path.lineTo(size.width, size.height * 0.55);
    path.close();

    canvas.drawPath(
      path,
      Paint()..color = const Color(0x99DDF4FF),
    );
  }

  void _paintForestSilhouette(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x66233A22);
    for (int i = 0; i < 18; i++) {
      final x = i / 17 * size.width;
      final h = 40 + (i % 5) * 18.0;
      final tree = Path()
        ..moveTo(x - 16, size.height * 0.55)
        ..lineTo(x, size.height * 0.55 - h)
        ..lineTo(x + 16, size.height * 0.55)
        ..close();
      canvas.drawPath(tree, paint);
    }
  }

  void _paintDesertDunes(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, size.height * 0.55);
    for (int i = 0; i <= 8; i++) {
      final x = i / 8 * size.width;
      final y = size.height * (0.52 + sin(i * 0.8) * 0.02);
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height * 0.55);
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = const Color(0x55FFD27A),
    );
  }

  void _paintRunwayGuides(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final horizonY = size.height * 0.55;
    final bottomY = size.height;

    final guide = Paint()
      ..color = Colors.white.withOpacity(0.14)
      ..strokeWidth = 2;

    canvas.drawLine(Offset(centerX - size.width * 0.28, bottomY),
        Offset(centerX - size.width * 0.08, horizonY), guide);
    canvas.drawLine(Offset(centerX + size.width * 0.28, bottomY),
        Offset(centerX + size.width * 0.08, horizonY), guide);

    for (int i = 0; i < 7; i++) {
      final t = i / 6;
      final y = GameMath.lerp(horizonY + 20, bottomY - 40, pow(t, 1.45).toDouble());
      final halfW = GameMath.lerp(size.width * 0.03, size.width * 0.24, t);
      canvas.drawLine(
        Offset(centerX - halfW, y),
        Offset(centerX + halfW, y),
        guide,
      );
    }
  }

  void _paintObstacle(Canvas canvas, Size size, Obstacle o) {
    final screen = _project(size, o.laneX, o.z, 0.72);
    final scale = _scaleForZ(o.z);
    final w = o.width * scale * size.width;
    final h = o.height * scale * size.height;

    switch (o.type) {
      case ObstacleType.pillar:
        final rect = Rect.fromCenter(
          center: Offset(screen.dx, screen.dy - h * 0.5),
          width: w,
          height: h,
        );
        final paint = Paint()..color = const Color(0xFFBBD2E1);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          paint,
        );
        canvas.drawRect(
          Rect.fromLTWH(rect.left + w * 0.15, rect.top + h * 0.08, w * 0.18, h * 0.84),
          Paint()..color = Colors.white.withOpacity(0.25),
        );
        break;

      case ObstacleType.tree:
        final trunk = Rect.fromCenter(
          center: Offset(screen.dx, screen.dy - h * 0.28),
          width: w * 0.22,
          height: h * 0.55,
        );
        canvas.drawRect(trunk, Paint()..color = const Color(0xFF654321));
        final crown = Path()
          ..moveTo(screen.dx, screen.dy - h)
          ..lineTo(screen.dx - w * 0.7, screen.dy - h * 0.3)
          ..lineTo(screen.dx + w * 0.7, screen.dy - h * 0.3)
          ..close();
        canvas.drawPath(crown, Paint()..color = const Color(0xFF2F8F4E));
        break;

      case ObstacleType.rock:
        final path = Path()
          ..moveTo(screen.dx - w * 0.55, screen.dy)
          ..lineTo(screen.dx - w * 0.35, screen.dy - h * 0.65)
          ..lineTo(screen.dx + w * 0.15, screen.dy - h * 0.85)
          ..lineTo(screen.dx + w * 0.55, screen.dy - h * 0.35)
          ..lineTo(screen.dx + w * 0.45, screen.dy)
          ..close();
        canvas.drawPath(path, Paint()..color = const Color(0xFFC08F5A));
        break;

      case ObstacleType.drone:
        _paintDrone(canvas, screen, w, h);
        break;

      case ObstacleType.gate:
        final left = Rect.fromCenter(
          center: Offset(screen.dx - w * 0.8, screen.dy - h * 0.5),
          width: w * 0.32,
          height: h,
        );
        final right = Rect.fromCenter(
          center: Offset(screen.dx + w * 0.8, screen.dy - h * 0.5),
          width: w * 0.32,
          height: h,
        );
        final topBar = Rect.fromCenter(
          center: Offset(screen.dx, screen.dy - h * 0.95),
          width: w * 1.95,
          height: h * 0.22,
        );
        final paint = Paint()..color = const Color(0xFFFFC857);
        canvas.drawRect(left, paint);
        canvas.drawRect(right, paint);
        canvas.drawRect(topBar, paint);
        break;
    }
  }

  void _paintDrone(Canvas canvas, Offset center, double w, double h) {
    final bodyPaint = Paint()..color = const Color(0xFFE96B6B);
    final wingPaint = Paint()..color = const Color(0xFFB84D4D);
    final cockpit = Paint()..color = const Color(0xFF9EE7FF);

    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(center.dx, center.dy - h * 0.45), width: w * 0.44, height: h * 0.42),
      const Radius.circular(8),
    );
    canvas.drawRRect(body, bodyPaint);

    final leftWing = Path()
      ..moveTo(center.dx - w * 0.2, center.dy - h * 0.42)
      ..lineTo(center.dx - w * 0.95, center.dy - h * 0.18)
      ..lineTo(center.dx - w * 0.35, center.dy - h * 0.06)
      ..close();
    final rightWing = Path()
      ..moveTo(center.dx + w * 0.2, center.dy - h * 0.42)
      ..lineTo(center.dx + w * 0.95, center.dy - h * 0.18)
      ..lineTo(center.dx + w * 0.35, center.dy - h * 0.06)
      ..close();
    canvas.drawPath(leftWing, wingPaint);
    canvas.drawPath(rightWing, wingPaint);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy - h * 0.48),
        width: w * 0.18,
        height: h * 0.16,
      ),
      cockpit,
    );
  }

  void _paintBullet(Canvas canvas, Size size, Bullet b) {
    final p = _project(size, b.x, b.z, b.y);
    final scale = _scaleForZ(b.z);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: p,
          width: 4 * scale * size.width * 0.02,
          height: 10 * scale * size.height * 0.03,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF7FDBFF),
    );
  }

  void _paintExplosion(Canvas canvas, Size size, Explosion e) {
    final p = Offset(size.width * (0.5 + e.x * 0.33), size.height * e.y);
    final r = 10 + e.t * 36;
    final alpha = (1.0 - e.t).clamp(0.0, 1.0);
    canvas.drawCircle(
      p,
      r,
      Paint()..color = Colors.orange.withOpacity(alpha * 0.55),
    );
    canvas.drawCircle(
      p,
      r * 0.55,
      Paint()..color = Colors.yellow.withOpacity(alpha * 0.85),
    );
  }

  void _paintPlayer(Canvas canvas, Size size) {
    final x = size.width * (0.5 + player.x * 0.33);
    final y = size.height * player.y;
    final scale = size.width * 0.11;

    // HACKABLE NOTE:
    // This ship is intentionally original. Easy to tweak:
    // - nose length
    // - wing angle
    // - engine glow
    final body = Path()
      ..moveTo(x, y - scale * 0.55)
      ..lineTo(x - scale * 0.18, y + scale * 0.18)
      ..lineTo(x, y + scale * 0.05)
      ..lineTo(x + scale * 0.18, y + scale * 0.18)
      ..close();

    final leftWing = Path()
      ..moveTo(x - scale * 0.12, y)
      ..lineTo(x - scale * 0.72, y + scale * 0.18)
      ..lineTo(x - scale * 0.26, y + scale * 0.34)
      ..close();

    final rightWing = Path()
      ..moveTo(x + scale * 0.12, y)
      ..lineTo(x + scale * 0.72, y + scale * 0.18)
      ..lineTo(x + scale * 0.26, y + scale * 0.34)
      ..close();

    final engineLeft = Rect.fromCenter(
      center: Offset(x - scale * 0.2, y + scale * 0.18),
      width: scale * 0.12,
      height: scale * 0.28,
    );
    final engineRight = Rect.fromCenter(
      center: Offset(x + scale * 0.2, y + scale * 0.18),
      width: scale * 0.12,
      height: scale * 0.28,
    );

    canvas.drawPath(leftWing, Paint()..color = const Color(0xFF98AFC7));
    canvas.drawPath(rightWing, Paint()..color = const Color(0xFF98AFC7));
    canvas.drawPath(body, Paint()..color = const Color(0xFFE5EEF7));

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x, y - scale * 0.18),
        width: scale * 0.14,
        height: scale * 0.18,
      ),
      Paint()..color = const Color(0xFF9EE7FF),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(engineLeft, const Radius.circular(3)),
      Paint()..color = const Color(0xFF6C7B8B),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(engineRight, const Radius.circular(3)),
      Paint()..color = const Color(0xFF6C7B8B),
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x - scale * 0.2, y + scale * 0.36),
        width: scale * 0.08,
        height: scale * 0.22,
      ),
      Paint()..color = const Color(0x667FDBFF),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(x + scale * 0.2, y + scale * 0.36),
        width: scale * 0.08,
        height: scale * 0.22,
      ),
      Paint()..color = const Color(0x667FDBFF),
    );
  }

  void _paintAimAssist(Canvas canvas, Size size) {
    final x = size.width * (0.5 + player.x * 0.33);
    final y = size.height * player.y - size.width * 0.08;

    final paint = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..strokeWidth = 1.5;

    canvas.drawLine(Offset(x, y), Offset(x, size.height * 0.20), paint);
    canvas.drawCircle(
      Offset(x, size.height * 0.22),
      12,
      paint..style = PaintingStyle.stroke,
    );
  }

  Offset _project(Size size, double laneX, double z, double yBase) {
    final perspective = _scaleForZ(z);
    final screenX = size.width * (0.5 + laneX * 0.34 * perspective);
    final horizonY = size.height * 0.55;
    final groundY = size.height * yBase;
    final screenY = GameMath.lerp(horizonY, groundY, perspective);
    return Offset(screenX, screenY);
  }

  double _scaleForZ(double z) {
    return (1.0 - z).clamp(0.08, 1.0);
  }

  @override
  bool shouldRepaint(covariant GamePainter oldDelegate) => true;
}
