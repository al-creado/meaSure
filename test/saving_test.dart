import 'package:ar_measure/measure/measure_controller.dart';
import 'package:ar_measure/measure/units.dart';
import 'package:ar_measure/storage/measurement_store.dart';
import 'package:ar_measure/storage/saved_measurement.dart';
import 'package:ar_measure/ui/measure_screen.dart';
import 'package:ar_measure/ui/saved_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

SavedMeasurement sample(String id, DateTime t, {MeasureMode mode = MeasureMode.distance, double value = 1.234}) =>
    SavedMeasurement(
      id: id,
      mode: mode,
      value: value,
      secondary: mode == MeasureMode.area ? 4.0 : null,
      edges: mode == MeasureMode.angle ? [0.5, 0.7] : [value],
      createdAt: t,
    );

void main() {
  narrowPhoneTests();
  group('PrefsMeasurementStore (SharedPreferences)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round-trips, newest first, and survives a "restart"', () async {
      final a = sample('a', DateTime(2026, 11, 1));
      final b = sample('b', DateTime(2026, 11, 2), mode: MeasureMode.area, value: 2.31);
      await PrefsMeasurementStore().save(a);
      await PrefsMeasurementStore().save(b); // new instance == app restart

      final loaded = await PrefsMeasurementStore().load();
      expect(loaded.map((m) => m.id), ['b', 'a']);
      expect(loaded.first.mode, MeasureMode.area);
      expect(loaded.first.secondary, 4.0);
      expect(loaded.last.value, 1.234);
      expect(loaded.last.createdAt, DateTime(2026, 11, 1));
    });

    test('save with same id replaces; delete and clear work', () async {
      final s = PrefsMeasurementStore();
      await s.save(sample('a', DateTime(2026, 11, 1)));
      await s.save(sample('a', DateTime(2026, 11, 1)).withNote('desk'));
      expect((await s.load()).single.note, 'desk');
      await s.save(sample('b', DateTime(2026, 11, 2)));
      await s.delete('a');
      expect((await s.load()).map((m) => m.id), ['b']);
      await s.clear();
      expect(await s.load(), isEmpty);
    });

    test('a corrupt entry is skipped instead of breaking the list', () async {
      SharedPreferences.setMockInitialValues({
        'saved_measurements_v1': [
          'not json at all',
          '{"id":"x","mode":"bogus","value":1,"edges":[],"createdAt":1}',
          '{"id":"ok","mode":"distance","value":0.5,"edges":[0.5],"createdAt":1700000000000}',
        ],
      });
      final loaded = await PrefsMeasurementStore().load();
      expect(loaded.map((m) => m.id), ['ok']);
    });

    test('caps the number of stored entries', () async {
      final s = PrefsMeasurementStore();
      for (var i = 0; i < PrefsMeasurementStore.maxEntries + 5; i++) {
        await s.save(sample('$i', DateTime(2026, 1, 1).add(Duration(minutes: i))));
      }
      final all = await s.load();
      expect(all.length, PrefsMeasurementStore.maxEntries);
      expect(all.first.id, '${PrefsMeasurementStore.maxEntries + 4}'); // newest kept
    });
  });

  group('SavedMeasurement text', () {
    test('formats in the requested unit system', () {
      final m = sample('a', DateTime(2026, 11, 1), value: 0.3048);
      expect(m.valueText(UnitSystem.metric), '30.5 cm');
      expect(m.valueText(UnitSystem.imperial), '1′ 0″');
      expect(m.withNote('  shelf  ').asText(UnitSystem.metric), 'Distance: 30.5 cm — shelf');
      expect(m.withNote('   ').note, isNull);
    });
  });

  group('MeasureController saving', () {
    late FakeAr ar;
    late MemoryMeasurementStore store;
    late MeasureController c;

    setUp(() {
      ar = FakeAr();
      store = MemoryMeasurementStore();
      c = MeasureController(ar, store: store, haptics: false);
    });
    tearDown(() => c.dispose());

    Future<void> measureOneMetre() async {
      c.onFrame(makeFrame(hitX: 0, hitZ: -1, distance: 1.2));
      await c.place();
      c.onFrame(makeFrame(hitX: 1, hitZ: -1, distance: 1.2, anchors: {1: [0, 0, -1]}));
      await c.place();
      c.onFrame(makeFrame(hitX: 3, hitZ: -1, distance: 1.2, anchors: {1: [0, 0, -1], 2: [1, 0, -1]}));
    }

    test('cannot save while a measurement is in progress', () async {
      c.onFrame(makeFrame(hitX: 0, hitZ: -1, distance: 1.2));
      await c.place();
      expect(c.hud.canSave, isFalse);
      expect(await c.saveActive(), isNull);
      expect(store.items, isEmpty);
    });

    test('saves a finished distance once, in SI units', () async {
      await measureOneMetre();
      expect(c.hud.canSave, isTrue);
      expect(c.hud.isSaved, isFalse);

      final m = await c.saveActive();
      expect(m, isNotNull);
      expect(m!.mode, MeasureMode.distance);
      expect(m.value, closeTo(1.0, 1e-6));
      expect(store.items.single.id, m.id);
      expect(c.saved.single.id, m.id);
      expect(c.hud.isSaved, isTrue);
      expect(c.hud.canSave, isFalse);
      expect(await c.saveActive(), isNull, reason: 'no duplicate saves');
      expect(store.items.length, 1);
    });

    test('saved values do not change when the unit toggle does', () async {
      await measureOneMetre();
      final m = (await c.saveActive())!;
      c.toggleUnits();
      expect(m.value, closeTo(1.0, 1e-6));
      expect(m.valueText(c.units), '3′ 3.5″');
    });

    test('saves area with perimeter and every edge', () async {
      c.setMode(MeasureMode.area);
      final pts = {
        1: [0.0, 0.0, -1.0],
        2: [1.0, 0.0, -1.0],
        3: [1.0, 0.0, -2.0],
        4: [0.0, 0.0, -2.0],
      };
      final placed = <int, List<double>>{};
      for (final e in pts.entries) {
        c.onFrame(makeFrame(hitX: e.value[0], hitZ: e.value[2], distance: 1.5, anchors: Map.of(placed)));
        await c.place();
        placed[e.key] = e.value;
      }
      c.onFrame(makeFrame(hitX: 5, hitZ: -5, distance: 4, anchors: placed));
      c.finishOutline();
      final m = (await c.saveActive())!;
      expect(m.value, closeTo(1.0, 1e-6));
      expect(m.secondary, closeTo(4.0, 1e-6));
      expect(m.edges.length, 4);
      expect(m.detailText(UnitSystem.metric), 'Perimeter 4.00 m');
    });

    test('refuses to save if an anchor is not tracked right now', () async {
      await measureOneMetre();
      c.onFrame(makeFrame(hitX: 3, hitZ: -1, distance: 1.2, anchors: {1: [0, 0, -1]})); // anchor 2 lost
      expect(await c.saveActive(), isNull);
      expect(store.items, isEmpty);
    });

    test('delete, undo-delete, note and clear keep list and storage in sync', () async {
      await measureOneMetre();
      final m = (await c.saveActive())!;

      await c.setNote(m.id, 'desk width');
      expect(store.items.single.note, 'desk width');

      await c.deleteSaved(m.id);
      expect(c.saved, isEmpty);
      expect(store.items, isEmpty);
      expect(c.hud.isSaved, isFalse, reason: 'can be saved again after deleting');

      await c.restoreSaved(m);
      expect(c.saved.single.id, m.id);

      await c.clearSaved();
      expect(c.saved, isEmpty);
      expect(store.items, isEmpty);
    });

    test('loads previously saved measurements on start', () async {
      await store.save(sample('old', DateTime(2026, 10, 1)));
      c.start();
      await Future<void>.delayed(Duration.zero);
      expect(c.saved.single.id, 'old');
    });

    test('reopening a saved shape with undo allows saving the new result', () async {
      await measureOneMetre();
      await c.saveActive();
      c.undo(); // reopen, remove 2nd point
      expect(c.hud.isSaved, isFalse);
      expect(c.hud.canSave, isFalse); // in progress again
    });
  });

  group('SavedScreen', () {
    testWidgets('shows entries, newest first, with notes; empty state when none', (tester) async {
      final store = MemoryMeasurementStore();
      final c = MeasureController(FakeAr(), store: store, haptics: false);
      addTearDown(c.dispose);

      await tester.pumpWidget(MaterialApp(home: SavedScreen(controller: c)));
      expect(find.text('Nothing saved yet'), findsOneWidget);

      c.saved = [
        sample('b', DateTime(2026, 11, 7, 14, 5), mode: MeasureMode.area, value: 2.31).withNote('Living room'),
        sample('a', DateTime(2026, 11, 1), value: 0.456),
      ];
      c.notifyListeners();
      await tester.pump();
      expect(find.text('2.31 m²'), findsOneWidget);
      expect(find.text('Perimeter 4.00 m'), findsOneWidget);
      expect(find.text('Living room'), findsOneWidget);
      expect(find.text('45.6 cm'), findsOneWidget);
      expect(find.textContaining('7 Nov 2026, 14:05'), findsOneWidget);
    });

    testWidgets('editing a note saves it and does not use a disposed controller', (tester) async {
      await tester.runAsync(loadTestFonts);
      final store = MemoryMeasurementStore();
      await store.save(sample('a', DateTime(2026, 11, 1), value: 0.456));
      final c = MeasureController(FakeAr(), store: store, haptics: false);
      addTearDown(c.dispose);
      await c.loadSaved();

      await tester.pumpWidget(MaterialApp(home: SavedScreen(controller: c)));
      await tester.tap(find.text('45.6 cm'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Dock 3');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Dock 3'), findsOneWidget);
      expect(store.items.single.note, 'Dock 3');
      expect(tester.takeException(), isNull);
    });

    testWidgets('swipe deletes from the list and the store', (tester) async {
      final store = MemoryMeasurementStore();
      final m = sample('a', DateTime(2026, 11, 1), value: 0.456);
      await store.save(m);
      final c = MeasureController(FakeAr(), store: store, haptics: false);
      addTearDown(c.dispose);
      await c.loadSaved();

      await tester.pumpWidget(MaterialApp(home: SavedScreen(controller: c)));
      expect(find.text('45.6 cm'), findsOneWidget);

      await tester.drag(find.text('45.6 cm'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(find.text('45.6 cm'), findsNothing);
      expect(store.items, isEmpty);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('45.6 cm'), findsOneWidget);
      expect(store.items.length, 1);
    });
  });
}

void narrowPhoneTests() {
  testWidgets('top bar and save button fit on a 360dp phone and saving works end to end', (tester) async {
    await tester.runAsync(loadTestFonts);
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final ar = FakeAr();
    final store = MemoryMeasurementStore();
    await tester.pumpWidget(
      MaterialApp(home: MeasureScreen(backend: ar, store: store, background: const SizedBox.expand())),
    );

    Future<void> tapPlace() async {
      await tester.tap(find.bySemanticsLabel('Place point'));
      await tester.pump(const Duration(milliseconds: 50));
    }

    ar.emit(makeFrame(hitX: 0, hitZ: -1, distance: 1.2));
    await tester.pump();
    await tapPlace();

    // The result flickers on and off faster than its 180 ms animation (the reticle losing and
    // regaining the surface). This used to trip a duplicate-key assertion.
    for (var i = 0; i < 6; i++) {
      ar.emit(makeFrame(hitX: i.isEven ? 0.5 : null, hitZ: -1, distance: 1.2, anchors: {1: [0, 0, -1]}));
      await tester.pump(const Duration(milliseconds: 15));
    }
    expect(tester.takeException(), isNull, reason: 'no duplicate-key assertion');

    ar.emit(makeFrame(hitX: 1, hitZ: -1, distance: 1.2, anchors: {1: [0, 0, -1]}));
    await tester.pump();
    await tapPlace();
    ar.emit(makeFrame(hitX: 3, hitZ: -1, distance: 1.2, anchors: {1: [0, 0, -1], 2: [1, 0, -1]}));
    await tester.pump();

    expect(find.text('1.00 m'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no overflow');

    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pump(const Duration(milliseconds: 100));
    expect(store.items.single.value, closeTo(1.0, 1e-6));
    expect(find.byIcon(Icons.bookmark_added_rounded), findsOneWidget);
    expect(find.text('Saved 1.00 m'), findsOneWidget);

    // Count badge appears on the Saved shortcut; opening it lists the entry.
    await tester.tap(find.byIcon(Icons.bookmarks_outlined));
    await tester.pumpAndSettle();
    expect(find.text('100.00 m'), findsNothing);
    expect(find.text('Saved'), findsWidgets);
    expect(find.text('1.00 m'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
