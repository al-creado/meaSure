enum UnitSystem { metric, imperial }

extension UnitSystemX on UnitSystem {
  UnitSystem get other =>
      this == UnitSystem.metric ? UnitSystem.imperial : UnitSystem.metric;
  String get label => this == UnitSystem.metric ? 'm' : 'ft';
}

const _metersPerInch = 0.0254;

/// Formats a length given in metres.
String formatLength(double meters, UnitSystem units) {
  if (units == UnitSystem.metric) {
    if (meters < 0.01) return '${(meters * 1000).round()} mm';
    if (meters < 1) return '${(meters * 100).toStringAsFixed(1)} cm';
    return '${meters.toStringAsFixed(2)} m';
  }
  final inches = meters / _metersPerInch;
  if (inches < 12) return '${_trim(inches, 1)} in';
  // Round to the nearest half inch, then split into feet and inches.
  final halves = (inches * 2).round();
  final feet = halves ~/ 24;
  final rest = (halves - feet * 24) / 2;
  return '$feet′ ${_trim(rest, 1)}″';
}

/// Formats an area given in square metres.
String formatArea(double squareMeters, UnitSystem units) {
  if (units == UnitSystem.metric) {
    if (squareMeters < 0.1) {
      return '${(squareMeters * 10000).toStringAsFixed(0)} cm²';
    }
    return '${squareMeters.toStringAsFixed(2)} m²';
  }
  final sqFt = squareMeters / (0.3048 * 0.3048);
  if (sqFt < 1) return '${(sqFt * 144).toStringAsFixed(0)} in²';
  return '${sqFt.toStringAsFixed(2)} ft²';
}

String formatAngle(double degrees) => '${degrees.toStringAsFixed(1)}°';

String _trim(double v, int digits) {
  final s = v.toStringAsFixed(digits);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// Formats a volume given in cubic metres.
String formatVolume(double cubicMeters, UnitSystem units) {
  if (units == UnitSystem.metric) {
    return '${_volumeNumber(cubicMeters)} m\u00B3';
  }
  return '${_volumeNumber(cubicMeters * 35.3146667)} ft\u00B3';
}

// 2 decimals for small volumes, whole numbers with thousands separators for big ones.
String _volumeNumber(double v) {
  if (v < 100) return v.toStringAsFixed(2);
  final whole = v.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  return buf.toString();
}

/// Parses a length typed by the user in the current unit system and returns metres, or null
/// if it is not a positive number. Accepts "8", "8.5", "8,5"; imperial also accepts
/// feet and inches like "26 ft 3" / "26'3\"".
double? parseLengthInput(String text, UnitSystem units) {
  final t = text.trim().toLowerCase().replaceAll(',', '.');
  if (t.isEmpty) return null;
  if (units == UnitSystem.metric) {
    final v = double.tryParse(t);
    return (v != null && v.isFinite && v > 0) ? v : null;
  }
  // "11.7 in" (inches only) must not be read as 11.7 feet.
  final inchesOnly = RegExp(r"""^(\d+(?:\.\d+)?)\s*(?:in|inch|inches|")$""").firstMatch(t);
  if (inchesOnly != null) {
    final meters = double.parse(inchesOnly.group(1)!) * 0.0254;
    return meters > 0 ? meters : null;
  }
  // Feet, optionally followed by inches. Inches may only follow a feet marker, so "11 7"
  // is rejected rather than guessed at; a bare number is feet.
  final m = RegExp(
    r"""^(\d+(?:\.\d+)?)\s*(?:(?:ft|feet|foot|')\s*(?:(\d+(?:\.\d+)?)\s*(?:in|inch|inches|")?)?)?$""",
  ).firstMatch(t);
  if (m == null) return null;
  final feet = double.parse(m.group(1)!);
  final inches = m.group(2) == null ? 0.0 : double.parse(m.group(2)!);
  final meters = (feet * 12 + inches) * 0.0254;
  return meters > 0 ? meters : null;
}

/// Parses the real length of a reference object typed by the user and returns metres, or
/// null if it is not a positive number. Meant for small things (a sheet of paper, a card, a
/// tape measure), so a bare number means centimetres (inches in imperial); units can be
/// given: "29.7", "297 mm", "0.297 m", "11.7 in", "2 ft 3".
double? parseReferenceLength(String text, UnitSystem units) {
  final t = text.trim().toLowerCase().replaceAll(',', '.');
  if (t.isEmpty) return null;
  if (units == UnitSystem.metric) {
    final m = RegExp(r'^(\d+(?:\.\d+)?)\s*(mm|cm|m)?$').firstMatch(t);
    if (m == null) return null;
    final v = double.parse(m.group(1)!);
    final meters = switch (m.group(2)) {
      'mm' => v / 1000,
      'm' => v,
      _ => v / 100,
    };
    return meters > 0 ? meters : null;
  }
  // Imperial: a bare number is inches; anything with feet/inches goes through the usual parser.
  final bare = RegExp(r'^(\d+(?:\.\d+)?)$').firstMatch(t);
  if (bare != null) {
    final meters = double.parse(bare.group(1)!) * 0.0254;
    return meters > 0 ? meters : null;
  }
  return parseLengthInput(t, units);
}
