import '../models/bead_move.dart';
import '../models/problem.dart';
import '../models/soroban_state.dart';
import 'addition_engine.dart';
import 'multiplication_engine.dart';
import 'multiplication_progress.dart';

/// Result from requesting a hint.
class HintResult {
  /// The checkpoint being executed.
  final DigitCheckpoint checkpoint;

  /// The list of atomic moves that form the chained animation for this full digit.
  final List<BeadMove> moves;

  /// The index of the checkpoint in the problem's checkpoint sequence.
  final int checkpointIndex;

  /// Whether the user was divergent/lost ("nyasar") before this hint was calculated.
  final bool recoveredFromDivergence;

  /// Starting state from which the moves should animate.
  final SorobanState fromState;

  const HintResult({
    required this.checkpoint,
    required this.moves,
    required this.checkpointIndex,
    required this.recoveredFromDivergence,
    required this.fromState,
  });
}

/// Result from requesting a hint for a multiplication.
///
/// A multiplication has no chain to index into, so this names the contribution
/// to add instead of a checkpoint position.
class MultiplicationHint {
  /// The contribution the hint adds to the board.
  final MultiplicationContribution contribution;

  /// The atomic moves that add [contribution], worked out from [fromState].
  final List<BeadMove> moves;

  /// The board the moves animate from: the user's own board, or, after
  /// divergence, the last valid board of the user's own work.
  final SorobanState fromState;

  /// The contributions that were on [fromState], in credit order.
  final List<int> baseOrder;

  /// Whether the board was not a valid multiplication state and had to be taken
  /// back to [fromState] first.
  final bool recoveredFromDivergence;

  const MultiplicationHint({
    required this.contribution,
    required this.moves,
    required this.fromState,
    required this.baseOrder,
    required this.recoveredFromDivergence,
  });
}

/// Hint and Replay Engine.
/// Manages checkpoint navigation, chained animation generation,
/// divergence recovery ("nyasar"), and replay state rollbacks.
class HintEngine {
  final AdditionEngine additionEngine;
  final MultiplicationEngine multiplicationEngine;

  const HintEngine({
    this.additionEngine = const AdditionEngine(),
    this.multiplicationEngine = const MultiplicationEngine(),
  });

  /// Finds the currently active checkpoint index given the [currentState] of the abacus.
  /// If the current value matches a checkpoint's targetValue exactly, the next
  /// checkpoint to execute is that index + 1.
  /// If [currentState] is 0, the next is 0.
  /// If the user diverged ("nyasar"), returns the index of the nearest previous valid checkpoint.
  int determineCurrentCheckpointIndex(
    SorobanState currentState,
    List<DigitCheckpoint> checkpoints,
  ) {
    final curVal = currentState.value;
    if (checkpoints.isEmpty) return 0;
    if (curVal == 0) return 0;

    // Check exact target match
    for (int i = checkpoints.length - 1; i >= 0; i--) {
      if (checkpoints[i].targetValue == curVal) {
        // This checkpoint was already reached, so next active is i + 1
        return i + 1 < checkpoints.length ? i + 1 : checkpoints.length;
      }
    }

    // If divergent ("nyasar"): find the nearest previous checkpoint whose target is valid
    // Sesuai spec §2.3: cari checkpoint TERDEKAT SEBELUMNYA yang match
    // Default to the first checkpoint if none matched
    return 0;
  }

  /// Calculates the hint for the current abacus state.
  /// Returns [HintResult] containing the full chained moves to complete the active digit.
  ///
  /// Reads a linear chain, which is what addition, subtraction and mixed
  /// problems are. A multiplication is not one: use [getNextMultiplicationHint].
  HintResult? getNextHint({
    required SorobanState currentState,
    required Problem problem,
    required List<SorobanState> checkpointSnapshots,
  }) {
    if (problem.checkpoints.isEmpty) return null;

    final curVal = currentState.value;
    int targetIdx = -1;

    // 1. Is user exactly at 0 and problem just started?
    if (curVal == 0 && checkpointSnapshots.length <= 1) {
      targetIdx = 0;
    } else {
      // Check if current value matches any checkpoint target
      for (int i = 0; i < problem.checkpoints.length; i++) {
        if (problem.checkpoints[i].targetValue == curVal) {
          targetIdx = i + 1;
          break;
        }
      }
    }

    // 2. If already completed all checkpoints:
    if (targetIdx >= problem.checkpoints.length) {
      return null;
    }

    // 3. If exact match found:
    if (targetIdx != -1) {
      final cp = problem.checkpoints[targetIdx];
      return HintResult(
        checkpoint: cp,
        moves: cp.atomicMoves,
        checkpointIndex: targetIdx,
        recoveredFromDivergence: false,
        fromState: currentState,
      );
    }

    // 4. User diverged ("nyasar"):
    // Find the latest valid checkpoint snapshot we have saved
    final validSnapshot = checkpointSnapshots.isNotEmpty
        ? checkpointSnapshots.last
        : SorobanState.zero(rodCount: currentState.rods.length);

    // Find which checkpoint that corresponds to
    int lastValidIdx = 0;
    for (int i = 0; i < problem.checkpoints.length; i++) {
      if (problem.checkpoints[i].targetValue == validSnapshot.value) {
        lastValidIdx = i + 1;
      }
    }

    if (lastValidIdx >= problem.checkpoints.length) {
      lastValidIdx = problem.checkpoints.length - 1;
    }

    final activeCheckpoint = problem.checkpoints[lastValidIdx];
    return HintResult(
      checkpoint: activeCheckpoint,
      moves: activeCheckpoint.atomicMoves,
      checkpointIndex: lastValidIdx,
      recoveredFromDivergence: true,
      fromState: validSnapshot,
    );
  }

  /// The next hint for a multiplication, read from the board.
  ///
  /// [creditedOrder] is the contributions already credited, oldest first (see
  /// `MultiplicationProgress.explain`).
  ///
  /// When the board is a valid intermediate state the hint continues from it,
  /// whatever route got it there: the next contribution follows the user's own
  /// pattern, and its moves are worked out from the board as it stands. Nothing
  /// is rolled back and nothing on the board is touched.
  ///
  /// Only a board that is no accumulation of contributions at all is
  /// "divergent". It is taken back to the last valid board of the user's *own*
  /// work ([creditedOrder]), not to the start of the canonical chain.
  ///
  /// Returns null when there is nothing left to add.
  MultiplicationHint? getNextMultiplicationHint({
    required SorobanState currentState,
    required MultiplicationProgress progress,
    required List<int> creditedOrder,
  }) {
    final total = progress.contributions.length;
    final explained = progress.explain(
      currentState.value,
      preferred: creditedOrder,
    );

    if (explained != null) {
      if (explained.length >= total) return null;

      final baseOrder = progress.ordered(creditedOrder, explained);
      final next = progress.nextContribution(baseOrder);
      if (next == null) return null;

      return MultiplicationHint(
        contribution: next,
        moves: multiplicationEngine.contributionMoves(currentState, next),
        fromState: currentState,
        baseOrder: baseOrder,
        recoveredFromDivergence: false,
      );
    }

    // Divergent ("nyasar"): the board is not something the multiplication can
    // explain. Go back to where the user's credited work left the board.
    if (creditedOrder.length >= total) return null;
    final next = progress.nextContribution(creditedOrder);
    if (next == null) return null;

    final recoverTo = SorobanState.fromValue(
      progress.valueOf(creditedOrder),
      rodCount: currentState.rods.length,
    );
    return MultiplicationHint(
      contribution: next,
      moves: multiplicationEngine.contributionMoves(recoverTo, next),
      fromState: recoverTo,
      baseOrder: List<int>.of(creditedOrder),
      recoveredFromDivergence: true,
    );
  }

  /// Prepares a replay of the currently active or most recently completed digit.
  /// Returns the starting state to rollback to, and the moves to animate.
  HintResult? getReplay({
    required int activeCheckpointIndex,
    required Problem problem,
    required List<SorobanState> checkpointSnapshots,
  }) {
    if (problem.checkpoints.isEmpty) return null;

    final targetIdx = activeCheckpointIndex.clamp(0, problem.checkpoints.length - 1);
    final cp = problem.checkpoints[targetIdx];

    // Rollback state is either the previous snapshot or state from cp.previousValue
    SorobanState rollbackState;
    if (targetIdx < checkpointSnapshots.length) {
      rollbackState = checkpointSnapshots[targetIdx];
    } else {
      rollbackState = SorobanState.fromValue(cp.previousValue);
    }

    return HintResult(
      checkpoint: cp,
      moves: cp.atomicMoves,
      checkpointIndex: targetIdx,
      recoveredFromDivergence: false,
      fromState: rollbackState,
    );
  }
}
