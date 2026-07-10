import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ReactifyGachaApp());
}
