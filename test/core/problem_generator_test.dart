import 'package:flutter_test/flutter_test.dart';
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
