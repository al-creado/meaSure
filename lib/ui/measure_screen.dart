import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ar/ar_backend.dart';
import '../measure/measure_controller.dart';
import '../measure/units.dart';
import '../storage/measurement_store.dart';
import 'ar_view.dart';
import 'overlay_painter.dart';
import 'prompt_dialog.dart';
import 'saved_screen.dart';
import 'snapshot.dart';
import 'theme.dart';

class MeasureScreen extends StatefulWidget {
  const MeasureScreen({
    super.key,
    required this.backend,
    required this.store,
    this.background = const ArView(),
  });

  final ArBackend backend;
  final MeasurementStore store;

  /// The live camera view. Replaceable so the UI can be previewed without a camera.
  final Widget background;

  @override
  State<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends State<MeasureScreen> {
  late final MeasureController _c = MeasureController(
    widget.backend,
    store: widget.store,
    // Saving a measurement also stores a photo of the scene with it drawn on top.
    overlayRenderer: (shape, frame, size) =>
        renderOverlayPng(_c, shape, frame, size),
  )..start();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          widget.background,
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: OverlayPainter(_c)),
            ),
          ),
          SafeArea(
            child: ListenableBuilder(
              listenable: _c,
              builder: (context, _) => _Hud(controller: _c),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.controller});

  final MeasureController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final hud = c.hud;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onLongPress: c.toggleDebug,
                child: _AccuracyPill(quality: hud.quality, depth: hud.depth),
              ),
              const Spacer(),
              _SavedButton(
                count: c.saved.length,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SavedScreen(controller: c),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _Pill(
                onTap: () {
                  HapticFeedback.selectionClick();
                  c.toggleUnits();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.swap_horiz_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      c.units.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // AnimatedSize, not AnimatedSwitcher: the value can appear and vanish several times
          // within one animation (the reticle losing the surface), and switcher children
          // with a repeated key trip Flutter's duplicate-key assertion.
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: hud.value == null
                ? const SizedBox.shrink()
                : _ResultCard(
                    value: hud.value!,
                    sub: hud.sub,
                    canSave: hud.canSave,
                    isSaved: hud.isSaved,
                    onSave: () => _save(context, c),
                  ),
          ),
          const SizedBox(height: 10),
          _Hint(text: hud.hint, warning: hud.hintIsWarning),
          if (c.showDebug) _DebugPanel(controller: c),
          const Spacer(),
          if (hud.canCloseLoop)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Pill(
                onTap: () => _closeLoop(context, c),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync_rounded, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Close loop at start corner',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          if (hud.canTypeHeight)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Pill(
                onTap: () => _typeHeight(context, c),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'Type height',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          _ModeSelector(mode: c.mode, onChanged: c.setMode),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                width: 64,
                child: _RoundButton(
                  icon: Icons.undo_rounded,
                  tooltip: 'Undo',
                  onPressed: hud.canUndo ? c.undo : null,
                ),
              ),
              _CaptureButton(
                enabled: hud.canPlace,
                snapping: hud.snapping,
                onPressed: c.place,
              ),
              SizedBox(
                width: 64,
                child: hud.canFinish
                    ? _RoundButton(
                        icon: Icons.check_rounded,
                        tooltip: 'Finish outline',
                        filled: true,
                        onPressed: c.finishOutline,
                      )
                    : _RoundButton(
                        icon: Icons.delete_outline_rounded,
                        tooltip: 'Clear all',
                        onPressed: hud.canUndo ? c.clearAll : null,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kPanel,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 13, color: Colors.white),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _AccuracyPill extends StatelessWidget {
  const _AccuracyPill({required this.quality, required this.depth});

  final int quality;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final label = switch (quality) {
      3 => 'Good',
      2 => 'Fair',
      1 => 'Low',
      _ => 'Scanning',
    };
    final color = switch (quality) {
      3 => const Color(0xFF30D158),
      2 => kAccent,
      1 => const Color(0xFFFF453A),
      _ => Colors.white54,
    };
    return _Pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Little signal-strength bars.
          for (var i = 1; i <= 3; i++)
            Container(
              width: 4,
              height: 5.0 + i * 3,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                color: i <= quality ? color : Colors.white24,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (depth > 0) ...[
            const SizedBox(width: 8),
            Text(
              depth == 2 ? 'ToF' : 'Depth',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    super.key,
    required this.value,
    this.sub,
    this.canSave = false,
    this.isSaved = false,
    this.onSave,
  });

  final String value;
  final String? sub;
  final bool canSave;
  final bool isSaved;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final showSave = canSave || isSaved;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 12, showSave ? 10 : 22, 12),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flexible so a long sub-line wraps instead of overflowing small screens.
          Flexible(
            child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (sub != null)
                Text(
                  sub!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white60,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
            ),
          ),
          if (showSave) ...[
            const SizedBox(width: 10),
            Tooltip(
              message: isSaved ? 'Saved' : 'Save measurement',
              child: Material(
                color: isSaved ? Colors.transparent : kAccent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: canSave ? onSave : null,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      isSaved
                          ? Icons.bookmark_added_rounded
                          : Icons.bookmark_add_outlined,
                      color: isSaved ? kAccent : Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SavedButton extends StatelessWidget {
  const _SavedButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Saved measurements',
      child: _Pill(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bookmarks_outlined, size: 18),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text(
                '$count',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _save(BuildContext context, MeasureController c) async {
  final messenger = ScaffoldMessenger.of(context);
  final m = await c.saveActive();
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 170),
      content: Text(
        m == null
            ? 'Could not save \u2013 keep the points in view and try again'
            : 'Saved ${m.valueText(c.units)}',
      ),
      action: m == null
          ? null
          : SnackBarAction(
              label: 'View',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SavedScreen(controller: c),
                ),
              ),
            ),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, required this.warning});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: warning ? kAccent.withValues(alpha: 0.92) : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: warning ? Colors.black : Colors.white,
          shadows: warning
              ? null
              : const [Shadow(blurRadius: 6, color: Colors.black54)],
        ),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final MeasureMode mode;
  final ValueChanged<MeasureMode> onChanged;

  static const _icons = {
    MeasureMode.distance: Icons.straighten_rounded,
    MeasureMode.area: Icons.pentagon_outlined,
    MeasureMode.volume: Icons.view_in_ar_rounded,
    MeasureMode.angle: Icons.architecture_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.all(Radius.circular(99)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in MeasureMode.values)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(m);
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: m == mode ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _icons[m],
                      size: 18,
                      color: m == mode ? Colors.black : Colors.white,
                    ),
                    if (m == mode) ...[
                      const SizedBox(width: 6),
                      Text(
                        m.label,
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CaptureButton extends StatefulWidget {
  const _CaptureButton({
    required this.enabled,
    required this.snapping,
    required this.onPressed,
  });

  final bool enabled;
  final bool snapping;
  final VoidCallback onPressed;

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final fill = !widget.enabled
        ? Colors.white30
        : (widget.snapping ? kAccent : Colors.white);
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: 'Place point',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 90),
          child: Container(
            width: 78,
            height: 78,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: widget.enabled ? 0.95 : 0.4,
                ),
                width: 3.5,
              ),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
              child: Icon(
                Icons.add_rounded,
                size: 34,
                color: widget.enabled ? Colors.black : Colors.black45,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Center(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: filled ? kAccent : kPanel,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onPressed!();
                  },
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(
                icon,
                color: filled
                    ? Colors.black
                    : (enabled ? Colors.white : Colors.white30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Raw numbers for diagnosing accuracy problems. Long-press the accuracy pill to show/hide.
class _DebugPanel extends StatelessWidget {
  const _DebugPanel({required this.controller});

  final MeasureController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ValueListenableBuilder(
        valueListenable: controller.frame,
        builder: (context, f, _) {
          if (f == null) return const SizedBox.shrink();
          final text = [
            f.diagnostics,
            'hit ${f.hitKind.name}  dist ${f.hitDistance.toStringAsFixed(3)} m  '
                'stab ${f.stability.toStringAsFixed(2)}',
            'depth ${f.depthLevel}  anchors ${f.anchors.length}  scan ${(f.scanProgress * 100).round()}%',
          ].join('\n');
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          );
        },
      ),
    );
  }
}

void _closeLoop(BuildContext context, MeasureController c) {
  final messenger = ScaffoldMessenger.of(context);
  final r = c.closeLoop();
  String text;
  if (r == null) {
    text = 'Aim at the start corner and wait for a steady reading, then try again';
  } else {
    final pct = r.error / r.path * 100;
    final verdict = pct <= 0.5
        ? 'Excellent'
        : pct <= 2
            ? 'Acceptable'
            : 'High drift \u2013 consider scanning again';
    text = 'Loop closed: ${formatLength(r.error, c.units)} off over '
        '${formatLength(r.path, c.units)} walked (${pct.toStringAsFixed(2)} %). $verdict.';
  }
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 170),
        duration: const Duration(seconds: 6),
        content: Text(text),
      ),
    );
}

/// Lets the user type a height instead of aiming at it (e.g. a ceiling out of AR range).
Future<void> _typeHeight(BuildContext context, MeasureController c) async {
  final metric = c.units == UnitSystem.metric;
  final text = await showTextPrompt(
    context,
    title: 'Height',
    hint: metric ? 'e.g. 8.5' : "e.g. 28 or 28' 6",
    suffix: metric ? 'm' : 'ft',
    helper: 'Floor to ceiling, or to the top of the stack',
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    confirmLabel: 'Set',
  );
  if (text == null) return;
  final meters = parseLengthInput(text, c.units);
  if (meters == null || !c.setManualHeight(meters)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Enter a height between 0 and 100')),
        );
    }
  }
}
