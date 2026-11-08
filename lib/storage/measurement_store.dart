import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'saved_measurement.dart';

/// The picture saved with a measurement: the camera photo, and the measurement drawn on a
/// transparent layer the same size. Kept apart so the drawing stays sharp at any size and
/// the files stay small.
class SavedImages {
  const SavedImages(this.photo, this.overlay);

  final Uint8List photo; // JPEG
  final Uint8List overlay; // PNG with transparency
}

/// Where saved measurements live. Newest first.
abstract class MeasurementStore {
  Future<List<SavedMeasurement>> load();

  /// Inserts or replaces (by id).
  Future<void> save(SavedMeasurement m);

  /// Removes the entry and its images.
  Future<void> delete(String id);

  /// Removes everything, images included.
  Future<void> clear();

  Future<void> saveImages(String id, SavedImages images);

  Future<SavedImages?> loadImages(String id);
}

/// On-device storage: measurements in SharedPreferences, pictures as files in the app's
/// private documents folder. Nothing leaves the phone.
class PrefsMeasurementStore implements MeasurementStore {
  /// [imageDirectory] is for tests; the app uses its documents folder.
  PrefsMeasurementStore({this.imageDirectory});

  static const _key = 'saved_measurements_v1';
  static const maxEntries = 500;

  final Directory? imageDirectory;

  Future<Directory> _images() async {
    final dir = imageDirectory ??
        Directory('${(await getApplicationDocumentsDirectory()).path}/measurement_images');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  File _photoFile(Directory d, String id) => File('${d.path}/$id.jpg');
  File _overlayFile(Directory d, String id) => File('${d.path}/$id.overlay.png');

  Future<void> _deleteImages(String id) async {
    try {
      final d = await _images();
      for (final f in [_photoFile(d, id), _overlayFile(d, id)]) {
        if (f.existsSync()) await f.delete();
      }
    } catch (_) {
      // Leftover image files are harmless; never fail a delete because of them.
    }
  }

  Future<List<SavedMeasurement>> _read(SharedPreferences p) async {
    final out = <SavedMeasurement>[];
    for (final s in p.getStringList(_key) ?? const <String>[]) {
      try {
        out.add(SavedMeasurement.fromJson((jsonDecode(s) as Map).cast<String, Object?>()));
      } catch (_) {
        // A corrupt entry must never take the whole list down.
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> _write(SharedPreferences p, List<SavedMeasurement> items) async {
    for (final dropped in items.skip(maxEntries)) {
      await _deleteImages(dropped.id);
    }
    await p.setStringList(_key, [for (final m in items.take(maxEntries)) jsonEncode(m.toJson())]);
  }

  @override
  Future<List<SavedMeasurement>> load() async => _read(await SharedPreferences.getInstance());

  @override
  Future<void> save(SavedMeasurement m) async {
    final p = await SharedPreferences.getInstance();
    final items = await _read(p);
    items.removeWhere((e) => e.id == m.id);
    items.add(m);
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _write(p, items);
  }

  @override
  Future<void> delete(String id) async {
    final p = await SharedPreferences.getInstance();
    final items = await _read(p);
    items.removeWhere((e) => e.id == id);
    await _write(p, items);
    await _deleteImages(id);
  }

  @override
  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
    try {
      final d = await _images();
      if (d.existsSync()) await d.delete(recursive: true);
    } catch (_) {}
  }

  @override
  Future<void> saveImages(String id, SavedImages images) async {
    final d = await _images();
    await _photoFile(d, id).writeAsBytes(images.photo, flush: true);
    await _overlayFile(d, id).writeAsBytes(images.overlay, flush: true);
  }

  @override
  Future<SavedImages?> loadImages(String id) async {
    try {
      final d = await _images();
      final photo = _photoFile(d, id), overlay = _overlayFile(d, id);
      if (!photo.existsSync() || !overlay.existsSync()) return null;
      return SavedImages(await photo.readAsBytes(), await overlay.readAsBytes());
    } catch (_) {
      return null;
    }
  }
}

/// For tests and previews.
class MemoryMeasurementStore implements MeasurementStore {
  final List<SavedMeasurement> items = [];
  final Map<String, SavedImages> images = {};

  @override
  Future<List<SavedMeasurement>> load() async => List.of(items);

  @override
  Future<void> save(SavedMeasurement m) async {
    items.removeWhere((e) => e.id == m.id);
    items.insert(0, m);
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> delete(String id) async {
    items.removeWhere((e) => e.id == id);
    images.remove(id);
  }

  @override
  Future<void> clear() async {
    items.clear();
    images.clear();
  }

  @override
  Future<void> saveImages(String id, SavedImages i) async => images[id] = i;

  @override
  Future<SavedImages?> loadImages(String id) async => images[id];
}
