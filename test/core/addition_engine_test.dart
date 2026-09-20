import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/engine/addition_engine.dart';
import 'package:soroban_app/core/models/bead_move.dart';
import 'package:soroban_app/core/models/rod.dart';
import 'package:soroban_app/core/models/soroban_state.dart';

void main() {
  group('Rod & SorobanState Model Tests', () {
    test('Rod correctly represents digits 0 through 9', () {
      for (int i = 0; i <= 9; i++) {
        final rod = Rod.fromValue(i);
        expect(rod.value, equals(i));
        expect(rod.heaven, equals(i >= 5));
        expect(rod.earth, equals(i % 5));
      }
    });

    test('SorobanState correctly computes multi-rod integer value', () {
      final state = SorobanState.fromValue(40823);
      expect(state.value, equals(40823));
      expect(state.rods[0].value, equals(3)); // units
      expect(state.rods[1].value, equals(2)); // tens
      expect(state.rods[2].value, equals(8)); // hundreds
      expect(state.rods[3].value, equals(0)); // thousands
      expect(state.rods[4].value, equals(4)); // ten-thousands
    });
  });

  group('AdditionEngine Mechanics Tests', () {
    const engine = AdditionEngine();

    test('Direct addition: 1 + 2 = 3 on rod 0', () {
      final start = SorobanState.fromValue(1);
      final moves = engine.calculateDigitMoves(start, 2, 0);

      expect(moves.length, equals(1));
      expect(moves[0].rodIndex, equals(0));
      expect(moves[0].kind, equals(BeadKind.earth));
      expect(moves[0].from, equals(1));
      expect(moves[0].to, equals(3));

      final end = engine.applyMoves(start, moves);
      expect(end.value, equals(3));
    });

    test('5-Complement (Kawan Kecil): 4 + 1 = 5 (heaven down, earth down)', () {
      final start = SorobanState.fromValue(4);
      final moves = engine.calculateDigitMoves(start, 1, 0);

      // 2 moves: heaven down (+5), earth down (-4)
      expect(moves.length, equals(2));
      expect(moves[0].kind, equals(BeadKind.heaven));
      expect(moves[0].to, equals(5));
      expect(moves[1].kind, equals(BeadKind.earth));
      expect(moves[1].to, equals(0));

      final end = engine.applyMoves(start, moves);
      expect(end.value, equals(5));
    });

    test('10-Complement (Kawan Besar): 9 + 1 = 10 with carry', () {
      final start = SorobanState.fromValue(9);
      final moves = engine.calculateDigitMoves(start, 1, 0);

      final end = engine.applyMoves(start, moves);
      expect(end.value, equals(10));
      expect(end.rods[0].value, equals(0));
      expect(end.rods[1].value, equals(1));
    });

    test('Ripple Carry: 9999 + 1 = 10000 across multiple rods', () {
      final start = SorobanState.fromValue(9999);
      final moves = engine.calculateDigitMoves(start, 1, 0);

      final end = engine.applyMoves(start, moves);
      expect(end.value, equals(10000));
    });

    test('Exact scenario from spec §2.1: 17823 + 23094 = 40917', () {
      SorobanState state = SorobanState.fromValue(17823);

      // Checkpoint 1: +20000 (Term 2, digit 2 at rod 4)
      final cp1Moves = engine.calculateDigitMoves(state, 2, 4);
      state = engine.applyMoves(state, cp1Moves);
      expect(state.value, equals(37823));

      // Checkpoint 2: +3000 (Term 2, digit 3 at rod 3)
      final cp2Moves = engine.calculateDigitMoves(state, 3, 3);
      state = engine.applyMoves(state, cp2Moves);
      expect(state.value, equals(40823));

      // Checkpoint 3: +90 (Term 2, digit 9 at rod 1) -> 2 chained moves:
      // rod 2 (hundreds) increases by 1, rod 1 (tens) decreases by 1
      final cp3Moves = engine.calculateDigitMoves(state, 9, 1);
      expect(cp3Moves.length, equals(2));
      state = engine.applyMoves(state, cp3Moves);
      expect(state.value, equals(40913));

      // Checkpoint 4: +4 (Term 2, digit 4 at rod 0)
      final cp4Moves = engine.calculateDigitMoves(state, 4, 0);
      state = engine.applyMoves(state, cp4Moves);
      expect(state.value, equals(40917));
    });

    test('Subtraction: 10 - 1 = 9 with borrow', () {
      final start = SorobanState.fromValue(10);
      final moves = engine.calculateDigitMoves(start, -1, 0);

      final end = engine.applyMoves(start, moves);
      expect(end.value, equals(9));
    });
  });
}
