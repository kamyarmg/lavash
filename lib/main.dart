import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_screen.dart';

/// App entrypoint.
///
/// - Ensures Flutter bindings are initialized before any async work.
/// - Locks orientation to portrait so the sliding puzzle layout stays stable.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MainApp());
}
