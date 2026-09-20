import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/engine/multiplication_engine.dart';
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
}
