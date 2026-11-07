import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ar_measure/ar/ar_backend.dart';
import 'package:ar_measure/ar/ar_frame.dart';

/// Builds an [ArFrame] the way the native side would, with an identity-ish camera looking
/// down -Z and a simple perspective projection.
ArFrame makeFrame({
  double? hitX,
  double hitY = 0,
  double hitZ = -1,
  HitKind kind = HitKind.plane,
  double distance = 1.0,
  double stability = 1.0,
  int tracking = 1,
  int failure = 0,
  int depth = 1,
  Map<int, List<double>> anchors = const {},
}) {
  final out = Float32List(ArFrame.header + anchors.length * 4);
  out[0] = tracking.toDouble();
  out[1] = failure.toDouble();
  out[2] = depth.toDouble();
  if (hitX != null) {
    out[3] = kind.index.toDouble();
    out[4] = distance;
    out[5] = hitX;
    out[6] = hitY;
    out[7] = hitZ;
    out[9] = 1; // normal = +Y
  }
  out[11] = stability;
  out[12] = anchors.length.toDouble();
  // View = identity.
  for (var i = 0; i < 4; i++) {
    out[13 + i * 5] = 1;
  }
  // Projection: 90 degree fov, square viewport, near 0.1, far 100 (OpenGL convention).
  const n = 0.1, f = 100.0;
  out[29] = 1;
  out[29 + 5] = 1;
  out[29 + 10] = -(f + n) / (f - n);
  out[29 + 11] = -1;
  out[29 + 14] = -2 * f * n / (f - n);
  var o = ArFrame.header;
  anchors.forEach((id, p) {
    out[o] = id.toDouble();
    out[o + 1] = p[0];
    out[o + 2] = p[1];
    out[o + 3] = p[2];
    o += 4;
  });
  return ArFrame(out);
}

class FakeAr implements ArBackend {
  final _frames = StreamController<ArFrame>.broadcast();
  final placed = <int>[];
  final removed = <int>[];
  final snaps = <int?>[];
  bool cleared = false;
  int _next = 1;
  int nextResult = 0; // 0 = hand out ids; otherwise return this

  void emit(ArFrame f) => _frames.add(f);

  @override
  Stream<ArFrame> get frames => _frames.stream;

  @override
  Future<ArAvailability> ensureArCore() async => ArAvailability.ready;

  @override
  Future<int> place({int? snapId}) async {
    snaps.add(snapId);
    if (nextResult != 0) return nextResult;
    final id = _next++;
    placed.add(id);
    return id;
  }

  @override
  Future<void> remove(int id) async => removed.add(id);

  @override
  Future<void> clear() async => cleared = true;
}

/// A portrait-phone frame (412x892 dp) looking horizontally at a floor 1.2 m below the
/// camera. [x],[z] is where the reticle hits the floor; null means "no surface".
ArFrame portraitFrame(double? x, double z, Map<int, List<double>> anchors, double dist) {
  final base = makeFrame(
    hitX: x,
    hitY: -1.2,
    hitZ: z,
    distance: dist,
    anchors: anchors,
    tracking: 1,
  );
  final raw = base.raw;
  // Re-do the projection for a tall viewport: vertical fov 90deg, aspect 412/892.
  const aspect = 412 / 892;
  raw[29] = 1 / aspect;
  raw[29 + 5] = 1;
  // Camera pitched 40 degrees down toward the floor: view = Rx(+40deg).
  const pitch = 40 * 3.141592653589793 / 180;
  final c = math.cos(pitch), s = math.sin(pitch);
  raw[13 + 5] = c;
  raw[13 + 6] = s;
  raw[13 + 9] = -s;
  raw[13 + 10] = c;
  return ArFrame(raw);
}
