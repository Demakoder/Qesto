import 'package:flutter/material.dart';

import 'app/qesto_app.dart';
import 'core/platform/qesto_command_line.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  setQestoCommandLineArguments(arguments);
  runApp(QestoApp());
}
