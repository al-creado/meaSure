import 'package:flutter/material.dart';

/// Accent used for the live measurement, the reticle when snapping, and the capture button.
const kAccent = Color(0xFFFFD60A);

/// Translucent dark surface used by every HUD element. Deliberately *not* blurred:
/// a backdrop blur over a camera preview is expensive and this keeps the UI light.
const kPanel = Color(0x99111418);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kAccent,
    brightness: Brightness.dark,
    surface: const Color(0xFF111418),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.black,
    splashFactory: InkRipple.splashFactory,
  );
}
