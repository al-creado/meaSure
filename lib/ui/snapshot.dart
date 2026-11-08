import 'dart:typed_data';
import 'dart:ui' as ui;


import '../ar/ar_frame.dart';
import '../measure/measure_controller.dart';
import 'overlay_painter.dart';

/// Draws [shape] (lines, points, labels, the 3D box for volumes) on a transparent image of
/// [pixels] size, using the AR data [frame] of the camera photo it will sit on.
///
/// The UI is laid out for a ~412 dp wide phone, so the drawing is made at that size and
/// scaled up: the result looks the same as on screen. Returns PNG bytes.
Future<Uint8List?> renderOverlayPng(
  MeasureController c,
  Shape shape,
  ArFrame frame,
  ui.Size pixels,
) async {
  const logicalWidth = 412.0;
  if (pixels.width < 1 || pixels.height < 1) return null;
  final scale = pixels.width / logicalWidth;
  final logical = ui.Size(logicalWidth, pixels.height / scale);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(scale);
  OverlayPainter.snapshot(c, frame, shape).paint(canvas, logical);
  final picture = recorder.endRecording();
  final image = await picture.toImage(pixels.width.round(), pixels.height.round());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
