import '../measure/measure_controller.dart';
import '../measure/units.dart';

/// A measurement the user chose to keep. Values are stored in SI units (metres, square
/// metres, cubic metres, degrees) and only formatted for display, so the unit toggle
/// works on old entries.
class SavedMeasurement {
  const SavedMeasurement({
    required this.id,
    required this.mode,
    required this.value,
    required this.edges,
    required this.createdAt,
    this.secondary,
    this.height,
    this.loopError,
    this.loopPath,
    this.hasImage = false,
    this.note,
  });

  final String id;
  final MeasureMode mode;

  /// Distance (m), area (m²), volume (m³) or angle (degrees).
  final double value;

  /// Area: perimeter (m). Volume: floor area (m²). Otherwise null.
  final double? secondary;

  /// Volume only: the height that was used (m).
  final double? height;

  /// If the outline was closed with "Close loop": how far the walk ended from where it
  /// started (m), and how long that walk was (m).
  final double? loopError;
  final double? loopPath;

  /// A photo of the scene with the measurement drawn on it was saved with this entry.
  final bool hasImage;

  /// Lengths of the individual sides in metres (one for distance, two arms for angle,
  /// every edge of the outline for area and volume).
  final List<double> edges;

  final DateTime createdAt;
  final String? note;

  SavedMeasurement withNote(String? note) => SavedMeasurement(
    id: id,
    mode: mode,
    value: value,
    secondary: secondary,
    height: height,
    loopError: loopError,
    loopPath: loopPath,
    hasImage: hasImage,
    edges: edges,
    createdAt: createdAt,
    note: (note == null || note.trim().isEmpty) ? null : note.trim(),
  );

  String valueText(UnitSystem u) => switch (mode) {
    MeasureMode.distance => formatLength(value, u),
    MeasureMode.area => formatArea(value, u),
    MeasureMode.volume => formatVolume(value, u),
    MeasureMode.angle => formatAngle(value),
  };

  /// Secondary lines under the value (may contain a newline), or null.
  String? detailText(UnitSystem u) {
    final main = switch (mode) {
      MeasureMode.distance => null,
      MeasureMode.area =>
        secondary == null ? null : 'Perimeter ${formatLength(secondary!, u)}',
      MeasureMode.volume =>
        secondary == null || height == null
            ? null
            : '${formatArea(secondary!, u)} × ${formatLength(height!, u)}',
      MeasureMode.angle =>
        edges.length == 2
            ? 'Arms ${formatLength(edges[0], u)} · ${formatLength(edges[1], u)}'
            : null,
    };
    final lines = [?main, ?loopText(u)];
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// e.g. "Loop closed, error 0.42 m (0.17 %)".
  String? loopText(UnitSystem u) {
    final err = loopError, path = loopPath;
    if (err == null || path == null || path <= 0) return null;
    return 'Loop closed, error ${formatLength(err, u)} '
        '(${(err / path * 100).toStringAsFixed(2)} %)';
  }

  /// Plain-text form for the clipboard.
  String asText(UnitSystem u) {
    final parts = [
      '${mode.label}: ${valueText(u)}',
      ?detailText(u)?.replaceAll('\n', ', '),
      ?note,
    ];
    return parts.join(' — ');
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'mode': mode.name,
    'value': value,
    'secondary': secondary,
    'height': height,
    'loopError': loopError,
    'loopPath': loopPath,
    'hasImage': hasImage,
    'edges': edges,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'note': note,
  };

  /// Throws if the data is malformed; the store skips such entries.
  factory SavedMeasurement.fromJson(Map<String, Object?> j) => SavedMeasurement(
    id: j['id']! as String,
    mode: MeasureMode.values.byName(j['mode']! as String),
    value: (j['value']! as num).toDouble(),
    secondary: (j['secondary'] as num?)?.toDouble(),
    height: (j['height'] as num?)?.toDouble(),
    loopError: (j['loopError'] as num?)?.toDouble(),
    loopPath: (j['loopPath'] as num?)?.toDouble(),
    hasImage: j['hasImage'] == true,
    edges: [
      for (final e in (j['edges'] as List? ?? const [])) (e as num).toDouble(),
    ],
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt']! as int),
    note: j['note'] as String?,
  );
}
