import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ar_measure/ar/ar_backend.dart';
import 'package:ar_measure/measure/measure_controller.dart';
import 'package:ar_measure/storage/measurement_store.dart';
import 'package:ar_measure/storage/saved_measurement.dart';
import 'package:ar_measure/ui/saved_screen.dart';
import 'package:ar_measure/ui/snapshot.dart';
import 'package:ar_measure/ui/snapshot_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

// A valid 1x1 PNG, usable wherever Image.memory needs real bytes.
final tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Future<void> twoPointDistance(MeasureController c) async {
  c.onFrame(portraitFrame(-0.5, -1.8, {}, 2.0));
  await c.place();
  c.onFrame(portraitFrame(0.55, -1.8, {1: [-0.5, -1.2, -1.8]}, 2.0));
  await c.place();
  c.onFrame(portraitFrame(0.0, -2.6, {
    1: [-0.5, -1.2, -1.8],
    2: [0.55, -1.2, -1.8],
  }, 2.0));
}

void main() {
  group('PrefsMeasurementStore images', () {
    late Directory dir;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('measure_images_');
    });
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    SavedMeasurement entry(String id) => SavedMeasurement(
          id: id,
          mode: MeasureMode.distance,
          value: 1,
          edges: const [1],
          createdAt: DateTime(2026, 11, 1),
          hasImage: true,
        );

    test('round-trips both layers and the hasImage flag', () async {
      final s = PrefsMeasurementStore(imageDirectory: dir);
      await s.save(entry('a'));
      await s.saveImages('a', SavedImages(Uint8List.fromList([1, 2, 3]), Uint8List.fromList([4, 5])));

      final again = PrefsMeasurementStore(imageDirectory: dir); // "restart"
      expect((await again.load()).single.hasImage, isTrue);
      final images = (await again.loadImages('a'))!;
      expect(images.photo, [1, 2, 3]);
      expect(images.overlay, [4, 5]);
      expect(await again.loadImages('nope'), isNull);
    });

    test('older entries without the flag load as hasImage = false', () async {
      SharedPreferences.setMockInitialValues({
        'saved_measurements_v1': ['{"id":"x","mode":"distance","value":1,"edges":[1],"createdAt":1700000000000}'],
      });
      expect((await PrefsMeasurementStore(imageDirectory: dir).load()).single.hasImage, isFalse);
    });

    test('delete and clear remove the picture files too', () async {
      final s = PrefsMeasurementStore(imageDirectory: dir);
      for (final id in ['a', 'b']) {
        await s.save(entry(id));
        await s.saveImages(id, SavedImages(Uint8List(3), Uint8List(3)));
      }
      expect(dir.listSync().length, 4);
      await s.delete('a');
      expect(dir.listSync().map((f) => f.path.split('/').last).toSet(), {'b.jpg', 'b.overlay.png'});
      await s.clear();
      expect(await s.load(), isEmpty);
      expect(dir.existsSync() ? dir.listSync() : [], isEmpty);
    });

    test('only one of the two files => treated as no picture', () async {
      final s = PrefsMeasurementStore(imageDirectory: dir);
      await s.saveImages('a', SavedImages(Uint8List(3), Uint8List(3)));
      File('${dir.path}/a.overlay.png').deleteSync();
      expect(await s.loadImages('a'), isNull);
    });
  });

  group('saving a measurement with a picture', () {
    late FakeAr ar;
    late MemoryMeasurementStore store;
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 1, 2, 3]);
    final png = Uint8List.fromList([9, 9, 9]);
    var rendered = <(Shape, int, Size)>[];

    MeasureController make({OverlayRenderer? renderer}) => MeasureController(
          ar,
          store: store,
          haptics: false,
          overlayRenderer: renderer,
        );

    setUp(() {
      ar = FakeAr();
      store = MemoryMeasurementStore();
      rendered = [];
      ar.capture = ArCapture(
        jpeg: jpeg,
        width: 720,
        height: 1600,
        frame: portraitFrame(null, 0, {}, 0),
      );
    });

    Future<MeasureController> finishedDistance({OverlayRenderer? renderer}) async {
      final c = make(renderer: renderer);
      addTearDown(c.dispose);
      await twoPointDistance(c);
      return c;
    }

    test('stores the photo and the drawn layer and flags the entry', () async {
      final c = await finishedDistance(renderer: (shape, frame, size) async {
        rendered.add((shape, frame.anchors.length, size));
        return png;
      });
      final m = (await c.saveActive())!;
      expect(m.hasImage, isTrue);
      expect(ar.captureCalls, 1);
      expect(rendered.single.$1, same(c.done.single));
      expect(rendered.single.$3, const Size(720, 1600));
      expect(store.images[m.id]!.photo, jpeg);
      expect(store.images[m.id]!.overlay, png);
      expect((await c.imagesFor(m.id))!.overlay, png);
    });

    test('no renderer => no photo is even requested', () async {
      final c = await finishedDistance();
      final m = (await c.saveActive())!;
      expect(m.hasImage, isFalse);
      expect(ar.captureCalls, 0);
    });

    // Each failure mode must still save the numbers, just without a picture.
    final failureModes = <String, (bool, OverlayRenderer)>{
      'the camera capture fails': (false, (_, _, _) async => png),
      'drawing the overlay returns nothing': (true, (_, _, _) async => null),
      'drawing the overlay throws': (true, (_, _, _) async => throw StateError('boom')),
    };
    failureModes.forEach((name, mode) {
      test('still saves the numbers when $name', () async {
        if (!mode.$1) ar.capture = null;
        final c = await finishedDistance(renderer: mode.$2);
        final m = (await c.saveActive())!;
        expect(m.hasImage, isFalse);
        expect(m.value, closeTo(1.05, 1e-4));
        expect(store.items.single.id, m.id);
        expect(store.images, isEmpty);
      });
    });

    test('delete removes the picture; undo brings the picture back', () async {
      final c = await finishedDistance(renderer: (_, _, _) async => png);
      final m = (await c.saveActive())!;
      expect(store.images.containsKey(m.id), isTrue);

      await c.deleteSaved(m.id);
      expect(store.images, isEmpty);
      expect(c.saved, isEmpty);

      await c.restoreSaved(m);
      expect(store.images[m.id]!.photo, jpeg);
      expect(c.saved.single.hasImage, isTrue);

      await c.clearSaved();
      expect(store.images, isEmpty);
    });
  });

  testWidgets('the real overlay renderer draws the measurement on a transparent layer', (tester) async {
    final ar = FakeAr();
    final c = MeasureController(ar, store: MemoryMeasurementStore(), haptics: false);
    addTearDown(c.dispose);
    await twoPointDistance(c);
    final shape = c.done.single;
    final frame = portraitFrame(null, 0, {
      1: [-0.5, -1.2, -1.8],
      2: [0.55, -1.2, -1.8],
    }, 0);

    late Uint8List bytes;
    late int painted, total;
    late int cornerAlpha;
    await tester.runAsync(() async {
      bytes = (await renderOverlayPng(c, shape, frame, const Size(412, 892)))!;
      final codec = await ui.instantiateImageCodec(bytes);
      final img = (await codec.getNextFrame()).image;
      expect((img.width, img.height), (412, 892));
      final rgba = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      total = img.width * img.height;
      painted = 0;
      for (var i = 3; i < rgba.lengthInBytes; i += 4) {
        if (rgba.getUint8(i) > 0) painted++;
      }
      cornerAlpha = rgba.getUint8(3);
      img.dispose();
    });

    expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47], reason: 'PNG signature');
    expect(painted, greaterThan(500), reason: 'line, dots and label were drawn');
    expect(painted, lessThan(total ~/ 4), reason: 'the rest stays transparent so the photo shows');
    expect(cornerAlpha, 0);
  });

  testWidgets('saved list shows a thumbnail for entries with a picture and opens a viewer', (tester) async {
    await tester.runAsync(loadTestFonts);
    final store = MemoryMeasurementStore();
    final withPic = SavedMeasurement(
      id: 'p',
      mode: MeasureMode.distance,
      value: 1.5,
      edges: const [1.5],
      createdAt: DateTime(2026, 11, 2),
      hasImage: true,
    );
    final without = SavedMeasurement(
      id: 'n',
      mode: MeasureMode.area,
      value: 4,
      secondary: 8,
      edges: const [2, 2, 2, 2],
      createdAt: DateTime(2026, 11, 1),
    );
    await store.save(withPic);
    await store.save(without);
    store.images['p'] = SavedImages(tinyPng, tinyPng);
    final c = MeasureController(FakeAr(), store: store, haptics: false);
    addTearDown(c.dispose);
    await c.loadSaved();

    await tester.pumpWidget(MaterialApp(home: SavedScreen(controller: c)));
    await tester.pump();
    await tester.pump();
    expect(find.byType(SnapshotThumb), findsOneWidget, reason: 'only the entry with a picture');
    expect(find.byIcon(Icons.pentagon_outlined), findsOneWidget, reason: 'the other keeps its icon');

    await tester.tap(find.byType(SnapshotThumb));
    await tester.pumpAndSettle();
    expect(find.byType(SnapshotViewer), findsOneWidget);
    expect(find.text('1.50 m'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
