import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/services/sound_service.dart';
import 'package:soroban_app/core/state/soroban_controller.dart';

import '../helpers/fixed_problem.dart';
void main() {
  group('One clack per gesture', () {
    // The player cannot be heard from a test, so these assert the part the
    // controller owns: how many clacks a gesture asks for.
    late SoundService sound;

    setUp(() {
      sound = SoundService();
      sound.clackRequestCount = 0;
    });

    test('nothing is asked for while the finger is still down', () {
      final controller = controllerForSum([4, 10]);
      setRodValue(controller, 0, 4);

      expect(
        sound.clackRequestCount,
        equals(0),
        reason: 'a commit is not a gesture, so it is not a sound either',
      );
    });

    test('a one-finger gesture asks for one clack', () {
      final controller = controllerForSum([4, 10]);
      setRodValue(controller, 0, 4);
      controller.onGestureSettled();

      expect(sound.clackRequestCount, equals(1));
      expect(controller.activeCheckpointIndex, equals(1));
    });

    test('a two-finger gesture on two rods still asks for one clack', () {
      final controller = controllerForSum([4, 10]);

      // Two fingers, two rods, two commits — the multi-touch case.
      setRodValue(controller, 0, 4);
      setRodValue(controller, 1, 1);
      controller.onGestureSettled();

      expect(
        sound.clackRequestCount,
        equals(1),
        reason: 'one motion, one sound: a second clack would overlap on the '
            'same player and take the pair down',
      );
      expect(controller.state.value, equals(14));
    });

    test('a two-finger gesture on one rod, both decks, asks for one clack', () {
      final controller = controllerForSum([4, 5]);

      // Heaven and earth set together: the quick "9" motion.
      controller.tapHeavenBead(0);
      controller.tapEarthBead(0, 4);
      controller.onGestureSettled();

      expect(sound.clackRequestCount, equals(1));
      expect(controller.state.rods[0].value, equals(9));
    });

    test('a gesture that moved nothing asks for nothing', () {
      final controller = controllerForSum([4, 10]);
      controller.onGestureSettled();

      expect(sound.clackRequestCount, equals(0));
    });

    test('consecutive gestures ask for one clack each', () {
      final controller = controllerForSum([4, 10]);

      setRodValue(controller, 0, 4);
      controller.onGestureSettled();
      setRodValue(controller, 1, 1);
      controller.onGestureSettled();

      expect(sound.clackRequestCount, equals(2));
      expect(controller.activeCheckpointIndex, equals(2));
    });

    test('a hint animation clacks per move, not per gesture', () async {
      final controller = controllerForSum([4, 10]);
      setRodValue(controller, 0, 4);
      controller.onGestureSettled();
      final afterGesture = sound.clackRequestCount;

      // Each animated move is a separate visible beat with its own delay, so
      // each one is its own sound. A stale pending clack from the interrupted
      // gesture must not fire on top of them.
      await controller.executeHint();
      expect(sound.clackRequestCount, greaterThan(afterGesture));
    });
  });

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
