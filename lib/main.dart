import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:sportika/app.dart';
import 'package:sportika/shared/data/local_storage.dart';
import 'package:sportika/shared/state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The prototype keeps its whole world in one on-device document, so the
  // first frame already has the saved scorecards and tournament state.
  final storage = await LocalStorage.open();
  final state = AppState(storage);
  await state.load();

  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const SportikaApp(),
    ),
  );
}
