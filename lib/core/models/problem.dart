import 'bead_move.dart';
import 'checkpoint_plan.dart';

/// Categories of mathematical operations supported by the app.
enum ProblemCategory {
  /// Pure addition: terms added sequentially.
  addition,

  /// Mixed addition and subtraction with non-negative intermediate totals.
  mixed,

  /// Multiplication with a 1-digit multiplier.
  multiplication1,

  /// Multiplication with a 2-digit multiplier.
  multiplication2,
}

/// Difficulty levels.
enum Difficulty {
  easy,
  medium,
  hard,
}

/// A checkpoint corresponding to one full digit being processed.
/// In addition/subtraction, this is one place-value digit (e.g. +20000, +90).
/// In multiplication, this is one partial product addition.
class DigitCheckpoint {
  /// Abacus target value once this digit is fully executed.
  final int targetValue;

  /// Abacus value immediately before this digit started.
  final int previousValue;

  /// Index of the term in the problem (0-indexed).
  final int termIndex;

  /// Index of the digit within the term (0 = leftmost/highest place value).
  final int digitIndex;

  /// Primary rod affected by this digit (0 = units).
  final int rodIndex;

  /// Sequence of physical finger flick moves executing this full digit.
  final List<BeadMove> atomicMoves;

  /// Which rods may be touched in which order to execute this digit.
  ///
  /// [atomicMoves] says *what* the digit costs; this says *what the user is
  /// allowed to do at any point in time*, which a flat move list cannot
  /// express. A single digit may span several groups (`999 -> 1000` is three
  /// ordered rods) and one group may be finished with several fingers at once
  /// (a `9` is heaven + earth on the same rod).
  final CheckpointPlan plan;

  /// Human-readable label (e.g., "+20000", "+90", "-400").
  final String label;

  const DigitCheckpoint({
    required this.targetValue,
    required this.previousValue,
    required this.termIndex,
    required this.digitIndex,
    required this.rodIndex,
    required this.atomicMoves,
    required this.plan,
    required this.label,
  });

  @override
  String toString() =>
      'DigitCheckpoint($label: $previousValue -> $targetValue, moves: ${atomicMoves.length})';
}

/// Represents a single math problem in Practice or Challenge mode.
class Problem {
  final ProblemCategory category;
  final Difficulty difficulty;

  /// List of operand terms (e.g. [17823, 23094] or [432, 7]).
  final List<int> terms;

  /// Operators between terms (e.g. ['+', '+'] or ['+', '-'] or ['x']).
  final List<String> operators;

  /// Final mathematical answer.
  final int expectedResult;

  /// Precomputed digit-group checkpoints from start (0) to finish.
  final List<DigitCheckpoint> checkpoints;

  const Problem({
    required this.category,
    required this.difficulty,
    required this.terms,
    required this.operators,
    required this.expectedResult,
    required this.checkpoints,
  });

  /// Formatted equation for display, e.g. "17823 + 23094" or "432 × 7".
  String get displayText {
    if (terms.isEmpty) return '';
    if (category == ProblemCategory.multiplication1 ||
        category == ProblemCategory.multiplication2) {
      return '${terms[0]} × ${terms[1]}';
    }

    final buffer = StringBuffer(terms[0].toString());
    for (int i = 0; i < operators.length && i + 1 < terms.length; i++) {
      buffer.write(' ${operators[i]} ${terms[i + 1]}');
    }
    return buffer.toString();
  }

  @override
  String toString() => 'Problem($displayText = $expectedResult)';
}
