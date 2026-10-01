import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/engine/multiplication_engine.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/state/soroban_controller.dart';

import '../helpers/fixed_problem.dart';

/// The snapshot chain keeps one entry more than the checkpoints credited.
void expectChainIntact(SorobanController controller) {
  expect(
    controller.checkpointSnapshotCount,
    equals(controller.activeCheckpointIndex + 1),
    reason: 'snapshot chain out of sync with the credited progress',
  );
}

void main() {
  group('123 × 3', () {
    test('the canonical chain is 300 → 360 → 369', () {
      final controller = controllerForProduct(123, 3);

      expect(
        controller.currentProblem!.checkpoints.map((c) => c.targetValue),
        [300, 360, 369],
      );
    });

    test('canonical order: 0 → 300 → 360 → 369 advances one at a time', () {
      final controller = controllerForProduct(123, 3);
      final checkpoints = controller.currentProblem!.checkpoints;

      for (var i = 0; i < checkpoints.length; i++) {
        performCheckpointGesture(controller, checkpoints[i]);
        expect(controller.activeCheckpointIndex, equals(i + 1));
        expectChainIntact(controller);
      }
      expect(controller.state.value, equals(369));
    });

    test('textbook order in one jump: 0 → 69 → 369', () {
      final controller = controllerForProduct(123, 3);

      setBoardValue(controller, 69);
      expect(controller.state.value, equals(69));
      expect(controller.activeCheckpointIndex, equals(2));
      expect(controller.creditedContributions, unorderedEquals([1, 2]));
      expectChainIntact(controller);

      setBoardValue(controller, 369);
      expect(controller.activeCheckpointIndex, equals(3));
      expectChainIntact(controller);
    });

    test('textbook order one digit at a time: 0 → 9 → 69 → 369', () {
      final controller = controllerForProduct(123, 3);
      final steps = <(int, List<int>)>[
        (9, [2]),
        (69, [2, 1]),
        (369, [2, 1, 0]),
      ];

      for (final (board, credited) in steps) {
        setBoardValue(controller, board);
        expect(controller.state.value, equals(board));
        expect(controller.creditedContributions, equals(credited));
        expect(controller.activeCheckpointIndex, equals(credited.length));
        expectChainIntact(controller);
      }
    });

    test('Hint at 69 finishes with 1 × 3, it does not go back to 300',
        () async {
      final controller = controllerForProduct(123, 3);
      setBoardValue(controller, 69);

      await controller.executeHint();

      expect(controller.state.value, equals(369));
      expect(controller.activeCheckpointIndex, equals(3));
    });
  });

  group('1234 × 23', () {
    test('the canonical chain runs the × 20 row first', () {
      final controller = controllerForProduct(1234, 23);

      expect(
        controller.currentProblem!.checkpoints.map((c) => c.targetValue),
        [20000, 24000, 24600, 24680, 27680, 28280, 28370, 28382],
      );
    });

    test('canonical order still advances one checkpoint per gesture', () {
      final controller = controllerForProduct(1234, 23);
      final checkpoints = controller.currentProblem!.checkpoints;

      for (var i = 0; i < checkpoints.length; i++) {
        performCheckpointGesture(controller, checkpoints[i]);
        expect(controller.activeCheckpointIndex, equals(i + 1));
        expectChainIntact(controller);
      }
    });

    test('route A: 0 → 24680 → 28382', () {
      final controller = controllerForProduct(1234, 23);

      setBoardValue(controller, 24680);
      expect(controller.activeCheckpointIndex, equals(4));
      expect(controller.creditedContributions, unorderedEquals([0, 1, 2, 3]));

      setBoardValue(controller, 28382);
      expect(controller.activeCheckpointIndex, equals(8));
      expectChainIntact(controller);
    });

    test('route B, the textbook one: 0 → 3702 → 28382', () {
      final controller = controllerForProduct(1234, 23);

      setBoardValue(controller, 3702);
      expect(controller.state.value, equals(3702));
      expect(controller.activeCheckpointIndex, equals(4));
      expect(controller.creditedContributions, unorderedEquals([4, 5, 6, 7]));
      expectChainIntact(controller);

      setBoardValue(controller, 28382);
      expect(controller.activeCheckpointIndex, equals(8));
      expectChainIntact(controller);
    });

    test('a mixed order that alternates between the two multiplier digits',
        () {
      final controller = controllerForProduct(1234, 23);
      // 4×3, 1×2, 3×2, 4×2, 3×3, 1×3, 2×2, 2×3
      const boards = [12, 20012, 20612, 20692, 20782, 23782, 27782, 28382];

      for (var i = 0; i < boards.length; i++) {
        setBoardValue(controller, boards[i]);
        expect(controller.state.value, equals(boards[i]));
        expect(controller.activeCheckpointIndex, equals(i + 1),
            reason: 'after landing on ${boards[i]}');
        expectChainIntact(controller);
      }
    });

    test('column by column, from the units: 4×3, 4×2, 3×3, 3×2, ...', () {
      final controller = controllerForProduct(1234, 23);
      const boards = [12, 92, 182, 782, 1382, 5382, 8382, 28382];

      for (var i = 0; i < boards.length; i++) {
        setBoardValue(controller, boards[i]);
        expect(controller.activeCheckpointIndex, equals(i + 1),
            reason: 'after landing on ${boards[i]}');
      }
      expect(controller.creditedContributions, equals([7, 3, 6, 2, 5, 1, 4, 0]));
    });

    test('two contributions of the same value are both credited', () {
      final controller = controllerForProduct(1234, 23);

      setBoardValue(controller, 600); // 3 × 2 or 2 × 3
      expect(controller.activeCheckpointIndex, equals(1));

      setBoardValue(controller, 1200); // both of them
      expect(controller.activeCheckpointIndex, equals(2));
      expect(controller.creditedContributions, unorderedEquals([2, 5]));
    });

    test('taking the work apart and building another valid state re-anchors',
        () {
      final controller = controllerForProduct(1234, 23);
      setBoardValue(controller, 20000);
      expect(controller.creditedContributions, equals([0]));

      setBoardValue(controller, 3702);

      expect(controller.state.value, equals(3702));
      expect(controller.creditedContributions, unorderedEquals([4, 5, 6, 7]));
      expect(controller.activeCheckpointIndex, equals(4));
      expectChainIntact(controller);
    });
  });

  group('Edge cases', () {
    test('a partial product carrying into the next rod is credited too', () {
      // 4 × 3 = 12 writes a 2 on rod 0 and a 1 on rod 1, so a board holding
      // it is not expressible as one digit on one rod.
      final controller = controllerForProduct(24, 3);

      setBoardValue(controller, 12);

      expect(controller.creditedContributions, [1], reason: '4 × 3 at rod 0');
      expect(controller.state.value, equals(12));
      expect(controller.activeCheckpointIndex, equals(1));
    });

    test('a digit with nothing to contribute counts as complete', () {
      // 101 × 3: the 0 in the middle never contributes a checkpoint.
      final controller = controllerForProduct(101, 3);
      setBoardValue(controller, 303);

      expect(
        controller.isMultiplicationDigitCompleted(termIndex: 0, digitIndex: 1),
        isTrue,
        reason: 'the 0 is finished the moment it is never needed',
      );
      expect(
        controller.isMultiplicationDigitCompleted(termIndex: 0, digitIndex: 0),
        isTrue,
      );
    });
  });

  group('Hint adapts to the route the user is on', () {
    test('at 3702 it keeps the board and never rolls back to 20000',
        () async {
      final controller = controllerForProduct(1234, 23);
      setBoardValue(controller, 3702);
      final seen = <int>[];
      void watch() => seen.add(controller.state.value);
      controller.addListener(watch);

      await controller.executeHint();
      controller.removeListener(watch);

      // Whatever the hint adds, it adds on top of the user's 3702.
      expect(controller.state.value - 3702, isIn([20000, 4000, 600, 80]));
      expect(controller.state.value, isNot(equals(20000)));
      expect(controller.activeCheckpointIndex, equals(5));
      expect(seen.every((value) => value >= 3702), isTrue,
          reason: 'the board dropped below the user\'s work: $seen');
      expectChainIntact(controller);
    });

    test('continues a right-to-left route into the next row', () async {
      final controller = controllerForProduct(1234, 23);
      for (final board in [12, 102, 702, 3702]) {
        setBoardValue(controller, board);
      }
      expect(controller.creditedContributions, equals([7, 6, 5, 4]));

      await controller.executeHint();

      // 4 × 2 at the units column: the next row, entered from the right like
      // the row before it.
      expect(controller.state.value, equals(3782));
      expect(controller.activeCheckpointIndex, equals(5));
    });

    test('follows the direction the user walked the row in', () async {
      // 1234 × 20 is a single row. Doing it right to left from the units,
      // the next contribution is 3 × 2 at rod 2, not 1 × 2.
      final controller = controllerForProduct(1234, 20);
      setBoardValue(controller, 80); // 4 × 2

      await controller.executeHint();

      expect(controller.state.value, equals(680),
          reason: '80 + 600 (3 × 2 at rod 2), continuing right to left');
      expect(controller.creditedContributions, equals([3, 2]));
    });

    test('on an invalid board it goes back to the user\'s own last valid board',
        () async {
      final controller = controllerForProduct(1234, 23);
      setBoardValue(controller, 3702);
      setBoardValue(controller, 3703); // a stray bead
      expect(controller.activeCheckpointIndex, equals(4));

      await controller.executeHint();

      // Back to 3702, then one contribution: never to the start of the chain.
      expect(controller.state.value - 3702, isIn([20000, 4000, 600, 80]));
      expect(controller.activeCheckpointIndex, equals(5));
      expectChainIntact(controller);
    });
  });

  group('A board that is no accumulation of contributions', () {
    test('is not progress and is left exactly as it is', () {
      final controller = controllerForProduct(1234, 23);

      for (final board in [5, 3703, 24681, 99999]) {
        setBoardValue(controller, board);
        expect(controller.state.value, equals(board));
        expect(controller.activeCheckpointIndex, equals(0),
            reason: '$board is not progress');
        expect(controller.creditedContributions, isEmpty);
        expectChainIntact(controller);
      }
    });

    test('does not undo the progress already made, and Reset still restores it',
        () {
      final controller = controllerForProduct(1234, 23);
      setBoardValue(controller, 3702);

      setBoardValue(controller, 3703);
      expect(controller.state.value, equals(3703));
      expect(controller.activeCheckpointIndex, equals(4));
      expect(controller.creditedContributions, unorderedEquals([4, 5, 6, 7]));

      controller.executeReset();
      expect(controller.state.value, equals(3702));
      expect(controller.activeCheckpointIndex, equals(4));
    });
  });

  group('Reset and Replay', () {
    test('Reset gives up one contribution at a time after a single jump', () {
      final controller = controllerForProduct(1234, 23);
      setBoardValue(controller, 3702);

      for (final expected in [3690, 3600, 3000, 0]) {
        controller.executeReset();
        expect(controller.state.value, equals(expected));
        expectChainIntact(controller);
      }
      expect(controller.activeCheckpointIndex, equals(0));
      expect(controller.creditedContributions, isEmpty);
    });

    test('work after a Reset is credited again', () {
      final controller = controllerForProduct(1234, 23);
      setBoardValue(controller, 3702);
      controller.executeReset();

      setBoardValue(controller, 3702);

      expect(controller.activeCheckpointIndex, equals(4));
      expectChainIntact(controller);
    });

    test('Replay plays the last hint again from where it started', () async {
      final controller = controllerForProduct(1234, 23);
      setBoardValue(controller, 3702);
      await controller.executeHint();
      final afterHint = controller.state.value;
      final credited = controller.creditedContributions;
      expect(controller.canReplay, isTrue);

      await controller.executeReplay();

      expect(controller.state.value, equals(afterHint));
      expect(controller.creditedContributions, equals(credited));
      expectChainIntact(controller);
    });
  });

  group('Which digits of the equation are done', () {
    test('follows the board, whatever the route', () {
      final routeA = controllerForProduct(1234, 23);
      setBoardValue(routeA, 24680); // the × 20 row
      expect(routeA.isMultiplicationDigitCompleted(termIndex: 1, digitIndex: 0),
          isTrue);
      expect(routeA.isMultiplicationDigitCompleted(termIndex: 1, digitIndex: 1),
          isFalse);

      final routeB = controllerForProduct(1234, 23);
      setBoardValue(routeB, 3702); // the × 3 row
      expect(routeB.isMultiplicationDigitCompleted(termIndex: 1, digitIndex: 1),
          isTrue);
      expect(routeB.isMultiplicationDigitCompleted(termIndex: 1, digitIndex: 0),
          isFalse);
      for (var digit = 0; digit < 4; digit++) {
        expect(
          routeB.isMultiplicationDigitCompleted(
              termIndex: 0, digitIndex: digit),
          isFalse,
          reason: 'multiplicand digit $digit still owes its × 2 product',
        );
      }
    });
  });

  group('At the sizes of the real difficulties', () {
    test('99999 × 99, carry-heavy: the × 9 row first, then the product', () {
      final controller = controllerForProduct(99999, 99);

      setBoardValue(controller, 899991);
      expect(controller.activeCheckpointIndex, equals(5));
      expect(controller.isMultiplicationDigitCompleted(termIndex: 1, digitIndex: 1),
          isTrue);

      setBoardValue(controller, 99999 * 99);
      expect(controller.activeCheckpointIndex, equals(10));
      expectChainIntact(controller);
    });

    test('12345 × 67: the × 7 row first, then the product', () {
      final controller = controllerForProduct(12345, 67);

      setBoardValue(controller, 12345 * 7);
      expect(controller.activeCheckpointIndex, equals(5));

      setBoardValue(controller, 12345 * 67);
      expect(controller.activeCheckpointIndex, equals(10));
    });
  });

  group('12 × 12: two contributions that look the same on the board', () {
    test('the canonical chain is 100 → 120 → 140 → 144', () {
      final controller = controllerForProduct(12, 12);

      expect(
        controller.currentProblem!.checkpoints.map((c) => c.targetValue),
        [100, 120, 140, 144],
      );
    });

    test('canonical order credits one contribution per gesture, and is solved '
        'only after the last', () {
      final controller = controllerForProduct(12, 12);
      final checkpoints = controller.currentProblem!.checkpoints;

      for (var i = 0; i < checkpoints.length; i++) {
        performCheckpointGesture(controller, checkpoints[i]);

        expect(controller.activeCheckpointIndex, equals(i + 1));
        expect(controller.creditedContributions,
            equals([for (var k = 0; k <= i; k++) k]));
        expect(controller.isMultiplicationSolved,
            equals(i == checkpoints.length - 1),
            reason: 'after checkpoint $i');
        expectChainIntact(controller);
      }
    });

    test('one 20, then the other 20: two contributions, one at a time', () {
      final controller = controllerForProduct(12, 12);

      setBoardValue(controller, 20);
      expect(controller.creditedContributions, equals([1]));
      expect(controller.activeCheckpointIndex, equals(1));
      expectChainIntact(controller);

      setBoardValue(controller, 40);
      expect(controller.creditedContributions, equals([1, 2]));
      expect(controller.activeCheckpointIndex, equals(2));
      expect(controller.isMultiplicationSolved, isFalse);
      expectChainIntact(controller);
    });

    test('both 20s in one jump are credited as two, because nothing else adds '
        'up to 40', () {
      final controller = controllerForProduct(12, 12);

      setBoardValue(controller, 40);

      expect(controller.creditedContributions, unorderedEquals([1, 2]));
      expect(controller.activeCheckpointIndex, equals(2));
      expectChainIntact(controller);
    });

    test('the same board, 24, is read by the route that led to it', () {
      final fromTheUnits = controllerForProduct(12, 12);
      setBoardValue(fromTheUnits, 4);
      setBoardValue(fromTheUnits, 24);

      final fromTheTens = controllerForProduct(12, 12);
      setBoardValue(fromTheTens, 20);
      setBoardValue(fromTheTens, 24);

      // Same board, same count, same work left. Only which 20 is credited
      // differs, and so which digit of the equation is dimmed.
      for (final controller in [fromTheUnits, fromTheTens]) {
        expect(controller.state.value, equals(24));
        expect(controller.activeCheckpointIndex, equals(2));
        expect(controller.isMultiplicationSolved, isFalse);
        expectChainIntact(controller);
      }

      // 4 then 20: row by row, 12 × 2 = 24. The multiplier's 2 is done.
      expect(fromTheUnits.creditedContributions, equals([3, 2]));
      expect(
        fromTheUnits.isMultiplicationDigitCompleted(
            termIndex: 1, digitIndex: 1),
        isTrue,
      );
      expect(
        fromTheUnits.isMultiplicationDigitCompleted(
            termIndex: 0, digitIndex: 1),
        isFalse,
      );

      // 20 then 4: column by column, 2 × 12 = 24. The multiplicand's 2 is done.
      expect(fromTheTens.creditedContributions, equals([1, 3]));
      expect(
        fromTheTens.isMultiplicationDigitCompleted(
            termIndex: 0, digitIndex: 1),
        isTrue,
      );
      expect(
        fromTheTens.isMultiplicationDigitCompleted(
            termIndex: 1, digitIndex: 1),
        isFalse,
      );
    });

    test('Hint on a lone 20 continues the row, and never credits a twin twice',
        () async {
      final controller = controllerForProduct(12, 12);
      setBoardValue(controller, 20);
      expect(controller.creditedContributions, equals([1]));

      await controller.executeHint();

      // 1 × 1 at rod 2, the rest of the row the 20 belongs to.
      expect(controller.state.value, equals(120));
      expect(controller.creditedContributions, equals([1, 0]));
      expect(controller.activeCheckpointIndex, equals(2));
      expect(controller.isMultiplicationSolved, isFalse);
      expectChainIntact(controller);
    });
  });

  group('Solved means the board shows the product', () {
    // Every value a 12 × 12 board can legitimately hold: sums of 100, 20, 20, 4.
    const accumulations = [0, 4, 20, 24, 40, 44, 100, 104, 120, 124, 140, 144];

    test('only the product is solved, whatever else the board holds', () {
      for (final board in [...accumulations, 1, 21, 143, 145, 9999999]) {
        final controller = controllerForProduct(12, 12);

        setBoardValue(controller, board);

        expect(controller.state.value, equals(board));
        expect(controller.isMultiplicationSolved, equals(board == 144),
            reason: 'board $board');
      }
    });

    test('leaving the product un-solves it, and coming back solves it again',
        () {
      final controller = controllerForProduct(12, 12);
      setBoardValue(controller, 144);
      expect(controller.isMultiplicationSolved, isTrue);

      setBoardValue(controller, 140);
      expect(controller.isMultiplicationSolved, isFalse,
          reason: 'the credit still counts four, the board no longer says 144');

      setBoardValue(controller, 144);
      expect(controller.isMultiplicationSolved, isTrue);
    });

    test('a problem that is not a multiplication is never "multiplication '
        'solved"', () {
      final controller = controllerForSum([4, 10]);

      setBoardValue(controller, 14);

      expect(controller.isMultiplicationSolved, isFalse);
    });
  });

  group('A problem the board cannot play is refused before anything changes',
      () {
    final chain = const MultiplicationEngine()
        .generateCheckpoints(multiplicand: 1234, multiplier: 23);
    final good = multiplicationProblem(1234, 23);

    final refused = <String, Problem>{
      'a chain that stops short of the product': multiplicationProblem(
        1234,
        23,
        checkpoints: chain.sublist(0, chain.length - 1),
      ),
      'an expected result that is not the product':
          multiplicationProblem(1234, 23, expectedResult: 28383),
      'a product that does not fit the board': multiplicationProblem(
        99999,
        999,
        checkpoints: const MultiplicationEngine()
            .generateCheckpoints(multiplicand: 99999, multiplier: 99),
      ),
    };

    for (final entry in refused.entries) {
      test('${entry.key}: the previous problem stays exactly as it was', () {
        final controller = SorobanController(
          generator: ScriptedProblemGenerator([good, entry.value]),
        );
        controller.startPracticeProblem(
            ProblemCategory.multiplication2, Difficulty.easy);
        setBoardValue(controller, 3702);
        final credited = controller.creditedContributions;

        expect(
          () => controller.startPracticeProblem(
              ProblemCategory.multiplication2, Difficulty.easy),
          throwsArgumentError,
        );

        expect(controller.currentProblem, same(good));
        expect(controller.state.value, equals(3702));
        expect(controller.creditedContributions, equals(credited));
        expect(controller.activeCheckpointIndex, equals(4));
        expect(controller.isMultiplicationSolved, isFalse);
        expectChainIntact(controller);
      });
    }

    test('a bad problem anywhere in a challenge session refuses the whole '
        'session, before it starts', () {
      final bad = multiplicationProblem(1234, 23, expectedResult: 28383);
      final controller = SorobanController(
        generator: ScriptedProblemGenerator([good, good, bad, good, good]),
      );

      expect(
        () => controller.startChallengeSession(
            ProblemCategory.multiplication2, Difficulty.easy),
        throwsArgumentError,
      );

      expect(controller.isChallengeMode, isFalse);
      expect(controller.totalChallengeProblems, equals(0));
      expect(controller.currentProblem, isNull);
    });
  });

  group('Everything that is not a multiplication', () {
    test('keeps the linear chain', () {
      final controller = controllerForSum([4, 10]);

      expect(controller.creditedContributions, isEmpty);
      expect(controller.isMultiplicationDigitCompleted(termIndex: 0, digitIndex: 0),
          isFalse);

      setRodValue(controller, 0, 4);
      controller.reconcileCheckpoints();
      expect(controller.activeCheckpointIndex, equals(1));
      expect(controller.creditedContributions, isEmpty);
    });
  });
}
