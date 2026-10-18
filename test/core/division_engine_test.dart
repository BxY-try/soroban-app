import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/engine/addition_engine.dart';
import 'package:soroban_app/core/engine/division_engine.dart';
import 'package:soroban_app/core/engine/problem_generator.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/models/soroban_state.dart';

void main() {
  const engine = DivisionEngine();

  test('147 / 3: independent work and quotient, correct physical moves', () {
    final problem = engine.createProblem(
      dividend: 147,
      divisor: 3,
      category: ProblemCategory.division1,
      difficulty: Difficulty.medium,
    );
    expect(problem.checkpoints.map((c) => c.targetValue),
        [1470040, 270040, 270049, 49]);
    expect(problem.division!.initialValue, 1470000);
    expect(problem.expectedResult, 49);
  });

  test('864 / 24: head and tail are separate, correctly aligned subtractions',
      () {
    final problem = engine.createProblem(
      dividend: 864,
      divisor: 24,
      category: ProblemCategory.division2,
      difficulty: Difficulty.easy,
    );
    expect(problem.checkpoints.map((c) => c.targetValue),
        [864030, 264030, 144030, 144036, 24036, 36]);
    expect(problem.checkpoints[1].description, contains('kepala'));
    expect(problem.checkpoints[2].description, contains('ekor'));
  });

  test('111 / 24: decimal remainder has a consistent fixed place value', () {
    final problem = engine.createProblem(
      dividend: 111,
      divisor: 24,
      category: ProblemCategory.divisionDecimal,
      difficulty: Difficulty.hard,
    );
    final board = problem.division!.layout;
    expect(problem.checkpoints.map((c) => board.workValue(c.targetValue)),
        [111000, 31000, 15000, 15000, 3000, 600, 600, 200, 120, 120, 20, 0]);
    expect(problem.checkpoints.map((c) => board.quotientValue(c.targetValue)), [
      4000,
      4000,
      4000,
      4600,
      4600,
      4600,
      4620,
      4620,
      4620,
      4625,
      4625,
      4625
    ]);
    expect(board.format(problem.expectedResult), '4,625');
  });

  test('zero tail, interior zero and quotient below one have no empty steps',
      () {
    for (final pair in [(105, 40), (101, 25), (12, 48), (204, 2)]) {
      final problem = engine.createProblem(
        dividend: pair.$1,
        divisor: pair.$2,
        category: pair.$2 == 2
            ? ProblemCategory.division1
            : ProblemCategory.divisionDecimal,
        difficulty: pair.$2 == 40 ? Difficulty.hard : Difficulty.medium,
      );
      final values = problem.checkpoints.map((c) => c.targetValue).toList();
      expect(values.toSet().length, values.length);
      expect(
          problem.checkpoints.every((c) => c.atomicMoves.isNotEmpty), isTrue);
      expect(values.last, pair.$1 * problem.division!.layout.scale ~/ pair.$2);
    }
  });

  test(
      'all generated levels terminate, preserve areas, and fit their fixed board',
      () {
    final generator = ProblemGenerator(random: Random(421));
    const arithmetic = AdditionEngine();
    for (final category in ProblemCategory.values.where((c) => c.isDivision)) {
      for (final difficulty in Difficulty.values) {
        for (var n = 0; n < 60; n++) {
          final problem = generator.generateProblem(
            category: category,
            difficulty: difficulty,
          );
          final division = problem.division!;
          final board = division.layout;
          final scaledDividend = division.dividend * board.scale;
          expect(scaledDividend % division.divisor, 0);
          expect(problem.expectedResult, scaledDividend ~/ division.divisor);
          expect(board.rodCount,
              DivisionEngine.layoutFor(category, difficulty).rodCount);
          if (category == ProblemCategory.divisionDecimal) {
            expect(problem.expectedResult % 10, isNot(0));
          }
          var state = SorobanState.fromValue(division.initialValue,
              rodCount: board.rodCount);
          final seen = <int>{state.value};
          for (final step in problem.checkpoints) {
            expect(step.previousValue, state.value);
            expect(step.targetValue, isNot(step.previousValue));
            for (final move in step.atomicMoves) {
              expect(move.rodIndex, inInclusiveRange(0, board.rodCount - 1));
              expect(move.rodIndex, isNot(board.spacerRod));
              state = arithmetic.applyMove(state, move);
              expect(state.rods[board.spacerRod].value, 0);
            }
            expect(state.value, step.targetValue);
            expect(seen.add(state.value), isTrue);
          }
          expect(board.workValue(state.value), 0);
          expect(state.value, problem.expectedResult);
          engine.validateProblem(problem);
        }
      }
    }
  });

  test(
      'division rejects non-terminating, zero-divisor and overflowing problems',
      () {
    for (final pair in [(11, 3), (12, 0), (10000, 2)]) {
      expect(
          () => engine.createProblem(
                dividend: pair.$1,
                divisor: pair.$2,
                category: ProblemCategory.divisionDecimal,
                difficulty: Difficulty.easy,
              ),
          throwsArgumentError);
    }
  });
}
