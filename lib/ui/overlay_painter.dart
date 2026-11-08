import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ar/ar_frame.dart';
import '../ar/projector.dart';
import '../measure/geometry.dart';
import '../measure/measure_controller.dart';
import '../measure/units.dart';
import 'theme.dart';

/// Draws the reticle, points, lines and labels over the camera feed.
///
/// It repaints on every AR frame by listening to the frame notifier directly, so the widget
/// tree is never rebuilt at camera rate.
class OverlayPainter extends CustomPainter {
  OverlayPainter(this.c) : super(repaint: Listenable.merge([c.frame, c]));

  final MeasureController c;

  static const _lineWidth = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final f = c.frame.value;
    if (f == null || f.tracking != ArTracking.tracking) {
      _drawIdleReticle(canvas, size, f);
      return;
    }
    final proj = Projector(f, size);

    for (final s in c.done) {
      _drawShape(canvas, proj, f, s, null);
    }
    _drawShape(canvas, proj, f, c.current, c.hud.canPlace ? c.reticle : null);
    _drawReticle(canvas, proj, f, size);
  }

  // --- Shapes ------------------------------------------------------------------------------

  void _drawShape(Canvas canvas, Projector proj, ArFrame f, Shape s, Vec3? live) {
    // Placed points, in order. A null means ARCore has lost that anchor for now.
    if (s.mode == MeasureMode.volume) {
      _drawVolume(canvas, proj, s, live);
      return;
    }
    final placed = <Vec3?>[for (final id in s.ids) c.pointOf(s, id)];
    final pts = <Vec3?>[...placed, if (live != null && !s.isComplete) live];
    if (pts.isEmpty) return;
    final liveIndex = (live != null && !s.isComplete) ? pts.length - 1 : -1;
    final units = c.units;

    // Area fill first, so lines and dots sit on top.
    if (s.mode == MeasureMode.area && pts.length >= 3 && pts.every((p) => p != null)) {
      final screen = [for (final p in pts) proj.project(p!)];
      if (screen.every((o) => o != null)) {
        final path = Path()..addPolygon(screen.cast<Offset>(), true);
        canvas.drawPath(path, Paint()..color = kAccent.withValues(alpha: 0.20));
      }
    }

    // Edges.
    final edges = <(int, int)>[
      for (var i = 0; i + 1 < pts.length; i++) (i, i + 1),
      if (s.mode == MeasureMode.area && s.closed && pts.length > 2) (pts.length - 1, 0),
    ];
    for (final (i, j) in edges) {
      final a = pts[i], b = pts[j];
      if (a == null || b == null) continue;
      final seg = proj.projectSegment(a, b);
      if (seg == null) continue;
      final isLive = j == liveIndex;
      _line(canvas, seg.$1, seg.$2, isLive ? kAccent : Colors.white, dashed: isLive);
      // Angle shows its value at the corner instead of on the edges.
      if (s.mode != MeasureMode.angle && (seg.$1 - seg.$2).distance > 56) {
        _label(canvas, proj.size, (seg.$1 + seg.$2) / 2, formatLength(a.distanceTo(b), units), accent: isLive);
      }
    }
    // Dashed closing hint for an open polygon.
    if (s.mode == MeasureMode.area && !s.closed && liveIndex > 1) {
      final a = pts[liveIndex], b = pts[0];
      if (a != null && b != null) {
        final seg = proj.projectSegment(a, b);
        if (seg != null) _line(canvas, seg.$1, seg.$2, kAccent.withValues(alpha: 0.6), dashed: true);
      }
    }

    // Angle arc + value.
    if (s.mode == MeasureMode.angle && pts.length >= 3 && pts[0] != null && pts[1] != null && pts[2] != null) {
      _angleArc(canvas, proj, pts[0]!, pts[1]!, pts[2]!, accent: liveIndex == 2);
    }

    // Area value at the centroid.
    if (s.mode == MeasureMode.area && pts.length >= 3 && pts.every((p) => p != null)) {
      final all = pts.cast<Vec3>();
      final p = proj.project(centroid(all));
      if (p != null) _label(canvas, proj.size, p, formatArea(polygonArea(all), units), accent: liveIndex >= 0, large: true);
    }

    // Placed points on top.
    for (final p in placed) {
      if (p == null) continue;
      final o = proj.project(p);
      if (o != null) _dot(canvas, o);
    }
  }

  /// Volume: floor outline, then a box up to the height point.
  void _drawVolume(Canvas canvas, Projector proj, Shape s, Vec3? live) {
    final placed = <Vec3?>[for (final id in s.ids) c.pointOf(s, id)];
    final heightPhase = s.closed;
    final basePlaced = heightPhase ? placed.take(s.baseCount).toList() : placed;
    final Vec3? top = heightPhase
        ? (placed.length > s.baseCount ? placed[s.baseCount] : live)
        : null;
    final liveCorner = !heightPhase && live != null;
    final base = <Vec3?>[...basePlaced, if (liveCorner) live];
    if (base.isEmpty) return;
    final allKnown = base.every((p) => p != null);
    final units = c.units;

    // Floor fill.
    if (allKnown && base.length >= 3) {
      final screen = [for (final p in base) proj.project(p!)];
      if (screen.every((o) => o != null)) {
        canvas.drawPath(
          Path()..addPolygon(screen.cast<Offset>(), true),
          Paint()..color = kAccent.withValues(alpha: heightPhase ? 0.12 : 0.20),
        );
      }
    }

    // Floor edges (the last one is the live one while outlining).
    final n = base.length;
    for (var i = 0; i + 1 < n; i++) {
      final a = base[i], b = base[i + 1];
      if (a == null || b == null) continue;
      final seg = proj.projectSegment(a, b);
      if (seg == null) continue;
      final isLive = liveCorner && i + 1 == n - 1;
      _line(canvas, seg.$1, seg.$2, isLive ? kAccent : Colors.white, dashed: isLive);
      if ((seg.$1 - seg.$2).distance > 56) {
        _label(canvas, proj.size, (seg.$1 + seg.$2) / 2, formatLength(a.distanceTo(b), units), accent: isLive);
      }
    }
    if (n >= 3 && base.first != null && base.last != null) {
      final seg = proj.projectSegment(base.last!, base.first!);
      if (seg != null) {
        if (heightPhase) {
          _line(canvas, seg.$1, seg.$2, Colors.white);
          if ((seg.$1 - seg.$2).distance > 56) {
            _label(canvas, proj.size, (seg.$1 + seg.$2) / 2, formatLength(base.last!.distanceTo(base.first!), units));
          }
        } else if (liveCorner) {
          _line(canvas, seg.$1, seg.$2, kAccent.withValues(alpha: 0.6), dashed: true);
        }
      }
    }

    // The box.
    if (heightPhase && top != null && allKnown && n >= 3) {
      final b = base.cast<Vec3>();
      final floorY = b.fold<double>(0, (a, p) => a + p.y) / n;
      final h = top.y - floorY;
      final up = Vec3(0, h, 0);
      final heightIsLive = s.ids.length == s.baseCount;
      final color = heightIsLive ? kAccent : Colors.white;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        final side = proj.projectSegment(b[i], b[i] + up);
        if (side != null) _line(canvas, side.$1, side.$2, color.withValues(alpha: 0.55));
        final lid = proj.projectSegment(b[i] + up, b[j] + up);
        if (lid != null) _line(canvas, lid.$1, lid.$2, color);
      }
      final mid = proj.project(midpoint(b.first, b.first + up));
      if (mid != null) _label(canvas, proj.size, mid, formatLength(h.abs(), units), accent: heightIsLive);
      final lidCenter = proj.project(centroid(b) + up);
      if (lidCenter != null) {
        _label(canvas, proj.size, lidCenter, formatVolume(polygonAreaXZ(b) * h.abs(), units),
            accent: heightIsLive, large: true);
      }
    }

    for (final p in placed) {
      if (p == null) continue;
      final o = proj.project(p);
      if (o != null) _dot(canvas, o);
    }
  }

  void _angleArc(Canvas canvas, Projector proj, Vec3 a, Vec3 v, Vec3 b, {required bool accent}) {
    final sv = proj.project(v), sa = proj.project(a), sb = proj.project(b);
    if (sv == null || sa == null || sb == null) return;
    final a1 = (sa - sv).direction;
    final a2 = (sb - sv).direction;
    var sweep = a2 - a1;
    while (sweep > math.pi) {
      sweep -= 2 * math.pi;
    }
    while (sweep < -math.pi) {
      sweep += 2 * math.pi;
    }
    const r = 30.0;
    canvas.drawArc(
      Rect.fromCircle(center: sv, radius: r),
      a1,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = accent ? kAccent : Colors.white,
    );
    final mid = a1 + sweep / 2;
    final at = sv + Offset(math.cos(mid), math.sin(mid)) * (r + 30);
    _label(canvas, proj.size, at, formatAngle(angleDegrees(a, v, b)), accent: accent);
  }

  // --- Reticle -----------------------------------------------------------------------------

  void _drawReticle(Canvas canvas, Projector proj, ArFrame f, Size size) {
    final hit = c.reticle;
    if (hit == null || !f.hasHit) {
      _drawIdleReticle(canvas, size, f);
      return;
    }
    final snapping = c.snapId != null;
    final ready = c.hud.canPlace;
    final color = snapping ? kAccent : (ready ? Colors.white : Colors.white54);

    // A ring lying *on the surface*, so you can see how the surface is oriented and how
    // big a given distance is at that depth.
    var n = f.hitNormal;
    if (n.length < 0.5) n = const Vec3(0, 1, 0);
    n = n.normalized();
    final helper = n.y.abs() < 0.9 ? const Vec3(0, 1, 0) : const Vec3(1, 0, 0);
    final t1 = n.cross(helper).normalized();
    final t2 = n.cross(t1).normalized();
    final radius = (f.hitDistance * 0.03).clamp(0.012, 0.08);

    final path = Path();
    var started = false;
    for (var i = 0; i <= 32; i++) {
      final a = i / 32 * 2 * math.pi;
      final p = hit + t1.scale(math.cos(a) * radius) + t2.scale(math.sin(a) * radius);
      final o = proj.project(p);
      if (o == null) continue;
      if (!started) {
        path.moveTo(o.dx, o.dy);
        started = true;
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    if (started) {
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.12));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = snapping ? 3.5 : 2.5
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }
    final center = proj.project(hit);
    if (center != null) {
      canvas.drawCircle(center, snapping ? 5 : 3.5, Paint()..color = color);
    }
  }

  /// Reticle shown while there is nothing to aim at: a faint dashed ring at screen centre.
  void _drawIdleReticle(Canvas canvas, Size size, ArFrame? f) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.45);
    const n = 14;
    for (var i = 0; i < n; i++) {
      final a0 = i / n * 2 * math.pi;
      canvas.drawArc(Rect.fromCircle(center: center, radius: 22), a0, math.pi / n, false, paint);
    }
    canvas.drawCircle(center, 2.5, Paint()..color = Colors.white.withValues(alpha: 0.6));
  }

  // --- Primitives --------------------------------------------------------------------------

  void _line(Canvas canvas, Offset a, Offset b, Color color, {bool dashed = false}) {
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _lineWidth + 3
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.28);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _lineWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    if (!dashed) {
      canvas.drawLine(a, b, shadow);
      canvas.drawLine(a, b, paint);
      return;
    }
    final total = (b - a).distance;
    if (total < 1) return;
    final dir = (b - a) / total;
    const dash = 9.0, gap = 7.0;
    for (var d = 0.0; d < total; d += dash + gap) {
      final p0 = a + dir * d;
      final p1 = a + dir * math.min(d + dash, total);
      canvas.drawLine(p0, p1, shadow);
      canvas.drawLine(p0, p1, paint);
    }
  }

  void _dot(Canvas canvas, Offset o) {
    canvas.drawCircle(o, 9, Paint()..color = Colors.black.withValues(alpha: 0.30));
    canvas.drawCircle(o, 6.5, Paint()..color = Colors.white);
  }

  void _label(Canvas canvas, Size bounds, Offset center, String text,
      {bool accent = false, bool large = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: accent ? Colors.black : Colors.white,
          fontSize: large ? 16 : 13,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final padH = large ? 12.0 : 9.0, padV = large ? 6.0 : 4.5;
    var rect = Rect.fromCenter(center: center, width: tp.width + padH * 2, height: tp.height + padV * 2);
    // Keep labels on screen.
    final dx = rect.left < 8 ? 8 - rect.left : (rect.right > bounds.width - 8 ? bounds.width - 8 - rect.right : 0.0);
    rect = rect.shift(Offset(dx, 0));
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    canvas.drawRRect(rr, Paint()..color = accent ? kAccent : const Color(0xCC111418));
    tp.paint(canvas, Offset(rect.left + padH, rect.top + padV));
  }

  @override
  bool shouldRepaint(OverlayPainter old) => old.c != c;
}
