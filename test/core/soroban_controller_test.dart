import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/models/bead_move.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/state/soroban_controller.dart';

void main() {
  group('SorobanController Reset & Replay Tests', () {
    test('executeReset restores divergence, then rolls back to previous checkpoint', () {
      final controller = SorobanController();
      controller.startPracticeProblem(ProblemCategory.addition, Difficulty.easy);

      final problem = controller.currentProblem!;
      final cp0Target = problem.checkpoints[0].targetValue;

      // 1. Advance to checkpoint 0
      // Simulate completing checkpoint 0 by moving beads or hint
      // Tap earth bead on rod 0 to change state
      controller.tapEarthBead(0, 1);
      expect(controller.canReset, isTrue);

      // Reset when divergence exists: restores to start of active checkpoint (0)
      controller.executeReset();
      expect(controller.state.value, equals(0));
      expect(controller.activeCheckpointIndex, equals(0));

      // 2. Set state to match checkpoint 0
      // Manually trigger advancement to cp0
      final moves = problem.checkpoints[0].atomicMoves;
      for (final move in moves) {
        if (move.kind == BeadKind.heaven) {
          controller.tapHeavenBead(move.rodIndex);
        } else {
          controller.tapEarthBead(move.rodIndex, move.to);
        }
      }

      // Checkpoint 0 reached!
      expect(controller.state.value, equals(cp0Target));
      expect(controller.activeCheckpointIndex, equals(1));

      // 3. User tries next checkpoint and makes a mistake
      controller.tapEarthBead(0, (controller.state.rods[0].earth + 1).clamp(0, 4));
      expect(controller.state.value != cp0Target, isTrue);

      // First reset: restores mistake to cp0Target
      controller.executeReset();
      expect(controller.state.value, equals(cp0Target));
      expect(controller.activeCheckpointIndex, equals(1));

      // Second reset (retri checkpoint sebelumnya): rolls back to checkpoint 0 start (value 0)
      controller.executeReset();
      expect(controller.state.value, equals(0));
      expect(controller.activeCheckpointIndex, equals(0));
    });

    test('canReplay is false before hint, true after hint', () async {
      final controller = SorobanController();
      controller.startPracticeProblem(ProblemCategory.addition, Difficulty.easy);

      // Before any hint, canReplay should be false
      expect(controller.canReplay, isFalse);

      // Execute hint for checkpoint 0
      await controller.executeHint();

      // After hint, canReplay should be true
      expect(controller.canReplay, isTrue);
    });

    test('executeReplay does not duplicate snapshots in checkpointSnapshots', () async {
      final controller = SorobanController();
      controller.startPracticeProblem(ProblemCategory.addition, Difficulty.easy);

      // Execute hint for checkpoint 0
      await controller.executeHint();
      expect(controller.canReplay, isTrue);

      final snapshotsCountAfterHint = controller.checkpointSnapshots.length;

      // Now execute replay
      await controller.executeReplay();
      expect(controller.checkpointSnapshots.length, equals(snapshotsCountAfterHint));
    });

    test('canReplay resets to false after executeReset rolls back checkpoint', () async {
      final controller = SorobanController();
      controller.startPracticeProblem(ProblemCategory.addition, Difficulty.easy);

      // Execute hint
      await controller.executeHint();
      expect(controller.canReplay, isTrue);

      // Reset to go back to previous checkpoint
      controller.executeReset();
      // After resetting back, canReplay should be false again
      expect(controller.canReplay, isFalse);
    });
  });
}
