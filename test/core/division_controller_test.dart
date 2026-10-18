import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soroban_app/core/engine/addition_engine.dart';
import 'package:soroban_app/core/engine/division_engine.dart';
import 'package:soroban_app/core/engine/problem_generator.dart';
import 'package:soroban_app/core/models/bead_move.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/models/soroban_state.dart';
import 'package:soroban_app/core/state/soroban_controller.dart';

import '../helpers/fixed_problem.dart';

class FixedDivisionGenerator extends ProblemGenerator {
  FixedDivisionGenerator(this.problem);
  final Problem problem;

  @override
  Problem generateProblem(
          {required ProblemCategory category,
          required Difficulty difficulty,
          int rodCount = 7}) =>
      problem;
}

class OnceFailingDivisionMoves extends AdditionEngine {
  bool failed = false;
  @override
  SorobanState applyMove(SorobanState state, BeadMove move) {
    if (!failed) {
      failed = true;
      throw StateError('Injected animation failure');
    }
    return super.applyMove(state, move);
  }
}

Problem example({bool decimal = false}) => const DivisionEngine().createProblem(
      dividend: decimal ? 111 : 864,
      divisor: 24,
      category:
          decimal ? ProblemCategory.divisionDecimal : ProblemCategory.division2,
      difficulty: decimal ? Difficulty.hard : Difficulty.easy,
    );

SorobanController controllerForDivision(Problem problem) {
  final controller =
      SorobanController(generator: FixedDivisionGenerator(problem));
  controller.startPracticeProblem(problem.category, problem.difficulty);
  return controller;
}

Future<void> animate(
    WidgetTester tester, Future<void> Function() action) async {
  var finished = false;
  final future = action().whenComplete(() => finished = true);
  for (var i = 0; i < 80 && !finished; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  expect(finished, isTrue,
      reason: 'animation must finish and release its lock');
  await future;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'hint/replay/reset preserve the nonzero starting board and snapshots',
      (tester) async {
    final problem = example(decimal: true);
    final controller = controllerForDivision(problem);
    addTearDown(controller.dispose);
    expect(controller.state.value, problem.division!.initialValue);
    expect(controller.state.rods.length, 12);
    expect(controller.canReset, isFalse);
    expect(controller.canReplay, isFalse);

    for (var step = 0; step < problem.checkpoints.length; step++) {
      await animate(tester, controller.executeHint);
      final afterHint = controller.state;
      final snapshots = controller.checkpointSnapshots;
      expect(afterHint.value, problem.checkpoints[step].targetValue);
      expect(controller.activeCheckpointIndex, step + 1);
      expect(controller.canReplay, isTrue);

      // A partial wrong gesture may be discarded by replay, without changing
      // which step was credited or replaying the next step by accident.
      if (step == 0) {
        controller.tapEarthBead(problem.division!.layout.spacerRod, 1);
      }
      await animate(tester, controller.executeReplay);
      expect(controller.state, afterHint);
      expect(controller.checkpointSnapshots, snapshots);
      expect(controller.activeCheckpointIndex, step + 1);
      expect(controller.isAnimating, isFalse);
    }
    expect(controller.state.value, 4625);
    for (var step = problem.checkpoints.length; step > 0; step--) {
      controller.executeReset();
      expect(controller.activeCheckpointIndex, step - 1);
      expect(controller.checkpointSnapshotCount, step);
    }
    expect(controller.state.value, problem.division!.initialValue);
    expect(controller.canReset, isFalse);
    expect(controller.canReplay, isFalse);
  });

  testWidgets(
      'manual advancement disables stale replay; next hint continues correctly',
      (tester) async {
    final problem = example();
    final controller = controllerForDivision(problem);
    addTearDown(controller.dispose);
    await animate(tester, controller.executeHint);
    setBoardValue(controller, problem.checkpoints[2].targetValue);
    expect(controller.activeCheckpointIndex, 3);
    expect(controller.canReplay, isFalse);
    final current = controller.state;
    await animate(tester, controller.executeReplay);
    expect(controller.state, current);
    await animate(tester, controller.executeHint);
    expect(controller.state.value, problem.checkpoints[3].targetValue);
    expect(controller.checkpointSnapshotCount, 5);
  });

  testWidgets(
      'wrong remainder/spacer cannot solve a challenge; all five problems work',
      (tester) async {
    final problem = example();
    final controller = controllerForDivision(problem);
    addTearDown(controller.dispose);
    controller.startChallengeSession(problem.category, problem.difficulty);
    await controller.executeHint();
    expect(controller.activeCheckpointIndex, 0);
    for (var n = 0; n < 5; n++) {
      final board = problem.division!.layout;
      setBoardValue(controller, board.encode(work: 1, quotient: 36));
      expect(controller.isShowingSplitOverlay, isFalse);
      setBoardValue(controller, 36 + board.workMultiplier ~/ 10);
      expect(controller.isShowingSplitOverlay, isFalse);
      setBoardValue(controller, 36);
      expect(controller.isShowingSplitOverlay, isTrue);
      controller.dismissSplitOverlay();
      if (n < 4) {
        expect(controller.state.value, problem.division!.initialValue);
        expect(controller.activeCheckpointIndex, 0);
      }
    }
    expect(controller.isChallengeCompleted, isTrue);
    expect(controller.splitTimes.length, 5);
    await tester.pump();
  });

  testWidgets(
      'replacing a problem during hint or replay cannot write to a new board',
      (tester) async {
    final controller = SorobanController();
    addTearDown(controller.dispose);
    for (final replay in [false, true]) {
      controller.startPracticeProblem(
          ProblemCategory.divisionDecimal, Difficulty.hard);
      if (replay) await animate(tester, controller.executeHint);
      final future =
          replay ? controller.executeReplay() : controller.executeHint();
      await tester.pump(const Duration(milliseconds: 500));
      controller.startPracticeProblem(
          ProblemCategory.multiplication1, Difficulty.easy);
      expect(controller.state.rods.length, 7);
      final newProblem = controller.currentProblem;
      var finished = false;
      final tracked = future.whenComplete(() => finished = true);
      for (var i = 0; i < 5 && !finished; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tracked;
      expect(controller.currentProblem, same(newProblem));
      expect(controller.state.value, 0);
      expect(controller.isAnimating, isFalse);
      expect(controller.canReplay, isFalse);
      expect(controller.checkpointSnapshotCount, 1);
      await animate(tester, controller.executeHint);
      expect(controller.state.value, greaterThan(0));
    }
  });

  testWidgets('divergent board recovers to its own last valid division state',
      (tester) async {
    final problem = example(decimal: true);
    final controller = controllerForDivision(problem);
    addTearDown(controller.dispose);
    setBoardValue(controller, problem.checkpoints[4].targetValue);
    setBoardValue(controller, 999);
    expect(controller.activeCheckpointIndex, 5);
    await animate(tester, controller.executeHint);
    expect(controller.state.value, problem.checkpoints[5].targetValue);
    await animate(tester, controller.executeReplay);
    expect(controller.state.value, problem.checkpoints[5].targetValue);
  });

  testWidgets('animation exceptions release the lock and permit recovery',
      (tester) async {
    final problem = example();
    final controller = SorobanController(
      generator: FixedDivisionGenerator(problem),
      additionEngine: OnceFailingDivisionMoves(),
    );
    addTearDown(controller.dispose);
    controller.startPracticeProblem(problem.category, problem.difficulty);
    Object? error;
    final future = controller.executeHint().catchError((Object value) {
      error = value;
    });
    await tester.pump(const Duration(seconds: 1));
    await future;
    expect(error, isA<StateError>());
    expect(controller.isAnimating, isFalse);
    expect(controller.canReplay, isFalse);
    await animate(tester, controller.executeHint);
    expect(controller.state.value, problem.checkpoints.first.targetValue);
  });
}
