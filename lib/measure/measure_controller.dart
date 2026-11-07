import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../ar/ar_backend.dart';
import '../ar/ar_frame.dart';
import 'geometry.dart';
import 'units.dart';

enum MeasureMode { distance, area, angle }

extension MeasureModeX on MeasureMode {
  String get label => switch (this) {
        MeasureMode.distance => 'Distance',
        MeasureMode.area => 'Area',
        MeasureMode.angle => 'Angle',
      };

  /// Number of points that completes the shape, or null if the user decides (area).
  int? get autoCompleteAt => switch (this) {
        MeasureMode.distance => 2,
        MeasureMode.angle => 3,
        MeasureMode.area => null,
      };
}

/// A measurement made of anchor ids. For [MeasureMode.angle] the order is
/// `[end, corner, end]`.
class Shape {
  Shape(this.mode);

  final MeasureMode mode;
  final List<int> ids = [];
  bool closed = false; // only meaningful for area

  bool get isComplete => mode == MeasureMode.area ? closed : ids.length >= mode.autoCompleteAt!;
}

/// Everything the HUD widgets display. A record, so `==` compares by value and the UI is
/// only rebuilt when something visible actually changed.
typedef Hud = ({
  String hint,
  bool hintIsWarning,
  String? value,
  String? sub,
  bool canPlace,
  bool snapping,
  int quality, // 0 unknown, 1 low, 2 fair, 3 good
  int depth, // 0 none, 1 depth API, 2 ToF
  bool canFinish,
  bool canUndo,
});

const Hud _initialHud = (
  hint: 'Starting camera…',
  hintIsWarning: false,
  value: null,
  sub: null,
  canPlace: false,
  snapping: false,
  quality: 0,
  depth: 0,
  canFinish: false,
  canUndo: false,
);

class MeasureController extends ChangeNotifier {
  MeasureController(this.ar, {this.haptics = true});

  final ArBackend ar;
  final bool haptics;

  /// Latest AR frame. The overlay painter listens to this directly (30 Hz) without
  /// rebuilding any widgets.
  final ValueNotifier<ArFrame?> frame = ValueNotifier(null);

  MeasureMode mode = MeasureMode.distance;
  UnitSystem units = UnitSystem.metric;
  final List<Shape> done = [];
  Shape current = Shape(MeasureMode.distance);

  Hud hud = _initialHud;

  /// Developer readout of camera/view sizes and hit quality; toggled by long-pressing the
  /// accuracy pill.
  bool showDebug = false;

  void toggleDebug() {
    showDebug = !showDebug;
    notifyListeners();
  }

  /// Anchor id the reticle is currently snapped to (an existing point), if any.
  int? snapId;

  /// Where a tap would place a point right now: the snapped point or the surface hit.
  Vec3? reticle;

  // Accuracy limits (metres from the camera).
  static const minRange = 0.15;
  static const goodRange = 3.0;
  static const maxRange = 6.0;

  StreamSubscription<ArFrame>? _sub;
  bool _busy = false;

  void start() {
    _sub ??= ar.frames.listen(onFrame);
  }

  // --- Frame handling ----------------------------------------------------------------------

  @visibleForTesting
  void onFrame(ArFrame f) {
    frame.value = f;

    final previousSnap = snapId;
    _updateReticle(f);
    if (snapId != null && snapId != previousSnap && haptics) {
      HapticFeedback.selectionClick();
    }

    final next = _buildHud(f);
    if (next != hud) {
      hud = next;
      notifyListeners();
    }
  }

  void _updateReticle(ArFrame f) {
    snapId = null;
    reticle = f.hitPosition;
    final hit = reticle;
    if (hit == null) return;

    // Magnetic snapping to existing points - lets you close a shape or start a new
    // measurement exactly at a previous corner. The radius grows with distance because
    // aiming precision shrinks with it.
    final radius = (f.hitDistance * 0.03).clamp(0.015, 0.08);
    var best = radius;
    for (final id in _allIds) {
      final p = f.anchors[id];
      if (p == null) continue;
      final d = p.distanceTo(hit);
      if (d < best) {
        best = d;
        snapId = id;
        reticle = p;
      }
    }
  }

  Iterable<int> get _allIds sync* {
    for (final s in done) {
      yield* s.ids;
    }
    yield* current.ids;
  }

  // --- Measurement values ------------------------------------------------------------------

  Shape? get _activeShape {
    if (current.ids.isNotEmpty) return current;
    return done.isEmpty ? null : done.last;
  }

  List<Vec3> positionsOf(Shape s, {Vec3? extra}) {
    final f = frame.value;
    final pts = <Vec3>[
      if (f != null)
        for (final id in s.ids)
          if (f.anchors[id] != null) f.anchors[id]!,
    ];
    if (extra != null) pts.add(extra);
    return pts;
  }

  ({String value, String? sub})? _liveValue() {
    final s = _activeShape;
    if (s == null) return null;
    final live = s.isComplete ? null : reticle;
    final pts = positionsOf(s, extra: live);
    switch (s.mode) {
      case MeasureMode.distance:
        if (pts.length < 2) return null;
        final d = pts[0].distanceTo(pts[1]);
        return (
          value: formatLength(d, units),
          sub: formatLength(d, units.other),
        );
      case MeasureMode.angle:
        if (pts.length < 3) return null;
        return (value: formatAngle(angleDegrees(pts[0], pts[1], pts[2])), sub: null);
      case MeasureMode.area:
        if (pts.length < 3) return null;
        final closed = s.closed;
        return (
          value: formatArea(polygonArea(pts), units),
          sub: 'Perimeter ${formatLength(pathLength(pts, closed: closed || live != null), units)}',
        );
    }
  }

  // --- HUD ---------------------------------------------------------------------------------

  Hud _buildHud(ArFrame f) {
    final live = _liveValue();
    final canUndo = current.ids.isNotEmpty || done.isNotEmpty;
    final canFinish = mode == MeasureMode.area && current.ids.length >= 3;

    String hint;
    var warn = true;
    var canPlace = false;
    var quality = 0;

    if (f.tracking == ArTracking.error) {
      hint = 'AR could not start on this device';
    } else if (f.tracking != ArTracking.tracking) {
      hint = switch (f.failure) {
        ArFailure.lowLight => 'Too dark – add some light',
        ArFailure.fastMotion => 'Moving too fast – slow down',
        ArFailure.fewFeatures => 'Point at a surface with more detail',
        ArFailure.cameraBusy => 'Camera is in use by another app',
        _ => 'Move your phone slowly to get started',
      };
    } else if (f.scanProgress < 1) {
      // ARCore only knows true scale after seeing the scene from several positions.
      hint = 'Move your phone around to calibrate \u2013 ${(f.scanProgress * 100).round()}%';
    } else if (!f.hasHit) {
      hint = 'Move slowly to find a surface';
    } else if (f.hitDistance < minRange) {
      hint = 'Too close – move back a little';
    } else if (f.hitDistance > maxRange) {
      hint = 'Too far – move closer';
    } else {
      canPlace = true;
      quality = _quality(f);
      if (f.hitDistance > goodRange) {
        hint = 'Move closer for better accuracy';
      } else if (f.stability < 0.5 && snapId == null) {
        hint = 'Hold steady…';
      } else {
        hint = _modeHint();
        warn = false;
      }
    }

    return (
      hint: hint,
      hintIsWarning: warn,
      value: live?.value,
      sub: live?.sub,
      canPlace: canPlace,
      snapping: snapId != null,
      quality: quality,
      depth: f.depthLevel,
      canFinish: canFinish,
      canUndo: canUndo,
    );
  }

  /// 1 (low) .. 3 (good). Heuristic combining the factors that matter for ARCore accuracy.
  int _quality(ArFrame f) {
    var score = 3;
    if (f.hitDistance > goodRange) score--;
    if (f.hitDistance > 4.5) score--;
    if (f.stability < 0.6) score--;
    if (f.depthLevel == 0 && f.hitKind != HitKind.plane) score--;
    return math.max(1, score);
  }

  String _modeHint() {
    final n = current.ids.length;
    switch (mode) {
      case MeasureMode.distance:
        return n == 0 ? 'Aim at the start point, then tap +' : 'Aim at the end point, then tap +';
      case MeasureMode.angle:
        return switch (n) {
          0 => 'Tap + on the first end of the angle',
          1 => 'Tap + on the corner',
          _ => 'Tap + on the other end',
        };
      case MeasureMode.area:
        return n < 3 ? 'Tap + at each corner' : 'Tap + for more corners, or ✓ to finish';
    }
  }

  // --- Actions -----------------------------------------------------------------------------

  Future<void> place() async {
    if (!hud.canPlace || _busy) return;
    final snap = snapId;
    // Ignore a double tap on the point we just placed.
    if (snap != null && current.ids.isNotEmpty && snap == current.ids.last) return;

    // Tapping the first corner of a polygon closes it instead of adding a point.
    if (mode == MeasureMode.area && current.ids.length >= 3 && snap == current.ids.first) {
      finishArea();
      return;
    }

    _busy = true;
    try {
      final id = await ar.place(snapId: snap);
      if (id <= 0) {
        if (haptics) HapticFeedback.heavyImpact();
        return;
      }
      if (haptics) HapticFeedback.lightImpact();
      current.ids.add(id);
      final auto = mode.autoCompleteAt;
      if (auto != null && current.ids.length >= auto) {
        done.add(current);
        current = Shape(mode);
      }
      _refresh();
    } finally {
      _busy = false;
    }
  }

  void finishArea() {
    if (mode != MeasureMode.area || current.ids.length < 3) return;
    current.closed = true;
    done.add(current);
    current = Shape(mode);
    if (haptics) HapticFeedback.mediumImpact();
    _refresh();
  }

  void undo() {
    if (current.ids.isEmpty) {
      if (done.isEmpty) return;
      current = done.removeLast()..closed = false;
      mode = current.mode;
    }
    ar.remove(current.ids.removeLast());
    _refresh();
  }

  void clearAll() {
    ar.clear();
    done.clear();
    current = Shape(mode);
    _refresh();
  }

  void setMode(MeasureMode m) {
    if (m == mode) return;
    // An unfinished measurement is discarded; finished ones stay on screen.
    for (final id in current.ids) {
      ar.remove(id);
    }
    mode = m;
    current = Shape(m);
    _refresh();
  }

  void toggleUnits() {
    units = units.other;
    _refresh();
  }

  void _refresh() {
    final f = frame.value;
    if (f != null) {
      _updateReticle(f);
      hud = _buildHud(f);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    frame.dispose();
    super.dispose();
  }
}
