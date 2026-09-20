import 'dart:math';
import '../models/problem.dart';
import '../models/soroban_state.dart';
import 'addition_engine.dart';
import 'multiplication_engine.dart';

/// Generates math problems for Practice and Challenge sessions using Rejection Sampling.
/// Guarantees that:
/// - Values fit on 7 rods (<= 9,999,999)
/// - Intermediate running totals never drop below 0 (non-negative constraint)
/// - Digits and terms strictly conform to the spec in §3
class ProblemGenerator {
  final Random _random;
  final AdditionEngine additionEngine;
  final MultiplicationEngine multiplicationEngine;

  ProblemGenerator({
    Random? random,
    this.additionEngine = const AdditionEngine(),
    this.multiplicationEngine = const MultiplicationEngine(),
  }) : _random = random ?? Random();

  /// Generates a single [Problem] for the given [category] and [difficulty].
  Problem generateProblem({
    required ProblemCategory category,
    required Difficulty difficulty,
    int rodCount = 7,
  }) {
    switch (category) {
      case ProblemCategory.addition:
        return _generateAdditionProblem(difficulty, rodCount);
      case ProblemCategory.mixed:
        return _generateMixedProblem(difficulty, rodCount);
      case ProblemCategory.multiplication1:
        return _generateMultiplication1Problem(difficulty, rodCount);
      case ProblemCategory.multiplication2:
        return _generateMultiplication2Problem(difficulty, rodCount);
    }
  }

  /// Generates a session of 5 problems for Challenge mode.
  List<Problem> generateChallengeSession({
    required ProblemCategory category,
    required Difficulty difficulty,
    int rodCount = 7,
    int count = 5,
  }) {
    return List<Problem>.generate(
      count,
      (_) => generateProblem(
        category: category,
        difficulty: difficulty,
        rodCount: rodCount,
      ),
    );
  }

  // --- Addition ---
  // Easy: 3 terms x 2 digits
  // Medium: 3 terms x 3 digits
  // Hard: 4 terms x 4 digits
  Problem _generateAdditionProblem(Difficulty difficulty, int rodCount) {
    final int termCount = difficulty == Difficulty.hard ? 4 : 3;
    final int digitCount = switch (difficulty) {
      Difficulty.easy => 2,
      Difficulty.medium => 3,
      Difficulty.hard => 4,
    };

    while (true) {
      final terms = <int>[];
      final operators = <String>[];
      int sum = 0;
      bool valid = true;

      for (int i = 0; i < termCount; i++) {
        final term = _randomNDigits(digitCount);
        terms.add(term);
        sum += term;
        if (i > 0) operators.add('+');
        if (sum > 9999999) {
          valid = false;
          break;
        }
      }

      if (!valid) continue;

      // Generate checkpoints
      final checkpoints = <DigitCheckpoint>[];
      SorobanState runningState = SorobanState.zero(rodCount: rodCount);

      for (int i = 0; i < terms.length; i++) {
        final termCps = additionEngine.generateCheckpointsForTerm(
          startingState: runningState,
          termValue: terms[i],
          isAddition: true,
          termIndex: i,
        );
        checkpoints.addAll(termCps);
        if (termCps.isNotEmpty) {
          runningState = SorobanState.fromValue(
            termCps.last.targetValue,
            rodCount: rodCount,
          );
        }
      }

      return Problem(
        category: ProblemCategory.addition,
        difficulty: difficulty,
        terms: terms,
        operators: operators,
        expectedResult: sum,
        checkpoints: checkpoints,
      );
    }
  }

  // --- Mixed Addition & Subtraction ---
  // Terms and digits identical to addition, but operators randomized.
  // Constraint: running total NEVER negative at any step.
  Problem _generateMixedProblem(Difficulty difficulty, int rodCount) {
    final int termCount = difficulty == Difficulty.hard ? 4 : 3;
    final int digitCount = switch (difficulty) {
      Difficulty.easy => 2,
      Difficulty.medium => 3,
      Difficulty.hard => 4,
    };

    while (true) {
      final terms = <int>[];
      final operators = <String>[];
      // First term is always positive
      int firstTerm = _randomNDigits(digitCount);
      // For mixed subtraction, start with a generous first term
      if (firstTerm < _pow10(digitCount - 1) * 3) {
        firstTerm += _pow10(digitCount - 1) * 3;
      }
      terms.add(firstTerm);

      int runningTotal = firstTerm;
      bool valid = true;

      for (int i = 1; i < termCount; i++) {
        final isAdd = _random.nextBool();
        final term = _randomNDigits(digitCount);

        if (isAdd) {
          runningTotal += term;
          operators.add('+');
        } else {
          // If subtracting would make total negative, force addition or adjust
          if (runningTotal - term < 0) {
            // rejection
            valid = false;
            break;
          }
          runningTotal -= term;
          operators.add('-');
        }

        if (runningTotal > 9999999) {
          valid = false;
          break;
        }
        terms.add(term);
      }

      if (!valid || terms.length != termCount) continue;

      // Simulate checkpoints
      final checkpoints = <DigitCheckpoint>[];
      SorobanState runningState = SorobanState.zero(rodCount: rodCount);

      // First term addition
      final firstCps = additionEngine.generateCheckpointsForTerm(
        startingState: runningState,
        termValue: terms[0],
        isAddition: true,
        termIndex: 0,
      );
      checkpoints.addAll(firstCps);
      if (firstCps.isNotEmpty) {
        runningState = SorobanState.fromValue(
          firstCps.last.targetValue,
          rodCount: rodCount,
        );
      }

      for (int i = 1; i < terms.length; i++) {
        final isAdd = operators[i - 1] == '+';
        final termCps = additionEngine.generateCheckpointsForTerm(
          startingState: runningState,
          termValue: terms[i],
          isAddition: isAdd,
          termIndex: i,
        );
        checkpoints.addAll(termCps);
        if (termCps.isNotEmpty) {
          runningState = SorobanState.fromValue(
            termCps.last.targetValue,
            rodCount: rodCount,
          );
        }
      }

      return Problem(
        category: ProblemCategory.mixed,
        difficulty: difficulty,
        terms: terms,
        operators: operators,
        expectedResult: runningTotal,
        checkpoints: checkpoints,
      );
    }
  }

  // --- Multiplication I: 1-digit multiplier ---
  // Easy: 3 digits x 1 digit
  // Medium: 4 digits x 1 digit
  // Hard: 5 digits x 1 digit
  Problem _generateMultiplication1Problem(Difficulty difficulty, int rodCount) {
    final int aDigits = switch (difficulty) {
      Difficulty.easy => 3,
      Difficulty.medium => 4,
      Difficulty.hard => 5,
    };

    while (true) {
      final a = _randomNDigits(aDigits);
      // Multiplier is 1 digit (2..9)
      final b = 2 + _random.nextInt(8);
      final product = a * b;

      if (product > 9999999) continue;

      final checkpoints = multiplicationEngine.generateCheckpoints(
        multiplicand: a,
        multiplier: b,
        rodCount: rodCount,
      );

      return Problem(
        category: ProblemCategory.multiplication1,
        difficulty: difficulty,
        terms: [a, b],
        operators: ['×'],
        expectedResult: product,
        checkpoints: checkpoints,
      );
    }
  }

  // --- Multiplication II: 2-digit multiplier ---
  // Easy: 4 digits x 2 digits
  // Medium: 5 digits x 2 digits
  // Hard: 5 digits x 2 digits (carry-heavy: digits 6..9, avoid zeroes)
  Problem _generateMultiplication2Problem(Difficulty difficulty, int rodCount) {
    final int aDigits = switch (difficulty) {
      Difficulty.easy => 4,
      Difficulty.medium => 5,
      Difficulty.hard => 5,
    };

    while (true) {
      int a;
      int b;

      if (difficulty == Difficulty.hard) {
        // Carry-heavy: generate digits 6..9 to maximize carries and bead moves
        a = _randomCarryHeavyDigits(aDigits);
        b = _randomCarryHeavyDigits(2);
      } else {
        a = _randomNDigits(aDigits);
        b = 10 + _random.nextInt(90); // 10..99
      }

      final product = a * b;
      if (product > 9999999) continue;

      final checkpoints = multiplicationEngine.generateCheckpoints(
        multiplicand: a,
        multiplier: b,
        rodCount: rodCount,
      );

      return Problem(
        category: ProblemCategory.multiplication2,
        difficulty: difficulty,
        terms: [a, b],
        operators: ['×'],
        expectedResult: product,
        checkpoints: checkpoints,
      );
    }
  }

  int _randomNDigits(int n) {
    if (n <= 1) return 1 + _random.nextInt(9);
    final min = _pow10(n - 1);
    final max = _pow10(n) - 1;
    return min + _random.nextInt(max - min + 1);
  }

  int _randomCarryHeavyDigits(int n) {
    int val = 0;
    for (int i = 0; i < n; i++) {
      final digit = 6 + _random.nextInt(4); // 6, 7, 8, 9
      val = val * 10 + digit;
    }
    return val;
  }

  int _pow10(int exp) {
    int res = 1;
    for (int i = 0; i < exp; i++) {
      res *= 10;
    }
    return res;
  }
}
