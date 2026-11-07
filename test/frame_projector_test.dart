import 'dart:ui';

import 'package:ar_measure/ar/ar_frame.dart';
import 'package:ar_measure/ar/projector.dart';
import 'package:ar_measure/measure/geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  test('frame decodes header fields and anchors', () {
    final f = makeFrame(
      hitX: 0.1,
      hitY: 0.2,
      hitZ: -1.5,
      kind: HitKind.depth,
      distance: 1.5,
      stability: 0.8,
      failure: 3,
      depth: 2,
      anchors: {
        7: [1, 2, 3],
        9: [-1, 0, -2],
      },
    );
    expect(f.tracking, ArTracking.tracking);
    expect(f.failure, ArFailure.fastMotion);
    expect(f.depthLevel, 2);
    expect(f.hitKind, HitKind.depth);
    expect(f.hitDistance, 1.5);
    expect(f.hitPosition!.z, closeTo(-1.5, 1e-6));
    expect(f.stability, closeTo(0.8, 1e-6));
    expect(f.anchors.keys, containsAll([7, 9]));
    expect(f.anchors[9], const Vec3(-1, 0, -2));
  });

  test('no hit => null position', () {
    expect(makeFrame().hitPosition, isNull);
  });

  test('truncated anchor list does not crash', () {
    final f = makeFrame(anchors: {1: [0, 0, -1]});
    f.raw[12] = 50; // claims more anchors than the array holds
    expect(f.anchors.length, 1);
  });

  group('projector', () {
    const size = Size(200, 400);
    late Projector p;
    setUp(() => p = Projector(makeFrame(), size));

    test('a point straight ahead lands in the centre', () {
      final o = p.project(const Vec3(0, 0, -2))!;
      expect(o.dx, closeTo(100, 1e-3));
      expect(o.dy, closeTo(200, 1e-3));
    });

    test('right is +x, up is -y on screen', () {
      final o = p.project(const Vec3(1, 1, -2))!; // tan(45) => 0.5 of the half-extent
      expect(o.dx, closeTo(150, 1e-3));
      expect(o.dy, closeTo(100, 1e-3));
    });

    test('points behind the camera are not projected', () {
      expect(p.project(const Vec3(0, 0, 2)), isNull);
    });

    test('segment crossing the camera plane is clipped, not dropped', () {
      final seg = p.projectSegment(const Vec3(0, 0, -2), const Vec3(0, 0, 3))!;
      expect(seg.$1.dx, closeTo(100, 1e-3));
      expect(seg.$2.dx.isFinite && seg.$2.dy.isFinite, isTrue);
      expect(p.projectSegment(const Vec3(0, 0, 1), const Vec3(0, 0, 3)), isNull);
    });
  });
}
