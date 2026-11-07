import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'saved_measurement.dart';

/// Where saved measurements live. Newest first.
abstract class MeasurementStore {
  Future<List<SavedMeasurement>> load();

  /// Inserts or replaces (by id).
  Future<void> save(SavedMeasurement m);

  Future<void> delete(String id);

  Future<void> clear();
}

/// On-device storage using SharedPreferences (a small private file in the app's data).
/// Nothing leaves the phone. Fine for hundreds of entries; move to a database if you ever
/// need thousands.
class PrefsMeasurementStore implements MeasurementStore {
  static const _key = 'saved_measurements_v1';
  static const maxEntries = 500;

  Future<List<SavedMeasurement>> _read(SharedPreferences p) async {
    final out = <SavedMeasurement>[];
    for (final s in p.getStringList(_key) ?? const <String>[]) {
      try {
        out.add(
          SavedMeasurement.fromJson(
            (jsonDecode(s) as Map).cast<String, Object?>(),
          ),
        );
      } catch (_) {
        // A corrupt entry must never take the whole list down.
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> _write(SharedPreferences p, List<SavedMeasurement> items) =>
      p.setStringList(_key, [
        for (final m in items.take(maxEntries)) jsonEncode(m.toJson()),
      ]);

  @override
  Future<List<SavedMeasurement>> load() async =>
      _read(await SharedPreferences.getInstance());

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
  }

  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(_key);
}

/// For tests and previews.
class MemoryMeasurementStore implements MeasurementStore {
  final List<SavedMeasurement> items = [];

  @override
  Future<List<SavedMeasurement>> load() async => List.of(items);

  @override
  Future<void> save(SavedMeasurement m) async {
    items.removeWhere((e) => e.id == m.id);
    items.insert(0, m);
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> delete(String id) async => items.removeWhere((e) => e.id == id);

  @override
  Future<void> clear() async => items.clear();
}
