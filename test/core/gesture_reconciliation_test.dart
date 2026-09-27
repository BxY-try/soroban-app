import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/engine/addition_engine.dart';
import 'package:soroban_app/core/engine/checkpoint_reconciler.dart';
import 'package:soroban_app/core/engine/problem_generator.dart';
import 'package:soroban_app/core/models/bead_move.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/models/soroban_state.dart';
import 'package:soroban_app/core/state/soroban_controller.dart';

/// Drives one rod to an absolute value with heaven/earth flicks.
void setRodValue(SorobanController controller, int rodIndex, int value) {
  final rod = controller.state.rods[rodIndex];
  if (rod.heaven != (value >= 5)) controller.tapHeavenBead(rodIndex);
  final earth = value % 5;
  if (rod.earth != earth) controller.tapEarthBead(rodIndex, earth);
}

/// One gesture that satisfies a whole checkpoint, the way the view does.
void performCheckpoint(
  SorobanController controller,
  DigitCheckpoint checkpoint,
) {
  controller.beginGesture();
  for (final move in checkpoint.atomicMoves) {
    if (move.kind == BeadKind.heaven) {
      controller.tapHeavenBead(move.rodIndex);
    } else {
      controller.tapEarthBead(move.rodIndex, move.to);
    }
  }
  controller.endGesture();
}

SorobanController seededController(int seed) {
  final controller = SorobanController(
    generator: ProblemGenerator(random: Random(seed)),
  );
  controller.startPracticeProblem(ProblemCategory.addition, Difficulty.easy);
  return controller;
}

/// Controller on a problem with exactly [terms], already started.
///
/// Creating the controller and starting the problem come as one call on
/// purpose: a controller without a problem has no checkpoint chain at all, and
/// every gesture on it is silently a no-op.
SorobanController fixedController(List<int> terms) {
  final controller = SorobanController(generator: _FixedProblemGenerator(terms));
  controller.startPracticeProblem(ProblemCategory.addition, Difficulty.easy);
  return controller;
}

Future<void> waitUntilIdle(SorobanController controller) async {
  for (var i = 0; i < 200 && controller.isAnimating; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  group('Same-rod parallel: two fingers, one rod (#1)', () {
    test('heaven and earth may be set in the same gesture, either order', () {
      for (final heavenFirst in [true, false]) {
        final controller = seededController(3);
        final checkpoint = controller.currentProblem!.checkpoints.first;
        final rodIndex = checkpoint.plan.groups.first.rods.first;
        final target = checkpoint.plan.groups.first.targets[rodIndex]!;

        // Two fingers, one rod, one commit each: the only difference is which
        // deck lands first. This is the `6`/`7`/`8`/`9` gesture — one value
        // made of two beads.
        controller.beginGesture();
        if (heavenFirst) {
          if (target >= 5) controller.tapHeavenBead(rodIndex);
          if (target % 5 != controller.state.rods[rodIndex].earth) {
            controller.tapEarthBead(rodIndex, target % 5);
          }
        } else {
          if (target % 5 != controller.state.rods[rodIndex].earth) {
            controller.tapEarthBead(rodIndex, target % 5);
          }
          if (target >= 5) controller.tapHeavenBead(rodIndex);
        }
        controller.endGesture();

        expect(
          controller.state.rods[rodIndex].value,
          target,
          reason: 'both finger orders must settle on the same rod '
              '(heavenFirst: $heavenFirst)',
        );
        expect(
          controller.activeCheckpointIndex,
          equals(1),
          reason: 'one gesture finishing the digit counts once',
        );
      }
    });

    test('the fast +9 that also lands the following digit is absorbed', () {
      // `4 + 5` on one rod: +4 is earth only, +5 is heaven only, and the quick
      // way to type 9 is one sweep of both decks. That must count as both
      // digits, not stall on the first.
      final controller = fixedController([4, 5]);
      final checkpoints = controller.currentProblem!.checkpoints;
      expect(checkpoints.map((c) => c.targetValue), [4, 9]);

      controller.beginGesture();
      setRodValue(controller, 0, 9);
      controller.endGesture();

      expect(controller.state.value, equals(9));
      expect(
        controller.activeCheckpointIndex,
        equals(2),
        reason: 'one motion absorbed both digits',
      );
      expect(
        controller.checkpointSnapshotCount,
        equals(3),
        reason: 'both crossed checkpoints got a snapshot entry',
      );
    });

    test('the absorbed chain still rewinds one digit at a time', () {
      final controller = fixedController([4, 5]);
      controller.beginGesture();
      setRodValue(controller, 0, 9);
      controller.endGesture();

      // Retri from the absorbed state lands on the canonical board for 4, which
      // is the position after the first digit even though the user never
      // stopped there.
      controller.executeReset();
      expect(controller.state.value, equals(4));
      expect(controller.activeCheckpointIndex, equals(1));

      controller.executeReset();
      expect(controller.state.value, equals(0));
      expect(controller.activeCheckpointIndex, equals(0));
    });
  });

  group('Sequential multi-group checkpoint (#3)', () {
    test('a carry chain advances one group per gesture, in order', () {
      final controller = fixedController([999, 1]);
      final checkpoints = controller.currentProblem!.checkpoints;

      // 999 is three separate digits; only the final +1 is the carry chain.
      for (final digit in checkpoints.take(checkpoints.length - 1)) {
        performCheckpoint(controller, digit);
      }
      final carry = checkpoints.last;
      // The carry is the fourth digit of the problem, so it starts with three
      // checkpoints already behind it.
      final baseIndex = controller.activeCheckpointIndex;
      expect(baseIndex, equals(checkpoints.length - 1));

      expect(
        carry.plan.groupCount,
        4,
        reason: '999 + 1 clears three rods and opens a fourth',
      );

      final rodsInOrder = [
        for (final group in carry.plan.groups) group.rods.single,
      ];
      expect(rodsInOrder, [3, 2, 1, 0]);

      for (var step = 0; step < rodsInOrder.length; step++) {
        final rodIndex = rodsInOrder[step];

        // Only the current group's rod may be touched at all.
        expect(
          controller.allowedRodsForNextTouch(),
          {rodIndex},
          reason: 'gesture ${step + 1} may only touch rod $rodIndex',
        );

        controller.beginGesture();
        setRodValue(
          controller,
          rodIndex,
          carry.plan.groups[step].targets[rodIndex]!,
        );
        controller.endGesture();

        final isLast = step == rodsInOrder.length - 1;

        // Progress inside the digit is read from whichever checkpoint is active,
        // so on the final group the digit is already handed over and the reading
        // belongs to the next one.
        expect(
          controller.matchedGroupCount,
          isLast ? 0 : step + 1,
          reason: 'progress inside the digit survives between gestures',
        );
        expect(
          controller.activeCheckpointIndex,
          isLast ? baseIndex + 1 : baseIndex,
          reason: 'the digit only completes on its last group',
        );
      }

      expect(controller.state.value, equals(1000));
    });
  });

  group('Duplicate target values (#6)', () {
    test('12 + 7 - 7 must not be advanced by matching the value 12 again', () {
      // Real plans from the engine: the targets are 10, 12, 19, 12 — the last
      // one repeats the second. Nothing about the board may be searched
      // globally, or the borrow would be "recognised" from a stale 12.
      const engine = AdditionEngine();
      var running = SorobanState.zero();
      final checkpoints = <DigitCheckpoint>[];
      for (final term in [12, 7]) {
        final produced = engine.generateCheckpointsForTerm(
          startingState: running,
          termValue: term,
          isAddition: true,
          termIndex: checkpoints.length,
        );
        checkpoints.addAll(produced);
        running = SorobanState.fromValue(produced.last.targetValue);
      }
      final borrow = engine.generateCheckpointsForTerm(
        startingState: running,
        termValue: 7,
        isAddition: false,
        termIndex: 2,
      );
      checkpoints.addAll(borrow);

      expect(checkpoints.map((c) => c.targetValue), [10, 12, 19, 12]);
      expect(
        checkpoints.map((c) => c.targetValue).toSet().length,
        3,
        reason: 'the duplicated value is the whole point of this fixture',
      );

      // Standing on 12 while the chain expects the borrow (19 -> 12).
      final board = SorobanState.fromValue(12);
      final progress = CheckpointReconciler.reconcileChain(
        board: board,
        baseline: SorobanState.fromValue(12),
        plans: [checkpoints[2].plan, checkpoints[3].plan],
      );

      expect(progress.diverged, isFalse);
      expect(
        progress.advanced,
        equals(0),
        reason: 'the borrow digit is not finished just because the total looks '
            'familiar',
      );
      expect(progress.absorbedNext, isFalse);
    });
  });

  group('Out-of-order work (#4, #5)', () {
    test('gating offers exactly the current group and nothing later', () {
      for (final seed in [3, 11, 29]) {
        final controller = seededController(seed);
        final checkpoints = controller.currentProblem!.checkpoints;

        for (final checkpoint in checkpoints) {
          // Gating always describes the checkpoint that is active *now*, so the
          // chain has to be walked forward for the comparison to mean anything.
          expect(
            controller.allowedRodsForNextTouch(),
            checkpoint.plan.groups.first.rods,
            reason: 'seed $seed, ${checkpoint.label}',
          );

          if (checkpoint.plan.groupCount > 1) {
            final later = checkpoint.plan.groups.skip(1).expand((g) => g.rods);
            for (final rodIndex in later) {
              expect(
                controller.allowedRodsForNextTouch().contains(rodIndex),
                isFalse,
                reason: 'a rod of a later group must not be touchable '
                    '(seed $seed, ${checkpoint.label})',
              );
            }
          }

          performCheckpoint(controller, checkpoint);
        }
      }
    });

    test('a rod from a later group is rolled back, not kept as progress', () async {
      final controller = fixedController([999, 1]);
      final checkpoints = controller.currentProblem!.checkpoints;
      for (final digit in checkpoints.take(checkpoints.length - 1)) {
        performCheckpoint(controller, digit);
      }
      final carry = checkpoints.last;
      final laterRod = carry.plan.groups[1].rods.single;

      // Reach past the gating the way a leak would, and reconcile.
      controller.beginGesture();
      setRodValue(controller, laterRod, 0);
      controller.endGesture();
      await waitUntilIdle(controller);

      expect(
        controller.state.rods[laterRod].value,
        equals(9),
        reason: 'the offending rod is put back where the digit started',
      );
    });

    test('an unfinished digit is never auto-reverted', () async {
      final controller = fixedController([999, 1]);
      final checkpoints = controller.currentProblem!.checkpoints;
      for (final digit in checkpoints.take(checkpoints.length - 1)) {
        performCheckpoint(controller, digit);
      }
      final carry = checkpoints.last;
      final rodIndex = carry.plan.groups.first.rods.single;

      // Set the carry rod to something that is neither its baseline nor 1.
      controller.beginGesture();
      setRodValue(controller, rodIndex, 3);
      controller.endGesture();
      await waitUntilIdle(controller);

      expect(
        controller.state.rods[rodIndex].value,
        equals(3),
        reason: 'partial work on the current group stays where the user put it',
      );
    });
  });

  group('Quiescence (#7, #8)', () {
    test('two commits in one gesture reconcile exactly once', () {
      final controller = seededController(3);
      final checkpoint = controller.currentProblem!.checkpoints.first;

      controller.beginGesture();
      for (final move in checkpoint.atomicMoves) {
        if (move.kind == BeadKind.heaven) {
          controller.tapHeavenBead(move.rodIndex);
        } else {
          controller.tapEarthBead(move.rodIndex, move.to);
        }
        // Still mid-gesture: the chain must not have moved yet.
        expect(controller.activeCheckpointIndex, equals(0));
      }
      controller.endGesture();

      expect(controller.activeCheckpointIndex, equals(1));
      expect(
        controller.checkpointSnapshotCount,
        equals(2),
        reason: 'one reconciliation means one snapshot, not one per commit',
      );
    });

    test('an interrupted gesture keeps the beads and defers reconciliation', () {
      final controller = fixedController([999, 1]);
      final checkpoints = controller.currentProblem!.checkpoints;
      for (final digit in checkpoints.take(checkpoints.length - 1)) {
        performCheckpoint(controller, digit);
      }
      final carry = checkpoints.last;
      final rodIndex = carry.plan.groups.first.rods.single;

      controller.beginGesture();
      setRodValue(controller, rodIndex, 1); // this is the whole group
      controller.abortGesture();

      expect(
        controller.state.rods[rodIndex].value,
        equals(1),
        reason: 'the board is the source of truth; nothing is rolled back',
      );
      expect(controller.hasActiveGesture, isFalse);

      // The next touch re-reads the same board and finds the work already done.
      controller.beginGesture();
      controller.endGesture();
      expect(
        controller.state.rods[rodIndex].value,
        equals(1),
        reason: 'no rollback either: the beads were already where they belong',
      );
    });
  });

  group('Manual vs hint parity (#9)', () {
    test('a manual gesture and the hint produce the same board', () async {
      final manual = seededController(3);
      final hint = seededController(3);
      final checkpoint = manual.currentProblem!.checkpoints.first;
      expect(
        hint.currentProblem!.expectedResult,
        manual.currentProblem!.expectedResult,
      );

      performCheckpoint(manual, checkpoint);
      await hint.executeHint();
      await waitUntilIdle(hint);

      expect(manual.state.value, equals(checkpoint.targetValue));
      expect(hint.state.value, equals(checkpoint.targetValue));
      expect(
        manual.state.rods.map((r) => r.value).toList(),
        hint.state.rods.map((r) => r.value).toList(),
        reason: 'both paths must agree rod by rod, not only on the total',
      );
      expect(manual.activeCheckpointIndex, equals(hint.activeCheckpointIndex));
      expect(
        manual.checkpointSnapshotCount,
        equals(hint.checkpointSnapshotCount),
      );
    });
  });
}

/// A generator that always yields the same terms, so checkpoint-driven
/// expectations can be written down instead of derived from randomness.
class _FixedProblemGenerator extends ProblemGenerator {
  _FixedProblemGenerator(this._terms) : super(random: Random(0));

  final List<int> _terms;

  @override
  Problem generateProblem({
    required ProblemCategory category,
    required Difficulty difficulty,
    int rodCount = 7,
  }) {
    final addition = const AdditionEngine();
    var running = SorobanState.zero(rodCount: rodCount);
    final checkpoints = <DigitCheckpoint>[];

    for (var i = 0; i < _terms.length; i++) {
      final produced = addition.generateCheckpointsForTerm(
        startingState: running,
        termValue: _terms[i],
        isAddition: true,
        termIndex: i,
      );
      checkpoints.addAll(produced);
      running = SorobanState.fromValue(
        produced.last.targetValue,
        rodCount: rodCount,
      );
    }

    return Problem(
      category: category,
      difficulty: difficulty,
      terms: _terms,
      operators: List.filled(_terms.length - 1, '+'),
      expectedResult: running.value,
      checkpoints: checkpoints,
    );
  }
}
