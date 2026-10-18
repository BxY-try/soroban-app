import 'bead_move.dart';
import 'division_exercise.dart';

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

  /// One-digit divisor, exact integer quotient.
  division1,

  /// Two-digit divisor, exact integer quotient.
  division2,

  /// Integer operands with an exact terminating decimal quotient.
  divisionDecimal,
}

extension ProblemCategoryDivision on ProblemCategory {
  bool get isDivision =>
      this == ProblemCategory.division1 ||
      this == ProblemCategory.division2 ||
      this == ProblemCategory.divisionDecimal;
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

  /// Explanation of the whole operation, rather than an individual flick.
  final String? description;

  const DigitCheckpoint({
    required this.targetValue,
    required this.previousValue,
    required this.termIndex,
    required this.digitIndex,
    required this.rodIndex,
    required this.atomicMoves,
    this.description,
  });

  @override
  String toString() =>
      'DigitCheckpoint($previousValue -> $targetValue, moves: ${atomicMoves.length})';
}

/// Represents a single math problem in Practice or Challenge mode.
class Problem {
  final ProblemCategory category;
  final Difficulty difficulty;

  /// List of operand terms (e.g. [17823, 23094] or [432, 7]).
  final List<int> terms;

  /// Operators between terms (e.g. ['+', '+'] or ['+', '-'] or ['x']).
  final List<String> operators;

  /// Final answer. For division this is an exact fixed-point integer, with
  /// [division.layout.decimalPlaces] digits after the decimal point.
  final int expectedResult;

  final DivisionExercise? division;

  /// Precomputed digit-group checkpoints. Division starts with the dividend
  /// already on the work area; other operations start on an empty board.
  final List<DigitCheckpoint> checkpoints;

  const Problem({
    required this.category,
    required this.difficulty,
    required this.terms,
    required this.operators,
    required this.expectedResult,
    required this.checkpoints,
    this.division,
  });

  /// Formatted equation for display, e.g. "17823 + 23094" or "432 × 7".
  String get displayText {
    if (terms.isEmpty) return '';
    if (category.isDivision && terms.length >= 2) {
      return '${terms[0]} ÷ ${terms[1]}';
    }
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
