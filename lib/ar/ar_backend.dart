import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'ar_frame.dart';

enum ArAvailability { ready, installing, declined, unsupported }

/// What the measuring logic needs from the AR engine. The real implementation talks to
/// ARCore over platform channels; tests use a fake.
abstract class ArBackend {
  Stream<ArFrame> get frames;

  Future<ArAvailability> ensureArCore();

  /// Places an anchor at the current reticle position (or at the existing anchor [snapId]).
  /// Returns the new anchor id, or a value <= 0 when nothing could be placed.
  Future<int> place({int? snapId});

  Future<void> remove(int id);

  Future<void> clear();
}

class ArChannel implements ArBackend {
  static const _control = MethodChannel('armeasure/control');
  static const _events = EventChannel('armeasure/frames');

  @override
  Stream<ArFrame> get frames => _events
      .receiveBroadcastStream()
      .where((e) => e is Float32List && e.length >= ArFrame.header)
      .map((e) => ArFrame(e as Float32List));

  @override
  Future<ArAvailability> ensureArCore() async {
    final r = await _control.invokeMethod<String>('ensureArCore');
    return switch (r) {
      'ready' => ArAvailability.ready,
      'installing' => ArAvailability.installing,
      'declined' => ArAvailability.declined,
      _ => ArAvailability.unsupported,
    };
  }

  @override
  Future<int> place({int? snapId}) async =>
      await _control.invokeMethod<int>('place', {'snapId': snapId}) ?? -1;

  @override
  Future<void> remove(int id) => _control.invokeMethod('remove', {'id': id});

  @override
  Future<void> clear() => _control.invokeMethod('clear');
}
