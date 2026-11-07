import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ar/ar_backend.dart';

enum _GateState {
  checking,
  needCamera,
  cameraBlocked,
  installing,
  declined,
  unsupported,
  ready,
}

/// Gets the camera permission and makes sure ARCore is installed before showing [builder].
class ArGate extends StatefulWidget {
  const ArGate({super.key, required this.backend, required this.builder});

  final ArBackend backend;
  final WidgetBuilder builder;

  @override
  State<ArGate> createState() => _ArGateState();
}

class _ArGateState extends State<ArGate> with WidgetsBindingObserver {
  _GateState _state = _GateState.checking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Coming back from the ARCore install screen or from system settings.
    if (s == AppLifecycleState.resumed && _state != _GateState.ready) _check();
  }

  Future<void> _check({bool ask = false}) async {
    var status = await Permission.camera.status;
    if (!status.isGranted && ask) status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(
        () => _state = status.isPermanentlyDenied
            ? _GateState.cameraBlocked
            : _GateState.needCamera,
      );
      return;
    }
    final ar = await widget.backend.ensureArCore();
    if (!mounted) return;
    setState(
      () => _state = switch (ar) {
        ArAvailability.ready => _GateState.ready,
        ArAvailability.installing => _GateState.installing,
        ArAvailability.declined => _GateState.declined,
        ArAvailability.unsupported => _GateState.unsupported,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (_state) {
      _GateState.ready => widget.builder(context),
      _GateState.checking => const _Message(
        busy: true,
        title: 'Getting ready…',
      ),
      _GateState.installing => const _Message(
        busy: true,
        title: 'Installing Google Play Services for AR…',
      ),
      _GateState.needCamera => _Message(
        icon: Icons.photo_camera_outlined,
        title: 'Camera access needed',
        body: 'Measure uses the camera to understand the space in front of you. Nothing is recorded or uploaded.',
        action: 'Allow camera',
        onAction: () => _check(ask: true),
      ),
      _GateState.cameraBlocked => _Message(
        icon: Icons.photo_camera_outlined,
        title: 'Camera access is off',
        body: 'Turn on the camera permission for Measure in system settings.',
        action: 'Open settings',
        onAction: openAppSettings,
      ),
      _GateState.declined => _Message(
        icon: Icons.download_outlined,
        title: 'Google Play Services for AR is required',
        body: 'It provides the motion tracking behind Measure.',
        action: 'Try again',
        onAction: _check,
      ),
      _GateState.unsupported => const _Message(
        icon: Icons.phonelink_erase_outlined,
        title: 'This device does not support AR',
        body: 'Measure needs a phone that supports Google ARCore.',
      ),
    };
  }
}

class _Message extends StatelessWidget {
  const _Message({
    this.icon,
    required this.title,
    this.body,
    this.action,
    this.onAction,
    this.busy = false,
  });

  final IconData? icon;
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else if (icon != null)
                  Icon(icon, size: 44, color: Colors.white70),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: text.titleLarge,
                ),
                if (body != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    body!,
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: Colors.white70),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onAction, child: Text(action!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
