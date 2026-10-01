import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/engine/multiplication_engine.dart';
import 'package:soroban_app/core/engine/multiplication_progress.dart';
import 'package:soroban_app/core/models/soroban_state.dart';

void main() {
  group('MultiplicationEngine Tests', () {
    const engine = MultiplicationEngine();

    test('Multiplication I (1-digit multiplier): 482 × 6 = 2892', () {
      final checkpoints = engine.generateCheckpoints(
        multiplicand: 482,
        multiplier: 6,
      );

      expect(checkpoints.isNotEmpty, isTrue);
      expect(checkpoints.last.targetValue, equals(2892));

      // Check monotonicity of calculations
      SorobanState state = SorobanState.zero();
      for (final cp in checkpoints) {
        state = engine.additionEngine.applyMoves(state, cp.atomicMoves);
        expect(state.value, equals(cp.targetValue));
      }
    });

    test('Multiplication II (2-digit multiplier): 1234 × 23 = 28382', () {
      final checkpoints = engine.generateCheckpoints(
        multiplicand: 1234,
        multiplier: 23,
      );

      expect(checkpoints.isNotEmpty, isTrue);
      expect(checkpoints.last.targetValue, equals(1234 * 23));
    });
  });

  group('Canonical teaching chain', () {
    const engine = MultiplicationEngine();

    List<int> targets(int a, int b) => engine
        .generateCheckpoints(multiplicand: a, multiplier: b)
        .map((cp) => cp.targetValue)
        .toList();

    test('123 × 3 goes 300 → 360 → 369', () {
      expect(targets(123, 3), [300, 360, 369]);
    });

    test('1234 × 23 runs the × 20 row first, then the × 3 row', () {
      final checkpoints =
          engine.generateCheckpoints(multiplicand: 1234, multiplier: 23);

      expect(checkpoints.map((cp) => cp.targetValue),
          [20000, 24000, 24600, 24680, 27680, 28280, 28370, 28382]);
      expect(checkpoints[4].termIndex, 1);
      expect(checkpoints[4].digitIndex, 0);
    });

    test('a product that does not fit the board is refused, not cut short', () {
      // 99999 × 99 = 9,899,901 needs seven rods. On six, the chain used to
      // come back without the contributions that did not fit.
      expect(
        () => engine.generateCheckpoints(
          multiplicand: 99999,
          multiplier: 99,
          rodCount: 6,
        ),
        throwsArgumentError,
      );
    });

    test('a product that exactly fills the board is a complete chain', () {
      expect(
        targets(3333333, 3),
        [9000000, 9900000, 9990000, 9999000, 9999900, 9999990, 9999999],
      );

      final three = engine
          .generateCheckpoints(multiplicand: 111, multiplier: 9, rodCount: 3)
          .map((cp) => cp.targetValue);
      expect(three, [900, 990, 999]);
    });

    test('99999 × 99 keeps its carry-heavy checkpoint', () {
      final checkpoints =
          engine.generateCheckpoints(multiplicand: 99999, multiplier: 99);

      expect(checkpoints, hasLength(10));
      expect(checkpoints[5].previousValue, 8999910);
      expect(checkpoints[5].targetValue, 9809910);
    });
  });

  group('contributionMoves', () {
    const engine = MultiplicationEngine();

    List<List<Object>> flick(Iterable<dynamic> moves) => [
          for (final m in moves) [m.rodIndex, m.kind, m.from, m.to],
        ];

    test('from the canonical board they are the canonical checkpoint\'s moves',
        () {
      final checkpoints =
          engine.generateCheckpoints(multiplicand: 1234, multiplier: 23);
      final contributions = MultiplicationContribution.decompose(
          multiplicand: 1234, multiplier: 23);
      var state = SorobanState.zero();

      for (var k = 0; k < checkpoints.length; k++) {
        final moves = engine.contributionMoves(state, contributions[k]);
        expect(flick(moves), flick(checkpoints[k].atomicMoves), reason: 'CP$k');
        state = engine.additionEngine.applyMoves(state, moves);
      }
    });

    test('a contribution that does not reach the board is refused', () {
      // 9 × 9 on rod 5 is 81: its tens digit lands on rod 6.
      const atTheTop = MultiplicationContribution(
        index: 0,
        multiplicandIndex: 0,
        multiplierIndex: 0,
        multiplicandDigit: 9,
        multiplierDigit: 9,
        rodIndex: 5,
      );

      final sixRods = SorobanState.zero(rodCount: 6);
      expect(
        () => engine.contributionMoves(sixRods, atTheTop),
        throwsArgumentError,
      );

      final sevenRods = SorobanState.zero(rodCount: 7);
      final moves = engine.contributionMoves(sevenRods, atTheTop);
      expect(engine.additionEngine.applyMoves(sevenRods, moves).value,
          equals(8100000));
    });

    test('a contribution whose top digit is on the last rod is not refused',
        () {
      // 2 × 4 on rod 5 is 8: one digit, on the last rod of six.
      const onTheLast = MultiplicationContribution(
        index: 0,
        multiplicandIndex: 0,
        multiplierIndex: 0,
        multiplicandDigit: 2,
        multiplierDigit: 4,
        rodIndex: 5,
      );
      final board = SorobanState.zero(rodCount: 6);

      final moves = engine.contributionMoves(board, onTheLast);

      expect(engine.additionEngine.applyMoves(board, moves).value,
          equals(800000));
    });

    test('the two contributions of 12 × 12 that both put 20 on rod 1 play the '
        'same moves from any board', () {
      final contributions =
          MultiplicationContribution.decompose(multiplicand: 12, multiplier: 12);
      final twins = contributions.where((c) => c.value == 20).toList();
      expect(twins, hasLength(2));

      // Whichever one the board is read as holding, Hint plays the same
      // fingers: the moves depend on the digit product and the rod, nothing
      // else, so the ambiguity cannot change what the user is shown.
      for (final start in [0, 4, 20, 24, 100, 104, 120, 124, 140]) {
        final board = SorobanState.fromValue(start);
        final first = engine.contributionMoves(board, twins[0]);
        final second = engine.contributionMoves(board, twins[1]);

        expect(flick(first), flick(second), reason: 'from $start');
        expect(engine.additionEngine.applyMoves(board, first).value,
            equals(start + 20));
      }
    });

    test('they are worked out from whatever board the user has', () {
      final contribution = MultiplicationContribution.decompose(
          multiplicand: 1234, multiplier: 23).last; // 4 × 3 = 12

      for (final start in [0, 8, 88, 1234, 3702]) {
        final board = SorobanState.fromValue(start);
        final moves = engine.contributionMoves(board, contribution);
        final after = engine.additionEngine.applyMoves(board, moves);

        expect(after.value, equals(start + 12), reason: 'from $start');
      }
    });
  });
}
