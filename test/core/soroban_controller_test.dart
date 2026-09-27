import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soroban_app/core/engine/problem_generator.dart';
import 'package:soroban_app/core/models/bead_move.dart';
import 'package:soroban_app/core/models/checkpoint_plan.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/state/soroban_controller.dart';

/// Performs a checkpoint exactly the way the view does: one gesture, every
/// atomic move committed inside it, then a single reconciliation when the last
/// finger lifts.
void performCheckpointGesture(
  SorobanController controller,
  DigitCheckpoint checkpoint,
) {
  controller.beginGesture();
  for (final move in checkpoint.atomicMoves) {
    if (move.kind == BeadKind.heaven) {
      controller.tapHeavenBead(move.rodIndex);
    } else {
      controller.tapEarthBead(move.rodIndex, move.to);
    }
  }
  controller.endGesture();
}

/// Drives one rod to an absolute value, as heaven/earth flicks.
void setRodValue(SorobanController controller, int rodIndex, int value) {
  final rod = controller.state.rods[rodIndex];
  if (rod.heaven != (value >= 5)) controller.tapHeavenBead(rodIndex);
  final earth = value % 5;
  if (rod.earth != earth) controller.tapEarthBead(rodIndex, earth);
}

/// A value that is neither where the rod stands nor where the current group
/// wants it, i.e. genuinely wrong work rather than partial work.
int wrongValueFor({required int baseline, required int target}) {
  var value = 0;
  while (value == baseline || value == target) {
    value++;
  }
  return value;
}

void main() {
  group('SorobanController Reset & Replay Tests', () {
    test('executeReset restores divergence, then rolls back to previous checkpoint', () {
      final controller = SorobanController(
        generator: ProblemGenerator(random: Random(3)),
      );
      controller.startPracticeProblem(ProblemCategory.addition, Difficulty.easy);

      final problem = controller.currentProblem!;
      final cp0 = problem.checkpoints[0];

      // 1. Move a bead without finishing the digit. This is legal: a half-done
      // digit is a digit in progress, never divergence.
      controller.beginGesture();
      setRodValue(controller, 0, 1);
      controller.endGesture();
      expect(controller.activeCheckpointIndex, equals(0));
      expect(controller.canReset, isTrue);

      // Reset when divergence exists: restores to start of active checkpoint (0)
      controller.executeReset();
      expect(controller.state.value, equals(0));
      expect(controller.activeCheckpointIndex, equals(0));

      // 2. Finish the first digit as one real gesture.
      performCheckpointGesture(controller, cp0);

      expect(controller.state.value, equals(cp0.targetValue));
      expect(controller.activeCheckpointIndex, equals(1));
      expect(
        controller.checkpointSnapshotCount,
        equals(2),
        reason: 'one snapshot entry per reached checkpoint index, appended',
      );

      // 3. User tries the next checkpoint and makes a mistake: the rod ends up
      // at a value that is neither its baseline nor the group's target.
      final cp1 = problem.checkpoints[1];
      final MoveGroup group = cp1.plan.groups.first;
      final rodIndex = group.rods.first;
      final mistake = wrongValueFor(
        baseline: controller.state.rods[rodIndex].value,
        target: group.targets[rodIndex]!,
      );

      controller.beginGesture();
      setRodValue(controller, rodIndex, mistake);
      controller.endGesture();

      // Wrong work is neither rewarded nor reverted.
      expect(controller.activeCheckpointIndex, equals(1));
      expect(controller.state.value, isNot(equals(cp0.targetValue)));

      // First reset: restores mistake to cp0Target
      controller.executeReset();
      expect(controller.state.value, equals(cp0.targetValue));
      expect(controller.activeCheckpointIndex, equals(1));

      // Second reset (retri checkpoint previously): rolls back to checkpoint 0 start (value 0)
      controller.executeReset();
      expect(controller.state.value, equals(0));
      expect(controller.activeCheckpointIndex, equals(0));
      expect(controller.checkpointSnapshotCount, equals(1));
    });

    test('a snapshot is appended per successful checkpoint, never assigned', () {
      // Guards the reconcile loop against writing by index into a list that only
      // ever grows by appending. Two consecutive checkpoints are required: the
      // first advance would still pass an index write (it rewrites entry 0 in
      // place, so nothing is out of range and only the entry count is wrong),
      // and it is the second advance that goes out of range for real.
      final controller = SorobanController(
        generator: ProblemGenerator(random: Random(3)),
      );
      controller.startPracticeProblem(ProblemCategory.addition, Difficulty.easy);

      final checkpoints = controller.currentProblem!.checkpoints;
      expect(checkpoints.length, greaterThanOrEqualTo(2));

      for (var i = 0; i < 2; i++) {
        performCheckpointGesture(controller, checkpoints[i]);
        expect(controller.activeCheckpointIndex, equals(i + 1));
        expect(
          controller.checkpointSnapshotCount,
          equals(i + 2),
          reason: 'after completing checkpoint $i: the chain must have grown',
        );
      }
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

  group('SorobanController Challenge Mode Behavior Tests', () {
    test('executeHint and executeReplay are completely disabled in Challenge Mode', () async {
      final controller = SorobanController();
      addTearDown(() => controller.dispose());
      controller.startChallengeSession(ProblemCategory.addition, Difficulty.easy);

      expect(controller.isChallengeMode, isTrue);
      expect(controller.canReplay, isFalse);
      expect(controller.state.value, equals(0));
      expect(controller.activeCheckpointIndex, equals(0));

      // Attempt to execute hint in challenge mode
      await controller.executeHint();

      // State and checkpoint must remain unchanged
      expect(controller.state.value, equals(0));
      expect(controller.activeCheckpointIndex, equals(0));
      expect(controller.canReplay, isFalse);

      // Attempt to execute replay in challenge mode
      await controller.executeReplay();
      expect(controller.state.value, equals(0));
      expect(controller.activeCheckpointIndex, equals(0));
    });

    test('executeReset still works properly in Challenge Mode', () {
      final controller = SorobanController();
      addTearDown(() => controller.dispose());
      controller.startChallengeSession(ProblemCategory.addition, Difficulty.easy);

      // Move a bead manually
      controller.tapEarthBead(0, 2);
      expect(controller.state.value, equals(2));
      expect(controller.canReset, isTrue);

      // Reset restores mistake to 0
      controller.executeReset();
      expect(controller.state.value, equals(0));
    });
  });

  group('SorobanController tap-to-toggle setting', () {
    test('is off by default, so beads stay drag-only', () {
      final controller = SorobanController();
      addTearDown(() => controller.dispose());

      expect(controller.tapToToggleEnabled, isFalse);
    });

    test('toggleTapToToggle flips the flag and persists it', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});

      final controller = SorobanController();
      addTearDown(() => controller.dispose());
      await controller.init();

      controller.toggleTapToToggle();
      expect(controller.tapToToggleEnabled, isTrue);
      // Let the async persist settle before reading the store back.
      await Future<void>.delayed(Duration.zero);
      expect(
        (await SharedPreferences.getInstance()).getBool('tap_to_toggle_enabled'),
        isTrue,
      );

      controller.toggleTapToToggle();
      expect(controller.tapToToggleEnabled, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(
        (await SharedPreferences.getInstance()).getBool('tap_to_toggle_enabled'),
        isFalse,
      );
    });

    test('init restores a previously enabled choice, and defaults to off otherwise',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({'tap_to_toggle_enabled': true});

      final enabled = SorobanController();
      addTearDown(() => enabled.dispose());
      await enabled.init();
      expect(enabled.tapToToggleEnabled, isTrue);

      SharedPreferences.setMockInitialValues({});
      final fresh = SorobanController();
      addTearDown(() => fresh.dispose());
      await fresh.init();
      expect(fresh.tapToToggleEnabled, isFalse);
    });
  });
}
