import '../models/bead_move.dart';
import '../models/checkpoint_plan.dart';
import '../models/problem.dart';
import '../models/rod.dart';
import '../models/soroban_state.dart';

/// Calculation engine for Soroban mechanical bead manipulations.
/// Accurately simulates the physical rules of Japanese Soroban:
/// - Direct movements (cukup manik)
/// - 5-complement ("kawan kecil": 1/4, 2/3 pairs)
/// - 10-complement ("kawan besar": 1/9, 2/8, 3/7, 4/6, 5/5 pairs) with carries and borrows
/// - Multi-rod ripple carries (simpanan beruntun) and ripple borrows
class AdditionEngine {
  const AdditionEngine();

  /// Applies a single [BeadMove] to [state], returning the updated [SorobanState].
  SorobanState applyMove(SorobanState state, BeadMove move) {
    if (move.rodIndex < 0 || move.rodIndex >= state.rods.length) {
      return state;
    }
    final currentRod = state.rods[move.rodIndex];
    Rod newRod;
    if (move.kind == BeadKind.heaven) {
      newRod = currentRod.copyWith(heaven: move.to == 5);
    } else {
      newRod = currentRod.copyWith(earth: move.to);
    }
    return state.updateRod(move.rodIndex, newRod);
  }

  /// Applies a sequence of [BeadMove]s to [state].
  SorobanState applyMoves(SorobanState state, List<BeadMove> moves) {
    SorobanState current = state;
    for (final move in moves) {
      current = applyMove(current, move);
    }
    return current;
  }

  /// Computes the exact atomic [BeadMove]s to add or subtract a single digit [signedDigit]
  /// (-9..9) at rod [rodIndex] starting from [state].
  List<BeadMove> calculateDigitMoves(
    SorobanState state,
    int signedDigit,
    int rodIndex,
  ) {
    return [
      for (final level in calculateDigitMoveLevels(state, signedDigit, rodIndex))
        ...level,
    ];
  }

  /// The same moves as [calculateDigitMoves], but split per recursion level.
  ///
  /// Each level is one rod's bead flicks, and each level is a unit of work that
  /// must happen before the next one. A carry/borrow recursion produces one
  /// level per rod, ordered from the highest rod down, because that is the
  /// order the engine itself needs to resolve the ripple. Heaven+earth on the
  /// same rod stay inside one level, which is what lets two fingers set a `9`
  /// in either order.
  List<List<BeadMove>> calculateDigitMoveLevels(
    SorobanState state,
    int signedDigit,
    int rodIndex,
  ) {
    if (signedDigit == 0) return const [];
    assert(
      rodIndex >= 0 && rodIndex < state.rods.length,
      'rodIndex out of bounds',
    );

    return signedDigit > 0
        ? _additionLevels(state, signedDigit, rodIndex)
        : _subtractionLevels(state, -signedDigit, rodIndex);
  }

  /// Builds the [CheckpointPlan] for one signed digit: one group per level,
  /// each carrying the rod values that must hold once that level is finished.
  CheckpointPlan? planForDigit({
    required SorobanState state,
    required int signedDigit,
    required int rodIndex,
  }) {
    final levels = calculateDigitMoveLevels(state, signedDigit, rodIndex);
    if (levels.every((level) => level.isEmpty)) return null;
    return buildPlanFromLevels(startState: state, levels: levels);
  }

  /// Turns ordered move levels into a [CheckpointPlan].
  ///
  /// [startState] is replayed level by level so each group records the value its
  /// rods end up at — the same values the engine's own ripple produced, so the
  /// plan's [CheckpointPlan.finalTargetValue] is a genuine consequence of the
  /// grouping rather than a number copied in by hand.
  CheckpointPlan buildPlanFromLevels({
    required SorobanState startState,
    required List<List<BeadMove>> levels,
  }) {
    var running = startState;
    final groups = <MoveGroup>[];

    for (final level in levels) {
      if (level.isEmpty) continue;
      final rods = <int>{};
      final targets = <int, int>{};
      for (final move in level) {
        running = applyMove(running, move);
        rods.add(move.rodIndex);
        targets[move.rodIndex] = running.rods[move.rodIndex].value;
      }
      groups.add(MoveGroup(rods, targets));
    }

    return CheckpointPlan(groups: groups, finalTargetValue: running.value);
  }

  /// Plan for a multiplication partial product, which may touch more than one
  /// rod: one group per changed rod, highest place value first.
  ///
  /// A rod can always be set directly, so absolute per-rod targets stay sound
  /// even when the tens and units computations interact — and they do interact.
  /// For `4 x 6 = 24` applied when the units rod already holds 7, adding the 4
  /// units carries 1 into the tens rod, so the two computations are not
  /// independent. Splitting by changed rod keeps every rod in exactly one group
  /// (a hard requirement of [CheckpointPlan]) without inventing a dependency
  /// that does not exist.
  CheckpointPlan planForPartialProduct({
    required SorobanState startState,
    required SorobanState endState,
  }) {
    assert(
      startState.rods.length == endState.rods.length,
      'partial product must not change the rod count',
    );

    final changed = <int>[];
    for (var i = 0; i < startState.rods.length; i++) {
      if (startState.rods[i].value != endState.rods[i].value) changed.add(i);
    }

    final groups = [
      // Descending rod index = highest place value first (tens/carry rods
      // before the units rod), which is the sequential order the spec picked.
      for (final rodIndex in changed.reversed)
        MoveGroup.single(rodIndex, endState.rods[rodIndex].value),
    ];

    return CheckpointPlan(groups: groups, finalTargetValue: endState.value);
  }

  static BeadMove _heavenMove({
    required int rodIndex,
    required int from,
    required int to,
  }) {
    final description = to == 5
        ? 'Rod $rodIndex: Turunkan manik langit (+5)'
        : 'Rod $rodIndex: Naikkan manik langit (-5)';
    return BeadMove(
      rodIndex: rodIndex,
      kind: BeadKind.heaven,
      from: from,
      to: to,
      description: description,
    );
  }

  static BeadMove _earthMove({
    required int rodIndex,
    required int from,
    required int to,
  }) {
    return BeadMove(
      rodIndex: rodIndex,
      kind: BeadKind.earth,
      from: from,
      to: to,
      description: 'Rod $rodIndex: Manik bumi $from -> $to',
    );
  }

  /// The bead flicks that take one rod from its current value to [targetVal],
  /// always heaven first, then the earth beads.
  ///
  /// This is the whole per-rod step: no recursion, no neighbouring rod. A rod
  /// can always be driven to any 0..9 value this way, which is why plans store
  /// final per-rod targets instead of a required flick order.
  List<BeadMove> _rodMoves(
    int rodIndex,
    int targetVal,
    Rod currentRod,
  ) {
    final moves = <BeadMove>[];
    final targetHeaven = targetVal >= 5;
    final targetEarth = targetVal % 5;

    if (!currentRod.heaven && targetHeaven) {
      moves.add(_heavenMove(rodIndex: rodIndex, from: 0, to: 5));
    } else if (currentRod.heaven && !targetHeaven) {
      moves.add(_heavenMove(rodIndex: rodIndex, from: 5, to: 0));
    }

    if (currentRod.earth != targetEarth) {
      moves.add(_earthMove(
        rodIndex: rodIndex,
        from: currentRod.earth,
        to: targetEarth,
      ));
    }

    return moves;
  }

  /// Adding [d] (1..9) to rod [rodIndex], as recursion levels.
  ///
  /// When the addition overflows, the carry is resolved one rod up *first*, so
  /// that level is emitted before this rod's own level.
  List<List<BeadMove>> _additionLevels(
    SorobanState state,
    int d,
    int rodIndex,
  ) {
    final currentRod = state.rods[rodIndex];
    final v = currentRod.value;
    final levels = <List<BeadMove>>[];

    if (v + d < 10) {
      levels.add(_rodMoves(rodIndex, v + d, currentRod));
      return levels;
    }

    // Carry required. Traditional Soroban: execute the carry into the next rod
    // first, then settle this rod on the wrapped value.
    levels.addAll(_additionLevels(state, 1, rodIndex + 1));
    levels.add(_rodMoves(rodIndex, v + d - 10, currentRod));
    return levels;
  }

  /// Subtracting [d] (1..9) from rod [rodIndex], as recursion levels.
  ///
  /// Mirror image of [_additionLevels]: the borrow is taken from the next rod
  /// before this rod is wrapped up.
  List<List<BeadMove>> _subtractionLevels(
    SorobanState state,
    int d,
    int rodIndex,
  ) {
    final currentRod = state.rods[rodIndex];
    final v = currentRod.value;
    final levels = <List<BeadMove>>[];

    if (v >= d) {
      levels.add(_rodMoves(rodIndex, v - d, currentRod));
      return levels;
    }

    // Borrow needed: take 1 from the next rod up, then wrap this rod to
    // v + 10 - d.
    levels.addAll(_subtractionLevels(state, 1, rodIndex + 1));
    levels.add(_rodMoves(rodIndex, v + 10 - d, currentRod));
    return levels;
  }

  /// Decomposes [termValue] into digit-group checkpoints (from highest place value to lowest).
  /// Generates a list of [DigitCheckpoint]s updating [startingState] progressively.
  List<DigitCheckpoint> generateCheckpointsForTerm({
    required SorobanState startingState,
    required int termValue,
    required bool isAddition,
    required int termIndex,
    String Function(int signedVal, int rodIndex)? labelBuilder,
  }) {
    final checkpoints = <DigitCheckpoint>[];
    if (termValue == 0) return checkpoints;

    final termStr = termValue.abs().toString();
    final totalDigits = termStr.length;
    SorobanState runningState = startingState;

    for (int i = 0; i < totalDigits; i++) {
      final digitChar = termStr[i];
      final digit = int.parse(digitChar);
      if (digit == 0) continue;

      final rodIndex = totalDigits - 1 - i;
      final signedDigit = isAddition ? digit : -digit;
      final levels = calculateDigitMoveLevels(runningState, signedDigit, rodIndex);
      final plan = buildPlanFromLevels(startState: runningState, levels: levels);
      final moves = [for (final level in levels) ...level];
      final prevState = runningState;
      runningState = applyMoves(runningState, moves);

      final multiplier = _pow10(rodIndex);
      final signedVal = signedDigit * multiplier;
      final label = labelBuilder != null
          ? labelBuilder(signedVal, rodIndex)
          : (isAddition ? '+$signedVal' : '$signedVal');

      checkpoints.add(DigitCheckpoint(
        targetValue: runningState.value,
        previousValue: prevState.value,
        termIndex: termIndex,
        digitIndex: i,
        rodIndex: rodIndex,
        atomicMoves: moves,
        plan: plan,
        label: label,
      ));
    }

    return checkpoints;
  }

  int _pow10(int exp) {
    int res = 1;
    for (int i = 0; i < exp; i++) {
      res *= 10;
    }
    return res;
  }
}
