import '../models/bead_move.dart';
import '../models/problem.dart';
import '../models/soroban_state.dart';
import 'addition_engine.dart';
import 'multiplication_progress.dart';

/// Engine that decomposes multiplication into partial products
/// and pipes each partial product directly into [AdditionEngine].
/// Adheres strictly to the architectural requirement:
/// "100% reuse of the Addition Engine for bead moves and friend techniques."
class MultiplicationEngine {
  final AdditionEngine additionEngine;

  const MultiplicationEngine({
    this.additionEngine = const AdditionEngine(),
  });

  /// Generates the canonical teaching sequence of [DigitCheckpoint]s for
  /// [multiplicand] × [multiplier].
  ///
  /// The contributions are those of [MultiplicationContribution.decompose],
  /// taken in that order: multiplier digits left to right and, within each,
  /// multiplicand digits left to right, each placed on rod `aExp + bExp`.
  ///
  /// This chain is the *default* route: what the app draws, and what Hint plays
  /// while the user follows it. It is not the only valid one. Progress on the
  /// board is read from [MultiplicationProgress], which accepts the
  /// contributions in any order.
  ///
  /// The chain has exactly one checkpoint per contribution and ends on the
  /// product. A product that does not fit on [rodCount] rods is refused with an
  /// [ArgumentError] by the decomposition, so a chain that stops short can never
  /// be returned.
  List<DigitCheckpoint> generateCheckpoints({
    required int multiplicand,
    required int multiplier,
    int rodCount = 7,
  }) {
    final checkpoints = <DigitCheckpoint>[];
    var runningState = SorobanState.zero(rodCount: rodCount);

    final contributions = MultiplicationContribution.decompose(
      multiplicand: multiplicand,
      multiplier: multiplier,
      rodCount: rodCount,
    );

    for (final contribution in contributions) {
      final moves = contributionMoves(runningState, contribution);
      if (moves.isEmpty) {
        // Never skipped: a checkpoint missing from the chain is a contribution
        // the board is never asked for, and the chain would end short of the
        // product without anything noticing.
        throw StateError('$contribution produced no moves on $runningState');
      }

      final prevState = runningState;
      runningState = additionEngine.applyMoves(runningState, moves);

      checkpoints.add(DigitCheckpoint(
        targetValue: runningState.value,
        previousValue: prevState.value,
        termIndex: contribution.multiplierIndex, // active multiplier digit
        digitIndex: contribution.multiplicandIndex, // active multiplicand digit
        rodIndex: contribution.rodIndex,
        atomicMoves: moves,
      ));
    }

    return checkpoints;
  }

  /// The bead moves that add [contribution] to the board [state].
  ///
  /// Worked out from [state] itself, not from any canonical position, so it is
  /// right for whatever the user has on the board: the same contribution needs
  /// different moves (carries included) on different boards.
  ///
  /// The tens digit of the digit product goes to the rod above first, then the
  /// units digit to the contribution's own rod, both through [AdditionEngine].
  ///
  /// A contribution that does not reach [state] (its top digit would land past
  /// the last rod) is an [ArgumentError]. It used to be skipped digit by digit,
  /// which returned moves for less than the contribution's value while the
  /// caller carried on as if all of it had been added.
  List<BeadMove> contributionMoves(
    SorobanState state,
    MultiplicationContribution contribution,
  ) {
    final rodCount = state.rods.length;
    final baseRod = contribution.rodIndex;
    final pTens = contribution.partial ~/ 10;
    final pUnits = contribution.partial % 10;

    final topRod = pTens > 0 ? baseRod + 1 : baseRod;
    if (baseRod < 0 || topRod >= rodCount) {
      throw ArgumentError(
        '$contribution does not fit on a board of $rodCount rods '
        '(it needs rod $topRod)',
      );
    }

    final moves = <BeadMove>[];
    var runningState = state;

    // 1. Add tens digit of partial product to (baseRod + 1) if > 0
    if (pTens > 0) {
      final tensMoves = additionEngine.calculateDigitMoves(
        runningState,
        pTens,
        baseRod + 1,
      );
      moves.addAll(tensMoves);
      runningState = additionEngine.applyMoves(runningState, tensMoves);
    }

    // 2. Add units digit of partial product to baseRod if > 0
    if (pUnits > 0) {
      final unitsMoves = additionEngine.calculateDigitMoves(
        runningState,
        pUnits,
        baseRod,
      );
      moves.addAll(unitsMoves);
    }

    return moves;
  }
}
