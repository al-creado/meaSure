import 'package:flutter/material.dart';

import '../measure/measure_controller.dart';
import '../measure/units.dart';
import '../storage/measurement_store.dart';
import '../storage/saved_measurement.dart';
import 'theme.dart';

/// The saved camera photo with the measurement drawn over it. Both layers have the same
/// size, so with the same [fit] they line up exactly.
class SnapshotImage extends StatelessWidget {
  const SnapshotImage({super.key, required this.images, this.fit = BoxFit.cover, this.cacheWidth});

  final SavedImages images;
  final BoxFit fit;

  /// Decode at this width to save memory when showing thumbnails.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(images.photo, fit: fit, cacheWidth: cacheWidth, gaplessPlayback: true),
        Image.memory(images.overlay, fit: fit, cacheWidth: cacheWidth, gaplessPlayback: true),
      ],
    );
  }
}

/// Small preview shown in the saved list; tap to open full screen.
class SnapshotThumb extends StatelessWidget {
  const SnapshotThumb({super.key, required this.controller, required this.item});

  final MeasureController controller;
  final SavedMeasurement item;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SavedImages?>(
      future: controller.imagesFor(item.id),
      builder: (context, snap) {
        final images = snap.data;
        return GestureDetector(
          onTap: images == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SnapshotViewer(images: images, item: item, units: controller.units),
                  ),
                ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 72,
              child: images == null
                  ? const ColoredBox(color: kPanel)
                  : SnapshotImage(images: images, cacheWidth: 200),
            ),
          ),
        );
      },
    );
  }
}

/// Full-screen, pinch-to-zoom view of a saved measurement picture.
class SnapshotViewer extends StatelessWidget {
  const SnapshotViewer({super.key, required this.images, required this.item, required this.units});

  final SavedImages images;
  final SavedMeasurement item;
  final UnitSystem units;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(item.valueText(units)),
      ),
      body: InteractiveViewer(
        maxScale: 5,
        child: SnapshotImage(images: images, fit: BoxFit.contain),
      ),
    );
  }
}
