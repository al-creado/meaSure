import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../measure/measure_controller.dart';
import '../storage/saved_measurement.dart';
import 'prompt_dialog.dart';
import 'theme.dart';

/// List of measurements saved on this device.
class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key, required this.controller});

  final MeasureController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.saved;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Saved'),
            backgroundColor: Colors.transparent,
            actions: [
              if (items.isNotEmpty)
                IconButton(
                  tooltip: 'Delete all',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: () => _confirmClear(context),
                ),
            ],
          ),
          body: items.isEmpty
              ? const _Empty()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _Tile(
                    key: ValueKey(items[i].id),
                    item: items[i],
                    controller: controller,
                  ),
                ),
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all saved measurements?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.clearSaved();
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 44,
              color: Colors.white38,
            ),
            SizedBox(height: 16),
            Text(
              'Nothing saved yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Finish a measurement and tap the bookmark next to the result to keep it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.item, required this.controller});

  final SavedMeasurement item;
  final MeasureController controller;

  static const _icons = {
    MeasureMode.distance: Icons.straighten_rounded,
    MeasureMode.area: Icons.pentagon_outlined,
    MeasureMode.volume: Icons.view_in_ar_rounded,
    MeasureMode.angle: Icons.architecture_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final u = controller.units;
    final detail = item.detailText(u);
    return Dismissible(
      key: ValueKey('d-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFB3261E),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline_rounded),
      ),
      onDismissed: (_) {
        controller.deleteSaved(item.id);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: const Text('Deleted'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => controller.restoreSaved(item),
              ),
            ),
          );
      },
      child: Material(
        color: const Color(0xFF1B1F24),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _editNote(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: kPanel,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icons[item.mode], size: 20, color: kAccent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.valueText(u),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white60,
                          ),
                        ),
                      if (item.note != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            item.note!,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.mode.label} · ${formatTimestamp(item.createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy',
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: item.asText(u)),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(const SnackBar(content: Text('Copied')));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editNote(BuildContext context) async {
    final result = await showTextPrompt(
      context,
      title: 'Add a note',
      initial: item.note ?? '',
      hint: 'e.g. Living room window',
      maxLength: 80,
      capitalization: TextCapitalization.sentences,
    );
    if (result != null) await controller.setNote(item.id, result);
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "7 Nov 2026, 14:05" (no locale package needed for something this small).
String formatTimestamp(DateTime t) {
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${_months[t.month - 1]} ${t.year}, $hh:$mm';
}
