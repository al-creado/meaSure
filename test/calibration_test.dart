import 'package:ar_measure/measure/measure_controller.dart';
import 'package:ar_measure/measure/units.dart';
import 'package:ar_measure/storage/measurement_store.dart';
import 'package:ar_measure/storage/saved_measurement.dart';
import 'package:ar_measure/ui/measure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('parseReferenceLength', () {
    test('metric: bare number is centimetres; units are honoured', () {
      expect(parseReferenceLength('29.7', UnitSystem.metric), closeTo(0.297, 1e-12));
      expect(parseReferenceLength('29,7 cm', UnitSystem.metric), closeTo(0.297, 1e-12));
      expect(parseReferenceLength('297 mm', UnitSystem.metric), closeTo(0.297, 1e-12));
      expect(parseReferenceLength('2 m', UnitSystem.metric), 2);
      for (final bad in ['', 'x', '0', '-5', '3 km', '1 2']) {
        expect(parseReferenceLength(bad, UnitSystem.metric), isNull, reason: bad);
      }
    });

    test('imperial: bare number is inches; feet and inches work', () {
      expect(parseReferenceLength('11.7', UnitSystem.imperial), closeTo(0.29718, 1e-5));
      expect(parseReferenceLength('11.7 in', UnitSystem.imperial), closeTo(0.29718, 1e-5));
      expect(parseReferenceLength('2 ft 3', UnitSystem.imperial), closeTo(0.6858, 1e-4));
      expect(parseReferenceLength('x', UnitSystem.imperial), isNull);
    });
  });

  group('MeasureController calibration', () {
    late FakeAr ar;
    late MemoryMeasurementStore store;
    late MeasureController c;

    setUp(() {
      ar = FakeAr();
      store = MemoryMeasurementStore();
      c = MeasureController(ar, store: store, haptics: false);
    });
    tearDown(() => c.dispose());

    final anchors = <int, List<double>>{};

    Future<void> placeAll(List<List<double>> pts) async {
      for (final p in pts) {
        c.onFrame(makeFrame(hitX: p[0], hitY: p[1], hitZ: p[2], distance: 1.5, anchors: Map.of(anchors)));
        await c.place();
        anchors[ar.placed.last] = p; // the fake engine's own anchor id
      }
    }

    void show() => c.onFrame(makeFrame(hitX: 9, hitY: 0, hitZ: 9, distance: 1.5, anchors: Map.of(anchors)));

    /// Measures a 1.00 m reference distance (raw AR metres) and leaves it on screen.
    Future<void> reference() async {
      await placeAll([
        [0, 0, -1],
        [1, 0, -1],
      ]);
      show();
    }

    test('reference distance reads raw, then calibrated, and does not stack', () async {
      await reference();
      expect(c.isCalibrated, isFalse);
      expect(c.referenceLength, closeTo(1.0, 1e-6));
      expect(c.hud.value, '1.00 m');

      expect(c.calibrateTo(0.95), isTrue);
      expect(c.calibration, closeTo(0.95, 1e-6));
      expect(c.referenceLength, closeTo(0.95, 1e-6));
      expect(c.hud.value, '95.0 cm');

      // Calibrating again replaces the factor (computed from the raw measurement).
      expect(c.calibrateTo(1.0), isTrue);
      expect(c.calibration, closeTo(1.0, 1e-6));
      expect(c.isCalibrated, isFalse);
      expect(c.hud.value, '1.00 m');
    });

    test('rejects implausible, invalid or impossible calibrations and changes nothing', () async {
      expect(c.calibrateTo(1), isFalse, reason: 'nothing measured yet');

      await reference();
      for (final real in [3.0, 0.4, 0.0, -1.0, double.nan, double.infinity]) {
        expect(c.calibrateTo(real), isFalse, reason: '$real');
      }
      expect(c.calibration, 1.0);

      // An area is not a reference.
      c.setMode(MeasureMode.area);
      await placeAll([
        [0, 0, 0],
        [2, 0, 0],
        [2, 0, 3],
      ]);
      c.finishOutline();
      show();
      expect(c.referenceLength, isNull);
      expect(c.calibrateTo(1), isFalse);
    });

    test('reset puts everything back', () async {
      await reference();
      c.calibrateTo(0.9);
      c.resetCalibration();
      expect(c.calibration, 1.0);
      expect(c.hud.value, '1.00 m');
    });

    test('area scales with the square of the factor, perimeter linearly', () async {
      await reference();
      c.calibrateTo(0.9);
      c.setMode(MeasureMode.area);
      await placeAll([
        [0, 0, 0],
        [2, 0, 0],
        [2, 0, 3],
        [0, 0, 3],
      ]);
      c.finishOutline();
      show();
      expect(c.hud.value, '4.86 m²'); // 6 m2 * 0.81
      expect(c.hud.sub, 'Perimeter 9.00 m'); // 10 m * 0.9
    });

    test('angles do not change', () async {
      await reference();
      c.calibrateTo(0.9);
      c.setMode(MeasureMode.angle);
      await placeAll([
        [1, 0, 0],
        [0, 0, 0],
        [0, 1, 0],
      ]);
      show();
      expect(c.hud.value, '90.0°');
    });

    Future<void> volumeFloor() async {
      await reference();
      c.calibrateTo(0.9);
      c.setMode(MeasureMode.volume);
      await placeAll([
        [0, 0, 0],
        [4, 0, 0],
        [4, 0, 3],
        [0, 0, 3],
      ]);
      c.finishOutline();
    }

    test('volume with a measured height: lengths scale by k, volume by k^3', () async {
      await volumeFloor();
      // Raw: floor 12 m2, top 2 m above the floor => 24 m3; calibrated: * 0.9^3.
      c.onFrame(makeFrame(hitX: 2, hitY: 2, hitZ: 1.5, distance: 1.5, anchors: Map.of(anchors)));
      expect(c.hud.value, '17.50 m\u00B3');
      expect(c.hud.sub, '9.72 m\u00B2 \u00D7 1.80 m');
    });

    test('volume with a typed height: the height is real, only the floor scales', () async {
      await volumeFloor();
      expect(c.setManualHeight(2), isTrue);
      show();
      expect(c.hud.value, '19.44 m\u00B3'); // 12 * 0.81 * 2
      expect(c.hud.sub, '9.72 m\u00B2 \u00D7 2.00 m');
    });

    test('close-loop error is reported in calibrated metres', () async {
      await reference();
      c.calibrateTo(0.9);
      c.setMode(MeasureMode.area);
      await placeAll([
        [0, 0, 0],
        [10, 0, 0],
        [10, 0, 10],
      ]);
      c.onFrame(makeFrame(hitX: 0.5, hitY: 0, hitZ: 0, distance: 1.5, anchors: Map.of(anchors)));
      final r = c.closeLoop()!;
      expect(r.error, closeTo(0.5 * 0.9, 1e-5));
      expect(r.error / r.path, closeTo(0.5 / (20 + 14.142), 1e-3), reason: 'the percentage is scale-free');
    });

    test('saved entries carry the calibrated numbers and the factor', () async {
      await reference();
      c.calibrateTo(0.95);
      show();
      final m = (await c.saveActive())!;
      expect(m.value, closeTo(0.95, 1e-6));
      expect(m.calibration, closeTo(0.95, 1e-6));
      expect(m.detailText(UnitSystem.metric), 'Scale calibrated ×0.950 (−5.0 %)');
      expect(m.asText(UnitSystem.metric), contains('Scale calibrated'));

      final again = SavedMeasurement.fromJson(m.toJson());
      expect(again.calibration, closeTo(0.95, 1e-9));

      // Uncalibrated entries say nothing about it.
      c.resetCalibration();
      await reference();
      final plain = (await c.saveActive())!;
      expect(plain.calibration, isNull);
      expect(plain.detailText(UnitSystem.metric), isNull);
    });
  });

  testWidgets('Accuracy sheet: calibrate with an A4 sheet end to end', (tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final ar = FakeAr();
    await tester.pumpWidget(
      MaterialApp(
        home: MeasureScreen(backend: ar, store: MemoryMeasurementStore(), background: const SizedBox.expand()),
      ),
    );
    ar.emit(makeFrame(hitX: 0, hitZ: -1, distance: 1.2));
    await tester.pump();

    // Nothing to calibrate against yet.
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    expect(find.text('Accuracy'), findsOneWidget);
    expect(find.text('Scale not calibrated'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
    await tester.pumpAndSettle();

    // Measure an "A4 sheet" that the phone thinks is 31.0 cm long.
    final anchors = <int, List<double>>{};
    for (final x in [0.0, 0.31]) {
      ar.emit(makeFrame(hitX: x, hitZ: -1, distance: 1.2, anchors: Map.of(anchors)));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Place point'));
      await tester.pump(const Duration(milliseconds: 50));
      anchors[anchors.length + 1] = [x, 0, -1];
    }
    ar.emit(makeFrame(hitX: 5, hitZ: -1, distance: 1.2, anchors: anchors));
    await tester.pump();
    expect(find.text('31.0 cm'), findsOneWidget);

    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    expect(find.text('Calibrate to 31.0 cm'), findsOneWidget);
    await tester.tap(find.text('Calibrate to 31.0 cm'));
    await tester.pumpAndSettle();

    expect(find.text('Real length'), findsOneWidget);
    expect(find.textContaining('The app measured 31.0 cm'), findsOneWidget);
    await tester.tap(find.text('A4 long side'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '29.7'), findsOneWidget);
    await tester.tap(find.text('Calibrate').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Calibrated. Measurements now use ×0.958'), findsOneWidget);
    expect(find.textContaining('Scale calibrated ×0.958 (−4.2 %)'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('29.7 cm'), findsOneWidget, reason: 'the measurement on screen now reads the real length');
    expect(find.text('×0.958'), findsOneWidget, reason: 'and the pill shows the factor');
    expect(tester.takeException(), isNull);
  });
}
