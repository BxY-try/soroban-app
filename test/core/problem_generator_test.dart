import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/engine/multiplication_progress.dart';
import 'package:soroban_app/core/engine/problem_generator.dart';
import 'package:soroban_app/core/models/problem.dart';

void main() {
  group('ProblemGenerator Rejection Sampling Tests', () {
    final generator = ProblemGenerator();

    test('Addition generates valid terms and conforms to digit specifications', () {
      // Easy: 3 terms x 2 digits
      final easy = generator.generateProblem(
        category: ProblemCategory.addition,
        difficulty: Difficulty.easy,
      );
      expect(easy.terms.length, equals(3));
      for (final t in easy.terms) {
        expect(t, inInclusiveRange(10, 99));
      }
      expect(easy.expectedResult, equals(easy.terms.reduce((a, b) => a + b)));
      expect(easy.expectedResult, lessThanOrEqualTo(9999999));

      // Hard: 4 terms x 4 digits
      final hard = generator.generateProblem(
        category: ProblemCategory.addition,
        difficulty: Difficulty.hard,
      );
      expect(hard.terms.length, equals(4));
      for (final t in hard.terms) {
        expect(t, inInclusiveRange(1000, 9999));
      }
      expect(hard.expectedResult, lessThanOrEqualTo(9999999));
    });

    test('Mixed (+/-) strictly guarantees non-negative running total at all points', () {
      for (int i = 0; i < 20; i++) {
        final problem = generator.generateProblem(
          category: ProblemCategory.mixed,
          difficulty: Difficulty.medium,
        );

        expect(problem.terms.length, equals(3));
        for (final t in problem.terms) {
          expect(t, inInclusiveRange(100, 999));
        }

        // Verify running total manually
        int total = problem.terms[0];
        expect(total, greaterThanOrEqualTo(0));
        for (int op = 0; op < problem.operators.length; op++) {
          if (problem.operators[op] == '+') {
            total += problem.terms[op + 1];
          } else {
            total -= problem.terms[op + 1];
          }
          expect(
            total,
            greaterThanOrEqualTo(0),
            reason: 'Running total must NEVER be negative in Soroban',
          );
        }
        expect(total, equals(problem.expectedResult));
      }
    });

    test('Multiplication I generates 1-digit multipliers', () {
      final problem = generator.generateProblem(
        category: ProblemCategory.multiplication1,
        difficulty: Difficulty.easy,
      );
      expect(problem.terms.length, equals(2));
      expect(problem.terms[0], inInclusiveRange(100, 999)); // 3 digits
      expect(problem.terms[1], inInclusiveRange(2, 9)); // 1 digit
      expect(problem.expectedResult, equals(problem.terms[0] * problem.terms[1]));
    });

    test('Multiplication II generates 2-digit multipliers', () {
      final problem = generator.generateProblem(
        category: ProblemCategory.multiplication2,
        difficulty: Difficulty.easy,
      );
      expect(problem.terms.length, equals(2));
      expect(problem.terms[0], inInclusiveRange(1000, 9999)); // 4 digits
      expect(problem.terms[1], inInclusiveRange(10, 99)); // 2 digits
      expect(problem.expectedResult, equals(problem.terms[0] * problem.terms[1]));
    });

    test('every multiplication is playable on the board it was made for', () {
      // forProblem is the gate the controller puts every problem through: a
      // generated multiplication must pass it, at every difficulty.
      final seeded = ProblemGenerator(random: Random(2026));

      for (final category in [
        ProblemCategory.multiplication1,
        ProblemCategory.multiplication2,
      ]) {
        for (final difficulty in Difficulty.values) {
          for (var i = 0; i < 25; i++) {
            final problem = seeded.generateProblem(
              category: category,
              difficulty: difficulty,
            );
            final progress = MultiplicationProgress.forProblem(problem);

            expect(progress, isNotNull, reason: '$problem');
            expect(progress!.total, equals(problem.expectedResult),
                reason: '$problem');
          }
        }
      }
    });

    test('the rod count is honoured: nothing is made that the board cannot hold',
        () {
      // 3 digits × 1 digit never needs more than four rods (999 × 9 = 8991),
      // but on a four-rod board the cap is 9999, not 9,999,999.
      for (var i = 0; i < 50; i++) {
        final problem = generator.generateProblem(
          category: ProblemCategory.multiplication1,
          difficulty: Difficulty.easy,
          rodCount: 4,
        );

        expect(problem.expectedResult, lessThanOrEqualTo(9999));
        expect(MultiplicationProgress.forProblem(problem, rodCount: 4),
            isNotNull);
      }
    });

    test('a candidate that does not fit is rejected and drawn again', () {
      // 5 digits × 1 digit on five rods fits only for a small multiplicand:
      // most candidates overflow, so this only returns by rejecting them.
      final problem = generator.generateProblem(
        category: ProblemCategory.multiplication1,
        difficulty: Difficulty.hard,
        rodCount: 5,
      );

      expect(problem.expectedResult, lessThanOrEqualTo(99999));
      expect(problem.terms[0] * problem.terms[1],
          equals(problem.expectedResult));
      expect(MultiplicationProgress.forProblem(problem, rodCount: 5),
          isNotNull);
    });

    test('a request that no candidate can satisfy ends in an error, not a loop',
        () {
      // Every 5-digit number is above 9999, the cap of a four-rod board.
      expect(
        () => generator.generateProblem(
          category: ProblemCategory.multiplication1,
          difficulty: Difficulty.hard,
          rodCount: 4,
        ),
        throwsStateError,
      );
      expect(
        () => generator.generateProblem(
          category: ProblemCategory.multiplication2,
          difficulty: Difficulty.hard,
          rodCount: 4,
        ),
        throwsStateError,
      );
    });

    test('Challenge session generates exactly 5 consecutive problems', () {
      final session = generator.generateChallengeSession(
        category: ProblemCategory.addition,
        difficulty: Difficulty.medium,
        count: 5,
      );
      expect(session.length, equals(5));
    });
  });
}
