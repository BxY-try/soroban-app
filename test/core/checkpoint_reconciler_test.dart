import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/engine/checkpoint_reconciler.dart';
import 'package:soroban_app/core/models/checkpoint_plan.dart';
import 'package:soroban_app/core/models/rod.dart';
import 'package:soroban_app/core/models/soroban_state.dart';

/// Builds a board with the given rod values on top of [base].
SorobanState withRods(SorobanState base, Map<int, int> rodValues) {
  var state = base;
  for (final entry in rodValues.entries) {
    state = state.updateRod(entry.key, Rod.fromValue(entry.value));
  }
  return state;
}

/// Plan with two sequential groups: rod 1 and rod 2 first, rod 3 after.
final CheckpointPlan twoStepPlan = CheckpointPlan(
  groups: [
    MoveGroup({1, 2}, {1: 1, 2: 2}), // one group, two rods
    MoveGroup.single(3, 4),
  ],
  finalTargetValue: 4210, // rod3=4, rod2=2, rod1=1
);

void main() {
  group('CheckpointPlan invariants', () {
    test('rejects a rod shared by two groups instead of mis-reconciling', () {
      expect(
        () => CheckpointPlan(
          groups: [
            MoveGroup.single(0, 1),
            MoveGroup.single(0, 2),
          ],
          finalTargetValue: 2,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'a rod in two groups would make "what may be touched next" '
            'ambiguous, so it must fail loudly at plan build time',
      );
    });

    test('rejects an empty group and an empty plan', () {
      expect(() => MoveGroup({}, {}), throwsA(isA<AssertionError>()));
      expect(
        () => CheckpointPlan(groups: const [], finalTargetValue: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a group whose rod has no target', () {
      expect(
        () => MoveGroup({0, 1}, {0: 3}),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('computeMatchedGroups', () {
    final zero = SorobanState.zero();

    test('counts leading groups and stops at the first gap', () {
      final board = withRods(zero, {1: 1, 2: 2});
      expect(CheckpointReconciler.computeMatchedGroups(board, twoStepPlan), 1);
    });

    test('does not skip ahead to a later satisfied group', () {
      // Group 0 unsatisfied, group 1 satisfied: matched must be 0, not 1.
      final board = withRods(zero, {3: 4});
      expect(CheckpointReconciler.computeMatchedGroups(board, twoStepPlan), 0);
    });

    test('counts every group once the whole board matches', () {
      final board = withRods(zero, {1: 1, 2: 2, 3: 4});
      expect(CheckpointReconciler.computeMatchedGroups(board, twoStepPlan), 2);
    });
  });

  group('allowedRodsForNextTouch', () {
    final zero = SorobanState.zero();

    test('opens only the current group, so ordering is enforced at input', () {
      expect(
        CheckpointReconciler.allowedRodsForNextTouch(zero, twoStepPlan),
        {1, 2},
      );

      // Rod 3 belongs to the next group: not touchable yet.
      expect(
        CheckpointReconciler.allowedRodsForNextTouch(
          withRods(zero, {1: 1, 2: 2}),
          twoStepPlan,
        ),
        {3},
      );
    });

    test('opens both rods of a multi-rod group for simultaneous fingers', () {
      final allowed = CheckpointReconciler.allowedRodsForNextTouch(
        zero,
        twoStepPlan,
      );
      expect(allowed.contains(1), isTrue);
      expect(allowed.contains(2), isTrue);
    });

    test('returns nothing while the board already satisfies the plan', () {
      final done = withRods(zero, {1: 1, 2: 2, 3: 4});
      expect(
        CheckpointReconciler.allowedRodsForNextTouch(done, twoStepPlan),
        isEmpty,
        reason: 'the checkpoint is complete and awaits reconciliation',
      );
    });
  });

  group('isDiverged', () {
    final zero = SorobanState.zero();

    test('a rod of a later group moving is diverged even if value is right', () {
      // Rod 3 already at its group-1 target while group 0 is untouched: this is
      // "right value, wrong order", which the spec treats as divergence.
      final board = withRods(zero, {3: 4});
      expect(
        CheckpointReconciler.isDiverged(
          board: board,
          baseline: zero,
          plan: twoStepPlan,
          matchedGroups: 0,
        ),
        isTrue,
      );
    });

    test('a completed board is never diverged', () {
      final board = withRods(zero, {1: 1, 2: 2, 3: 4});
      expect(
        CheckpointReconciler.isDiverged(
          board: board,
          baseline: zero,
          plan: twoStepPlan,
          matchedGroups: 2,
        ),
        isFalse,
      );
    });

    test('a current-group rod holding any value is never diverged', () {
      // Group 0 wants rod 1 = 1 and rod 2 = 2. The user set rod 1 = 1 and then
      // drifted it to 3. That is a digit in progress, not a rule violation: the
      // board must be left alone so the user can keep adjusting it.
      final board = withRods(zero, {1: 3});
      expect(
        CheckpointReconciler.isDiverged(
          board: board,
          baseline: zero,
          plan: twoStepPlan,
          matchedGroups: 0,
        ),
        isFalse,
      );
    });
  });

  group('reconcileChain', () {
    final zero = SorobanState.zero();

    // `4 + 5` on one rod: the first digit is +4 (earth only), the second is +5
    // (heaven only), and the fast one-motion version of "+9" satisfies both.
    final plusFour = CheckpointPlan(
      groups: [MoveGroup.single(0, 4)],
      finalTargetValue: 4,
    );
    final plusFive = CheckpointPlan(
      groups: [MoveGroup.single(0, 9)],
      finalTargetValue: 9,
    );

    test('one motion settling two digits on the same rod advances twice', () {
      final progress = CheckpointReconciler.reconcileChain(
        board: withRods(zero, {0: 9}),
        baseline: zero,
        plans: [plusFour, plusFive],
      );

      expect(progress.advanced, 2);
      expect(progress.absorbedNext, isTrue);
      expect(progress.diverged, isFalse);
    });

    test('landing exactly on the active checkpoint advances only once', () {
      final progress = CheckpointReconciler.reconcileChain(
        board: withRods(zero, {0: 4}),
        baseline: zero,
        plans: [plusFour, plusFive],
      );

      expect(progress.advanced, 1);
      expect(progress.absorbedNext, isFalse);
    });

    test('a half-finished digit advances nothing and diverges not', () {
      final progress = CheckpointReconciler.reconcileChain(
        board: withRods(zero, {0: 7}),
        baseline: zero,
        plans: [plusFour, plusFive],
      );

      expect(progress.advanced, 0);
      expect(progress.diverged, isFalse);
    });

    test('does not absorb a next digit that works on a different rod', () {
      // Value 40 can be read as "rod 1 = 4" while the first digit wanted
      // "rod 0 = 4". Same total, different board, and not reachable in one
      // motion, so it must not count as two finished digits.
      final onRod0 = CheckpointPlan(
        groups: [MoveGroup.single(0, 4)],
        finalTargetValue: 4,
      );
      final onRod1 = CheckpointPlan(
        groups: [MoveGroup.single(1, 4)],
        finalTargetValue: 40,
      );

      final progress = CheckpointReconciler.reconcileChain(
        board: withRods(zero, {1: 4}),
        baseline: zero,
        plans: [onRod0, onRod1],
      );

      expect(progress.advanced, 0);
      expect(progress.absorbedNext, isFalse);
    });

    test('does not absorb a next digit that needs more than one motion', () {
      // `8 + 7 = 15`: the second digit is a carry, so it is two groups and can
      // never have happened inside a single gesture.
      final plusEight = CheckpointPlan(
        groups: [MoveGroup.single(0, 8)],
        finalTargetValue: 8,
      );
      final plusSeven = CheckpointPlan(
        groups: [MoveGroup.single(1, 1), MoveGroup.single(0, 5)],
        finalTargetValue: 15,
      );

      final progress = CheckpointReconciler.reconcileChain(
        board: withRods(zero, {0: 5, 1: 1}),
        baseline: withRods(zero, {0: 8}),
        plans: [plusEight, plusSeven],
      );

      expect(progress.absorbedNext, isFalse);
    });

    test('look-ahead stops at one checkpoint', () {
      final third = CheckpointPlan(
        groups: [MoveGroup.single(0, 9)],
        finalTargetValue: 9,
      );
      final progress = CheckpointReconciler.reconcileChain(
        board: withRods(zero, {0: 9}),
        baseline: zero,
        plans: [plusFour, plusFive, third],
        lookAhead: 1,
      );
      expect(progress.advanced, lessThanOrEqualTo(2));
    });

    test('out-of-order work still reports divergence from the chain view', () {
      final progress = CheckpointReconciler.reconcileChain(
        board: withRods(zero, {3: 4}),
        baseline: zero,
        plans: [twoStepPlan, plusFive],
      );
      expect(progress.diverged, isTrue);
      expect(progress.advanced, 0);
    });
  });

  group('reconcile', () {
    final zero = SorobanState.zero();

    test('partial progress is neither advanced nor diverged', () {
      // One rod of the current group is done, the other is not: the group is
      // unsatisfied, but the work is legal and must not be reverted.
      final result = CheckpointReconciler.reconcile(
        board: withRods(zero, {1: 1}),
        baseline: zero,
        plan: twoStepPlan,
      );
      expect(result.outcome, ReconcileOutcome.partialProgress);
      expect(result.matchedGroups, 0);
    });

    test('completing every group completes the checkpoint', () {
      final result = CheckpointReconciler.reconcile(
        board: withRods(zero, {1: 1, 2: 2, 3: 4}),
        baseline: zero,
        plan: twoStepPlan,
      );
      expect(result.outcome, ReconcileOutcome.checkpointComplete);
      expect(result.matchedGroups, 2);
    });

    test('out-of-order work is diverged, not treated as progress', () {
      final result = CheckpointReconciler.reconcile(
        board: withRods(zero, {3: 4}),
        baseline: zero,
        plan: twoStepPlan,
      );
      expect(result.outcome, ReconcileOutcome.diverged);
      expect(result.matchedGroups, 0);
    });

    test('does not search the board value globally for a stale target', () {
      // The whole-board value of this position (rod 3 = 4) is 4000, while a
      // plan that was already completed claims 2214. Reconciliation must be
      // driven by group satisfaction, so a later-looking value cannot jump the
      // checkpoint index backwards or forwards.
      final stale = CheckpointReconciler.reconcile(
        board: withRods(zero, {3: 4}),
        baseline: zero,
        plan: twoStepPlan,
      );
      expect(stale.outcome, isNot(ReconcileOutcome.checkpointComplete));
    });
  });
}
