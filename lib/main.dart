import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/state/soroban_controller.dart';
import 'features/challenge/mode_select_screen.dart';
import 'shared/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation permanently to landscape (as specified in §5)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Hide system notification bar and navigation buttons for immersive full-screen display
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final controller = SorobanController();
  await controller.init();

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const SorobanApp(),
    ),
  );
}

class SorobanApp extends StatelessWidget {
  const SorobanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Soroban - Japanese Abacus',
      debugShowCheckedModeBanner: false,
      theme: SorobanTheme.themeData,
      home: const ModeSelectScreen(),
    );
  }
}
