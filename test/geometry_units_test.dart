import 'dart:math' as math;

import 'package:ar_measure/measure/geometry.dart';
import 'package:ar_measure/measure/units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('geometry', () {
    test('distance and path length', () {
      expect(const Vec3(0, 0, 0).distanceTo(const Vec3(3, 4, 0)), 5);
      expect(pathLength(const [Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(1, 1, 0)]), 2);
      expect(pathLength(const [Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(1, 1, 0)], closed: true), closeTo(3.414, 1e-3));
    });

    test('polygon area is orientation independent', () {
      // 2 x 1.5 rectangle lying on the floor (XZ plane) ...
      const floor = [Vec3(0, 0, 0), Vec3(2, 0, 0), Vec3(2, 0, 1.5), Vec3(0, 0, 1.5)];
      expect(polygonArea(floor), closeTo(3.0, 1e-9));
      // ... and the same rectangle on a wall (XY plane), and tilted.
      const wall = [Vec3(0, 0, 0), Vec3(2, 0, 0), Vec3(2, 1.5, 0), Vec3(0, 1.5, 0)];
      expect(polygonArea(wall), closeTo(3.0, 1e-9));
      final tilt = [for (final p in wall) Vec3(p.x, p.y * math.cos(0.7), p.y * math.sin(0.7))];
      expect(polygonArea(tilt), closeTo(3.0, 1e-9));
    });

    test('concave polygon area', () {
      // L shape: 2x2 square minus 1x1 corner = 3
      const l = [Vec3(0, 0, 0), Vec3(2, 0, 0), Vec3(2, 0, 1), Vec3(1, 0, 1), Vec3(1, 0, 2), Vec3(0, 0, 2)];
      expect(polygonArea(l), closeTo(3.0, 1e-9));
    });

    test('angles', () {
      expect(angleDegrees(const Vec3(1, 0, 0), Vec3.zero, const Vec3(0, 1, 0)), closeTo(90, 1e-9));
      expect(angleDegrees(const Vec3(1, 0, 0), Vec3.zero, const Vec3(-1, 0, 0)), closeTo(180, 1e-9));
      expect(angleDegrees(const Vec3(1, 0, 0), Vec3.zero, const Vec3(1, 1, 0)), closeTo(45, 1e-9));
    });
  });

  group('units', () {
    test('metric length', () {
      expect(formatLength(0.004, UnitSystem.metric), '4 mm');
      expect(formatLength(0.123, UnitSystem.metric), '12.3 cm');
      expect(formatLength(1.2345, UnitSystem.metric), '1.23 m');
    });

    test('imperial length', () {
      expect(formatLength(0.0254 * 8.5, UnitSystem.imperial), '8.5 in');
      expect(formatLength(0.0254 * 8, UnitSystem.imperial), '8 in');
      expect(formatLength(0.3048, UnitSystem.imperial), '1′ 0″');
      expect(formatLength(0.0254 * 38.5, UnitSystem.imperial), '3′ 2.5″');
      // Rounds up into the next foot instead of printing 12".
      expect(formatLength(0.0254 * 23.9, UnitSystem.imperial), '2′ 0″');
    });

    test('area and angle', () {
      expect(formatArea(2.5, UnitSystem.metric), '2.50 m²');
      expect(formatArea(0.05, UnitSystem.metric), '500 cm²');
      expect(formatArea(1, UnitSystem.imperial), '10.76 ft²');
      expect(formatAngle(47.26), '47.3°');
    });
  });
}
