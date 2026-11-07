import 'dart:math' as math;

/// Minimal immutable 3D vector, in ARCore world space (metres).
class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x, y, z;

  static const zero = Vec3(0, 0, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 scale(double s) => Vec3(x * s, y * s, z * s);
  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  Vec3 cross(Vec3 o) => Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  double distanceTo(Vec3 o) => (this - o).length;

  Vec3 normalized() {
    final l = length;
    return l < 1e-9 ? this : scale(1 / l);
  }

  @override
  bool operator ==(Object other) => other is Vec3 && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => 'Vec3($x, $y, $z)';
}

Vec3 midpoint(Vec3 a, Vec3 b) => (a + b).scale(0.5);

Vec3 centroid(List<Vec3> pts) {
  var sum = Vec3.zero;
  for (final p in pts) {
    sum = sum + p;
  }
  return sum.scale(1 / pts.length);
}

/// Perimeter of a polyline / polygon.
double pathLength(List<Vec3> pts, {bool closed = false}) {
  var total = 0.0;
  for (var i = 0; i + 1 < pts.length; i++) {
    total += pts[i].distanceTo(pts[i + 1]);
  }
  if (closed && pts.length > 2) total += pts.last.distanceTo(pts.first);
  return total;
}

/// Area of a (nearly) planar polygon in 3D, in square metres.
///
/// Uses the magnitude of the vector area (sum of cross products), so the polygon can lie
/// on any plane - floor, wall, tabletop - with no need to project it first.
double polygonArea(List<Vec3> pts) {
  if (pts.length < 3) return 0;
  var sum = Vec3.zero;
  final o = pts.first;
  for (var i = 1; i + 1 < pts.length; i++) {
    sum = sum + (pts[i] - o).cross(pts[i + 1] - o);
  }
  return sum.length / 2;
}

/// Angle at [vertex] between rays to [a] and [b], in degrees (0..180).
double angleDegrees(Vec3 a, Vec3 vertex, Vec3 b) {
  final u = (a - vertex).normalized();
  final v = (b - vertex).normalized();
  final c = u.dot(v).clamp(-1.0, 1.0);
  return math.acos(c) * 180 / math.pi;
}
