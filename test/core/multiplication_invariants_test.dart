import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/engine/hint_engine.dart';
import 'package:soroban_app/core/engine/multiplication_engine.dart';
import 'package:soroban_app/core/engine/multiplication_progress.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/models/soroban_state.dart';

import '../helpers/fixed_problem.dart';

/// The invariants of a multiplication, written down as tests.
///
/// 1. REPRESENTABLE. `multiplicand × multiplier <= 10^rodCount - 1`. A
///    multiplication that violates it does not exist as a progress model: it is
///    refused with an error, never returned in part.
/// 2. COMPLETE. The contributions add up to exactly the product, and a problem
///    carries one checkpoint per contribution, ending on the product. So
///    "every contribution is on the board" and "the board shows the product"
///    are one fact, and a problem cannot be solved anywhere else.
/// 3. IDENTITY. A contribution is its `index` (and its pair of digits), never
///    its `(value, rod)`: `12 × 12` has two different contributions that both
///    put 20 on rod 1. What the board cannot tell apart, the user's route does,
///    and the answer is a pure function of (board, route).

MultiplicationProgress progressOf(int a, int b, {int rodCount = 7}) =>
    MultiplicationProgress(multiplicand: a, multiplier: b, rodCount: rodCount);

bool fits(int a, int b, int rods) => MultiplicationContribution.fitsOnBoard(
      multiplicand: a,
      multiplier: b,
      rodCount: rods,
    );

/// 9, 99, 999, ...
int capacityOf(int rods) {
  var capacity = 1;
  for (var i = 0; i < rods; i++) {
    capacity *= 10;
  }
  return capacity - 1;
}

/// Every subset of [count] contributions, as sets of indices.
Iterable<Set<int>> allSubsets(int count) sync* {
  for (var mask = 0; mask < (1 << count); mask++) {
    yield {
      for (var k = 0; k < count; k++)
        if (((mask >> k) & 1) == 1) k,
    };
  }
}

void main() {
  group('Representable: the product fits on the board or it is refused', () {
    test('the boundary is exactly the capacity of the board', () {
      expect(fits(3333333, 3, 7), isTrue, reason: '9,999,999: every rod full');
      expect(fits(3333334, 3, 7), isFalse, reason: '10,000,002: one past');
      expect(fits(111, 9, 3), isTrue, reason: '999 on three rods');
      expect(fits(112, 9, 3), isFalse, reason: '1,008 on three rods');
      expect(fits(99999, 99, 7), isTrue, reason: '9,899,901: the hardest');
    });

    test('one rod fewer than the product needs is refused, not shortened', () {
      // 482 × 6 = 2892 needs four rods.
      expect(fits(482, 6, 4), isTrue);
      expect(progressOf(482, 6, rodCount: 4).total, equals(2892));

      expect(fits(482, 6, 3), isFalse);
      expect(
        () => progressOf(482, 6, rodCount: 3),
        throwsArgumentError,
      );
    });

    test('a product can overflow although no single contribution does', () {
      // 3 × 34 = 102 is 90 (rod 1) plus 12 (rods 0 and 1): each part sits on
      // two rods and the sum needs three. Checking contributions one by one,
      // which is what the decomposition used to do, lets this through and
      // returns all of it, silently describing a board that cannot exist.
      expect(fits(3, 33, 2), isTrue, reason: '99');
      expect(fits(3, 34, 2), isFalse, reason: '102');
      expect(
        () => progressOf(3, 34, rodCount: 2),
        throwsArgumentError,
      );
    });

    test('whatever the operands and the rod count: adds up to the product, '
        'or is refused', () {
      final failures = <String>[];

      for (var rods = 1; rods <= 6; rods++) {
        final capacity = capacityOf(rods);
        for (var a = 0; a <= 120; a++) {
          for (var b = 0; b <= 120; b++) {
            final shouldFit = a * b <= capacity;
            if (fits(a, b, rods) != shouldFit) {
              failures.add('fitsOnBoard($a, $b, $rods) is not $shouldFit');
            }

            List<MultiplicationContribution>? parts;
            try {
              parts = MultiplicationContribution.decompose(
                multiplicand: a,
                multiplier: b,
                rodCount: rods,
              );
            } on ArgumentError {
              parts = null;
            }

            if (parts == null) {
              if (shouldFit) failures.add('$a × $b on $rods rods: refused');
              continue;
            }
            if (!shouldFit) {
              failures.add('$a × $b on $rods rods: accepted, overflows');
              continue;
            }

            final sum = parts.fold<int>(0, (s, c) => s + c.value);
            if (sum != a * b) {
              failures.add('$a × $b on $rods rods: adds up to $sum');
            }
            for (var k = 0; k < parts.length; k++) {
              if (parts[k].index != k) {
                failures.add('$a × $b on $rods rods: index ${parts[k].index}');
              }
            }
          }
        }
      }

      expect(failures, isEmpty, reason: failures.take(5).join('\n'));
    });

    test('a rod count the arithmetic cannot stand behind is refused', () {
      for (final rods in [0, -1, 16]) {
        expect(() => fits(1, 1, rods), throwsArgumentError, reason: '$rods');
        expect(() => progressOf(1, 1, rodCount: rods), throwsArgumentError,
            reason: '$rods');
      }
      expect(progressOf(1, 1, rodCount: 15).total, equals(1));
    });

    test('negative operands are refused whatever the build mode', () {
      expect(
        () => MultiplicationContribution.decompose(
            multiplicand: -1, multiplier: 5),
        throwsArgumentError,
      );
      expect(
        () => MultiplicationContribution.decompose(
            multiplicand: 5, multiplier: -1),
        throwsArgumentError,
      );
      expect(fits(-1, 5, 7), isFalse);
    });

    test('the decomposition does not depend on the rod count, only its '
        'acceptance does', () {
      // 482 × 6 = 2400 + 480 + 12.
      List<int> values(int rods) => [
            for (final c in progressOf(482, 6, rodCount: rods).contributions)
              c.value,
          ];

      expect(values(7), equals([2400, 480, 12]));
      for (final rods in [4, 5, 12]) {
        expect(values(rods), equals([2400, 480, 12]), reason: '$rods rods');
      }
    });
  });

  group('Complete: a problem built outside the generator', () {
    final chain = const MultiplicationEngine()
        .generateCheckpoints(multiplicand: 1234, multiplier: 23);

    void expectRefused(Problem problem, {int rodCount = 7, String? reason}) {
      expect(
        () => MultiplicationProgress.forProblem(problem, rodCount: rodCount),
        throwsArgumentError,
        reason: reason,
      );
    }

    test('the canonical problem is accepted: one checkpoint per contribution, '
        'ending on the product', () {
      final problem = multiplicationProblem(1234, 23);
      final progress = MultiplicationProgress.forProblem(problem);

      expect(progress, isNotNull);
      expect(progress!.contributions, hasLength(problem.checkpoints.length));
      expect(progress.total, equals(problem.expectedResult));
      expect(problem.checkpoints.last.targetValue,
          equals(problem.expectedResult));
    });

    test('a chain that stops short of the product is refused', () {
      expectRefused(multiplicationProblem(1234, 23,
          checkpoints: chain.sublist(0, chain.length - 1)));
    });

    test('a chain with a checkpoint too many is refused', () {
      expectRefused(
          multiplicationProblem(1234, 23, checkpoints: [...chain, chain.last]));
    });

    test('a chain with no checkpoints at all is refused', () {
      expectRefused(multiplicationProblem(1234, 23,
          checkpoints: const <DigitCheckpoint>[]));
    });

    test('an expected result that is not the product is refused', () {
      expectRefused(multiplicationProblem(1234, 23, expectedResult: 28383));
    });

    test('a product that does not fit the board is refused', () {
      // 99999 × 999 = 99,899,001 needs eight rods. Its checkpoints are those of
      // 99999 × 99, so the only thing wrong with it is that it cannot be shown.
      expectRefused(multiplicationProblem(
        99999,
        999,
        checkpoints: const MultiplicationEngine()
            .generateCheckpoints(multiplicand: 99999, multiplier: 99),
      ));
    });

    test('the rod count of the board is the one that counts', () {
      final problem = multiplicationProblem(1234, 23); // 28,382

      expect(MultiplicationProgress.forProblem(problem, rodCount: 5),
          isNotNull);
      expectRefused(problem, rodCount: 4, reason: '28,382 > 9,999');
    });

    test('operands that are not two positive numbers are refused', () {
      for (final terms in [
        <int>[1234],
        <int>[1234, 23, 2],
        <int>[0, 5],
        <int>[3, 0],
        <int>[-3, 4],
      ]) {
        expectRefused(multiplicationProblem(1234, 23, terms: terms),
            reason: '$terms');
      }
    });

    test('a problem that is not a multiplication is not its business', () {
      for (final category in [ProblemCategory.addition, ProblemCategory.mixed]) {
        final problem = Problem(
          category: category,
          difficulty: Difficulty.easy,
          terms: const [5, 7],
          operators: const ['+'],
          expectedResult: 12,
          checkpoints: const <DigitCheckpoint>[],
        );
        expect(MultiplicationProgress.forProblem(problem), isNull);
      }
    });
  });

  group('Solved is the product: complete and correct are one fact', () {
    test('all contributions explain exactly the product, nothing less does',
        () {
      for (final (a, b) in [(12, 12), (123, 3), (1234, 23), (12345, 67)]) {
        final progress = progressOf(a, b);
        final count = progress.contributions.length;

        for (final subset in allSubsets(count)) {
          final value = progress.valueOf(subset);
          final explained = progress.explain(value);

          expect(explained, isNotNull, reason: '$a × $b at $value');
          expect(explained!.length == count, value == a * b,
              reason: '$a × $b at $value');
        }
      }
    });

    test('a board past the product is not explained by anything', () {
      final progress = progressOf(1234, 23); // 28,382

      for (final over in [28383, 28394, 30000, 9999999]) {
        expect(progress.explain(over), isNull, reason: '$over');
      }
    });
  });

  group('Identity: a contribution is its index, not its value and rod', () {
    test('in every product each contribution is its own pair of digits', () {
      for (final (a, b) in [
        (12, 12),
        (11, 11),
        (2112, 12),
        (1234, 23),
        (12345, 67),
        (99999, 99),
      ]) {
        final contributions = progressOf(a, b).contributions;
        final pairs = {
          for (final c in contributions) (c.multiplicandIndex, c.multiplierIndex),
        };

        expect(pairs, hasLength(contributions.length), reason: '$a × $b');
        expect(
          contributions.map((c) => c.index).toList(),
          equals([for (var k = 0; k < contributions.length; k++) k]),
          reason: '$a × $b',
        );
      }
    });
  });

  group('12 × 12: two contributions with the same value on the same rod', () {
    final progress = progressOf(12, 12);

    /// The digits of the equation that would be dimmed, as (term, digit).
    List<(int, int)> dimmed(List<int> credited) {
      final digits = <(int, int)>[];
      for (var term = 0; term < 2; term++) {
        for (var digit = 0; digit < 2; digit++) {
          if (progress.isDigitComplete(credited,
              termIndex: term, digitIndex: digit)) {
            digits.add((term, digit));
          }
        }
      }
      return digits;
    }

    test('they are two contributions, told apart by index and digit positions',
        () {
      final contributions = progress.contributions;
      expect(contributions.map((c) => c.value), [100, 20, 20, 4]);
      expect(progress.total, equals(144));

      final twins = contributions.where((c) => c.value == 20).toList();
      expect(twins, hasLength(2));
      expect(twins[0].rodIndex, equals(twins[1].rodIndex));
      expect(twins[0].value, equals(twins[1].value));
      expect(twins[0].index, isNot(equals(twins[1].index)));
      // 2 × 1 and 1 × 2, as (multiplicand digit, multiplier digit) positions.
      expect([twins[0].multiplicandIndex, twins[0].multiplierIndex], [1, 0]);
      expect([twins[1].multiplicandIndex, twins[1].multiplierIndex], [0, 1]);
    });

    test('one 20 on the board is one contribution, two of them are two', () {
      expect(progress.explain(20), hasLength(1));
      expect(progress.explain(40), unorderedEquals([1, 2]));
      expect(progress.explain(40, preferred: [1]), unorderedEquals([1, 2]));
      expect(progress.explain(40, preferred: [2]), unorderedEquals([1, 2]));
    });

    test('the twin the user already holds is never swapped for the other', () {
      expect(progress.explain(20, preferred: [1]), unorderedEquals([1]));
      expect(progress.explain(20, preferred: [2]), unorderedEquals([2]));

      // Building on a twin keeps it, whatever else is added.
      expect(progress.explain(24, preferred: [1]), unorderedEquals([1, 3]));
      expect(progress.explain(24, preferred: [2]), unorderedEquals([2, 3]));
      expect(progress.explain(120, preferred: [1]), unorderedEquals([0, 1]));
      expect(progress.explain(120, preferred: [2]), unorderedEquals([0, 2]));
    });

    test('the same board is read by the route that led to it', () {
      // 24 is a 20 and a 4. Which 20 is not on the board: it is in the route.
      final fromTheUnits = progress.explain(24, preferred: [3])!;
      final fromTheTens = progress.explain(24, preferred: [1])!;

      expect(progress.valueOf(fromTheUnits), equals(24));
      expect(progress.valueOf(fromTheTens), equals(24));
      expect(fromTheUnits.length, equals(fromTheTens.length));

      // Row by row (12 × 2 = 24): the multiplier's 2 is done.
      expect(dimmed(progress.ordered([3], fromTheUnits)), [(1, 1)]);
      // Column by column (2 × 12 = 24): the multiplicand's 2 is done.
      expect(dimmed(progress.ordered([1], fromTheTens)), [(0, 1)]);
    });

    test('which digits are done follows exactly the contributions credited',
        () {
      expect(dimmed([1]), isEmpty);
      expect(dimmed([2]), isEmpty);
      expect(dimmed([1, 2]), isEmpty);
      expect(dimmed([2, 3]), [(1, 1)]);
      expect(dimmed([0, 1]), [(1, 0)]);
      expect(dimmed([0, 2]), [(0, 0)]);
      expect(dimmed([1, 3]), [(0, 1)]);
      expect(dimmed([0, 1, 2]), [(0, 0), (1, 0)]);
      expect(dimmed([1, 0, 3]), [(0, 1), (1, 0)]);
    });

    test('every digit is done only when all four contributions are', () {
      for (final subset in allSubsets(4)) {
        expect(dimmed(subset.toList()).length == 4, subset.length == 4,
            reason: '$subset');
      }
    });

    test('the reading is a function of its inputs, not of the instance', () {
      final first = progressOf(12, 12);
      final second = progressOf(12, 12);

      for (final subset in allSubsets(4)) {
        final value = first.valueOf(subset);
        for (final preferred in [
          const <int>[],
          const [1],
          const [2],
          const [3, 1],
          const [2, 0],
        ]) {
          expect(
            second.explain(value, preferred: preferred),
            equals(first.explain(value, preferred: preferred)),
            reason: '$value after $preferred',
          );
        }
      }
    });
  });

  group('A board several readings fit', () {
    test('12345 × 67 at 2400 is one contribution or two, depending on the '
        'route', () {
      final progress = progressOf(12345, 67);
      // 4 × 6 at rod 2 is 2400; 5 × 6 (300) with 3 × 7 (2100) is 2400 too.
      expect(progress.contributions[3].value, equals(2400));
      expect(progress.contributions[4].value + progress.contributions[7].value,
          equals(2400));

      expect(progress.explain(2400), unorderedEquals([3]));
      expect(progress.explain(2400, preferred: [3]), unorderedEquals([3]));
      expect(progress.explain(2400, preferred: [4]), unorderedEquals([4, 7]));
      expect(progress.explain(2400, preferred: [7]), unorderedEquals([4, 7]));
      expect(progress.explain(2400, preferred: [7, 4]), unorderedEquals([4, 7]));
    });

    test('from any board, Hint reaches the product, adds each contribution '
        'once, and the board and the credit never part ways', () {
      const hintEngine = HintEngine();

      // Includes the products with equal-valued contributions (12 × 12,
      // 11 × 11) and the one where different counts reach the same board
      // (12345 × 67).
      for (final (a, b) in [
        (12, 12),
        (11, 11),
        (123, 3),
        (1234, 23),
        (12345, 67),
      ]) {
        final progress = progressOf(a, b);
        final count = progress.contributions.length;

        for (final subset in allSubsets(count)) {
          var order = subset.toList()..sort();
          var board = SorobanState.fromValue(progress.valueOf(order));
          var steps = 0;

          while (true) {
            final hint = hintEngine.getNextMultiplicationHint(
              currentState: board,
              progress: progress,
              creditedOrder: order,
            );
            if (hint == null) break;

            expect(hint.recoveredFromDivergence, isFalse,
                reason: '$a × $b from $subset');
            expect(hint.baseOrder, isNot(contains(hint.contribution.index)),
                reason: '$a × $b from $subset');

            board = hintEngine.additionEngine
                .applyMoves(hint.fromState, hint.moves);
            order = [...hint.baseOrder, hint.contribution.index];
            steps++;

            expect(board.value, equals(progress.valueOf(order)),
                reason: '$a × $b from $subset, step $steps');
            expect(steps, lessThanOrEqualTo(count),
                reason: '$a × $b from $subset does not converge');
          }

          expect(board.value, equals(a * b), reason: '$a × $b from $subset');
          expect(order.toSet(), hasLength(count), reason: '$a × $b');
        }
      }
    });
  });
}
