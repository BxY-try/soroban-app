import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/engine/addition_engine.dart';
import 'package:soroban_app/core/engine/checkpoint_reconciler.dart';
import 'package:soroban_app/core/engine/multiplication_engine.dart';
import 'package:soroban_app/core/engine/problem_generator.dart';
import 'package:soroban_app/core/models/checkpoint_plan.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/models/rod.dart';
import 'package:soroban_app/core/models/soroban_state.dart';

/// Rod indices a set of move groups touches, in group order.
List<int> rodsOf(CheckpointPlan plan) =>
    [for (final group in plan.groups) ...group.rods];

/// Drives the board through [plan] group by group, the way a user who
/// respects the order would, and returns the resulting board.
SorobanState applyPlanInOrder(SorobanState board, CheckpointPlan plan) {
  var state = board;
  for (final group in plan.groups) {
    for (final entry in group.targets.entries) {
      state = state.updateRod(entry.key, Rod.fromValue(entry.value));
    }
  }
  return state;
}

void main() {
  const engine = AdditionEngine();

  group('AdditionEngine grouping', () {
    test('a single digit is one group on one rod (heaven+earth together)', () {
      final plan = engine.planForDigit(
        state: SorobanState.zero(),
        signedDigit: 9,
        rodIndex: 0,
      )!;

      expect(plan.groupCount, 1);
      expect(plan.groups.single.targets, {0: 9});
      expect(plan.finalTargetValue, 9);
      expect(
        engine.calculateDigitMoves(SorobanState.zero(), 9, 0).length,
        2,
        reason: 'a 9 is two flicks, but one group: two fingers, any order',
      );
    });

    test('a carry ripple becomes one group per rod, highest rod first', () {
      // 999 + 1 = 1000 clears three rods and opens a fourth, so it is four
      // strictly ordered groups and therefore four gestures.
      final start = SorobanState.fromValue(999);
      final plan =
          engine.planForDigit(state: start, signedDigit: 1, rodIndex: 0)!;

      expect(rodsOf(plan), [3, 2, 1, 0]);
      expect(plan.groups.map((g) => g.targets), [
        {3: 1},
        {2: 0},
        {1: 0},
        {0: 0},
      ]);
      expect(plan.finalTargetValue, 1000);
    });

    test('only the top rod of a carry chain is touchable first', () {
      final start = SorobanState.fromValue(999);
      final plan =
          engine.planForDigit(state: start, signedDigit: 1, rodIndex: 0)!;

      expect(
        CheckpointReconciler.allowedRodsForNextTouch(start, plan),
        {3},
        reason: 'the carry has to be made before the rods below can settle',
      );
    });

    test('carry chain progress survives across separate gestures', () {
      final start = SorobanState.fromValue(999);
      final plan =
          engine.planForDigit(state: start, signedDigit: 1, rodIndex: 0)!;

      // One gesture per group, each with a fresh baseline, exactly like a user
      // lifting their finger between rods.
      final steps = <(int, int)>[
        (3, 1),
        (2, 0),
        (1, 0),
        (0, 0),
      ];

      var board = start;
      for (var i = 0; i < steps.length; i++) {
        final baseline = board;
        board = board.updateRod(steps[i].$1, Rod.fromValue(steps[i].$2));

        final result = CheckpointReconciler.reconcile(
          board: board,
          baseline: baseline,
          plan: plan,
        );

        final isLast = i == steps.length - 1;
        expect(
          result.outcome,
          isLast
              ? ReconcileOutcome.checkpointComplete
              : ReconcileOutcome.partialProgress,
          reason: 'after gesture ${i + 1} of ${steps.length}',
        );
        expect(result.matchedGroups, i + 1);
      }

      expect(board.value, 1000);
    });

    test('a borrow ripple groups the same way, highest rod first', () {
      // 20 - 3 = 17: lend one from rod 1, then settle rod 0 at 7.
      final start = SorobanState.fromValue(20);
      final plan = engine.planForDigit(state: start, signedDigit: -3, rodIndex: 0)!;

      expect(rodsOf(plan), [1, 0]);
      expect(plan.groups.map((g) => g.targets), [
        {1: 1},
        {0: 7},
      ]);
      expect(plan.finalTargetValue, 17);
    });

    test('a subtraction that stays on one rod is a single group', () {
      final start = SorobanState.fromValue(47);
      final plan = engine.planForDigit(state: start, signedDigit: -3, rodIndex: 0)!;
      expect(plan.groupCount, 1);
      expect(plan.groups.single.targets, {0: 4});
    });

    test('plan targets are the values the engine itself produces', () {
      for (final seed in [7, 23, 101]) {
        final generator = ProblemGenerator(random: Random(seed));
        for (final category in ProblemCategory.values) {
          final problem = generator.generateProblem(
            category: category,
            difficulty: Difficulty.easy,
          );
          var running = SorobanState.zero();
          for (final checkpoint in problem.checkpoints) {
            expect(
              running.value,
              checkpoint.previousValue,
              reason: 'checkpoints must chain from the previous one',
            );
            final board = applyPlanInOrder(running, checkpoint.plan);
            expect(
              CheckpointReconciler.reconcile(
                board: board,
                baseline: running,
                plan: checkpoint.plan,
              ).outcome,
              ReconcileOutcome.checkpointComplete,
              reason: 'following the plan must always finish the checkpoint '
                  '($category, seed $seed, ${checkpoint.label})',
            );
            running = board;
            expect(running.value, checkpoint.targetValue);
          }
        }
      }
    });
  });

  group('MultiplicationEngine grouping', () {
    const multiplication = MultiplicationEngine();

    test('a partial product becomes sequential groups, tens rod first', () {
      final checkpoints = multiplication.generateCheckpoints(
        multiplicand: 3,
        multiplier: 4,
      );

      expect(checkpoints, hasLength(1));
      final plan = checkpoints.single.plan;
      expect(plan.groups.map((g) => g.targets), [
        {1: 1},
        {0: 2},
      ]);
      expect(plan.finalTargetValue, 12);
      expect(
        CheckpointReconciler.allowedRodsForNextTouch(
          SorobanState.zero(),
          plan,
        ),
        {1},
        reason: '§12 decided sequential: the tens rod is the only one open',
      );
    });

    test('a rod touched twice by the flat move list is still one group', () {
      // The spec assumed the tens and units computations of one partial product
      // never interact. They do: when a units add overflows it carries into the
      // very rod the tens of the same partial product already touched, so the
      // flat move list mentions that rod twice. Grouping must therefore come
      // from absolute per-rod targets, never from the move list.
      DigitCheckpoint? found;
      for (var a = 11; a < 100 && found == null; a++) {
        for (var b = 11; b < 100 && found == null; b++) {
          for (final checkpoint
              in multiplication.generateCheckpoints(
            multiplicand: a,
            multiplier: b,
          )) {
            final counts = <int, int>{};
            for (final move in checkpoint.atomicMoves) {
              counts[move.rodIndex] = (counts[move.rodIndex] ?? 0) + 1;
            }
            if (counts.values.any((c) => c > 1)) {
              found = checkpoint;
              break;
            }
          }
        }
      }

      expect(found, isNotNull, reason: 'search space must contain such a case');
      final repeated = found!.atomicMoves.map((m) => m.rodIndex).toList();
      expect(repeated.toSet().length, lessThan(repeated.length));

      final plan = found.plan;
      expect(rodsOf(plan).toSet(), repeated.toSet());
      expect(
        rodsOf(plan).toSet().length,
        rodsOf(plan).length,
        reason: 'each rod still belongs to exactly one group',
      );
      expect(plan.finalTargetValue, found.targetValue);
      expect(
        applyPlanInOrder(SorobanState.fromValue(found.previousValue), plan).value,
        found.targetValue,
      );
    });

    test('the plan stays reachable even when the carries interact', () {
      for (var a = 2; a < 40; a++) {
        for (var b = 2; b < 12; b++) {
          final checkpoints = multiplication.generateCheckpoints(
            multiplicand: a,
            multiplier: b,
          );
          var running = SorobanState.zero();
          for (final checkpoint in checkpoints) {
            expect(
              running.value,
              checkpoint.previousValue,
              reason: 'partial products must chain for $a x $b',
            );
            final board = applyPlanInOrder(running, checkpoint.plan);
            expect(
              CheckpointReconciler.reconcile(
                board: board,
                baseline: running,
                plan: checkpoint.plan,
              ).outcome,
              ReconcileOutcome.checkpointComplete,
              reason: 'plan for $a x $b (${checkpoint.label}) must be followable',
            );
            expect(board.value, checkpoint.targetValue);
            running = board;
          }
        }
      }
    });
  });
}
