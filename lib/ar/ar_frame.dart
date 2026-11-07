import 'dart:typed_data';

import '../measure/geometry.dart';

enum ArTracking { none, tracking, paused, error }

enum ArFailure { none, badState, lowLight, fastMotion, fewFeatures, cameraBusy }

enum HitKind { none, plane, depth, point }

/// One camera frame of AR state, decoded from the flat float array the native side sends.
///
/// Layout (keep in sync with `ArMeasureView.kt`):
/// ```
///  0 tracking state      1 failure reason     2 depth level (0 none, 1 depth API, 2 ToF)
///  3 hit kind            4 hit distance (m)   5..7 hit position   8..10 hit normal
///  11 hit stability 0..1 12 anchor count
///  45 view w  46 view h  47/48 camera image w/h  49/50 texture w/h  51 display rotation
///  52 scan progress 0..1 (camera travel needed for ARCore to lock in metric scale)
///  13..28 view matrix    29..44 projection matrix (column-major)
///  53.. anchors: [id, x, y, z] * count
/// ```
class ArFrame {
  ArFrame(this.raw);

  static const header = 53;

  final Float32List raw;

  ArTracking get tracking =>
      ArTracking.values[_enumIndex(raw[0], ArTracking.values.length)];
  ArFailure get failure =>
      ArFailure.values[_enumIndex(raw[1], ArFailure.values.length)];
  int get depthLevel => raw[2].round();
  HitKind get hitKind =>
      HitKind.values[_enumIndex(raw[3], HitKind.values.length)];
  bool get hasHit => hitKind != HitKind.none;
  double get hitDistance => raw[4];
  Vec3? get hitPosition => hasHit ? Vec3(raw[5], raw[6], raw[7]) : null;
  Vec3 get hitNormal => Vec3(raw[8], raw[9], raw[10]);
  double get stability => raw[11];

  /// 0..1 - how much of the camera travel ARCore needs to settle its scale has happened.
  double get scanProgress => raw[52];

  /// Diagnostics: sizes in pixels and the display rotation (0..3) ARCore was told about.
  String get diagnostics =>
      'view ${raw[45].round()}x${raw[46].round()}  '
      'image ${raw[47].round()}x${raw[48].round()}  '
      'tex ${raw[49].round()}x${raw[50].round()}  rot ${raw[51].round()}';

  /// Current world positions of every live anchor, by id.
  late final Map<int, Vec3> anchors = _parseAnchors();

  /// Combined projection * view matrix, column-major.
  late final Float64List viewProjection = _multiply(raw, 29, raw, 13);

  Map<int, Vec3> _parseAnchors() {
    final n = raw[12].round().clamp(0, (raw.length - header) ~/ 4);
    final map = <int, Vec3>{};
    for (var i = 0; i < n; i++) {
      final o = header + i * 4;
      map[raw[o].round()] = Vec3(raw[o + 1], raw[o + 2], raw[o + 3]);
    }
    return map;
  }

  static int _enumIndex(double v, int length) => v.round().clamp(0, length - 1);

  // out = a * b for column-major 4x4 matrices stored at the given offsets.
  static Float64List _multiply(Float32List a, int ao, Float32List b, int bo) {
    final out = Float64List(16);
    for (var col = 0; col < 4; col++) {
      for (var row = 0; row < 4; row++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[ao + k * 4 + row] * b[bo + col * 4 + k];
        }
        out[col * 4 + row] = sum;
      }
    }
    return out;
  }
}
