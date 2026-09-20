import '../models/bead_move.dart';
import '../models/problem.dart';
import '../models/rod.dart';
import '../models/soroban_state.dart';

/// Calculation engine for Soroban mechanical bead manipulations.
/// Accurately simulates the physical rules of Japanese Soroban:
/// - Direct movements (cukup manik)
/// - 5-complement ("kawan kecil": 1/4, 2/3 pairs)
/// - 10-complement ("kawan besar": 1/9, 2/8, 3/7, 4/6, 5/5 pairs) with carries and borrows
/// - Multi-rod ripple carries (simpanan beruntun) and ripple borrows
class AdditionEngine {
  const AdditionEngine();

  /// Applies a single [BeadMove] to [state], returning the updated [SorobanState].
  SorobanState applyMove(SorobanState state, BeadMove move) {
    if (move.rodIndex < 0 || move.rodIndex >= state.rods.length) {
      return state;
    }
    final currentRod = state.rods[move.rodIndex];
    Rod newRod;
    if (move.kind == BeadKind.heaven) {
      newRod = currentRod.copyWith(heaven: move.to == 5);
    } else {
      newRod = currentRod.copyWith(earth: move.to);
    }
    return state.updateRod(move.rodIndex, newRod);
  }

  /// Applies a sequence of [BeadMove]s to [state].
  SorobanState applyMoves(SorobanState state, List<BeadMove> moves) {
    SorobanState current = state;
    for (final move in moves) {
      current = applyMove(current, move);
    }
    return current;
  }

  /// Computes the exact atomic [BeadMove]s to add or subtract a single digit [signedDigit]
  /// (-9..9) at rod [rodIndex] starting from [state].
  List<BeadMove> calculateDigitMoves(
    SorobanState state,
    int signedDigit,
    int rodIndex,
  ) {
    if (signedDigit == 0) return const [];
    assert(
      rodIndex >= 0 && rodIndex < state.rods.length,
      'rodIndex out of bounds',
    );

    if (signedDigit > 0) {
      return _calculateAdditionMoves(state, signedDigit, rodIndex);
    } else {
      return _calculateSubtractionMoves(state, -signedDigit, rodIndex);
    }
  }

  /// Internal: calculates moves for adding [d] (1..9) to rod [rodIndex].
  List<BeadMove> _calculateAdditionMoves(
    SorobanState state,
    int d,
    int rodIndex,
  ) {
    final moves = <BeadMove>[];
    final currentRod = state.rods[rodIndex];
    final v = currentRod.value;

    if (v + d < 10) {
      // No carry to next rod.
      final targetVal = v + d;
      final targetHeaven = targetVal >= 5;
      final targetEarth = targetVal % 5;

      if (!currentRod.heaven && targetHeaven) {
        // Heaven bead activated (+5)
        moves.add(BeadMove(
          rodIndex: rodIndex,
          kind: BeadKind.heaven,
          from: 0,
          to: 5,
          description: 'Rod $rodIndex: Turunkan manik langit (+5)',
        ));
      } else if (currentRod.heaven && !targetHeaven) {
        // Should not happen for addition without carry, but for completeness:
        moves.add(BeadMove(
          rodIndex: rodIndex,
          kind: BeadKind.heaven,
          from: 5,
          to: 0,
          description: 'Rod $rodIndex: Naikkan manik langit (-5)',
        ));
      }

      if (currentRod.earth != targetEarth) {
        moves.add(BeadMove(
          rodIndex: rodIndex,
          kind: BeadKind.earth,
          from: currentRod.earth,
          to: targetEarth,
          description:
              'Rod $rodIndex: Manik bumi ${currentRod.earth} -> $targetEarth',
        ));
      }
    } else {
      // Carry required: v + d >= 10.
      // Traditional Soroban: First execute carry (+1 to rodIndex + 1),
      // then subtract 10-complement (10 - d) from rodIndex.
      final carryMoves = _calculateAdditionMoves(state, 1, rodIndex + 1);
      moves.addAll(carryMoves);

      // Now on current rod, new value is (v + d - 10).
      final targetVal = (v + d) - 10;
      final targetHeaven = targetVal >= 5;
      final targetEarth = targetVal % 5;

      if (currentRod.heaven && !targetHeaven) {
        // Heaven bead goes from active (5) to inactive (0)
        moves.add(BeadMove(
          rodIndex: rodIndex,
          kind: BeadKind.heaven,
          from: 5,
          to: 0,
          description: 'Rod $rodIndex: Naikkan manik langit (-5)',
        ));
      } else if (!currentRod.heaven && targetHeaven) {
        moves.add(BeadMove(
          rodIndex: rodIndex,
          kind: BeadKind.heaven,
          from: 0,
          to: 5,
          description: 'Rod $rodIndex: Turunkan manik langit (+5)',
        ));
      }

      if (currentRod.earth != targetEarth) {
        moves.add(BeadMove(
          rodIndex: rodIndex,
          kind: BeadKind.earth,
          from: currentRod.earth,
          to: targetEarth,
          description:
              'Rod $rodIndex: Manik bumi ${currentRod.earth} -> $targetEarth',
        ));
      }
    }

    return moves;
  }

  /// Internal: calculates moves for subtracting [d] (1..9) from rod [rodIndex].
  List<BeadMove> _calculateSubtractionMoves(
    SorobanState state,
    int d,
    int rodIndex,
  ) {
    final moves = <BeadMove>[];
    final currentRod = state.rods[rodIndex];
    final v = currentRod.value;

    if (v >= d) {
      // No borrow needed.
      final targetVal = v - d;
      final targetHeaven = targetVal >= 5;
      final targetEarth = targetVal % 5;

      if (currentRod.heaven && !targetHeaven) {
        moves.add(BeadMove(
          rodIndex: rodIndex,
          kind: BeadKind.heaven,
          from: 5,
          to: 0,
          description: 'Rod $rodIndex: Naikkan manik langit (-5)',
        ));
      }

      if (currentRod.earth != targetEarth) {
        moves.add(BeadMove(
          rodIndex: rodIndex,
          kind: BeadKind.earth,
          from: currentRod.earth,
          to: targetEarth,
          description:
              'Rod $rodIndex: Manik bumi ${currentRod.earth} -> $targetEarth',
        ));
      }
    } else {
      // Borrow needed: v < d.
      // Traditional Soroban: Borrow 1 from rodIndex + 1 (-1 to rodIndex + 1),
      // then add (10 - d) to current rod -> targetVal = v + 10 - d.
      final borrowMoves = _calculateSubtractionMoves(state, 1, rodIndex + 1);
      moves.addAll(borrowMoves);

      final targetVal = (v + 10) - d;
      final targetHeaven = targetVal >= 5;
      final targetEarth = targetVal % 5;

      if (!currentRod.heaven && targetHeaven) {
        moves.add(BeadMove(
          rodIndex: rodIndex,
          kind: BeadKind.heaven,
          from: 0,
          to: 5,
          description: 'Rod $rodIndex: Turunkan manik langit (+5)',
        ));
      } else if (currentRod.heaven && !targetHeaven) {
        moves.add(BeadMove(
          rodIndex: rodIndex,
          kind: BeadKind.heaven,
          from: 5,
          to: 0,
          description: 'Rod $rodIndex: Naikkan manik langit (-5)',
        ));
      }

      if (currentRod.earth != targetEarth) {
        moves.add(BeadMove(
          rodIndex: rodIndex,
          kind: BeadKind.earth,
          from: currentRod.earth,
          to: targetEarth,
          description:
              'Rod $rodIndex: Manik bumi ${currentRod.earth} -> $targetEarth',
        ));
      }
    }

    return moves;
  }

  /// Decomposes [termValue] into digit-group checkpoints (from highest place value to lowest).
  /// Generates a list of [DigitCheckpoint]s updating [startingState] progressively.
  List<DigitCheckpoint> generateCheckpointsForTerm({
    required SorobanState startingState,
    required int termValue,
    required bool isAddition,
    required int termIndex,
    String Function(int signedVal, int rodIndex)? labelBuilder,
  }) {
    final checkpoints = <DigitCheckpoint>[];
    if (termValue == 0) return checkpoints;

    final termStr = termValue.abs().toString();
    final totalDigits = termStr.length;
    SorobanState runningState = startingState;

    for (int i = 0; i < totalDigits; i++) {
      final digitChar = termStr[i];
      final digit = int.parse(digitChar);
      if (digit == 0) continue;

      final rodIndex = totalDigits - 1 - i;
      final signedDigit = isAddition ? digit : -digit;
      final moves = calculateDigitMoves(runningState, signedDigit, rodIndex);
      final prevState = runningState;
      runningState = applyMoves(runningState, moves);

      final multiplier = _pow10(rodIndex);
      final signedVal = signedDigit * multiplier;
      final label = labelBuilder != null
          ? labelBuilder(signedVal, rodIndex)
          : (isAddition ? '+$signedVal' : '$signedVal');

      checkpoints.add(DigitCheckpoint(
        targetValue: runningState.value,
        previousValue: prevState.value,
        termIndex: termIndex,
        digitIndex: i,
        rodIndex: rodIndex,
        atomicMoves: moves,
        label: label,
      ));
    }

    return checkpoints;
  }

  int _pow10(int exp) {
    int res = 1;
    for (int i = 0; i < exp; i++) {
      res *= 10;
    }
    return res;
  }
}
