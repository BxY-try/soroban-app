import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/engine/hint_engine.dart';
import 'package:soroban_app/core/engine/problem_generator.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/models/soroban_state.dart';

void main() {
  group('HintEngine Tests', () {
    const hintEngine = HintEngine();
    final generator = ProblemGenerator();

    test('Hint retrieves next checkpoint correctly when matching valid state', () {
      final problem = generator.generateProblem(
        category: ProblemCategory.addition,
        difficulty: Difficulty.easy,
      );

      final snapshots = <SorobanState>[SorobanState.zero()];

      // 1. Initial hint at 0
      final hint1 = hintEngine.getNextHint(
        currentState: SorobanState.zero(),
        problem: problem,
        checkpointSnapshots: snapshots,
      );

      expect(hint1, isNotNull);
      expect(hint1!.checkpointIndex, equals(0));
      expect(hint1.recoveredFromDivergence, isFalse);

      // Advance state to checkpoint 1 target
      final target1 = problem.checkpoints[0].targetValue;
      final state1 = SorobanState.fromValue(target1);
      snapshots.add(state1);

      // 2. Next hint should target checkpoint 1 (the 2nd checkpoint)
      final hint2 = hintEngine.getNextHint(
        currentState: state1,
        problem: problem,
        checkpointSnapshots: snapshots,
      );

      expect(hint2, isNotNull);
      expect(hint2!.checkpointIndex, equals(1));
    });

    test('Replay rolls back to start of active checkpoint', () {
      final problem = generator.generateProblem(
        category: ProblemCategory.addition,
        difficulty: Difficulty.easy,
      );

      final cp0Target = problem.checkpoints[0].targetValue;
      final snapshots = [
        SorobanState.zero(),
        SorobanState.fromValue(cp0Target),
      ];

      // Replay checkpoint 0
      final replay = hintEngine.getReplay(
        activeCheckpointIndex: 0,
        problem: problem,
        checkpointSnapshots: snapshots,
      );

      expect(replay, isNotNull);
      expect(replay!.fromState.value, equals(0));
      expect(replay.checkpoint.targetValue, equals(cp0Target));
    });

    test('Divergence ("Nyasar") recovery restores to valid checkpoint snapshot', () {
      final problem = generator.generateProblem(
        category: ProblemCategory.addition,
        difficulty: Difficulty.easy,
      );

      final cp0Target = problem.checkpoints[0].targetValue;
      final snapshots = [
        SorobanState.zero(),
        SorobanState.fromValue(cp0Target),
      ];

      // User accidentally tapped beads creating an arbitrary invalid value 999
      final arbitraryLostState = SorobanState.fromValue(999);

      final hint = hintEngine.getNextHint(
        currentState: arbitraryLostState,
        problem: problem,
        checkpointSnapshots: snapshots,
      );

      expect(hint, isNotNull);
      expect(hint!.recoveredFromDivergence, isTrue);
      expect(hint.fromState.value, equals(cp0Target));
    });
  });
}
