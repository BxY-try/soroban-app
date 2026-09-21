import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/state/soroban_controller.dart';
import 'package:soroban_app/features/challenge/challenge_screen.dart';
import 'package:soroban_app/features/challenge/mode_select_screen.dart';
import 'package:soroban_app/features/soroban_widget/soroban_view.dart';
import 'package:soroban_app/shared/theme.dart';

import 'package:soroban_app/features/practice/practice_screen.dart';

void main() {
  testWidgets('ModeSelectScreen displays category choices and navigation', (tester) async {
    final controller = SorobanController();
    addTearDown(() => controller.dispose());

    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: SorobanTheme.themeData,
          home: const ModeSelectScreen(),
        ),
      ),
    );

    expect(find.text('SOROBAN JAPANESE ABACUS'), findsOneWidget);
    expect(find.text('Penjumlahan'), findsOneWidget);
    expect(find.text('Campuran (+ / -)'), findsOneWidget);
    expect(find.text('Perkalian I'), findsOneWidget);
    expect(find.text('Perkalian II'), findsOneWidget);
    expect(find.text('Mode Practice'), findsOneWidget);
  });

  testWidgets(
      'ChallengeScreen displays SorobanView and Reset button without Hint, Replay, or equals display',
      (tester) async {
    final controller = SorobanController();
    controller.startChallengeSession(ProblemCategory.addition, Difficulty.easy);

    // Set a wide landscape test surface
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: SorobanTheme.themeData,
          home: const ChallengeScreen(),
        ),
      ),
    );

    expect(find.byType(SorobanView), findsOneWidget);

    // Reset / Retri button is present
    expect(find.byIcon(Icons.restart_alt_rounded), findsOneWidget);

    // Hint & Replay buttons are NOT present in Challenge Mode
    expect(find.byIcon(Icons.lightbulb_rounded), findsNothing);
    expect(find.byIcon(Icons.repeat_rounded), findsNothing);

    // '=' and abacus value display are NOT present in Challenge Mode problem text
    expect(find.text('='), findsNothing);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('PracticeScreen displays Hint, Replay, Reset, and equals display', (tester) async {
    final controller = SorobanController();
    addTearDown(() => controller.dispose());
    controller.startPracticeProblem(ProblemCategory.addition, Difficulty.easy);

    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: SorobanTheme.themeData,
          home: const PracticeScreen(),
        ),
      ),
    );

    expect(find.byType(SorobanView), findsOneWidget);
    expect(find.byIcon(Icons.restart_alt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lightbulb_rounded), findsOneWidget);
    expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    expect(find.textContaining('='), findsOneWidget);
  });
}
