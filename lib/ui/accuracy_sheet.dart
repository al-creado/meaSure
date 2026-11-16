import 'package:flutter/material.dart';

import '../measure/measure_controller.dart';
import '../measure/units.dart';
import 'theme.dart';

/// Opens the Accuracy sheet: scale calibration and tips.
Future<void> showAccuracySheet(BuildContext context, MeasureController c) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF15181C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _AccuracySheet(controller: c),
  );
}

class _AccuracySheet extends StatefulWidget {
  const _AccuracySheet({required this.controller});

  final MeasureController controller;

  @override
  State<_AccuracySheet> createState() => _AccuracySheetState();
}

class _AccuracySheetState extends State<_AccuracySheet> {
  String? _message;
  bool _messageIsWarning = false;

  MeasureController get c => widget.controller;

  Future<void> _calibrate() async {
    final shown = c.referenceLength;
    if (shown == null) return;
    final real = await showCalibrateDialog(
      context,
      shownMeters: shown,
      units: c.units,
    );
    if (real == null) return;
    final ok = c.calibrateTo(real);
    if (!mounted) return;
    setState(() {
      if (!ok) {
        _messageIsWarning = true;
        _message =
            'That would change the scale by more than 2×, which is almost '
            'certainly a mistake. Check that both points sit exactly on the ends '
            'of the object and that you typed its real length.';
      } else {
        final pct = (c.calibration - 1) * 100;
        _messageIsWarning = pct.abs() > 10;
        _message = pct.abs() > 10
            ? 'Calibrated, but that is a large correction (${pct.toStringAsFixed(1)} %). '
                'If it surprises you, check where the points were.'
            : 'Calibrated. Measurements now use ×${c.calibration.toStringAsFixed(3)}.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final reference = c.referenceLength;
        final pct = (c.calibration - 1) * 100;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Accuracy', style: text.titleLarge),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2228),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.straighten_rounded, size: 20, color: kAccent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              c.isCalibrated
                                  ? 'Scale calibrated ×${c.calibration.toStringAsFixed(3)} '
                                      '(${pct >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(1)} %)'
                                  : 'Scale not calibrated',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'The phone can misjudge overall size by a few percent, and by '
                        'different amounts each time. Measure something of known length '
                        'once and every measurement is corrected to match.',
                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.35),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: reference == null ? null : _calibrate,
                              icon: const Icon(Icons.tune_rounded, size: 18),
                              label: Text(
                                reference == null
                                    ? 'Calibrate scale'
                                    : 'Calibrate to ${formatLength(reference, c.units)}',
                              ),
                            ),
                          ),
                          if (c.isCalibrated) ...[
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: () => setState(() {
                                c.resetCalibration();
                                _messageIsWarning = false;
                                _message = 'Calibration removed.';
                              }),
                              child: const Text('Reset'),
                            ),
                          ],
                        ],
                      ),
                      if (reference == null) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'First measure something of known length in Distance mode: a '
                          'tape measure, an A4 sheet (29.7 cm) or a credit card (8.56 cm). '
                          'Place a point at each end, then open this sheet again.',
                          style: TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.35),
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _message!,
                          style: TextStyle(
                            color: _messageIsWarning ? kAccent : const Color(0xFF30D158),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text('For the best accuracy', style: text.titleSmall),
                const SizedBox(height: 8),
                const _Tip('Calibrate at the start of each session, and again if tracking was lost.'),
                const _Tip('Use a long reference (a 2–3 m tape beats a credit card): its error is a smaller share of the length.'),
                const _Tip('Move the phone side to side for a few seconds first, so it can judge depth.'),
                const _Tip('Measure from 0.5–3 m, aiming at textured, well-lit surfaces.'),
                const _Tip('Large spaces: measure in zones and use Close loop to see the drift.'),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 10),
            child: Icon(Icons.circle, size: 5, color: Colors.white38),
          ),
          Expanded(
            child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

/// Asks for the real length of the reference object. Returns metres, or null if cancelled.
Future<double?> showCalibrateDialog(
  BuildContext context, {
  required double shownMeters,
  required UnitSystem units,
}) {
  return showDialog<double>(
    context: context,
    builder: (_) => _CalibrateDialog(shownMeters: shownMeters, units: units),
  );
}

class _CalibrateDialog extends StatefulWidget {
  const _CalibrateDialog({required this.shownMeters, required this.units});

  final double shownMeters;
  final UnitSystem units;

  @override
  State<_CalibrateDialog> createState() => _CalibrateDialogState();
}

class _CalibrateDialogState extends State<_CalibrateDialog> {
  // Common reference objects (real, standardised sizes), in metres.
  static const _presets = <(String, double)>[
    ('A4 long side', 0.297),
    ('A4 short side', 0.210),
    ('Credit card', 0.08560),
  ];

  // The field owns its controller here, so it is disposed with the dialog (never earlier).
  late final TextEditingController _field = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  bool get _metric => widget.units == UnitSystem.metric;

  void _submit() {
    final meters = parseReferenceLength(_field.text, widget.units);
    if (meters == null) {
      setState(() => _error = 'Enter a length, for example ${_metric ? '29.7 or 297 mm' : "11.7 or 2' 3"}');
      return;
    }
    Navigator.pop(context, meters);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Real length'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The app measured ${formatLength(widget.shownMeters, widget.units)}. '
            'How long is it really?',
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (name, meters) in _presets)
                ActionChip(
                  label: Text(name),
                  onPressed: () => setState(() {
                    _error = null;
                    _field.text = _metric
                        ? (meters * 100).toStringAsFixed(meters == 0.0856 ? 2 : 1)
                        : (meters / 0.0254).toStringAsFixed(2);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _field,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: _metric ? 'e.g. 29.7' : 'e.g. 11.7',
              suffixText: _metric ? 'cm' : 'in',
              helperText: _metric ? 'cm by default; or add mm / m' : 'inches by default; or ft',
              errorText: _error,
              errorMaxLines: 2,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _submit, child: const Text('Calibrate')),
      ],
    );
  }
}
