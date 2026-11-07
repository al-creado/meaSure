import 'package:ar_measure/ar/ar_frame.dart';
import 'package:ar_measure/measure/measure_controller.dart';
import 'package:ar_measure/measure/units.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeAr ar;
  late MeasureController c;

  setUp(() {
    ar = FakeAr();
    c = MeasureController(ar, haptics: false);
  });
  tearDown(() => c.dispose());

  ArFrame aimAt(double x, double y, double z, {Map<int, List<double>> anchors = const {}, double stability = 1}) =>
      makeFrame(hitX: x, hitY: y, hitZ: z, distance: 1.2, stability: stability, anchors: anchors);

  test('hints reflect tracking and range problems', () {
    c.onFrame(makeFrame(tracking: 2, failure: 2));
    expect(c.hud.canPlace, isFalse);
    expect(c.hud.hint, contains('dark'));

    c.onFrame(makeFrame());
    expect(c.hud.hint, contains('find a surface'));

    c.onFrame(makeFrame(hitX: 0, distance: 0.05));
    expect(c.hud.canPlace, isFalse);
    expect(c.hud.hint, contains('Too close'));

    c.onFrame(makeFrame(hitX: 0, distance: 9));
    expect(c.hud.canPlace, isFalse);
    expect(c.hud.hint, contains('Too far'));

    c.onFrame(makeFrame(hitX: 0, distance: 4));
    expect(c.hud.canPlace, isTrue);
    expect(c.hud.hint, contains('closer for better accuracy'));
    expect(c.hud.quality, lessThan(3));

    c.onFrame(aimAt(0, 0, -1, stability: 0.1));
    expect(c.hud.hint, contains('steady'));

    c.onFrame(aimAt(0, 0, -1));
    expect(c.hud.canPlace, isTrue);
    expect(c.hud.quality, 3);
  });

  test('measuring is blocked until the user has moved around enough', () {
    c.onFrame(makeFrame(hitX: 0, scan: 0.4));
    expect(c.hud.canPlace, isFalse);
    expect(c.hud.hint, contains('calibrate'));
    expect(c.hud.hint, contains('40%'));
    c.onFrame(makeFrame(hitX: 0, scan: 1));
    expect(c.hud.canPlace, isTrue);
  });

  test('distance: live value, then completes after two points', () async {
    c.onFrame(aimAt(0, 0, -1));
    await c.place();
    expect(c.current.ids, [1]);

    // Live distance from anchor 1 to wherever the reticle is now.
    c.onFrame(aimAt(0.5, 0, -1, anchors: {1: [0, 0, -1]}));
    expect(c.hud.value, '50.0 cm');
    expect(c.hud.sub, '1\u2032 7.5\u2033');

    await c.place();
    expect(c.done.length, 1);
    expect(c.current.ids, isEmpty);

    c.onFrame(aimAt(2, 0, -1, anchors: {1: [0, 0, -1], 2: [0.5, 0, -1]}));
    // Finished measurement stays shown while nothing new is in progress.
    expect(c.hud.value, '50.0 cm');
  });

  test('area: three corners, finish, value is exact', () async {
    c.setMode(MeasureMode.area);
    c.onFrame(aimAt(0, 0, -1));
    await c.place();
    c.onFrame(aimAt(1, 0, -1, anchors: {1: [0, 0, -1]}));
    await c.place();
    c.onFrame(aimAt(1, 0, -2, anchors: {1: [0, 0, -1], 2: [1, 0, -1]}));
    await c.place();
    final anchors = {
      1: [0.0, 0.0, -1.0],
      2: [1.0, 0.0, -1.0],
      3: [1.0, 0.0, -2.0],
    };
    // Reticle on the 4th corner of a 1 m square (not placed yet, shown live).
    c.onFrame(aimAt(0, 0, -2, anchors: anchors));
    expect(c.hud.value, '1.00 m²');
    expect(c.hud.canFinish, isTrue);

    await c.place(); // 4th corner
    c.onFrame(aimAt(5, 0, -5, anchors: {...anchors, 4: [0, 0, -2]}));
    c.finishArea();
    expect(c.done.single.closed, isTrue);
    expect(c.hud.value, '1.00 m²');
    expect(c.hud.sub, 'Perimeter 4.00 m');
  });

  test('angle uses the middle point as the corner', () async {
    c.setMode(MeasureMode.angle);
    c.onFrame(aimAt(1, 0, 0));
    await c.place();
    c.onFrame(aimAt(0, 0, 0, anchors: {1: [1, 0, 0]}));
    await c.place();
    c.onFrame(aimAt(0, 1, 0, anchors: {1: [1, 0, 0], 2: [0, 0, 0]}));
    expect(c.hud.value, '90.0°');
    await c.place();
    expect(c.done.single.ids, [1, 2, 3]);
  });

  test('snaps to an existing point and passes its id to the engine', () async {
    c.onFrame(aimAt(0, 0, -1));
    await c.place(); // anchor 1
    c.onFrame(aimAt(0.4, 0, -1, anchors: {1: [0, 0, -1]}));
    await c.place(); // anchor 2, distance measurement done

    // Aim 5 mm from anchor 1 => snaps.
    c.onFrame(aimAt(0.005, 0, -1, anchors: {1: [0, 0, -1], 2: [0.4, 0, -1]}));
    expect(c.snapId, 1);
    expect(c.reticle!.x, 0); // reticle jumps to the exact anchor position
    expect(c.hud.snapping, isTrue);
    await c.place();
    expect(ar.snaps.last, 1);

    // 20 cm away => no snap.
    c.onFrame(aimAt(0.2, 0, -1, anchors: {1: [0, 0, -1], 2: [0.4, 0, -1]}));
    expect(c.snapId, isNull);
  });

  test('tapping the first corner closes a polygon', () async {
    c.setMode(MeasureMode.area);
    final pts = <int, List<double>>{};
    for (final (i, p) in [(1, [0.0, 0.0, -1.0]), (2, [1.0, 0.0, -1.0]), (3, [1.0, 0.0, -2.0])]) {
      c.onFrame(aimAt(p[0], p[1], p[2], anchors: Map.of(pts)));
      await c.place();
      pts[i] = p;
    }
    c.onFrame(aimAt(0.003, 0, -1, anchors: pts));
    expect(c.snapId, 1);
    final before = ar.placed.length;
    await c.place();
    expect(ar.placed.length, before, reason: 'closing must not create a new anchor');
    expect(c.done.single.closed, isTrue);
  });

  test('failed placement adds nothing', () async {
    ar.nextResult = -1;
    c.onFrame(aimAt(0, 0, -1));
    await c.place();
    expect(c.current.ids, isEmpty);
  });

  test('undo walks back through points and reopens finished shapes; clear resets', () async {
    c.onFrame(aimAt(0, 0, -1));
    await c.place();
    c.onFrame(aimAt(1, 0, -1, anchors: {1: [0, 0, -1]}));
    await c.place();
    expect(c.done.length, 1);

    c.undo();
    expect(ar.removed, [2]);
    expect(c.done, isEmpty);
    expect(c.current.ids, [1]);
    c.undo();
    expect(ar.removed, [2, 1]);
    expect(c.hud.canUndo, isFalse);

    c.onFrame(aimAt(0, 0, -1));
    await c.place();
    c.clearAll();
    expect(ar.cleared, isTrue);
    expect(c.current.ids, isEmpty);
  });

  test('switching mode drops the unfinished shape only', () async {
    c.onFrame(aimAt(0, 0, -1));
    await c.place();
    c.onFrame(aimAt(1, 0, -1, anchors: {1: [0, 0, -1]}));
    await c.place(); // done: 1,2
    c.onFrame(aimAt(0, 0, -1, anchors: {1: [0, 0, -1], 2: [1, 0, -1]}));
    await c.place(); // current: 3
    c.setMode(MeasureMode.angle);
    expect(ar.removed, [3]);
    expect(c.done.length, 1);
  });

  test('unit toggle changes formatting', () async {
    c.onFrame(aimAt(0, 0, -1));
    await c.place();
    c.onFrame(aimAt(1, 0, -1, anchors: {1: [0, 0, -1]}));
    expect(c.hud.value, '1.00 m');
    c.toggleUnits();
    expect(c.units, UnitSystem.imperial);
    expect(c.hud.value, '3′ 3.5″');
  });
}
