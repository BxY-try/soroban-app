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
