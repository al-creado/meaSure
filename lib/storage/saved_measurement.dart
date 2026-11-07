import '../measure/measure_controller.dart';
import '../measure/units.dart';

/// A measurement the user chose to keep. Values are stored in SI units (metres, square
/// metres, degrees) and only formatted for display, so the unit toggle works on old entries.
class SavedMeasurement {
  const SavedMeasurement({
    required this.id,
    required this.mode,
    required this.value,
    required this.edges,
    required this.createdAt,
    this.secondary,
    this.note,
  });

  final String id;
  final MeasureMode mode;

  /// Distance (m), area (m²) or angle (degrees).
  final double value;

  /// Area: perimeter (m). Otherwise null.
  final double? secondary;

  /// Lengths of the individual sides in metres (one for distance, two arms for angle,
  /// every edge for area).
  final List<double> edges;

  final DateTime createdAt;
  final String? note;

  SavedMeasurement withNote(String? note) => SavedMeasurement(
    id: id,
    mode: mode,
    value: value,
    secondary: secondary,
    edges: edges,
    createdAt: createdAt,
    note: (note == null || note.trim().isEmpty) ? null : note.trim(),
  );

  String valueText(UnitSystem u) => switch (mode) {
    MeasureMode.distance => formatLength(value, u),
    MeasureMode.area => formatArea(value, u),
    MeasureMode.angle => formatAngle(value),
  };

  String? detailText(UnitSystem u) => switch (mode) {
    MeasureMode.distance => null,
    MeasureMode.area =>
      secondary == null ? null : 'Perimeter ${formatLength(secondary!, u)}',
    MeasureMode.angle =>
      edges.length == 2
          ? 'Arms ${formatLength(edges[0], u)} · ${formatLength(edges[1], u)}'
          : null,
  };

  /// Plain-text form for the clipboard.
  String asText(UnitSystem u) {
    final parts = [
      '${mode.label}: ${valueText(u)}',
      if (detailText(u) != null) detailText(u)!,
      ?note,
    ];
    return parts.join(' — ');
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'mode': mode.name,
    'value': value,
    'secondary': secondary,
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
    edges: [
      for (final e in (j['edges'] as List? ?? const [])) (e as num).toDouble(),
    ],
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt']! as int),
    note: j['note'] as String?,
  );
}
