import 'package:flutter/material.dart';

/// A one-field dialog that returns the typed text, or null if cancelled.
///
/// The dialog is a StatefulWidget that owns its controller: disposing a controller right
/// after `showDialog` returns is a bug, because the dialog is still animating out and its
/// TextField is still using it.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String? suffix,
  String? helper,
  int? maxLength,
  TextInputType? keyboardType,
  TextCapitalization capitalization = TextCapitalization.none,
  String confirmLabel = 'Save',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(
      title: title,
      initial: initial,
      hint: hint,
      suffix: suffix,
      helper: helper,
      maxLength: maxLength,
      keyboardType: keyboardType,
      capitalization: capitalization,
      confirmLabel: confirmLabel,
    ),
  );
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
    required this.capitalization,
    this.hint,
    this.suffix,
    this.helper,
    this.maxLength,
    this.keyboardType,
  });

  final String title;
  final String initial;
  final String? hint;
  final String? suffix;
  final String? helper;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextCapitalization capitalization;
  final String confirmLabel;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _field = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _field,
        autofocus: true,
        maxLength: widget.maxLength,
        keyboardType: widget.keyboardType,
        textCapitalization: widget.capitalization,
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixText: widget.suffix,
          helperText: widget.helper,
          helperMaxLines: 2,
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _field.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
