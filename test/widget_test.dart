import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soroban_app/core/models/bead_move.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/state/soroban_controller.dart';
import 'package:soroban_app/features/challenge/challenge_screen.dart';
import 'package:soroban_app/features/challenge/mode_select_screen.dart';
import 'package:soroban_app/features/soroban_widget/soroban_layout.dart';
import 'package:soroban_app/features/soroban_widget/soroban_view.dart';
import 'package:soroban_app/shared/theme.dart';

import 'package:soroban_app/features/challenge/result_screen.dart';
import 'package:soroban_app/features/settings/settings_screen.dart';
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

  testWidgets('ChallengeScreen back button position matches SettingsScreen back button position',
      (tester) async {
    final controller = SorobanController();

    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // 1. Check SettingsScreen
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: SorobanTheme.themeData,
          home: const SettingsScreen(),
        ),
      ),
    );
    final settingsBackBtnCenter = tester.getCenter(find.byIcon(Icons.arrow_back_rounded));

    // 2. Check ChallengeScreen
    controller.startChallengeSession(ProblemCategory.addition, Difficulty.easy);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: SorobanTheme.themeData,
          home: const ChallengeScreen(),
        ),
      ),
    );
    final challengeBackBtnCenter = tester.getCenter(find.byIcon(Icons.arrow_back_rounded));

    // Both back buttons must have identical horizontal X position (matching alignment)
    expect(challengeBackBtnCenter.dx, equals(settingsBackBtnCenter.dx));

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
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

    // Verify positioning:
    // 1. Timer and Problem progress (1/5) and Reset button are on the LEFT of SorobanView
    final sorobanLeft = tester.getTopLeft(find.byType(SorobanView)).dx;
    final resetButtonCenter = tester.getCenter(find.byIcon(Icons.restart_alt_rounded)).dx;
    final problemProgressCenter = tester.getCenter(find.text('1/5')).dx;
    final timerCenter = tester.getCenter(find.byIcon(Icons.timer_outlined)).dx;

    expect(resetButtonCenter < sorobanLeft, isTrue);
    expect(problemProgressCenter < sorobanLeft, isTrue);
    expect(timerCenter < sorobanLeft, isTrue);

    // 2. Settings button is on the top right
    final settingsCenter = tester.getCenter(find.byIcon(Icons.settings_outlined)).dx;
    final backButtonCenter = tester.getCenter(find.byIcon(Icons.arrow_back_rounded)).dx;
    expect(settingsCenter > sorobanLeft, isTrue);
    expect(backButtonCenter < sorobanLeft, isTrue);

    // Hint & Replay buttons are NOT present in Challenge Mode
    expect(find.byIcon(Icons.lightbulb_rounded), findsNothing);
    expect(find.byIcon(Icons.repeat_rounded), findsNothing);

    // '=' and abacus value display are NOT present in Challenge Mode problem text
    expect(find.text('='), findsNothing);

    // Verify digital readout under Soroban shows 7 column digits (all 0 initially)
    expect(
      find.descendant(of: find.byType(SorobanView), matching: find.text('0')),
      findsNWidgets(7),
    );

    // When beads are toggled, the corresponding rod digital value updates
    controller.tapEarthBead(0, 3); // 3 earth beads active on rod 0
    await tester.pump();
    expect(
      find.descendant(of: find.byType(SorobanView), matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(SorobanView), matching: find.text('0')),
      findsNWidgets(6),
    );

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('PracticeScreen displays Hint, Replay, Reset, and dimmed problem text', (tester) async {
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
    // Problem text now uses Text.rich with per-digit dimmed style (no '=' sign)
    expect(find.byType(RichText), findsWidgets);
  });

  testWidgets(
      'ChallengeScreen layout has correct vertical hierarchy in left panel and Soroban horizontal alignment',
      (tester) async {
    final controller = SorobanController();
    controller.startChallengeSession(ProblemCategory.addition, Difficulty.easy);

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

    final backButtonY = tester.getCenter(find.byIcon(Icons.arrow_back_rounded)).dy;
    final soalBadgeY = tester.getCenter(find.text('SOAL')).dy;
    final timerBadgeY = tester.getCenter(find.byIcon(Icons.timer_outlined)).dy;
    final resetButtonY = tester.getCenter(find.byIcon(Icons.restart_alt_rounded)).dy;

    // 1. Verify vertical order: Back button < SOAL badge < Timer badge < Reset button
    expect(backButtonY < soalBadgeY, isTrue);
    expect(soalBadgeY < timerBadgeY, isTrue);
    expect(timerBadgeY < resetButtonY, isTrue);

    // 2. Verify breathing room between SOAL badge and Timer badge (distance >= 10px)
    final soalBadgeBottom = tester
        .getBottomLeft(
            find.ancestor(of: find.text('SOAL'), matching: find.byType(Container)).first)
        .dy;
    final timerBadgeTop = tester
        .getTopLeft(find
            .ancestor(of: find.byIcon(Icons.timer_outlined), matching: find.byType(Container))
            .first)
        .dy;
    expect(timerBadgeTop - soalBadgeBottom >= 10.0, isTrue);

    // 3. Verify Soroban and problem text are horizontally aligned with sub-pixel precision (< 2.0px)
    final sorobanCenter = tester.getCenter(find.byType(SorobanView)).dx;
    final problemCenter = tester.getCenter(find.byKey(const Key('challenge_problem_text'))).dx;
    expect((sorobanCenter - problemCenter).abs() < 2.0, isTrue);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
      'ChallengeScreen fades completed digits dynamically when checkpoint is reached and resets',
      (tester) async {
    final controller = SorobanController();
    controller.startChallengeSession(ProblemCategory.addition, Difficulty.easy);

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

    bool hasFadedSpan(WidgetTester tester) {
      final textWidget = tester.widget<Text>(find.byKey(const Key('challenge_problem_text')));
      final spanTree = textWidget.textSpan as TextSpan?;
      if (spanTree == null || spanTree.children == null) return false;
      for (final child in spanTree.children!) {
        if (child is TextSpan && child.style?.color != null) {
          // SorobanTheme.problemEquationCompletedStyle uses alpha 0.28
          if (child.style!.color!.a < 0.5) return true;
        }
      }
      return false;
    }

    // Initially activeCheckpointIndex is 0: no digit is faded
    expect(hasFadedSpan(tester), isFalse);

    // Advance to checkpoint 0
    final problem = controller.currentProblem!;
    final moves = problem.checkpoints[0].atomicMoves;
    for (final move in moves) {
      if (move.kind == BeadKind.heaven) {
        controller.tapHeavenBead(move.rodIndex);
      } else {
        controller.tapEarthBead(move.rodIndex, move.to);
      }
    }
    await tester.pump();

    expect(controller.activeCheckpointIndex, equals(1));
    // Checkpoint 0 completed: first digit is now faded!
    expect(hasFadedSpan(tester), isTrue);

    // Press reset to rollback checkpoint
    controller.executeReset();
    await tester.pump();
    expect(controller.activeCheckpointIndex, equals(0));
    // After reset: digit is no longer faded
    expect(hasFadedSpan(tester), isFalse);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('ResultScreen renders without overflow on compact landscape screen', (tester) async {
    final controller = SorobanController();
    addTearDown(() => controller.dispose());

    // Constrained landscape viewport (e.g. mobile landscape 640x360)
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: SorobanTheme.themeData,
          home: const ResultScreen(),
        ),
      ),
    );

    expect(find.text('TANTANGAN SELESAI!'), findsOneWidget);
    expect(find.text('Menu Utama'), findsOneWidget);
    expect(find.text('Coba Lagi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ChallengeScreen Soroban keeps beads stable while travel grows across sizes',
      (tester) async {
    // Tight phone landscape up to a wide tablet-ish landscape, exercising both
    // the height-limited and the width-limited branch of the Soroban box.
    for (final viewport in [const Size(640, 360), const Size(1280, 720)]) {
      final controller = SorobanController();
      controller.startChallengeSession(ProblemCategory.addition, Difficulty.easy);

      tester.view.physicalSize = viewport;
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

      expect(find.byType(SorobanView), findsOneWidget, reason: 'at $viewport');
      final boost = tester.widget<SorobanView>(find.byType(SorobanView)).travelBoost;
      expect(boost, greaterThan(0), reason: 'travel boost must be wired at $viewport');

      // The block (abacus frame + digital readout) keeps a comfortable clearance
      // above the screen bottom and stays balanced against the space left under
      // the problem text above it.
      final block = tester.getRect(find.byType(SorobanView));
      final textBottom =
          tester.getBottomLeft(find.byKey(const Key('challenge_problem_text'))).dy;
      final clearanceBottom = viewport.height - block.bottom;
      expect(clearanceBottom, greaterThanOrEqualTo(12.0), reason: 'clearance at $viewport');
      expect(
        (block.top - textBottom - clearanceBottom).abs(),
        lessThan(4.0),
        reason: 'vertical balance at $viewport',
      );

      final canvas = tester.getSize(
        find
            .descendant(of: find.byType(SorobanView), matching: find.byType(CustomPaint))
            .first,
      );
      final plain = SorobanLayout(size: canvas, totalRods: 7);
      final boosted = SorobanLayout(
        size: canvas,
        totalRods: 7,
        travelBoost: boost,
      );

      // The travel path is roomier (by ~0.79 * boost, since the same px also
      // shrink the proportional part of the travel)...
      final travelGain = boosted.travelDistance - plain.travelDistance;
      expect(travelGain, greaterThan(1.0), reason: 'travel at $viewport');
      expect(travelGain, lessThan(boost), reason: 'travel at $viewport');
      // ...and it is paid for purely by the bead budget, so the 2x height the
      // screen grants keeps the beads at their previous size.
      expect(
        plain.beadHeight - boosted.beadHeight,
        closeTo(2 * boost / (5.0 + 2.0 * SorobanLayout.travelRatio), 0.001),
        reason: 'bead height delta at $viewport',
      );
      // Bead width only depends on the available width, which never changed.
      expect(boosted.beadWidth, closeTo(plain.beadWidth, 0.001),
          reason: 'bead width at $viewport');

      expect(tester.takeException(), isNull, reason: 'overflow at $viewport');

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });
}
