import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/state/soroban_controller.dart';

import '../helpers/fixed_problem.dart';
void main() {
  group('SorobanController Reset & Replay Tests', () {
    test('executeReset restores the board, then rolls back to previous checkpoint', () {
      final controller = controllerForSum([4, 10]);
      final cp0 = controller.currentProblem!.checkpoints[0];

      // 1. A value that is not a checkpoint. Nothing happens to it, and Reset
      // takes it back to where the exercise started.
      setRodValue(controller, 0, 1);
      controller.reconcileCheckpoints();
      expect(controller.activeCheckpointIndex, equals(0));
      expect(controller.canReset, isTrue);

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

      // 3. Wander off onto a rod the next digit has nothing to do with. The
      // board is free, so the move is kept and the chain stays where it was.
      setRodValue(controller, 5, 9);
      controller.reconcileCheckpoints();

      expect(controller.activeCheckpointIndex, equals(1));
      expect(controller.state.value, isNot(equals(cp0.targetValue)));

      // First reset: back to the last completed checkpoint.
      controller.executeReset();
      expect(controller.state.value, equals(cp0.targetValue));
      expect(controller.activeCheckpointIndex, equals(1));

      // Second reset: back one more.
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
      final controller = controllerForSum([4, 10]);
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
