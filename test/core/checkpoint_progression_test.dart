import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/core/models/bead_move.dart';
import 'package:soroban_app/core/state/soroban_controller.dart';

import '../helpers/fixed_problem.dart';

void main() {
  group('Free board: the user is never steered', () {
    test('any rod may be moved, whatever the active checkpoint wants', () {
      // `4 + 10`: the first digit is rod 0 = 4, the second is rod 1 = 1.
      final controller = controllerForSum([4, 10]);
      final checkpoints = controller.currentProblem!.checkpoints;
      expect(checkpoints.map((c) => c.targetValue), [4, 14]);

      // Rod 6 is nothing to do with either digit, and it moves anyway. Nothing
      // stops it and nothing warns about it.
      setRodValue(controller, 6, 7);
      controller.reconcileCheckpoints();

      expect(controller.state.rods[6].value, equals(7));
      expect(
        controller.activeCheckpointIndex,
        equals(0),
        reason: '7,000,000 is not a checkpoint, and the move is simply kept',
      );
    });

    test('a rod the user did not mean to set simply costs them the match', () {
      // The honest consequence of a free board: the chain matches the whole
      // board, so a stray bead somewhere else keeps the digit from registering.
      // The user is told nothing and nothing moves on its own — Reset is theirs.
      final controller = controllerForSum([4, 10]);

      setRodValue(controller, 6, 7);
      setRodValue(controller, 0, 4);
      controller.reconcileCheckpoints();

      expect(controller.state.value, equals(7000004));
      expect(controller.activeCheckpointIndex, equals(0));
      expect(controller.canReset, isTrue);

      controller.executeReset();
      expect(controller.state.value, equals(0));
    });

    test('work left half-finished is never taken back', () {
      final controller = controllerForSum([4, 10]);

      setRodValue(controller, 0, 2); // on the way to 4, stopped at 2
      controller.reconcileCheckpoints();

      expect(controller.state.rods[0].value, equals(2));
      expect(controller.activeCheckpointIndex, equals(0));
    });
  });

  group('Reconciliation happens only at quiescence', () {
    test('commits alone never advance the chain', () {
      final controller = controllerForSum([4, 10]);
      final cp0 = controller.currentProblem!.checkpoints.first;

      // Every atomic move of the first digit, with no reconcile in between.
      for (final move in cp0.atomicMoves) {
        if (move.kind == BeadKind.heaven) {
          controller.tapHeavenBead(move.rodIndex);
        } else {
          controller.tapEarthBead(move.rodIndex, move.to);
        }
        expect(
          controller.activeCheckpointIndex,
          equals(0),
          reason: 'a commit is not a gesture',
        );
      }

      expect(controller.state.value, equals(4));
      expect(controller.activeCheckpointIndex, equals(0));

      // The gesture ends here.
      controller.reconcileCheckpoints();
      expect(controller.activeCheckpointIndex, equals(1));
    });
  });

  group('No match means nothing happens', () {
    test('a value that matches nothing leaves the board alone', () {
      final controller = controllerForSum([4, 10]);

      setRodValue(controller, 0, 3); // neither 4 nor 14
      controller.reconcileCheckpoints();

      expect(controller.state.value, equals(3));
      expect(controller.activeCheckpointIndex, equals(0));
      expect(controller.checkpointSnapshotCount, equals(1));
    });

    test('a value that only matches an already passed checkpoint is ignored',
        () {
      final controller = controllerForSum([4, 10]);
      performCheckpointGesture(controller, controller.currentProblem!.checkpoints[0]);
      expect(controller.activeCheckpointIndex, equals(1));

      // Back to the value of checkpoint 0, which is behind the chain now.
      setRodValue(controller, 0, 2);
      controller.reconcileCheckpoints();

      expect(controller.state.value, equals(2));
      expect(
        controller.activeCheckpointIndex,
        equals(1),
        reason: 'progression only ever moves forward',
      );
    });
  });

  group('Skipping checkpoints is allowed', () {
    test('landing on a later value counts everything up to it', () {
      final controller = controllerForSum([20, 5, 30, 2]);
      final checkpoints = controller.currentProblem!.checkpoints;
      expect(checkpoints.map((c) => c.targetValue), [20, 25, 55, 57]);

      // One gesture that produces 55 without ever resting on 20 or 25.
      setRodValue(controller, 0, 5);
      setRodValue(controller, 1, 5);
      controller.reconcileCheckpoints();

      expect(controller.state.value, equals(55));
      expect(
        controller.activeCheckpointIndex,
        equals(3),
        reason: 'CP0 and CP1 never became settled boards, and that is fine',
      );
    });

    test('a carry done in one sweep lands on the last value directly', () {
      // `999 + 1` = 1000: four rods change, and a fast pair of hands can do it
      // in one motion instead of four.
      final controller = controllerForSum([999, 1]);
      final checkpoints = controller.currentProblem!.checkpoints;
      expect(checkpoints.last.targetValue, 1000);

      setRodValue(controller, 0, 0);
      setRodValue(controller, 1, 0);
      setRodValue(controller, 2, 0);
      setRodValue(controller, 3, 1);
      controller.reconcileCheckpoints();

      expect(controller.state.value, equals(1000));
      expect(
        controller.activeCheckpointIndex,
        equals(checkpoints.length),
        reason: 'the whole ripple counts as done',
      );
    });
  });

  group('A repeated target value resolves to the first match', () {
    // `12 + 7 - 7` produces 10, 12, 19, 12 — the last value repeats the
    // second. Matching the furthest one instead of the first would hand the
    // user credit for a digit they never placed.
    late List<int> targets;
    SorobanController mixedController() {
      final controller = controllerFor(
        FixedCheckpointsProblemGenerator(
          checkpointsForSequence([(12, true), (7, true), (7, false)]),
        ),
      );
      targets =
          controller.currentProblem!.checkpoints.map((c) => c.targetValue).toList();
      return controller;
    }

    test('the sequence really does repeat a value', () {
      mixedController();
      expect(targets, [10, 12, 19, 12]);
      expect(targets.toSet().length, lessThan(targets.length));
    });

    test('standing on 12 with the chain at 10 advances one step, not three',
        () {
      final controller = mixedController();
      setRodValue(controller, 0, 2); // 12
      setRodValue(controller, 1, 1);
      controller.reconcileCheckpoints();

      expect(controller.state.value, equals(12));
      expect(
        controller.activeCheckpointIndex,
        equals(2),
        reason: 'the first match at or after the chain start is CP1, not CP3',
      );
    });
  });

  group('Snapshot chain has no holes', () {
    test('every crossed checkpoint gets an entry', () {
      final controller = controllerForSum([20, 5, 30, 2]);
      final checkpoints = controller.currentProblem!.checkpoints;

      setRodValue(controller, 0, 5);
      setRodValue(controller, 1, 5); // 55, crossing three checkpoints
      controller.reconcileCheckpoints();
      expect(controller.activeCheckpointIndex, equals(3));

      // Length must match the reached index: no gap for Reset or Replay to trip
      // over, which is what used to throw a RangeError.
      expect(controller.checkpointSnapshotCount, equals(4));

      // Each entry is the board that checkpoint describes. The chain is indexed
      // by where a checkpoint *starts*, which is the board the previous
      // checkpoint produced — the layout Reset and Replay index into.
      expect(controller.checkpointSnapshots.first.value, equals(0));
      for (var i = 1; i < checkpoints.length; i++) {
        expect(
          controller.checkpointSnapshots[i].value,
          equals(checkpoints[i - 1].targetValue),
          reason: 'snapshot $i is where checkpoint ${i - 1} left off',
        );
      }
      expect(
        controller.checkpointSnapshots.last.value,
        equals(55),
        reason: 'the last entry is the board the user actually has',
      );
    });

    test('entries are added, never assigned over', () {
      final controller = controllerForSum([20, 5, 30, 2]);

      // Two consecutive gestures, so an index-based write would have gone out
      // of range on the second one.
      setRodValue(controller, 1, 2);
      controller.reconcileCheckpoints();
      expect(controller.activeCheckpointIndex, equals(1));
      expect(controller.checkpointSnapshotCount, equals(2));

      setRodValue(controller, 0, 5);
      controller.reconcileCheckpoints();
      expect(controller.activeCheckpointIndex, equals(2));
      expect(controller.checkpointSnapshotCount, equals(3));
    });
  });

  group('Reset stays manual', () {
    test('a wrong board is only corrected when asked', () {
      final controller = controllerForSum([4, 10]);
      performCheckpointGesture(controller, controller.currentProblem!.checkpoints[0]);
      expect(controller.activeCheckpointIndex, equals(1));

      // Wander off anywhere.
      setRodValue(controller, 0, 2);
      setRodValue(controller, 5, 9);
      controller.reconcileCheckpoints();

      expect(controller.state.value, equals(2 + 900000));
      expect(controller.activeCheckpointIndex, equals(1));
      expect(controller.canReset, isTrue);

      controller.executeReset();
      expect(controller.state.value, equals(4));
      expect(controller.activeCheckpointIndex, equals(1));
    });

    test('with nothing completed yet, reset returns to the start', () {
      final controller = controllerForSum([4, 10]);
      setRodValue(controller, 3, 8);
      controller.reconcileCheckpoints();

      expect(controller.canReset, isTrue);
      controller.executeReset();

      expect(controller.state.value, equals(0));
      expect(controller.activeCheckpointIndex, equals(0));
    });

    test('rewinding a skipped chain steps one checkpoint at a time', () {
      final controller = controllerForSum([20, 5, 30, 2]);
      setRodValue(controller, 0, 5);
      setRodValue(controller, 1, 5);
      controller.reconcileCheckpoints();
      expect(controller.activeCheckpointIndex, equals(3));

      // First reset: the board already matches the last snapshot, so it rewinds
      // to the board after checkpoint 2 (value 55 -> 55 is the snapshot, so the
      // rewind is to checkpoint 2's start, which is 25).
      controller.executeReset();
      expect(controller.state.value, equals(25));
      expect(controller.activeCheckpointIndex, equals(2));

      controller.executeReset();
      expect(controller.state.value, equals(20));
      expect(controller.activeCheckpointIndex, equals(1));
    });
  });

  group('Skip then Reset', () {
    // `20 + 5 + 30 + 2` runs 20 -> 25 -> 55 -> 57. Landing straight on 55 in
    // one gesture means two checkpoints were never settled as boards of their
    // own, and the snapshot chain has to be complete anyway.
    SorobanController skipped() {
      final controller = controllerForSum([20, 5, 30, 2]);
      final checkpoints = controller.currentProblem!.checkpoints;
      expect(checkpoints.map((c) => c.targetValue), [20, 25, 55, 57]);

      setRodValue(controller, 0, 5);
      setRodValue(controller, 1, 5);
      controller.reconcileCheckpoints();

      expect(controller.state.value, equals(55));
      expect(controller.activeCheckpointIndex, equals(3));
      return controller;
    }

    test('the chain is complete right after the skip', () {
      final controller = skipped();
      final snapshots = controller.checkpointSnapshots;

      // No hole: one entry per index from 0 up to the reached checkpoint.
      expect(snapshots.length, equals(4));
      expect(
        snapshots.map((s) => s.value).toList(),
        [0, 20, 25, 55],
        reason: 'each skipped checkpoint still got a valid boundary board',
      );
    });

    test('rewinds one crossed checkpoint at a time', () {
      final controller = skipped();

      // First press: the board already equals the last entry, so it steps back
      // to where the *last* crossed digit started — 55 -> 25, not 55 -> 20.
      controller.executeReset();
      expect(controller.state.value, equals(25));
      expect(controller.activeCheckpointIndex, equals(2));
      expect(controller.checkpointSnapshotCount, equals(3));

      controller.executeReset();
      expect(controller.state.value, equals(20));
      expect(controller.activeCheckpointIndex, equals(1));
      expect(controller.checkpointSnapshotCount, equals(2));

      controller.executeReset();
      expect(controller.state.value, equals(0));
      expect(controller.activeCheckpointIndex, equals(0));
      expect(controller.checkpointSnapshotCount, equals(1));

      // Nothing left to rewind to: further presses are no-ops, not crashes.
      controller.executeReset();
      expect(controller.state.value, equals(0));
      expect(controller.activeCheckpointIndex, equals(0));
    });

    test('a partial edit after the skip goes back to the last crossed board', () {
      final controller = skipped();

      // Wander somewhere that matches nothing at all.
      setRodValue(controller, 2, 1); // 155
      controller.reconcileCheckpoints();
      expect(controller.activeCheckpointIndex, equals(3));
      expect(controller.state.value, equals(155));

      // The board is not where the chain says it should be, so the first press
      // restores the last crossed board instead of rewinding a digit.
      controller.executeReset();
      expect(controller.state.value, equals(55));
      expect(controller.activeCheckpointIndex, equals(3));
      expect(controller.checkpointSnapshotCount, equals(4));
    });

    test('a skip straight to the final value rewinds all the way without a hole',
        () {
      final controller = controllerForSum([20, 5, 30, 2]);
      setRodValue(controller, 0, 7);
      setRodValue(controller, 1, 5); // 57, the last checkpoint
      controller.reconcileCheckpoints();

      expect(controller.state.value, equals(57));
      expect(controller.activeCheckpointIndex, equals(4));
      expect(controller.checkpointSnapshotCount, equals(5));
      expect(
        controller.checkpointSnapshots.map((s) => s.value).toList(),
        [0, 20, 25, 55, 57],
      );

      for (final expected in [55, 25, 20, 0]) {
        controller.executeReset();
        expect(
          controller.state.value,
          equals(expected),
          reason: 'rewinding one crossed checkpoint at a time',
        );
        expect(
          controller.checkpointSnapshotCount,
          equals(controller.activeCheckpointIndex + 1),
          reason: 'the chain never loses its invariant on the way down',
        );
      }
    });
  });

  group('Skip then Replay', () {
    test('replay rolls back to the entry the skip filled, and adds no hole',
        () async {
      final controller = controllerForSum([20, 5, 30, 2]);

      // Skip over 20 and 25, landing straight on 55.
      setRodValue(controller, 0, 5);
      setRodValue(controller, 1, 5);
      controller.reconcileCheckpoints();
      expect(controller.activeCheckpointIndex, equals(3));
      expect(controller.checkpointSnapshots.map((s) => s.value).toList(),
          [0, 20, 25, 55]);

      // Hint the remaining digit (+2 -> 57), which extends the chain.
      await controller.executeHint();
      expect(controller.canReplay, isTrue);
      expect(controller.state.value, equals(57));
      expect(controller.activeCheckpointIndex, equals(4));
      expect(controller.checkpointSnapshotCount, equals(5));
      expect(
        controller.checkpointSnapshots.map((s) => s.value).toList(),
        [0, 20, 25, 55, 57],
      );

      // Replay re-runs that digit from the snapshot its start, which only exists
      // because the skip filled the chain. If it were missing, the fallback would
      // silently reconstruct a different board.
      await controller.executeReplay();
      expect(controller.state.value, equals(57));
      expect(controller.activeCheckpointIndex, equals(4));
      expect(
        controller.checkpointSnapshotCount,
        equals(5),
        reason: 'replaying must refresh its entry, never append a duplicate',
      );
      expect(
        controller.checkpointSnapshots.map((s) => s.value).toList(),
        [0, 20, 25, 55, 57],
        reason: 'the boundary boards are the same after a replay as before',
      );
    });

    test('replaying repeatedly keeps the chain the same length', () async {
      final controller = controllerForSum([20, 5, 30, 2]);
      setRodValue(controller, 0, 5);
      setRodValue(controller, 1, 5);
      controller.reconcileCheckpoints();
      await controller.executeHint();

      final lengthAfterHint = controller.checkpointSnapshotCount;
      expect(lengthAfterHint, equals(5));

      for (var i = 0; i < 3; i++) {
        await controller.executeReplay();
        expect(
          controller.checkpointSnapshotCount,
          equals(lengthAfterHint),
          reason: 'replay #$i must not grow the chain',
        );
        expect(controller.state.value, equals(57));
        expect(controller.activeCheckpointIndex, equals(4));
      }
    });
  });

  group('No problem means no reconciliation', () {
    test('free play never advances anything', () {
      final controller = controllerForSum([4, 10]);
      // A fresh controller with no problem at all.
      final free = SorobanController();
      setRodValue(free, 0, 9);
      free.reconcileCheckpoints();

      expect(free.state.value, equals(9));
      expect(free.activeCheckpointIndex, equals(0));
      expect(controller.currentProblem, isNotNull);
    });
  });
}
