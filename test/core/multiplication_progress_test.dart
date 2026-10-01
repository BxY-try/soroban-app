import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/engine/multiplication_engine.dart';
import 'package:soroban_app/core/engine/multiplication_progress.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/models/soroban_state.dart';

MultiplicationProgress progressOf(int a, int b) =>
    MultiplicationProgress(multiplicand: a, multiplier: b);

/// Every subset of [count] contributions, as sets of indices.
Iterable<Set<int>> allSubsets(int count) sync* {
  for (var mask = 0; mask < (1 << count); mask++) {
    yield {
      for (var k = 0; k < count; k++)
        if (((mask >> k) & 1) == 1) k,
    };
  }
}

Problem productProblem(
  int a,
  int b, {
  ProblemCategory category = ProblemCategory.multiplication2,
  List<DigitCheckpoint>? checkpoints,
}) {
  return Problem(
    category: category,
    difficulty: Difficulty.easy,
    terms: [a, b],
    operators: const ['x'],
    expectedResult: a * b,
    checkpoints: checkpoints ??
        const MultiplicationEngine()
            .generateCheckpoints(multiplicand: a, multiplier: b),
  );
}

void main() {
  const products = [
    (123, 3),
    (482, 6),
    (1234, 23),
    (12345, 67),
    (99999, 99),
    (54321, 9),
    (98765, 96),
  ];

  group('MultiplicationContribution.decompose', () {
    test('1234 × 23 is eight contributions, in the canonical order', () {
      final progress = progressOf(1234, 23);

      expect(
        progress.contributions.map((c) => c.value),
        [20000, 4000, 600, 80, 3000, 600, 90, 12],
      );
      expect(progress.contributions.map((c) => c.rodIndex),
          [4, 3, 2, 1, 3, 2, 1, 0]);
    });

    test('the contributions of any product add up to the product', () {
      for (final (a, b) in [...products, (1003, 20), (10, 10)]) {
        expect(progressOf(a, b).total, equals(a * b), reason: '$a × $b');
      }
    });

    test('a zero digit adds nothing', () {
      final progress = progressOf(1003, 20);

      expect(progress.contributions.map((c) => c.value), [20000, 60]);
    });

    test('a contribution that does not fit on the board is dropped', () {
      final progress = MultiplicationProgress(
        multiplicand: 99,
        multiplier: 99,
        rodCount: 3,
      );

      expect(progress.contributions, hasLength(3));
    });
  });

  group('MultiplicationProgress.forProblem', () {
    test('a multiplication built by the engine is understood', () {
      final problem = productProblem(1234, 23);
      final progress = MultiplicationProgress.forProblem(problem);

      expect(progress, isNotNull);
      expect(progress!.contributions.length, problem.checkpoints.length);
    });

    test('anything that is not a multiplication is left to the linear chain',
        () {
      final problem =
          productProblem(1234, 23, category: ProblemCategory.addition);

      expect(MultiplicationProgress.forProblem(problem), isNull);
    });

    test('checkpoints that are not the operands\' own chain are not trusted',
        () {
      final foreign = const MultiplicationEngine()
          .generateCheckpoints(multiplicand: 1234, multiplier: 24);
      final problem = productProblem(1234, 23, checkpoints: foreign);

      expect(MultiplicationProgress.forProblem(problem), isNull);
    });
  });

  group('explain', () {
    test('every accumulation of contributions is recognised', () {
      for (final (a, b) in products) {
        final progress = progressOf(a, b);
        for (final subset in allSubsets(progress.contributions.length)) {
          final value = progress.valueOf(subset);
          final explained = progress.explain(value);
          if (explained == null) fail('$a × $b: $value was not recognised');
          expect(progress.valueOf(explained), equals(value),
              reason: '$a × $b: $value');
        }
      }
    });

    test('building on the credit always extends it', () {
      final progress = progressOf(1234, 23);
      final subsets = allSubsets(progress.contributions.length).toList();

      for (final credited in subsets) {
        for (final target in subsets) {
          if (target.length <= credited.length ||
              !target.containsAll(credited)) {
            continue;
          }
          final value = progress.valueOf(target);
          final explained = progress.explain(value, preferred: credited);
          if (explained == null) fail('$credited -> $target: not recognised');
          expect(progress.valueOf(explained), equals(value));
          expect(explained.containsAll(credited), isTrue,
              reason: '$credited -> $target gave $explained');
        }
      }
    });

    test('a board that is no accumulation is not explained', () {
      final progress = progressOf(1234, 23);

      for (final value in [-1, 1, 5, 3703, 20001, 24681, 28383, 99999999]) {
        expect(progress.explain(value), isNull, reason: '$value');
      }
    });

    test('an empty board is explained by nothing', () {
      final progress = progressOf(1234, 23);

      expect(progress.explain(0), isEmpty);
      expect(progress.explain(0, preferred: [0]), isEmpty);
    });

    test('a board built another way is explained by its own contributions',
        () {
      final progress = progressOf(1234, 23);

      expect(progress.explain(3702, preferred: [0]),
          unorderedEquals([4, 5, 6, 7]));
    });

    test('equal-valued contributions are told apart by the user\'s route',
        () {
      final progress = progressOf(1234, 23);

      // 3 × 2 and 2 × 3 both put 600 on rod 2: the board cannot say which.
      expect(progress.explain(600), hasLength(1));
      expect(progress.explain(600, preferred: [5]), unorderedEquals([5]));

      // Right to left through the × 3 row: the 600 is 2 × 3.
      expect(progress.explain(702, preferred: [7, 6]),
          unorderedEquals([7, 6, 5]));
      // Column by column: the 600 is 3 × 2.
      expect(progress.explain(782, preferred: [7, 3, 6]),
          unorderedEquals([7, 3, 6, 2]));
    });
  });

  group('ordered', () {
    test('keeps the credit order and appends what is new', () {
      final progress = progressOf(1234, 23);

      expect(progress.ordered([7, 3], {7, 3, 2}), [7, 3, 2]);
      expect(progress.ordered([7, 3, 2], {7}), [7]);
      expect(progress.ordered(const [], {5, 4}), [4, 5]);
    });
  });

  group('nextContribution', () {
    test('follows the pattern the user is on', () {
      final progress = progressOf(1234, 23);
      final cases = <(List<int>, int)>[
        (const [], 0), // nothing to read: the canonical start
        (const [0, 1], 2), // canonical prefix: canonical continuation
        (const [0, 1, 2, 3], 4), // × 20 row done: the × 3 row
        (const [7, 6, 5], 4), // right to left: keep going left
        (const [7, 6, 5, 4], 3), // row done: next row, entered from the right
        (const [4, 5, 6, 7], 0), // reached in one jump: canonical
        (const [7, 3], 6), // column by column: the next column's first
        (const [7, 3, 6], 2), // ... and its second
      ];

      for (final (order, expected) in cases) {
        expect(progress.nextContribution(order)?.index, equals(expected),
            reason: 'after $order');
      }
    });

    test('is null once everything is on the board', () {
      final progress = progressOf(123, 3);

      expect(progress.nextContribution([0, 1, 2]), isNull);
    });

    test('from any board, in any order, it adds exactly one new contribution',
        () {
      const engine = MultiplicationEngine();

      for (final (a, b) in [(123, 3), (1234, 23), (99999, 99)]) {
        final progress = progressOf(a, b);
        final count = progress.contributions.length;

        for (final subset in allSubsets(count)) {
          final ascending = subset.toList()..sort();
          for (final order in [ascending, ascending.reversed.toList()]) {
            final next = progress.nextContribution(order);
            if (order.length == count) {
              expect(next, isNull);
              continue;
            }
            if (next == null) fail('$a × $b after $order: no next');
            expect(order, isNot(contains(next.index)));

            final board = SorobanState.fromValue(progress.valueOf(order));
            final moves = engine.contributionMoves(board, next);
            expect(moves, isNotEmpty);
            final after = engine.additionEngine.applyMoves(board, moves);
            expect(after.value, equals(board.value + next.value),
                reason: '$a × $b after $order, adding ${next.index}');
          }
        }
      }
    });
  });

  group('isDigitComplete', () {
    test('follows the contributions on the board, not their position', () {
      final progress = progressOf(1234, 23);
      bool done(List<int> credited, int term, int digit) =>
          progress.isDigitComplete(credited,
              termIndex: term, digitIndex: digit);

      // The × 20 row.
      expect(done([0, 1, 2, 3], 1, 0), isTrue);
      expect(done([0, 1, 2, 3], 1, 1), isFalse);
      expect(done([0, 1, 2, 3], 0, 0), isFalse); // the 1 still owes 1 × 3
      expect(done([0, 4], 0, 0), isTrue);

      // The × 3 row, reached first.
      expect(done([4, 5, 6, 7], 1, 1), isTrue);
      expect(done([4, 5, 6, 7], 1, 0), isFalse);
    });

    test('a digit that contributes nothing counts as complete', () {
      final progress = progressOf(1003, 20);

      expect(
          progress.isDigitComplete(const [], termIndex: 0, digitIndex: 1),
          isTrue);
    });
  });
}
