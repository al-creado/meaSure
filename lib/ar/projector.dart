import 'dart:ui';

import '../measure/geometry.dart';
import 'ar_frame.dart';

/// Projects world-space points onto the AR view using the matrices ARCore reported for
/// the very same camera frame, so the overlay stays glued to the real world.
class Projector {
  Projector(ArFrame frame, this.size) : _m = frame.viewProjection;

  final Size size;
  final List<double> _m;

  /// Points closer than this (in clip-space w, i.e. metres in front of the camera) are
  /// treated as behind the camera.
  static const _nearW = 0.02;

  List<double> _clip(Vec3 p) {
    final m = _m;
    return [
      m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12],
      m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
      m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14],
      m[3] * p.x + m[7] * p.y + m[11] * p.z + m[15],
    ];
  }

  Offset _toScreen(double x, double y, double w) =>
      Offset((x / w * 0.5 + 0.5) * size.width, (1 - (y / w * 0.5 + 0.5)) * size.height);

  /// Screen position of [p], or null when it is behind the camera.
  Offset? project(Vec3 p) {
    final c = _clip(p);
    if (c[3] <= _nearW) return null;
    return _toScreen(c[0], c[1], c[3]);
  }

  /// Projects the segment [a]-[b], clipping the part behind the camera.
  /// Returns null if the whole segment is invisible.
  (Offset, Offset)? projectSegment(Vec3 a, Vec3 b) {
    var c0 = _clip(a);
    var c1 = _clip(b);
    final in0 = c0[3] > _nearW;
    final in1 = c1[3] > _nearW;
    if (!in0 && !in1) return null;
    if (!in0 || !in1) {
      final t = (_nearW - c0[3]) / (c1[3] - c0[3]);
      final cut = [for (var i = 0; i < 4; i++) c0[i] + (c1[i] - c0[i]) * t];
      if (!in0) {
        c0 = cut;
      } else {
        c1 = cut;
      }
    }
    return (_toScreen(c0[0], c0[1], c0[3]), _toScreen(c1[0], c1[1], c1[3]));
  }
}
