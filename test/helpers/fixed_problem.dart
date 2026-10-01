import 'dart:math';

import 'package:soroban_app/core/engine/addition_engine.dart';
import 'package:soroban_app/core/engine/multiplication_engine.dart';
import 'package:soroban_app/core/engine/problem_generator.dart';
import 'package:soroban_app/core/models/bead_move.dart';
import 'package:soroban_app/core/models/problem.dart';
import 'package:soroban_app/core/models/soroban_state.dart';
import 'package:soroban_app/core/state/soroban_controller.dart';

/// Checkpoints for a sum of [terms], added in the order given.
List<DigitCheckpoint> checkpointsForSum(
  List<int> terms, {
  int rodCount = 7,
}) {
  final engine = const AdditionEngine();
  var running = SorobanState.zero(rodCount: rodCount);
  final checkpoints = <DigitCheckpoint>[];

  for (var i = 0; i < terms.length; i++) {
    final produced = engine.generateCheckpointsForTerm(
      startingState: running,
      termValue: terms[i],
      isAddition: true,
      termIndex: i,
    );
    checkpoints.addAll(produced);
    running = SorobanState.fromValue(
      produced.last.targetValue,
      rodCount: rodCount,
    );
  }

  return checkpoints;
}

/// Checkpoints for a mixed sequence, so a test can reach shapes the random
/// generators do not produce on demand — notably a mixed sum, whose target
/// values are neither ascending nor unique.
List<DigitCheckpoint> checkpointsForSequence(
  List<(int, bool)> signedTerms, {
  int rodCount = 7,
}) {
  final engine = const AdditionEngine();
  var running = SorobanState.zero(rodCount: rodCount);
  final checkpoints = <DigitCheckpoint>[];

  for (var i = 0; i < signedTerms.length; i++) {
    final (term, isAddition) = signedTerms[i];
    final produced = engine.generateCheckpointsForTerm(
      startingState: running,
      termValue: term,
      isAddition: isAddition,
      termIndex: i,
    );
    checkpoints.addAll(produced);
    running = SorobanState.fromValue(
      produced.last.targetValue,
      rodCount: rodCount,
    );
  }

  return checkpoints;
}

/// Problem generator that always produces the same sum, so a test can write the
/// expected checkpoint values down instead of deriving them from randomness.
class FixedSumProblemGenerator extends ProblemGenerator {
  FixedSumProblemGenerator(this.terms) : super(random: Random(0));

  final List<int> terms;

  @override
  Problem generateProblem({
    required ProblemCategory category,
    required Difficulty difficulty,
    int rodCount = 7,
  }) {
    return problemFromCheckpoints(
      checkpointsForSum(terms, rodCount: rodCount),
      terms: terms,
      operators: List.filled(terms.length - 1, '+'),
      category: category,
      difficulty: difficulty,
      rodCount: rodCount,
    );
  }
}

/// Problem generator that returns exactly the checkpoints it was handed.
class FixedCheckpointsProblemGenerator extends ProblemGenerator {
  FixedCheckpointsProblemGenerator(
    this.checkpoints, {
    this.terms = const [],
  }) : super(random: Random(0));

  final List<DigitCheckpoint> checkpoints;
  final List<int> terms;

  @override
  Problem generateProblem({
    required ProblemCategory category,
    required Difficulty difficulty,
    int rodCount = 7,
  }) {
    return problemFromCheckpoints(
      checkpoints,
      terms: terms,
      operators: const [],
      category: category,
      difficulty: difficulty,
      rodCount: rodCount,
    );
  }
}

/// Problem generator for `multiplicand × multiplier`, built the way the app
/// builds one: the operands as terms and the canonical chain from
/// [MultiplicationEngine] as checkpoints. The requested category is ignored,
/// because a multiplication is not free to be anything else.
class FixedProductProblemGenerator extends ProblemGenerator {
  FixedProductProblemGenerator(this.multiplicand, this.multiplier)
      : super(random: Random(0));

  final int multiplicand;
  final int multiplier;

  ProblemCategory get problemCategory => multiplier < 10
      ? ProblemCategory.multiplication1
      : ProblemCategory.multiplication2;

  @override
  Problem generateProblem({
    required ProblemCategory category,
    required Difficulty difficulty,
    int rodCount = 7,
  }) {
    return Problem(
      category: problemCategory,
      difficulty: difficulty,
      terms: [multiplicand, multiplier],
      operators: const ['x'],
      expectedResult: multiplicand * multiplier,
      checkpoints: const MultiplicationEngine().generateCheckpoints(
        multiplicand: multiplicand,
        multiplier: multiplier,
        rodCount: rodCount,
      ),
    );
  }
}

Problem problemFromCheckpoints(
  List<DigitCheckpoint> checkpoints, {
  required List<int> terms,
  required List<String> operators,
  required ProblemCategory category,
  required Difficulty difficulty,
  int rodCount = 7,
}) {
  return Problem(
    category: category,
    difficulty: difficulty,
    terms: terms,
    operators: operators,
    expectedResult:
        checkpoints.isEmpty ? 0 : checkpoints.last.targetValue,
    checkpoints: checkpoints,
  );
}

/// Controller already running the problem [generator] produces.
SorobanController controllerFor(ProblemGenerator generator) {
  final controller = SorobanController(generator: generator);
  controller.startPracticeProblem(ProblemCategory.addition, Difficulty.easy);
  return controller;
}

/// Controller on `multiplicand × multiplier`, e.g. `controllerForProduct(123, 3)`.
SorobanController controllerForProduct(int multiplicand, int multiplier) {
  final generator = FixedProductProblemGenerator(multiplicand, multiplier);
  final controller = SorobanController(generator: generator);
  controller.startPracticeProblem(generator.problemCategory, Difficulty.easy);
  return controller;
}

/// Controller on a sum of [terms], e.g. `controllerForSum([4, 5])`.
SorobanController controllerForSum(List<int> terms) =>
    controllerFor(FixedSumProblemGenerator(terms));

/// Drives one rod to an absolute value with heaven/earth flicks.
///
/// The user's hands, not a plan: this is the same thing a finger does on a
/// physical abacus, and it may touch any rod at any time.
void setRodValue(SorobanController controller, int rodIndex, int value) {
  final rod = controller.state.rods[rodIndex];
  if (rod.heaven != (value >= 5)) controller.tapHeavenBead(rodIndex);
  final earth = value % 5;
  if (rod.earth != earth) controller.tapEarthBead(rodIndex, earth);
}

/// Puts the whole board on [value], rod by rod, and ends the gesture: a hand
/// that lands on a number without stopping anywhere on the way.
void setBoardValue(SorobanController controller, int value) {
  var remaining = value;
  for (var rod = 0; rod < controller.state.rods.length; rod++) {
    setRodValue(controller, rod, remaining % 10);
    remaining ~/= 10;
  }
  controller.onGestureSettled();
}

/// Commits [moves] and then ends the gesture, as a physical one would.
void performGesture(
  SorobanController controller,
  List<BeadMove> moves,
) {
  for (final move in moves) {
    if (move.kind == BeadKind.heaven) {
      controller.tapHeavenBead(move.rodIndex);
    } else {
      controller.tapEarthBead(move.rodIndex, move.to);
    }
  }
  controller.onGestureSettled();
}

/// Commits one whole checkpoint as a single gesture.
void performCheckpointGesture(
  SorobanController controller,
  DigitCheckpoint checkpoint,
) {
  performGesture(controller, checkpoint.atomicMoves);
}
