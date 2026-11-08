import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../ar/ar_backend.dart';
import '../ar/ar_frame.dart';
import '../storage/measurement_store.dart';
import '../storage/saved_measurement.dart';
import 'geometry.dart';
import 'units.dart';

enum MeasureMode { distance, area, volume, angle }

extension MeasureModeX on MeasureMode {
  String get label => switch (this) {
    MeasureMode.distance => 'Distance',
    MeasureMode.area => 'Area',
    MeasureMode.volume => 'Volume',
    MeasureMode.angle => 'Angle',
  };

  /// Number of points that completes the shape, or null if the user decides (area, volume).
  int? get autoCompleteAt => switch (this) {
    MeasureMode.distance => 2,
    MeasureMode.angle => 3,
    MeasureMode.area => null,
    MeasureMode.volume => null,
  };
}

/// A measurement made of anchor ids. For [MeasureMode.angle] the order is
/// `[end, corner, end]`.
class Shape {
  Shape(this.mode);

  final MeasureMode mode;
  final List<int> ids = [];

  /// Area/volume: the floor outline has been closed. For a volume the next point placed is
  /// then the height point.
  bool closed = false;

  /// Volume: how many of [ids] are floor corners (the height point comes after them).
  int baseCount = 0;

  /// Set when the outline was closed with "Close loop": how far the walk ended from where it
  /// started, and the length of the walk (both metres).
  ({double error, double path})? loop;

  /// Per-point corrections (world space, metres) from the loop closure.
  final Map<int, Vec3> adjust = {};

  /// Id of the saved copy of this measurement, once the user has saved it.
  String? savedId;

  bool get isComplete => switch (mode) {
    MeasureMode.area => closed,
    MeasureMode.volume => closed && ids.length > baseCount,
    _ => ids.length >= mode.autoCompleteAt!,
  };
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
  bool canCloseLoop,
  bool canUndo,
  bool canSave,
  bool isSaved,
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
  canCloseLoop: false,
  canUndo: false,
  canSave: false,
  isSaved: false,
);

/// A measurement in SI units, before formatting.
typedef Reading = ({
  MeasureMode mode,
  double value,
  double? secondary,
  List<double> edges,
  double? height, // volume only; null while the height has not been set yet
  ({double error, double path})? loop,
});

class MeasureController extends ChangeNotifier {
  MeasureController(this.ar, {required this.store, this.haptics = true});

  final ArBackend ar;
  final MeasurementStore store;

  /// Saved measurements, newest first.
  List<SavedMeasurement> saved = [];
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
    loadSaved();
  }

  Future<void> loadSaved() async {
    saved = await store.load();
    notifyListeners();
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
    for (final s in [...done, current]) {
      for (final id in s.ids) {
        final p = pointOf(s, id);
        if (p == null) continue;
        final d = p.distanceTo(hit);
        if (d < best) {
          best = d;
          snapId = id;
          reticle = p;
        }
      }
    }
  }

  // --- Measurement values ------------------------------------------------------------------

  Shape? get _activeShape {
    if (current.ids.isNotEmpty) return current;
    return done.isEmpty ? null : done.last;
  }

  /// World position of anchor [id] of shape [s], including any loop-closure correction.
  /// Null while ARCore is not tracking that anchor.
  Vec3? pointOf(Shape s, int id) {
    final p = frame.value?.anchors[id];
    if (p == null) return null;
    final a = s.adjust[id];
    return a == null ? p : p + a;
  }

  List<Vec3> positionsOf(Shape s, {Vec3? extra}) {
    final pts = <Vec3>[
      for (final id in s.ids) ?pointOf(s, id),
    ];
    if (extra != null) pts.add(extra);
    return pts;
  }

  /// SI-unit reading of [s], optionally with [extra] (the reticle) as a provisional last
  /// point. Null while there are not enough points yet.
  Reading? _reading(Shape s, {Vec3? extra}) {
    final pts = positionsOf(s, extra: extra);
    switch (s.mode) {
      case MeasureMode.distance:
        if (pts.length < 2) return null;
        final d = pts[0].distanceTo(pts[1]);
        return (
          mode: s.mode,
          value: d,
          secondary: null,
          edges: [d],
          height: null,
          loop: null,
        );
      case MeasureMode.angle:
        if (pts.length < 3) return null;
        return (
          mode: s.mode,
          value: angleDegrees(pts[0], pts[1], pts[2]),
          secondary: null,
          edges: [pts[0].distanceTo(pts[1]), pts[1].distanceTo(pts[2])],
          height: null,
          loop: null,
        );
      case MeasureMode.area:
        if (pts.length < 3) return null;
        final closed = s.closed || extra != null;
        final edges = [
          for (var i = 0; i + 1 < pts.length; i++)
            pts[i].distanceTo(pts[i + 1]),
          if (closed) pts.last.distanceTo(pts.first),
        ];
        return (
          mode: s.mode,
          value: polygonArea(pts),
          secondary: edges.fold<double>(0, (a, b) => a + b),
          edges: edges,
          height: null,
          loop: s.loop,
        );
      case MeasureMode.volume:
        // Still outlining the floor, or outline closed and the height point is next/placed.
        if (s.closed ? pts.length != s.baseCount + 1 : pts.length < 3) {
          return null;
        }
        final base = s.closed ? pts.sublist(0, s.baseCount) : pts;
        final edges = [
          for (var i = 0; i < base.length; i++)
            base[i].distanceTo(base[(i + 1) % base.length]),
        ];
        final floor = polygonAreaXZ(base);
        final perimeter = edges.fold<double>(0, (a, b) => a + b);
        if (!s.closed) {
          return (
            mode: s.mode,
            value: floor,
            secondary: perimeter,
            edges: edges,
            height: null,
            loop: s.loop,
          );
        }
        // Height = how far the top point is above (or below) the average floor level.
        final floorY = base.fold<double>(0, (a, p) => a + p.y) / base.length;
        final h = (pts.last.y - floorY).abs();
        return (
          mode: s.mode,
          value: floor * h,
          secondary: floor,
          edges: edges,
          height: h,
          loop: s.loop,
        );
    }
  }

  ({String value, String? sub})? _liveValue() {
    final s = _activeShape;
    if (s == null) return null;
    final r = _reading(s, extra: s.isComplete ? null : reticle);
    if (r == null) return null;
    switch (r.mode) {
      case MeasureMode.distance:
        return (
          value: formatLength(r.value, units),
          sub: formatLength(r.value, units.other),
        );
      case MeasureMode.angle:
        return (value: formatAngle(r.value), sub: null);
      case MeasureMode.area:
        return (
          value: formatArea(r.value, units),
          sub: 'Perimeter ${formatLength(r.secondary!, units)}',
        );
      case MeasureMode.volume:
        if (r.height == null) {
          return (
            value: formatArea(r.value, units),
            sub: 'Floor area \u00B7 finish the outline, then set height',
          );
        }
        return (
          value: formatVolume(r.value, units),
          sub:
              '${formatArea(r.secondary!, units)} \u00D7 ${formatLength(r.height!, units)}',
        );
    }
  }

  // --- Saving ------------------------------------------------------------------------------

  /// The finished measurement that is currently on display and has not been saved yet.
  Shape? get _savable {
    if (current.ids.isNotEmpty || done.isEmpty) return null;
    final s = done.last;
    return s.savedId == null ? s : null;
  }

  /// Saves the finished measurement on display. Returns null if there is nothing to save
  /// (still in progress, already saved, or an anchor is currently lost).
  Future<SavedMeasurement?> saveActive() async {
    final s = _savable;
    if (s == null) return null;
    if (positionsOf(s).length != s.ids.length) {
      return null; // an anchor is not tracked right now
    }
    final r = _reading(s);
    if (r == null) return null;
    final now = DateTime.now();
    final m = SavedMeasurement(
      id: now.microsecondsSinceEpoch.toString(),
      mode: r.mode,
      value: r.value,
      secondary: r.secondary,
      height: r.height,
      loopError: r.loop?.error,
      loopPath: r.loop?.path,
      edges: r.edges,
      createdAt: now,
    );
    await store.save(m);
    saved = [m, ...saved];
    s.savedId = m.id;
    if (haptics) HapticFeedback.mediumImpact();
    _refresh();
    return m;
  }

  Future<void> deleteSaved(String id) async {
    await store.delete(id);
    saved = [
      for (final m in saved)
        if (m.id != id) m,
    ];
    for (final s in done) {
      if (s.savedId == id) s.savedId = null;
    }
    _refresh();
  }

  /// Puts back an entry removed by [deleteSaved] (undo).
  Future<void> restoreSaved(SavedMeasurement m) async {
    await store.save(m);
    saved = [...saved, m]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<void> setNote(String id, String? note) async {
    final i = saved.indexWhere((m) => m.id == id);
    if (i < 0) return;
    final updated = saved[i].withNote(note);
    await store.save(updated);
    saved = [...saved]..[i] = updated;
    notifyListeners();
  }

  Future<void> clearSaved() async {
    await store.clear();
    saved = [];
    for (final s in done) {
      s.savedId = null;
    }
    _refresh();
  }

  // --- HUD ---------------------------------------------------------------------------------

  Hud _buildHud(ArFrame f) {
    final live = _liveValue();
    final canUndo = current.ids.isNotEmpty || done.isNotEmpty;
    final openOutline = _hasOutline && !current.closed && current.ids.length >= 3;
    final canFinish = openOutline;

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
      hint =
          'Move your phone around to calibrate \u2013 ${(f.scanProgress * 100).round()}%';
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
      canCloseLoop: openOutline && canPlace,
      canUndo: canUndo,
      canSave: _savable != null,
      isSaved:
          current.ids.isEmpty && done.isNotEmpty && done.last.savedId != null,
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
        return n == 0
            ? 'Aim at the start point, then tap +'
            : 'Aim at the end point, then tap +';
      case MeasureMode.angle:
        return switch (n) {
          0 => 'Tap + on the first end of the angle',
          1 => 'Tap + on the corner',
          _ => 'Tap + on the other end',
        };
      case MeasureMode.area:
        return n < 3
            ? 'Tap + at each corner'
            : 'Tap + for more corners, or the check button to finish';
      case MeasureMode.volume:
        if (current.closed) {
          return 'Aim at the top of the stack or the ceiling, then tap +';
        }
        return n < 3
            ? 'Tap + on each floor corner'
            : 'More corners, the check button to finish, or walk back and Close loop';
    }
  }

  // --- Actions -----------------------------------------------------------------------------

  Future<void> place() async {
    if (!hud.canPlace || _busy) return;
    final snap = snapId;
    // Ignore a double tap on the point we just placed.
    if (snap != null && current.ids.isNotEmpty && snap == current.ids.last) {
      return;
    }

    // Tapping the first corner of an outline closes it instead of adding a point.
    if (_hasOutline &&
        !current.closed &&
        current.ids.length >= 3 &&
        snap == current.ids.first) {
      finishOutline();
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
      if ((auto != null && current.ids.length >= auto) || current.isComplete) {
        done.add(current);
        current = Shape(mode);
      }
      _refresh();
    } finally {
      _busy = false;
    }
  }

  bool get _hasOutline =>
      mode == MeasureMode.area || mode == MeasureMode.volume;

  /// Closes the floor outline. An area is then finished; a volume waits for its height point.
  void finishOutline() {
    if (!_hasOutline || current.closed || current.ids.length < 3) return;
    current.closed = true;
    if (mode == MeasureMode.volume) {
      current.baseCount = current.ids.length;
    } else {
      done.add(current);
      current = Shape(mode);
    }
    if (haptics) HapticFeedback.mediumImpact();
    _refresh();
  }

  /// "Close loop": the user has walked back to the first corner and is aiming at it.
  ///
  /// Phone AR drifts a little with distance walked. Standing at the start again shows how
  /// much: the gap between where the reticle is and where the first corner was recorded.
  /// That gap is then spread along the walk in proportion to the distance covered
  /// (the "compass rule" surveyors use to adjust a closed traverse), so later corners move
  /// more than early ones, and the outline is closed.
  ///
  /// Returns the closure error and the length of the walk, or null if not possible now.
  ({double error, double path})? closeLoop() {
    final r = reticle;
    if (!hud.canPlace || r == null || !_hasOutline) return null;
    if (current.closed || current.ids.length < 3) return null;
    final pts = [for (final id in current.ids) pointOf(current, id)];
    if (pts.any((p) => p == null)) return null;
    final p = pts.cast<Vec3>();

    // Horizontal error only: the floor plan is what matters, and height is handled apart.
    final e = Vec3(r.x - p.first.x, 0, r.z - p.first.z);
    final cumulative = <double>[0];
    for (var i = 1; i < p.length; i++) {
      cumulative.add(cumulative.last + p[i - 1].distanceTo(p[i]));
    }
    final total = cumulative.last + p.last.distanceTo(r);
    if (total <= 0) return null;

    for (var i = 1; i < p.length; i++) {
      final id = current.ids[i];
      current.adjust[id] = (current.adjust[id] ?? Vec3.zero) -
          e.scale(cumulative[i] / total);
    }
    current.loop = (error: e.length, path: total);
    finishOutline();
    return current.loop ?? done.last.loop;
  }

  void _reopen(Shape s) {
    s.closed = false;
    s.baseCount = 0;
    s.loop = null;
    s.adjust.clear();
  }

  void undo() {
    if (current.ids.isEmpty) {
      if (done.isEmpty) return;
      current = done.removeLast()..savedId = null;
      mode = current.mode;
      // An area reopens as an outline; a volume goes back to waiting for its height point.
      if (current.mode == MeasureMode.area) _reopen(current);
    } else if (current.mode == MeasureMode.volume &&
        current.closed &&
        current.ids.length == current.baseCount) {
      _reopen(current); // outline was closed, no height yet: reopen the outline
      _refresh();
      return;
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
