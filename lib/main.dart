import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ar/ar_backend.dart';
import 'ui/ar_gate.dart';
import 'ui/measure_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  runApp(const MeasureApp());
}

class MeasureApp extends StatelessWidget {
  const MeasureApp({super.key});

  // Stateless (static platform channels), so one shared instance is fine.
  static final ArBackend _backend = ArChannel();

  @override
  Widget build(BuildContext context) {
    final backend = _backend;
    return MaterialApp(
      title: 'Measure',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ArGate(
        backend: backend,
        builder: (_) => MeasureScreen(backend: backend),
      ),
    );
  }
}
