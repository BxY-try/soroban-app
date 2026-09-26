import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

    // 3. The problem text must sit on the Soroban FRAME centre, not the widget
    // box centre. Those two differ whenever the left and right frame gutters
    // are asymmetric, which is exactly the case for the configured 0.99 left /
    // 0.97 right gutters, so measuring against the box would hide a real
    // misalignment. See the dedicated drift-guard test below for why this is
    // asserted behaviourally rather than against the helper directly.
    final sorobanBox = tester.getRect(find.byType(SorobanView));
    final abacusLayout = SorobanLayout(
      size: sorobanBox.size,
      totalRods: controller.state.rods.length,
    );
    final frameCenter = sorobanBox.left + abacusLayout.frameRect.center.dx;
    final problemCenter =
        tester.getCenter(find.byKey(const Key('challenge_problem_text'))).dx;

    expect((frameCenter - problemCenter).abs() < 2.0, isTrue,
        reason: 'text should be centred on the painted abacus frame');

    // Sanity: the frame really is off-centre inside its box right now, so the
    // check above is not passing trivially by comparing two identical values.
    final boxCenter = sorobanBox.center.dx;
    expect(
      (frameCenter - boxCenter).abs(),
      greaterThan(1.0),
      reason: 'asymmetric gutters should shift the frame centre off the box',
    );

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
      'ChallengeScreen problem text tracks the abacus FRAME centre across screen sizes',
      (tester) async {
    // Guards _abacusFrameFor against the layout chain drifting away from it:
    // the text follows the helper, so if the chain changes shape the text stops
    // matching the real box and this fails.
    //
    // NOTE ON WHAT THIS DOES *NOT* ASSERT
    //
    // _abacusFrameFor() and _problemTextLeftFor() are private to
    // _ChallengeScreenState, so this file cannot call them and compare their
    // return values. The assertions below are therefore behavioural: they build
    // the real screen, read the box Flutter actually laid out, rebuild the
    // painted frame from it, and check the text landed on that frame's centre.
    //
    // That covers the same regression from the outside — a layout chain that
    // no longer matches the helper moves the text away from the real frame — and
    // it stays valid across screen sizes, but it does NOT pin the helper's own
    // arithmetic (for example it would not catch the helper returning the right
    // answer for the wrong reason). If direct coverage of the helper is ever
    // wanted, extract it together with the four layout constants
    // (_groupHorizontalPadding, _leftPanelWidth, _leftPanelGap,
    // _problemTextRightInset) into a public class, then add unit tests against
    // it here. Until then, do not "simplify" this test into comparing the text
    // against the widget box centre again: that is exactly the mistake that let
    // a 17px visual misalignment pass while this assertion stayed green.
    final controller = SorobanController();
    controller.startChallengeSession(ProblemCategory.addition, Difficulty.easy);
    addTearDown(() => tester.view.resetPhysicalSize());

    for (final screen in [
      const Size(360, 800),
      const Size(400, 800),
      const Size(412, 915),
      const Size(1280, 720),
    ]) {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
            theme: SorobanTheme.themeData,
            home: const ChallengeScreen(),
          ),
        ),
      );
      await tester.pump();

      final box = tester.getRect(find.byType(SorobanView));
      final layout = SorobanLayout(
        size: box.size,
        totalRods: controller.state.rods.length,
      );
      final frameCenter = box.left + layout.frameRect.center.dx;
      final problemCenter =
          tester.getCenter(find.byKey(const Key('challenge_problem_text'))).dx;

      expect(
        (frameCenter - problemCenter).abs(),
        lessThan(1.0),
        reason: 'text should be centred on the abacus frame at $screen',
      );

      // The frame centre must differ from the box centre, otherwise this test
      // would be satisfied by the old box-centred behaviour.
      expect(
        (frameCenter - box.center.dx).abs(),
        greaterThan(0.5),
        reason: 'asymmetric gutters should shift the frame off the box centre at $screen',
      );

      await tester.pumpWidget(const SizedBox());
    }

    // Disposed explicitly, not via addTearDown: the framework verifies there are
    // no pending timers before tearDown runs, and startChallengeSession leaves a
    // repeating timer behind.
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

  testWidgets('SorobanView beads are drag-only until "Klik Manik" is enabled',
      (tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    /// Boots a real controller (so the setting comes from persisted prefs, not
    /// a back door) and pumps a bare abacus sized 320x600.
    Future<SorobanController> pumpAbacus({required bool tapEnabled}) async {
      SharedPreferences.setMockInitialValues(
        tapEnabled ? {'tap_to_toggle_enabled': true} : {},
      );
      final controller = SorobanController();
      addTearDown(() => controller.dispose());
      await controller.init(initAudio: false);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: MaterialApp(
            theme: SorobanTheme.themeData,
            home: const Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320,
                  height: 600,
                  child: SorobanView(showDigitalReadout: false),
                ),
              ),
            ),
          ),
        ),
      );
      return controller;
    }

    /// Global position of the heaven bead on [rodIndex], derived from the very
    /// same layout the painter uses.
    Offset heavenBeadCenter(int rodIndex) {
      final canvas = find
          .descendant(
            of: find.byType(SorobanView),
            matching: find.byType(CustomPaint),
          )
          .first;
      final layout = SorobanLayout(
        size: tester.getSize(canvas),
        totalRods: 7,
      );
      return tester.getTopLeft(canvas) +
          Offset(
            layout.rodCenterX(rodIndex),
            layout.computeHeavenY(false) + (layout.beadHeight / 2),
          );
    }

    // Default (flag OFF): tapping straight onto a bead must do nothing.
    final dragOnly = await pumpAbacus(tapEnabled: false);
    expect(dragOnly.tapToToggleEnabled, isFalse);

    await tester.tapAt(heavenBeadCenter(0));
    await tester.pumpAndSettle();
    expect(dragOnly.state.rods[0].heaven, isFalse);
    expect(dragOnly.state.value, equals(0));

    await tester.pumpWidget(const SizedBox());

    // Opted in: the exact same tap now moves the bead.
    final tappable = await pumpAbacus(tapEnabled: true);
    expect(tappable.tapToToggleEnabled, isTrue);

    await tester.tapAt(heavenBeadCenter(0));
    await tester.pumpAndSettle();
    expect(tappable.state.rods[0].heaven, isTrue);
    // Heaven bead carries 5, so rod 0 now reads 5 (not 1).
    expect(tappable.state.value, equals(5));

    expect(tester.takeException(), isNull);
  });

  testWidgets('SorobanView drags several rods at once with one finger each',
      (tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // No tap-to-toggle: both fingers below are pure drags.
    SharedPreferences.setMockInitialValues({});
    final controller = SorobanController();
    addTearDown(() => controller.dispose());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: SorobanTheme.themeData,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 600,
                child: SorobanView(showDigitalReadout: false),
              ),
            ),
          ),
        ),
      ),
    );

    final canvas = find
        .descendant(
          of: find.byType(SorobanView),
          matching: find.byType(CustomPaint),
        )
        .first;
    final layout = SorobanLayout(size: tester.getSize(canvas), totalRods: 7);
    final origin = tester.getTopLeft(canvas);

    /// Global centre of a bead, from the very same layout the painter uses.
    Offset beadCenter(int rodIndex,
        {required bool heaven, required int index}) {
      final y = heaven
          ? layout.computeHeavenY(false)
          : layout.computeEarthY(index, 0);
      return origin +
          Offset(layout.rodCenterX(rodIndex), y + layout.beadHeight / 2);
    }

    // Rod 0: lowest earth bead, dragged up against the beam (+1).
    // Rod 6: heaven bead, dragged down against the beam (+5).
    final earthFinger = await tester
        .startGesture(beadCenter(0, heaven: false, index: 0));
    final heavenFinger = await tester
        .startGesture(beadCenter(6, heaven: true, index: 0));

    await earthFinger.moveBy(const Offset(0, -70));
    await heavenFinger.moveBy(const Offset(0, 70));
    await tester.pump();

    // Both beads float under their own finger, neither committed yet.
    expect(controller.state.value, equals(0));

    // Lifting the first finger commits only ITS rod; the other bead is still
    // mid-air because its finger has not lifted yet.
    await earthFinger.up();
    await tester.pump();
    expect(controller.state.rods[0].earth, equals(1));
    expect(controller.state.rods[6].heaven, isFalse);

    await heavenFinger.up();
    await tester.pump();
    expect(controller.state.rods[6].heaven, isTrue);
    // Rod 0 is units (+1), rod 6 is the millions rod (+5.000.000).
    expect(controller.state.value, equals(5000001));

    expect(tester.takeException(), isNull);
  });

  testWidgets('SorobanView ignores a second finger on an already held rod',
      (tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    SharedPreferences.setMockInitialValues({});
    final controller = SorobanController();
    addTearDown(() => controller.dispose());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: SorobanTheme.themeData,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 600,
                child: SorobanView(showDigitalReadout: false),
              ),
            ),
          ),
        ),
      ),
    );

    final canvas = find
        .descendant(
          of: find.byType(SorobanView),
          matching: find.byType(CustomPaint),
        )
        .first;
    final layout = SorobanLayout(size: tester.getSize(canvas), totalRods: 7);
    final origin = tester.getTopLeft(canvas);
    final rod0EarthBead = origin +
        Offset(
          layout.rodCenterX(0),
          layout.computeEarthY(0, 0) + layout.beadHeight / 2,
        );

    final first = await tester.startGesture(rod0EarthBead);
    final second = await tester.startGesture(rod0EarthBead);

    await first.moveBy(const Offset(0, -70));
    await second.moveBy(const Offset(0, -70));
    await second.up();
    await tester.pump();

    // The second finger never owned the rod, so its release moves nothing.
    expect(controller.state.rods[0].earth, equals(0));

    await first.up();
    await tester.pump();
    expect(controller.state.rods[0].earth, equals(1));

    expect(tester.takeException(), isNull);
  });

  testWidgets('SorobanView toggles two rods from two simultaneous taps',
      (tester) async {
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    SharedPreferences.setMockInitialValues({'tap_to_toggle_enabled': true});
    final controller = SorobanController();
    addTearDown(() => controller.dispose());
    await controller.init(initAudio: false);
    expect(controller.tapToToggleEnabled, isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: SorobanTheme.themeData,
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 600,
                child: SorobanView(showDigitalReadout: false),
              ),
            ),
          ),
        ),
      ),
    );

    final canvas = find
        .descendant(
          of: find.byType(SorobanView),
          matching: find.byType(CustomPaint),
        )
        .first;
    final layout = SorobanLayout(size: tester.getSize(canvas), totalRods: 7);
    final origin = tester.getTopLeft(canvas);

    final earthFinger = await tester.startGesture(origin +
        Offset(
            layout.rodCenterX(0),
            layout.computeEarthY(0, 0) + layout.beadHeight / 2));
    final heavenFinger = await tester.startGesture(origin +
        Offset(
            layout.rodCenterX(6),
            layout.computeHeavenY(false) + layout.beadHeight / 2));

    await earthFinger.up();
    await heavenFinger.up();
    await tester.pumpAndSettle();

    expect(controller.state.rods[0].earth, equals(1));
    expect(controller.state.rods[6].heaven, isTrue);
    // Rod 0 is units (+1), rod 6 is the millions rod (+5.000.000).
    expect(controller.state.value, equals(5000001));

    expect(tester.takeException(), isNull);
  });

  testWidgets('SettingsScreen exposes the "Klik Manik" toggle', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = SorobanController();
    addTearDown(() => controller.dispose());
    await controller.init(initAudio: false);

    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: SorobanTheme.themeData,
          home: const SettingsScreen(),
        ),
      ),
    );

    expect(find.text('Interaksi Manik'), findsOneWidget);

    final tile = find.widgetWithText(SwitchListTile, 'Klik Manik (Tap to Toggle)');
    expect(tile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);

    // The switch flips the controller, i.e. the gesture gate in SorobanView.
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(controller.tapToToggleEnabled, isTrue);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    expect(tester.takeException(), isNull);
  });
}
