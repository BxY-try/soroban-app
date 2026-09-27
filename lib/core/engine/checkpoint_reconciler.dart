import '../models/checkpoint_plan.dart';
import '../models/soroban_state.dart';

/// What a reconciliation decided about the active checkpoint.
enum ReconcileOutcome {
  /// Board satisfies at least the first group but not all of them. Legal
  /// partial progress: the beads already hold it, so nothing has to be stored.
  partialProgress,

  /// Every group is satisfied. The caller advances and snapshots.
  checkpointComplete,

  /// A rod outside the current group moved, or a rod inside it took a value
  /// that is neither its baseline nor its target. Not valid progress.
  diverged,
}

/// Result of a reconciliation pass.
class ReconcileResult {
  /// How many leading groups the board satisfies, in order.
  final int matchedGroups;

  /// The classification of this pass.
  final ReconcileOutcome outcome;

  const ReconcileResult(this.matchedGroups, this.outcome);

  @override
  String toString() =>
      'ReconcileResult(matched: $matchedGroups, ${outcome.name})';
}

/// How far a single gesture moved the checkpoint chain.
class ChainProgress {
  /// Checkpoints completed by this gesture: 0, 1, or 2.
  final int advanced;

  /// Group progress inside the checkpoint that was active when the gesture
  /// started.
  ///
  /// TODO(§9): when [absorbedNext] is true this reports the group count of the
  /// checkpoint that was just *finished*, not of the one now active (which has
  /// started from nothing). A progress indicator that reads this will therefore
  /// show the old digit as full for one frame. Cosmetic, but it has to be
  /// resolved before the indicator is built — derive it from the plan of
  /// `_activeCheckpointIndex` after the advance, not from here.
  final int matchedGroups;

  /// Whether the board did something illegal and must be corrected.
  final bool diverged;

  /// True when [advanced] is 2 because the board also satisfied the *next*
  /// checkpoint, meaning one motion settled two digits.
  final bool absorbedNext;

  const ChainProgress({
    required this.advanced,
    required this.matchedGroups,
    required this.diverged,
    required this.absorbedNext,
  });

  @override
  String toString() => 'ChainProgress(advanced: $advanced, '
      'matched: $matchedGroups, diverged: $diverged, absorbed: $absorbedNext)';
}

/// Pure reconciliation rules for a [CheckpointPlan].
///
/// Deliberately free of controller, gesture and view concerns: these are the
/// only place in the app that decides "how far along is the active digit, and
/// is this board a legal way to get there". Input gating, the quiescence-time
/// reconciliation and any future progress UI all call the same functions, so
/// there is only ever one definition of progress.
class CheckpointReconciler {
  const CheckpointReconciler._();

  /// How many leading groups [board] satisfies, stopping at the first one that
  /// is not (groups after a gap are not counted, not skipped).
  static int computeMatchedGroups(SorobanState board, CheckpointPlan plan) {
    var matched = 0;
    for (final group in plan.groups) {
      if (!_groupSatisfied(board, group)) break;
      matched++;
    }
    return matched;
  }

  /// Rods the next finger may claim: the current group's rods, or nothing when
  /// the board is already complete and awaiting reconciliation.
  static Set<int> allowedRodsForNextTouch(
    SorobanState board,
    CheckpointPlan plan,
  ) {
    final matched = computeMatchedGroups(board, plan);
    if (matched >= plan.groupCount) return const {};
    return plan.groups[matched].rods;
  }

  /// Whether [board] is an illegal way to be partway through [plan].
  ///
  /// One rule only: a rod belonging to a *later* group must still equal its
  /// baseline. Value correctness does not excuse doing things out of order, so
  /// this is the defence-in-depth behind the input gating — if a rod from a
  /// future group ever moves, the gesture is rejected.
  ///
  /// A rod of the *current* group is never divergence, whatever it holds. A
  /// digit the user has not finished yet is simply a digit in progress: the
  /// beads stay where they were put, and the user can keep adjusting, ask for a
  /// hint, or reset. That is also the pre-existing behaviour of the board, and
  /// it is the only sane thing to do for a value that happens to sit between
  /// baseline and target — snapping it back would throw away real work on every
  /// imprecise lift.
  static bool isDiverged({
    required SorobanState board,
    required SorobanState baseline,
    required CheckpointPlan plan,
    required int matchedGroups,
  }) {
    if (matchedGroups >= plan.groupCount) return false;

    for (final group in plan.groups.sublist(matchedGroups + 1)) {
      for (final rodIndex in group.rods) {
        if (board.rods[rodIndex].value != baseline.rods[rodIndex].value) {
          return true;
        }
      }
    }

    return false;
  }

  /// Classifies [board] against [plan]. Pure: it decides, it does not mutate.
  static ReconcileResult reconcile({
    required SorobanState board,
    required SorobanState baseline,
    required CheckpointPlan plan,
  }) {
    final matched = computeMatchedGroups(board, plan);

    if (matched >= plan.groupCount) {
      // A complete plan that does not land on the plan's own target value means
      // the engine generated an inconsistent grouping. Fail in tests/debug
      // rather than advancing a checkpoint the user never actually reached.
      assert(
        board.value == plan.finalTargetValue,
        'completed groups but board is ${board.value}, '
        'plan expects ${plan.finalTargetValue}',
      );
      return ReconcileResult(matched, ReconcileOutcome.checkpointComplete);
    }

    if (isDiverged(
      board: board,
      baseline: baseline,
      plan: plan,
      matchedGroups: matched,
    )) {
      return ReconcileResult(matched, ReconcileOutcome.diverged);
    }

    return ReconcileResult(matched, ReconcileOutcome.partialProgress);
  }

  static bool _groupSatisfied(SorobanState board, MoveGroup group) {
    for (final entry in group.targets.entries) {
      if (board.rods[entry.key].value != entry.value) return false;
    }
    return true;
  }

  /// Reconciles one gesture against the active checkpoint and, at most,
  /// [lookAhead] checkpoints beyond it.
  ///
  /// The look-ahead exists for the fast one-motion digit: on `4 + 5` a single
  /// sweep of heaven+earth takes the rod from 0 straight to 9, so the board
  /// matches the *second* checkpoint's value and never passes through the
  /// first checkpoint's value. Without this, the rod would sit on the correct
  /// answer while the chain stayed stuck on the checkpoint before it.
  ///
  /// It is deliberately bounded and conservative — see [_canAbsorb] for the two
  /// guards that stop it from swallowing a digit the user never actually
  /// performed.
  static ChainProgress reconcileChain({
    required SorobanState board,
    required SorobanState baseline,
    required List<CheckpointPlan> plans,
    int lookAhead = 1,
  }) {
    assert(plans.isNotEmpty, 'need the active checkpoint plan at least');

    final active = reconcile(
      board: board,
      baseline: baseline,
      plan: plans.first,
    );

    if (active.outcome == ReconcileOutcome.checkpointComplete) {
      return ChainProgress(
        advanced: 1,
        matchedGroups: active.matchedGroups,
        diverged: false,
        absorbedNext: false,
      );
    }

    if (active.outcome == ReconcileOutcome.diverged) {
      return ChainProgress(
        advanced: 0,
        matchedGroups: active.matchedGroups,
        diverged: true,
        absorbedNext: false,
      );
    }

    // Bounded look-ahead: one gesture may absorb the checkpoint right after the
    // active one, and only that one. A wider scan is deliberately not
    // implemented — absorbing three digits from a single motion would need the
    // same guard applied transitively, and until there is usage data saying it
    // matters, one step is the behaviour we can reason about.
    if (lookAhead >= 1 &&
        plans.length > 1 &&
        _canAbsorb(plans[0], plans[1], board, baseline)) {
      return ChainProgress(
        advanced: 2,
        matchedGroups: plans[1].groupCount,
        diverged: false,
        absorbedNext: true,
      );
    }

    return ChainProgress(
      advanced: 0,
      matchedGroups: active.matchedGroups,
      diverged: false,
      absorbedNext: false,
    );
  }

  /// Whether the board landing on [next]'s final value means [finished] was
  /// performed at the same time.
  ///
  /// Three guards matter, because the value alone proves nothing about the path:
  ///
  /// * Both plans must be a single group. A multi-group checkpoint is by
  ///   definition more than one motion (a carry chain, a tens-then-units
  ///   partial product), so it cannot have been part of this gesture.
  /// * The two must cover the same rods. If they touched different rods, the
  ///   board could reach the next checkpoint's value while the first
  ///   checkpoint's rod was never set — a different board that happens to carry
  ///   the same total. Treating that as "two digits done" would reward a skipped
  ///   digit, and it is not physically reachable through the input gating either.
  /// * [next] must not have been satisfied *before* the gesture started. This is
  ///   what stops a repeated target value from being read as fresh work: in
  ///   `12 + 7 - 7` the last digit is `-7`, whose target (12) is where the board
  ///   already stood, so a board sitting on 12 would otherwise look like it had
  ///   just finished the `+7` as well. Progress has to be *new*.
  static bool _canAbsorb(
    CheckpointPlan finished,
    CheckpointPlan next,
    SorobanState board,
    SorobanState baseline,
  ) {
    if (board.value != next.finalTargetValue) return false;
    if (finished.groupCount != 1 || next.groupCount != 1) return false;
    if (computeMatchedGroups(baseline, next) >= next.groupCount) return false;
    return finished.allRods.containsAll(next.allRods) &&
        next.allRods.containsAll(finished.allRods);
  }
}
