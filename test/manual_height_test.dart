import 'package:ar_measure/measure/measure_controller.dart';
import 'package:ar_measure/measure/units.dart';
import 'package:ar_measure/storage/measurement_store.dart';
import 'package:ar_measure/ui/measure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('parseLengthInput', () {
    test('metric', () {
      expect(parseLengthInput('8', UnitSystem.metric), 8);
      expect(parseLengthInput(' 8,5 ', UnitSystem.metric), 8.5);
      for (final bad in ['', 'abc', '-3', '0', '8 m 5']) {
        expect(parseLengthInput(bad, UnitSystem.metric), isNull, reason: bad);
      }
    });

    test('imperial feet and inches', () {
      expect(parseLengthInput('10', UnitSystem.imperial), closeTo(3.048, 1e-9));
      expect(parseLengthInput('10 ft', UnitSystem.imperial), closeTo(3.048, 1e-9));
      expect(parseLengthInput("26' 3", UnitSystem.imperial), closeTo(8.0010, 1e-4));
      expect(parseLengthInput('26 ft 3 in', UnitSystem.imperial), closeTo(8.0010, 1e-4));
      expect(parseLengthInput('x', UnitSystem.imperial), isNull);
    });
  });

  group('MeasureController typed height', () {
    late FakeAr ar;
    late MemoryMeasurementStore store;
    late MeasureController c;
    var anchors = <int, List<double>>{};

    setUp(() async {
      ar = FakeAr();
      store = MemoryMeasurementStore();
      c = MeasureController(ar, store: store, haptics: false)..setMode(MeasureMode.volume);
      anchors = {};
      // 60 x 40 m floor.
      final corners = [
        [0.0, 0.0, 0.0],
        [60.0, 0.0, 0.0],
        [60.0, 0.0, 40.0],
        [0.0, 0.0, 40.0],
      ];
      for (final p in corners) {
        c.onFrame(makeFrame(hitX: p[0], hitY: 0, hitZ: p[2], distance: 1.5, anchors: Map.of(anchors)));
        await c.place();
        anchors[anchors.length + 1] = p;
      }
    });
    tearDown(() => c.dispose());

    test('only offered once the outline is closed', () {
      expect(c.hud.canTypeHeight, isFalse);
      expect(c.setManualHeight(8), isFalse);
      c.finishOutline();
      c.onFrame(makeFrame(hitX: 3, hitY: 0, hitZ: 3, distance: 1.5, anchors: anchors));
      expect(c.hud.canTypeHeight, isTrue);
    });

    test('60 x 40 x 8 m warehouse = 19,200 m3, savable, height recorded', () async {
      c.finishOutline();
      expect(c.setManualHeight(8), isTrue);
      expect(c.done.single.isComplete, isTrue);
      expect(c.current.ids, isEmpty);

      c.onFrame(makeFrame(hitX: 3, hitY: 0, hitZ: 3, distance: 1.5, anchors: anchors));
      expect(c.hud.value, '19,200 m³');
      expect(c.hud.sub, '2,400.00 m² × 8.00 m'.replaceAll('2,400.00', '2400.00'));
      expect(c.hud.canTypeHeight, isFalse);

      final m = (await c.saveActive())!;
      expect(m.value, closeTo(19200, 1e-6));
      expect(m.height, 8);
      expect(m.secondary, closeTo(2400, 1e-6));
    });

    test('rejects nonsense heights', () {
      c.finishOutline();
      for (final bad in [0.0, -2.0, 100.5, double.nan, double.infinity]) {
        expect(c.setManualHeight(bad), isFalse, reason: '$bad');
      }
      expect(c.done, isEmpty);
    });

    test('cannot overwrite a height that is already set', () {
      c.finishOutline();
      c.setManualHeight(8);
      expect(c.setManualHeight(9), isFalse);
      expect(c.done.single.manualHeight, 8);
    });

    test('undo takes the typed height back without touching the corners', () {
      c.finishOutline();
      c.setManualHeight(8);
      c.undo();
      expect(c.done, isEmpty);
      expect(c.current.closed, isTrue);
      expect(c.current.manualHeight, isNull);
      expect(c.current.ids.length, 4);
      expect(ar.removed, isEmpty);
      expect(c.hud.canTypeHeight, isTrue, reason: 'offered again straight away');
    });
  });

  testWidgets('Type height dialog sets the height and shows the volume', (tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final ar = FakeAr();
    await tester.pumpWidget(
      MaterialApp(
        home: MeasureScreen(
          backend: ar,
          store: MemoryMeasurementStore(),
          background: const SizedBox.expand(),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.view_in_ar_rounded));
    await tester.pump(const Duration(milliseconds: 250));

    final anchors = <int, List<double>>{};
    for (final p in [
      [0.0, 0.0, -1.0],
      [4.0, 0.0, -1.0],
      [4.0, 0.0, 2.0],
      [0.0, 0.0, 2.0],
    ]) {
      ar.emit(makeFrame(hitX: p[0], hitY: 0, hitZ: p[2], distance: 1.5, anchors: Map.of(anchors)));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Place point'));
      await tester.pump(const Duration(milliseconds: 50));
      anchors[anchors.length + 1] = p;
    }
    ar.emit(makeFrame(hitX: 1, hitY: 0, hitZ: 0, distance: 1.5, anchors: anchors));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check_rounded));
    await tester.pump(const Duration(milliseconds: 100));
    ar.emit(makeFrame(hitX: 1, hitY: 0, hitZ: 0, distance: 1.5, anchors: anchors));
    await tester.pump();

    expect(find.text('Type height'), findsOneWidget);
    await tester.tap(find.text('Type height'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2,5');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();

    expect(find.text('30.00 m³'), findsOneWidget); // 12 m2 x 2.5 m
    expect(find.text('Type height'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
