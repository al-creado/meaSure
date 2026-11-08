import 'package:ar_measure/measure/geometry.dart';
import 'package:ar_measure/measure/measure_controller.dart';
import 'package:ar_measure/measure/units.dart';
import 'package:ar_measure/storage/measurement_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeAr ar;
  late MemoryMeasurementStore store;
  late MeasureController c;

  setUp(() {
    ar = FakeAr();
    store = MemoryMeasurementStore();
    c = MeasureController(ar, store: store, haptics: false)
      ..setMode(MeasureMode.volume);
  });
  tearDown(() => c.dispose());

  /// Places [corners] (x, y, z) one after another; returns the anchor map so far.
  Future<Map<int, List<double>>> placeAll(List<List<double>> corners) async {
    final anchors = <int, List<double>>{};
    for (final p in corners) {
      c.onFrame(
        makeFrame(
          hitX: p[0],
          hitY: p[1],
          hitZ: p[2],
          distance: 1.5,
          anchors: Map.of(anchors),
        ),
      );
      await c.place();
      anchors[anchors.length + 1] = p;
    }
    return anchors;
  }

  const box4x3 = [
    [0.0, 0.0, 0.0],
    [4.0, 0.0, 0.0],
    [4.0, 0.0, 3.0],
    [0.0, 0.0, 3.0],
  ];

  test('floor outline, then height: 4 x 3 x 2 m = 24 m3', () async {
    var anchors = await placeAll(box4x3);
    // Aiming back at the first corner leaves the outline unchanged: floor area is shown.
    c.onFrame(makeFrame(hitX: 0, hitY: 0, hitZ: 0, distance: 1.5, anchors: anchors));
    expect(c.hud.hint, contains('Close loop'));
    expect(c.hud.value, '12.00 m\u00B2', reason: 'floor area while outlining');
    expect(c.hud.canFinish, isTrue);

    c.finishOutline();
    expect(c.current.closed, isTrue);
    expect(c.done, isEmpty, reason: 'a volume is not complete until it has a height');
    c.onFrame(makeFrame(hitX: 2, hitY: 2, hitZ: 1.5, distance: 1.5, anchors: anchors));
    expect(c.hud.hint, contains('top of the stack'));
    expect(c.hud.value, '24.00 m³');
    expect(c.hud.sub, '12.00 m² × 2.00 m');
    expect(c.hud.canSave, isFalse);

    await c.place(); // height point
    anchors = {...anchors, 5: [2, 2, 1.5]};
    expect(c.done.single.isComplete, isTrue);
    expect(c.current.ids, isEmpty);
    c.onFrame(makeFrame(hitX: 9, hitY: 0, hitZ: 9, distance: 1.5, anchors: anchors));
    expect(c.hud.value, '24.00 m³');
    expect(c.hud.canSave, isTrue);

    final m = (await c.saveActive())!;
    expect(m.value, closeTo(24, 1e-6));
    expect(m.secondary, closeTo(12, 1e-6));
    expect(m.height, closeTo(2, 1e-6));
    expect(m.asText(UnitSystem.metric), 'Volume: 24.00 m³ — 12.00 m² × 2.00 m');
  });

  test('height is measured from the average floor level, not from y = 0', () async {
    // Floor sits 1.0 m below the camera origin (y = -1); top is 1.5 m above it.
    final anchors = await placeAll([
      [0, -1.0, 0],
      [2, -1.0, 0],
      [2, -1.0, 2],
      [0, -1.0, 2],
    ]);
    c.finishOutline();
    c.onFrame(makeFrame(hitX: 1, hitY: 0.5, hitZ: 1, distance: 1.5, anchors: anchors));
    expect(c.hud.value, '6.00 m³'); // 4 m2 x 1.5 m
  });

  test('big warehouse numbers format with thousands separators', () async {
    final anchors = await placeAll([
      [0, 0, 0],
      [60, 0, 0],
      [60, 0, 40],
      [0, 0, 40],
    ]);
    c.finishOutline();
    c.onFrame(makeFrame(hitX: 30, hitY: 8, hitZ: 20, distance: 1.5, anchors: anchors));
    expect(c.hud.value, '19,200 m³'); // 2400 m2 x 8 m
    c.toggleUnits();
    expect(c.hud.value, '678,042 ft³');
  });

  test('undo: height, then outline, then corners', () async {
    var anchors = await placeAll(box4x3);
    c.finishOutline();
    c.onFrame(makeFrame(hitX: 2, hitY: 2, hitZ: 1.5, distance: 1.5, anchors: anchors));
    await c.place();
    anchors = {...anchors, 5: [2, 2, 1.5]};
    expect(c.done.length, 1);

    c.undo(); // removes the height point, back to "set height"
    expect(c.done, isEmpty);
    expect(c.current.closed, isTrue);
    expect(c.current.ids.length, 4);
    expect(ar.removed, [5]);

    c.undo(); // reopens the outline, keeps all four corners
    expect(c.current.closed, isFalse);
    expect(c.current.ids.length, 4);
    expect(ar.removed, [5]);

    c.undo(); // now removes the last corner
    expect(c.current.ids.length, 3);
    expect(ar.removed, [5, 4]);
  });

  test('aiming back at the first corner closes the outline (snap)', () async {
    final anchors = await placeAll(box4x3.sublist(0, 3));
    c.onFrame(makeFrame(hitX: 0.004, hitY: 0, hitZ: 0, distance: 1.5, anchors: anchors));
    expect(c.snapId, 1);
    final before = ar.placed.length;
    await c.place();
    expect(ar.placed.length, before);
    expect(c.current.closed, isTrue);
  });

  group('close loop', () {
    // A 40 x 25 m floor walked clockwise. ARCore drifts by `e` over the whole 130 m walk,
    // growing with distance walked, so every corner is recorded slightly off, and when we
    // come back to the start the phone believes it is `e` away from where it began.
    const e = Vec3(0.8, 0, -0.4);
    const truth = [Vec3(0, 0, 0), Vec3(40, 0, 0), Vec3(40, 0, 25), Vec3(0, 0, 25)];
    const walked = [0.0, 40.0, 65.0, 105.0];
    const total = 130.0;

    List<List<double>> measured() => [
      for (var i = 0; i < 4; i++)
        () {
          final p = truth[i] + e.scale(walked[i] / total);
          return [p.x, p.y, p.z];
        }(),
    ];

    Future<Map<int, List<double>>> walk() => placeAll(measured());

    test('reports the closure error and recovers the true floor area', () async {
      final anchors = await walk();
      final rawArea = polygonAreaXZ([
        for (final m in measured()) Vec3(m[0], m[1], m[2]),
      ]);

      // Back at the start corner, the phone thinks it is at start + e.
      final back = truth.first + e;
      c.onFrame(makeFrame(hitX: back.x, hitY: 0, hitZ: back.z, distance: 1.5, anchors: anchors));
      expect(c.hud.canCloseLoop, isTrue);

      final r = c.closeLoop()!;
      expect(r.error, closeTo(e.length, 1e-5));
      expect(r.path, closeTo(total, 0.5));
      expect(c.current.closed, isTrue);

      final fixed = polygonAreaXZ([
        for (final id in c.current.ids) c.pointOf(c.current, id)!,
      ]);
      expect((fixed - 1000).abs(), lessThan((rawArea - 1000).abs()));
      expect((fixed - 1000).abs() / 1000, lessThan(0.002));
    });

    test('area mode finishes and the saved record carries the loop error', () async {
      c.setMode(MeasureMode.area);
      final anchors = await walk();
      final back = truth.first + e;
      c.onFrame(makeFrame(hitX: back.x, hitY: 0, hitZ: back.z, distance: 1.5, anchors: anchors));
      c.closeLoop();
      expect(c.done.single.closed, isTrue);
      expect(c.hud.value, contains('m²'));

      c.onFrame(makeFrame(hitX: 9, hitY: 0, hitZ: 9, distance: 1.5, anchors: anchors));
      final m = (await c.saveActive())!;
      expect(m.loopError, closeTo(e.length, 1e-5));
      expect(m.loopText(UnitSystem.metric), 'Loop closed, error 89.4 cm (0.69 %)');
      expect(m.detailText(UnitSystem.metric), contains('Loop closed'));
    });

    test('not available with fewer than three corners or without a surface', () async {
      final anchors = await placeAll(box4x3.sublist(0, 2));
      c.onFrame(makeFrame(hitX: 0, hitY: 0, hitZ: 0, distance: 1.5, anchors: anchors));
      expect(c.hud.canCloseLoop, isFalse);
      expect(c.closeLoop(), isNull);

      final more = await placeAll(box4x3);
      c.onFrame(makeFrame(anchors: more)); // no surface under the reticle
      expect(c.closeLoop(), isNull);
    });

    test('undoing a closed loop drops the correction', () async {
      final anchors = await walk();
      final back = truth.first + e;
      c.onFrame(makeFrame(hitX: back.x, hitY: 0, hitZ: back.z, distance: 1.5, anchors: anchors));
      c.closeLoop();
      expect(c.current.adjust, isNotEmpty);
      c.undo(); // volume, no height yet: reopens the outline
      expect(c.current.adjust, isEmpty);
      expect(c.current.loop, isNull);
      expect(c.current.closed, isFalse);
    });
  });
}
