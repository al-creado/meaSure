# Measure

A lightweight AR tape measure for Android, in Flutter. Point the camera, tap **+**, read the
distance. Modes: **Distance**, **Area** (any polygon, on floors, walls or tabletops) and **Angle**.
Metric / imperial, snapping to existing points, haptics, and a live accuracy indicator.

## Architecture

```
Flutter (Dart)                                   Android (Kotlin)
──────────────────────────────────────────       ──────────────────────────────────────
ui/measure_screen.dart   HUD, mode switcher      ArMeasureView.kt  ARCore session + hit-testing
ui/overlay_painter.dart  reticle/lines/labels    BackgroundRenderer.kt  camera image (GL)
measure/*                modes, snapping, math   ArBridge.kt / MainActivity.kt  channels
ar/ar_frame.dart         decodes a frame         
ar/projector.dart        world -> screen         one Float32List per camera frame (~30 Hz)
```

ARCore is driven directly (no third-party Flutter AR plugin - those are unmaintained and
built on the deprecated Sceneform). Native code owns the camera, tracking, depth and anchors.
Flutter only receives a flat float array per frame (view + projection matrices, the surface
under the reticle, and anchor positions) and draws the overlay itself with the *same*
matrices, so lines stay locked to the world. No 3D engine, no meshes: that is what keeps it light.

## Run it

Needs a physical ARCore-capable phone (emulators have no usable camera tracking).

```bash
flutter pub get
flutter run --release
```

First launch asks for camera permission and installs *Google Play Services for AR* if missing.
`minSdk` is 24 (ARCore's minimum).

```bash
flutter analyze && flutter test
```

## How accuracy is achieved

Phone AR realistically gives ~1-2 % error at 0.5-3 m with good conditions. The app maximises
what ARCore can do and tells you when conditions are poor:

| Technique | Where |
|---|---|
| Hardware depth (ToF / stereo) camera config when the device has one | `ArMeasureView.configure` |
| Depth API (`DepthMode.AUTOMATIC`) so hits land on real geometry, not sparse feature points | `ArMeasureView.configure` |
| Only trust *tracked* planes (inside their polygon), depth points and oriented feature points | `pickHit` |
| Nearest surface wins (top of a box, not the table behind), but a detected plane within 2 cm replaces a noisy depth sample | `pickHit` |
| The reticle position is the **median of the last 5 hits**: kills outliers/jitter with no low-pass lag, and the same value is what is placed | `process` |
| Points are anchored to the trackable they hit, so ARCore keeps refining them as its map improves | `createAnchorAt` |
| Magnetic snapping to existing points (close shapes, share corners) | `MeasureController._updateReticle` |
| Range gating: refuses < 0.15 m and > 6 m, warns beyond 3 m | `MeasureController` |
| Live tracking diagnostics (too dark, moving too fast, not enough detail) | `_buildHud` |
| 3D polygon area (vector area), valid on any orientation | `measure/geometry.dart` |

Tips for users: move the phone slowly side-to-side for a few seconds before measuring (parallax
is what ARCore needs), measure from 0.5-3 m, aim at textured, well-lit surfaces (blank white
walls and glass track poorly), and place both ends of a line from the same position when you can.

### Ideas to push it further

- **Raw Depth API** (`acquireRawDepthImage16Bits` + confidence image): average a small patch
  and reject low-confidence pixels instead of one ray.
- **Per-device calibration**: measure a known object (A4 sheet, credit card) and store a
  scale factor to cancel systematic bias.
- **Edge snapping** from the camera image / depth discontinuities for exact object corners.
- Distance-from-camera error bars in the label.

## Status

The Dart side (logic, projection, UI) is covered by unit tests and analysed clean. The Kotlin
ARCore layer has **not yet been compiled or run on a device** - build it on a machine with the
Android SDK and tune on real hardware.
