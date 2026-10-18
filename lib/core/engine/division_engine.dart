import '../models/bead_move.dart';
import '../models/division_exercise.dart';
import '../models/problem.dart';
import '../models/soroban_state.dart';
import 'addition_engine.dart';

/// Split-method division. All arithmetic is fixed-point integer arithmetic.
/// Each quotient digit is written on the right, then the corresponding
/// head/tail products are subtracted on the left using the existing physical
/// addition engine. Every checkpoint changes the board: zero digits and zero
/// tails need no empty animation or ambiguous repeated checkpoint.
class DivisionEngine {
  final AdditionEngine additionEngine;

  const DivisionEngine({this.additionEngine = const AdditionEngine()});

  static DivisionLayout layoutFor(ProblemCategory category, Difficulty level) {
    if (!category.isDivision) throw ArgumentError('Not a division category');
    final stage = level.index;
    if (category == ProblemCategory.division1) {
      return DivisionLayout(
        dividendDigits: 2 + stage,
        quotientIntegerDigits: 2 + stage,
      );
    }
    if (category == ProblemCategory.division2) {
      return DivisionLayout(
        dividendDigits: 3 + stage,
        quotientIntegerDigits: 2 + stage,
      );
    }
    return DivisionLayout(
      dividendDigits: level == Difficulty.easy ? 2 : 3,
      quotientIntegerDigits: 2,
      decimalPlaces: stage + 1,
    );
  }

  Problem createProblem({
    required int dividend,
    required int divisor,
    required ProblemCategory category,
    required Difficulty difficulty,
    DivisionLayout? layout,
  }) {
    final board = layout ?? layoutFor(category, difficulty);
    if (!category.isDivision ||
        dividend <= 0 ||
        divisor < 2 ||
        divisor > 99 ||
        board.decimalPlaces < 0 ||
        board.decimalPlaces > 3 ||
        board.dividendDigits < 1 ||
        board.quotientIntegerDigits < 1 ||
        board.rodCount > 12 ||
        dividend >= decimalPower(board.dividendDigits) ||
        dividend * board.scale % divisor != 0) {
      throw ArgumentError(
          'Division must fit and terminate exactly on its board');
    }
    if (category == ProblemCategory.division1 && divisor > 9 ||
        category == ProblemCategory.division2 && divisor < 10 ||
        category == ProblemCategory.divisionDecimal &&
            board.decimalPlaces == 0 ||
        category != ProblemCategory.divisionDecimal &&
            board.decimalPlaces != 0) {
      throw ArgumentError('Divisor/precision does not match the category');
    }

    final result = dividend * board.scale ~/ divisor;
    final exercise = DivisionExercise(
      layout: board,
      dividend: dividend,
      divisor: divisor,
    );
    var state = SorobanState.fromValue(
      exercise.initialValue,
      rodCount: board.rodCount,
    );
    var work = dividend * board.scale;
    var quotient = 0;
    final checkpoints = <DigitCheckpoint>[];
    final pendingZeroes = <String>[];

    void record(int change, int offset, String description, int digitIndex) {
      final previous = state;
      final moves = <BeadMove>[];
      final digits = change.abs().toString();
      for (var i = 0; i < digits.length; i++) {
        final digit = int.parse(digits[i]);
        if (digit == 0) continue;
        final produced = additionEngine.calculateDigitMoves(
          state,
          change < 0 ? -digit : digit,
          offset + digits.length - 1 - i,
        );
        moves.addAll(produced);
        state = additionEngine.applyMoves(state, produced);
      }
      if (state.value != board.encode(work: work, quotient: quotient)) {
        throw StateError('Division move crossed the boundary between areas');
      }
      checkpoints.add(DigitCheckpoint(
        previousValue: previous.value,
        targetValue: state.value,
        termIndex: 0,
        digitIndex: digitIndex,
        rodIndex: offset + digits.length - 1,
        atomicMoves: List.unmodifiable(moves),
        description:
            '${pendingZeroes.join(' ')}${pendingZeroes.isEmpty ? '' : ' '}$description',
      ));
      pendingZeroes.clear();
    }

    for (var position = board.resultRods - 1; position >= 0; position--) {
      final place = decimalPower(position);
      final digit = work ~/ (divisor * place);
      if (digit > 9) {
        throw ArgumentError('Quotient exceeds reserved result area');
      }
      if (digit == 0) {
        // Leading empty capacity is not a lesson or a disclosure of answer size.
        if (quotient > 0 && work > 0) {
          pendingZeroes
              .add('Hasil di tiang ${board.resultPlace(position)} tetap 0.');
        }
        continue;
      }
      quotient += digit * place;
      final part = board.format(digit * place);
      record(
        digit,
        position,
        '$part × $divisor = ${board.format(digit * divisor * place)} '
        'masih muat dalam sisa ${board.format(work)}. '
        'Tulis $digit pada tiang ${board.resultPlace(position)} di area hasil.',
        board.resultRods - 1 - position,
      );

      final divisorDigits = divisor.toString();
      for (var i = 0; i < divisorDigits.length; i++) {
        final factor = int.parse(divisorDigits[i]);
        if (factor == 0) continue;
        final component = factor * decimalPower(divisorDigits.length - 1 - i);
        final subtract = digit * component * place;
        work -= subtract;
        final name = divisorDigits.length == 1
            ? 'pembagi'
            : i == 0
                ? 'kepala'
                : 'ekor';
        record(
          -subtract,
          board.workOffset,
          'Kurangi ${board.format(subtract)} dari area soal/sisa '
          '($part × $component, $name). '
          'Sisa menjadi ${board.format(work)}.',
          board.resultRods - 1 - position,
        );
      }
    }
    if (work != 0 || quotient != result || checkpoints.isEmpty) {
      throw StateError('Division did not finish with an empty work area');
    }
    return Problem(
      category: category,
      difficulty: difficulty,
      terms: [dividend, divisor],
      operators: const ['÷'],
      expectedResult: result,
      checkpoints: List.unmodifiable(checkpoints),
      division: exercise,
    );
  }

  /// Validate before a controller changes its board, timer, or session. In
  /// particular a malformed plan can never report an unfinished remainder as
  /// solved, or pass animation moves outside the reserved areas.
  void validateProblem(Problem problem) {
    final exercise = problem.division;
    if (!problem.category.isDivision) {
      if (exercise != null) throw ArgumentError('Unexpected division metadata');
      return;
    }
    if (exercise == null ||
        problem.terms.length != 2 ||
        exercise.dividend != problem.terms[0] ||
        exercise.divisor != problem.terms[1]) {
      throw ArgumentError('Missing or inconsistent division metadata');
    }
    final expected = createProblem(
      dividend: exercise.dividend,
      divisor: exercise.divisor,
      category: problem.category,
      difficulty: problem.difficulty,
      layout: exercise.layout,
    );
    if (expected.expectedResult != problem.expectedResult ||
        expected.checkpoints.length != problem.checkpoints.length) {
      throw ArgumentError('Incomplete division plan');
    }
    for (var i = 0; i < expected.checkpoints.length; i++) {
      final actual = problem.checkpoints[i];
      final canonical = expected.checkpoints[i];
      if (actual.previousValue != canonical.previousValue ||
          actual.targetValue != canonical.targetValue ||
          actual.atomicMoves.length != canonical.atomicMoves.length) {
        throw ArgumentError('Invalid division checkpoint');
      }
      for (var j = 0; j < actual.atomicMoves.length; j++) {
        final a = actual.atomicMoves[j];
        final b = canonical.atomicMoves[j];
        if (a.rodIndex != b.rodIndex ||
            a.kind != b.kind ||
            a.from != b.from ||
            a.to != b.to) {
          throw ArgumentError('Invalid division animation');
        }
      }
    }
  }
}
