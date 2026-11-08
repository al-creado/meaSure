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
