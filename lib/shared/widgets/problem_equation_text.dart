import 'package:flutter/material.dart';

import '../../core/models/problem.dart';
import '../../core/state/soroban_controller.dart';
import '../theme.dart';

/// The problem equation rendered with per-digit dimmed feedback for completed
/// checkpoints.
///
/// Shared by the Challenge and Practice screens so both modes render the
/// equation identically: same dynamic font sizing, same completed-digit
/// styling, same centring behaviour. The host screen centres the widget on
/// the abacus frame (see `ExerciseLayout.problemTextLeftFor`); when the
/// equation outgrows its band the [FittedBox] shrinks it down instead of
/// moving it, so the equation's centre always stays on the frame centre.
class ProblemEquationText extends StatelessWidget {
  const ProblemEquationText({
    super.key,
    required this.controller,
    this.textKey,
  });

  final SorobanController controller;

  /// Key applied to the inner [Text] widget. Hosts that are located in tests
  /// (e.g. the challenge screen's `Key('challenge_problem_text')`) keep their
  /// historical key here.
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final problem = controller.currentProblem;
    if (problem == null) return const SizedBox.shrink();

    final displayText = problem.displayText;
    final length = displayText.length;

    // Dynamic font sizing based on equation length:
    final double fontSize;
    if (length <= 8) {
      fontSize = 25.0;
    } else if (length <= 14) {
      fontSize = 22.0;
    } else if (length <= 20) {
      fontSize = 19.0;
    } else {
      fontSize = 17.0;
    }

    final activeCpIdx = controller.activeCheckpointIndex;
    final textSpans = _buildProblemTextSpans(
      problem: problem,
      activeCheckpointIndex: activeCpIdx,
      fontSize: fontSize,
      controller: controller,
    );

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text.rich(
        key: textKey,
        TextSpan(
          style: SorobanTheme.problemEquationStyle(fontSize: fontSize),
          children: textSpans,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  List<InlineSpan> _buildProblemTextSpans({
    required Problem problem,
    required int activeCheckpointIndex,
    required double fontSize,
    required SorobanController controller,
  }) {
    final spans = <InlineSpan>[];

    if (problem.division != null) {
      final complete = activeCheckpointIndex >= problem.checkpoints.length;
      return [
        TextSpan(
          text: problem.displayText,
          style: complete
              ? SorobanTheme.problemEquationCompletedStyle(fontSize: fontSize)
              : SorobanTheme.problemEquationStyle(fontSize: fontSize),
        )
      ];
    }

    if (problem.category == ProblemCategory.multiplication1 ||
        problem.category == ProblemCategory.multiplication2) {
      if (problem.terms.length >= 2) {
        // Multiplicand (term 0)
        final aStr = problem.terms[0].abs().toString();
        for (int d = 0; d < aStr.length; d++) {
          final isDone = _isDigitCompleted(
            problem: problem,
            controller: controller,
            activeCheckpointIndex: activeCheckpointIndex,
            termIndex: 0,
            digitIndex: d,
          );
          spans.add(TextSpan(
            text: aStr[d],
            style: isDone
                ? SorobanTheme.problemEquationCompletedStyle(fontSize: fontSize)
                : SorobanTheme.problemEquationStyle(fontSize: fontSize),
          ));
        }

        // Operator
        spans.add(TextSpan(
          text: ' × ',
          style: SorobanTheme.problemEquationStyle(fontSize: fontSize),
        ));

        // Multiplier (term 1)
        final bStr = problem.terms[1].abs().toString();
        for (int d = 0; d < bStr.length; d++) {
          final isDone = _isDigitCompleted(
            problem: problem,
            controller: controller,
            activeCheckpointIndex: activeCheckpointIndex,
            termIndex: 1,
            digitIndex: d,
          );
          spans.add(TextSpan(
            text: bStr[d],
            style: isDone
                ? SorobanTheme.problemEquationCompletedStyle(fontSize: fontSize)
                : SorobanTheme.problemEquationStyle(fontSize: fontSize),
          ));
        }
      }
      return spans;
    }

    // Addition & Mixed: terms separated by operators
    for (int t = 0; t < problem.terms.length; t++) {
      if (t > 0 && t - 1 < problem.operators.length) {
        spans.add(TextSpan(
          text: ' ${problem.operators[t - 1]} ',
          style: SorobanTheme.problemEquationStyle(fontSize: fontSize),
        ));
      }

      final termStr = problem.terms[t].abs().toString();
      for (int d = 0; d < termStr.length; d++) {
        final isDone = _isDigitCompleted(
          problem: problem,
          controller: controller,
          activeCheckpointIndex: activeCheckpointIndex,
          termIndex: t,
          digitIndex: d,
        );
        spans.add(TextSpan(
          text: termStr[d],
          style: isDone
              ? SorobanTheme.problemEquationCompletedStyle(fontSize: fontSize)
              : SorobanTheme.problemEquationStyle(fontSize: fontSize),
        ));
      }
    }

    return spans;
  }

  bool _isDigitCompleted({
    required Problem problem,
    required SorobanController controller,
    required int activeCheckpointIndex,
    required int termIndex,
    required int digitIndex,
  }) {
    if (activeCheckpointIndex <= 0) {
      return false;
    }
    if (activeCheckpointIndex >= problem.checkpoints.length) {
      return true;
    }

    if (problem.category == ProblemCategory.multiplication1 ||
        problem.category == ProblemCategory.multiplication2) {
      // Which contributions the board holds is the controller's call, not a
      // position in the canonical chain: the user may have worked in any order.
      return controller.isMultiplicationDigitCompleted(
        termIndex: termIndex,
        digitIndex: digitIndex,
      );
    }

    // Addition & Mixed:
    // 1. Direct match with any completed checkpoint:
    for (int k = 0; k < activeCheckpointIndex; k++) {
      final cp = problem.checkpoints[k];
      if (cp.termIndex == termIndex && cp.digitIndex == digitIndex) {
        return true;
      }
    }

    // 2. If this digit didn't generate a checkpoint (e.g. '0'):
    final lastCompleted = problem.checkpoints[activeCheckpointIndex - 1];
    if (lastCompleted.termIndex > termIndex) return true;
    if (lastCompleted.termIndex == termIndex &&
        lastCompleted.digitIndex > digitIndex) {
      return true;
    }

    return false;
  }
}
