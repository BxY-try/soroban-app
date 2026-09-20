import '../models/bead_move.dart';
import '../models/problem.dart';
import '../models/soroban_state.dart';
import 'addition_engine.dart';

/// Engine that decomposes multiplication into partial products
/// and pipes each partial product directly into [AdditionEngine].
/// Adheres strictly to the architectural requirement:
/// "100% reuse of the Addition Engine for bead moves and friend techniques."
class MultiplicationEngine {
  final AdditionEngine additionEngine;

  const MultiplicationEngine({
    this.additionEngine = const AdditionEngine(),
  });

  /// Generates the sequence of [DigitCheckpoint]s for [multiplicand] × [multiplier].
  /// Traverses each digit of the multiplier, and each digit of the multiplicand,
  /// placing the partial products on the corresponding rods (10^(i+j)).
  List<DigitCheckpoint> generateCheckpoints({
    required int multiplicand,
    required int multiplier,
    int rodCount = 7,
  }) {
    final checkpoints = <DigitCheckpoint>[];
    final aStr = multiplicand.toString(); // Multiplicand (left)
    final bStr = multiplier.toString(); // Multiplier (right)

    SorobanState runningState = SorobanState.zero(rodCount: rodCount);

    // Typically on Soroban, multiplier digits are processed from left to right (highest to lowest)
    // or multiplicand digits from left to right.
    for (int j = 0; j < bStr.length; j++) {
      final bDigit = int.parse(bStr[j]);
      final bExp = bStr.length - 1 - j; // place value exponent of multiplier digit

      for (int i = 0; i < aStr.length; i++) {
        final aDigit = int.parse(aStr[i]);
        final aExp = aStr.length - 1 - i; // place value exponent of multiplicand digit

        final partial = aDigit * bDigit;
        if (partial == 0) continue;

        // The product contributes partial * 10^(aExp + bExp)
        final baseRod = aExp + bExp;
        final pTens = partial ~/ 10;
        final pUnits = partial % 10;

        final moves = <BeadMove>[];
        final prevState = runningState;

        // 1. Add tens digit of partial product to (baseRod + 1) if > 0
        if (pTens > 0 && (baseRod + 1) < rodCount) {
          final tensMoves = additionEngine.calculateDigitMoves(
            runningState,
            pTens,
            baseRod + 1,
          );
          moves.addAll(tensMoves);
          runningState = additionEngine.applyMoves(runningState, tensMoves);
        }

        // 2. Add units digit of partial product to baseRod if > 0
        if (pUnits > 0 && baseRod < rodCount) {
          final unitsMoves = additionEngine.calculateDigitMoves(
            runningState,
            pUnits,
            baseRod,
          );
          moves.addAll(unitsMoves);
          runningState = additionEngine.applyMoves(runningState, unitsMoves);
        }

        if (moves.isNotEmpty) {
          checkpoints.add(DigitCheckpoint(
            targetValue: runningState.value,
            previousValue: prevState.value,
            termIndex: j, // active multiplier digit
            digitIndex: i, // active multiplicand digit
            rodIndex: baseRod,
            atomicMoves: moves,
            label: '$aDigit × $bDigit = $partial',
          ));
        }
      }
    }

    return checkpoints;
  }
}
