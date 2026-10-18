import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/state/soroban_controller.dart';
import 'package:soroban_app/features/challenge/challenge_screen.dart';
import 'package:soroban_app/features/challenge/mode_select_screen.dart';
import 'package:soroban_app/features/practice/practice_screen.dart';
import 'package:soroban_app/features/soroban_widget/soroban_painter.dart';
import 'package:soroban_app/features/soroban_widget/soroban_view.dart';
import 'package:soroban_app/shared/theme.dart';

Widget host(SorobanController controller, Widget child) =>
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(theme: SorobanTheme.themeData, home: child),
    );

SorobanFramePainter framePainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<SorobanFramePainter>()
    .single;

void main() {
  for (final size in [const Size(800, 360), const Size(1280, 720)]) {
    testWidgets('all division boards fit $size and survive changes of category',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = SorobanController();
      addTearDown(controller.dispose);
      controller.startPracticeProblem(
          ProblemCategory.division1, Difficulty.easy);
      // Deliberately keep the SAME const view: its own controller listener
      // must rebuild the static frame when a replacement has more/fewer rods.
      await tester.pumpWidget(host(
        controller,
        const Scaffold(
            body: Center(
                child: AspectRatio(
          aspectRatio: 2.05,
          child: SorobanView(),
        ))),
      ));
      for (final category
          in ProblemCategory.values.where((c) => c.isDivision)) {
        for (final difficulty in Difficulty.values) {
          controller.startPracticeProblem(category, difficulty);
          await tester.pumpAndSettle();
          expect(framePainter(tester).totalRods,
              controller.currentProblem!.division!.layout.rodCount);
          expect(find.text('kosong'), findsOneWidget);
          expect(find.text('Sisa · 1'), findsOneWidget);
          expect(find.text('Hasil · 1'), findsOneWidget);
          expect(find.byKey(const Key('division_guide')), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
      controller.startPracticeProblem(
          ProblemCategory.multiplication1, Difficulty.easy);
      await tester.pumpAndSettle();
      expect(framePainter(tester).totalRods, 7);
      expect(find.byKey(const Key('division_guide')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('division practice controls and explanations fit $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = SorobanController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(host(controller, const PracticeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<ProblemCategory>));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Pembagian Desimal'), 80,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('Pembagian Desimal').last);
      await tester.pumpAndSettle();
      expect(
          controller.currentProblem!.category, ProblemCategory.divisionDecimal);
      expect(find.text('Bantuan'), findsOneWidget);
      expect(find.text('Putar Ulang'), findsOneWidget);
      expect(find.byKey(const Key('division_guide')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('decimal challenge follows category → difficulty → five problems',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = SorobanController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(controller, const ModeSelectScreen()));
    await tester.scrollUntilVisible(find.text('Pembagian Desimal'), 250);
    await tester.tap(find.text('Pembagian Desimal'));
    await tester.pumpAndSettle();
    expect(find.text('Tingkat Kesulitan: Pembagian Desimal'), findsOneWidget);
    await tester.tap(find.text('Mulai (5 Soal)').last);
    await tester.pumpAndSettle();
    expect(find.byType(ChallengeScreen), findsOneWidget);
    expect(controller.currentProblem!.difficulty, Difficulty.hard);
    expect(controller.totalChallengeProblems, 5);
    expect(framePainter(tester).totalRods, 12);
    expect(find.byKey(const Key('division_guide')), findsNothing);
    expect(find.text('Bantuan'), findsNothing);
    expect(tester.takeException(), isNull);
    controller.cancelChallengeSession();
    await tester.pumpWidget(const SizedBox());
  });
}
