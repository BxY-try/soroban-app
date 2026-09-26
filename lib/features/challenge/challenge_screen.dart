import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/problem.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';
import '../settings/settings_screen.dart';
import '../soroban_widget/soroban_layout.dart';
import '../soroban_widget/soroban_view.dart';
import 'result_screen.dart';

/// The core exercise & challenge screen.
/// Implements the compact landscape layout:
/// - Top strip: Back button (left), Centered Problem text (center), Settings (right).
/// - Main area: Left panel (problem number, timer, reset) + Central Soroban.
class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key});

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  /// Scale factor for the main interactive challenge area (left controls + Soroban)
  /// to provide gentle breathing room towards the center without shrinking excessively.
  static const double groupScale = 0.98;

  /// Scale factor for the Soroban itself inside the main area, so the abacus
  /// reads slightly larger than the surrounding chrome while keeping safe margins.
  static const double sorobanScale = 0.992;

  /// Lifts the whole Soroban block (abacus frame + digital readout) upward by this
  /// many pixels so the space below it is no longer cramped.
  ///
  /// Applied as a paint transform on purpose: the box keeps the exact layout
  /// constraints it had before, so the frame dimensions and the bead size are
  /// untouched — unlike a bottom/top padding change, which would take the height
  /// away from the abacus and shrink the beads.
  static const double sorobanLift = 5.0;

  /// Extra bead travel (px) granted to each deck, widening the heaven↔beam and
  /// beam↔earth gaps at the cost of bead height.
  ///
  /// Sized so the beads land at ~8% above the pre-scale-bump baseline (the
  /// bigger scale requested in 457418a would otherwise inflate them by ~10%,
  /// because the vertical budget is exactly saturated). Practice mode keeps the
  /// default 0.0 and is therefore unaffected.
  static const double sorobanTravelBoost = 3.92;

  // ── Main area layout chain ─────────────────────────────────────────
  // These four values define how the Soroban is positioned horizontally.
  // They are used BOTH by the layout chain itself and by [_abacusFrameFor], so
  // the problem text can be centred on the abacus without duplicating numbers.

  /// Horizontal padding around the whole left-panel + Soroban group.
  static const double _groupHorizontalPadding = 10.0;

  /// Fixed width of the left control panel.
  static const double _leftPanelWidth = 56.0;

  /// Gap between the left control panel and the Soroban.
  static const double _leftPanelGap = 12.0;

  /// Margin kept between the problem text and the right screen edge.
  static const double _problemTextRightInset = 10.0;

  /// Horizontal geometry of the painted Soroban for a content area
  /// [contentWidth] px wide.
  ///
  /// Mirrors, value for value, the layout chain that positions the SorobanView:
  /// group padding, [groupScale] on the whole group, the fixed left panel plus
  /// [_leftPanelGap], then [sorobanScale] on the Soroban itself.
  ///
  /// Both the layout chain and this function read the constants above, and
  /// `widget_test.dart` asserts the problem text lands on the *actually laid out*
  /// frame centre at several screen sizes. That assertion is the drift guard: if
  /// the chain ever changes shape, the text follows this function instead of the
  /// real box, and that test fails.
  ///
  /// [frameCenter] is the centre of the *painted frame*, which is NOT the centre
  /// of the box whenever the left and right gutters differ. That is exactly the
  /// value the problem text should sit on.
  static ({double left, double width, double frameCenter}) _abacusFrameFor(
    double contentWidth,
  ) {
    final avail = contentWidth - 2 * _groupHorizontalPadding;
    final groupWidth = avail * groupScale;
    final groupLeft = _groupHorizontalPadding + (avail - groupWidth) / 2;

    final slotWidth = groupWidth - _leftPanelWidth - _leftPanelGap;
    final boxWidth = slotWidth > 0.0 ? slotWidth * sorobanScale : 0.0;
    final boxLeft = groupLeft + _leftPanelWidth + _leftPanelGap +
        (slotWidth - boxWidth) / 2;

    // The frame is inset by the SorobanLayout gutters, which may be asymmetric.
    final gutters = SorobanLayout.guttersFor(boxWidth);
    final frameCenter =
        boxLeft + boxWidth / 2 + (gutters.left - gutters.right) / 2;

    return (left: boxLeft, width: boxWidth, frameCenter: frameCenter);
  }

  /// Left inset of the problem text band that centres it on the abacus frame
  /// while keeping [_problemTextRightInset] free on the right.
  ///
  /// With symmetric gutters this returns the historical 78.0 exactly, so turning
  /// both gutter scales to 1.0 restores the previous layout bit for bit.
  static double _problemTextLeftFor(double contentWidth) {
    return 2 * _abacusFrameFor(contentWidth).frameCenter -
        contentWidth +
        _problemTextRightInset;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SorobanController>();

    // If challenge just completed, push ResultScreen
    if (controller.isChallengeMode && controller.isChallengeCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ResultScreen()),
        );
      });
    }

    return PopScope(
      canPop: !controller.isChallengeMode || controller.isChallengeCompleted,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExit(context, controller);
      },
      child: Scaffold(
        backgroundColor: SorobanTheme.backgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              // Top Row: Back button (matching SettingsScreen exact position), Problem Text (aligned with Soroban), Settings button
              _buildTopRow(context, controller),

              const SizedBox(height: 4),

              // Main Interactive Group: Left controls (SOAL, Timer, Reset) + Central Soroban View
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _groupHorizontalPadding,
                    vertical: 2.0,
                  ),
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: groupScale,
                      heightFactor: groupScale,
                      child: Row(
                        children: [
                          _buildLeftPanel(context, controller),

                          const SizedBox(width: _leftPanelGap),

                          // Central Soroban View. It is centred inside this slot;
                          // the problem text above is what chases the painted
                          // frame centre, not the other way round.
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 2.0),
                              child: Center(
                                child: Transform.translate(
                                  offset: const Offset(0, -sorobanLift),
                                  child: const FractionallySizedBox(
                                    widthFactor: sorobanScale,
                                    heightFactor: sorobanScale,
                                    child: AspectRatio(
                                      aspectRatio: 2.05,
                                      child: SorobanView(
                                        travelBoost: sorobanTravelBoost,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmExit(BuildContext context, SorobanController controller) async {
    if (!controller.isChallengeMode || controller.isChallengeCompleted) {
      if (context.mounted) Navigator.of(context).pop();
      return;
    }

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SorobanTheme.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Tinggalkan Tantangan?',
          style: TextStyle(
            color: SorobanTheme.textDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Waktu dan progres tantangan yang sedang berjalan akan dibatalkan.',
          style: TextStyle(color: SorobanTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Lanjut Main',
              style: TextStyle(color: SorobanTheme.beadDefaultColor, fontWeight: FontWeight.bold),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SorobanTheme.frameColor,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (shouldLeave == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Top row in main area:
  /// - Left: Back button staying in exact SettingsScreen position (left: 4.0, center: 28.0)
  /// - Right: Settings button staying at initial top-right corner (right: 10.0)
  /// - Center: Problem text horizontally aligned with Soroban center axis (W / 2 + 34.0)
  Widget _buildTopRow(BuildContext context, SorobanController controller) {
    return SizedBox(
      height: 48,
      child: Stack(
        children: [
          // 1. Back button matching SettingsScreen exact position (left: 4.0, center: 28.0)
          Positioned(
            left: 4.0,
            top: 0,
            bottom: 0,
            child: Center(
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: SorobanTheme.frameColor,
                ),
                tooltip: 'Kembali ke App',
                onPressed: () => _confirmExit(context, controller),
              ),
            ),
          ),

          // 2. Settings button staying in initial top-right corner
          Positioned(
            right: 10.0,
            top: 0,
            bottom: 0,
            child: Center(
              child: IconButton(
                icon: const Icon(Icons.settings_outlined, size: 22),
                tooltip: 'Pengaturan',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ),
          ),

          // 3. Problem text centred on the Soroban FRAME centre.
          //
          // The frame centre is not the box centre when the left and right
          // frame gutters differ, so the band is derived from
          // _problemTextLeftFor instead of a hard-coded 78.0. With symmetric
          // gutters that helper returns 78.0 again, so this is a no-op then.
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: EdgeInsets.only(
                  left: _problemTextLeftFor(constraints.maxWidth),
                  right: _problemTextRightInset,
                ),
                child: Center(child: _buildProblemText(controller)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Displays the mathematical problem equation, centered to the Soroban with dynamic font sizing
  /// and faded visual feedback for completed checkpoint digits.
  Widget _buildProblemText(SorobanController controller) {
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
    );

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Text.rich(
        key: const Key('challenge_problem_text'),
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
  }) {
    final spans = <InlineSpan>[];

    if (problem.category == ProblemCategory.multiplication1 ||
        problem.category == ProblemCategory.multiplication2) {
      if (problem.terms.length >= 2) {
        // Multiplicand (term 0)
        final aStr = problem.terms[0].abs().toString();
        for (int d = 0; d < aStr.length; d++) {
          final isDone = _isDigitCompleted(
            problem: problem,
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
      if (termIndex == 0) {
        // Multiplicand digit: completed if all checkpoints for this digit have been completed
        final hasRemaining = problem.checkpoints
            .asMap()
            .entries
            .any((e) => e.value.digitIndex == digitIndex && e.key >= activeCheckpointIndex);
        return !hasRemaining;
      } else {
        // Multiplier digit: completed if all checkpoints for this multiplier digit have been completed
        final hasRemaining = problem.checkpoints
            .asMap()
            .entries
            .any((e) => e.value.termIndex == digitIndex && e.key >= activeCheckpointIndex);
        return !hasRemaining;
      }
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
    if (lastCompleted.termIndex == termIndex && lastCompleted.digitIndex > digitIndex) {
      return true;
    }

    return false;
  }

  /// Left panel containing the interactive badges and reset button:
  /// 1. Badge posisi soal ("SOAL 1/5")
  /// 2. Badge waktu ("00:12") dengan jarak napas yang ditambah lebih lega (18px)
  /// 3. Spacer mendorong tombol Reset ke bawah
  /// 4. Tombol Reset dinaikkan lagi (bottom padding 44px)
  Widget _buildLeftPanel(BuildContext context, SorobanController controller) {
    const panelWidth = _leftPanelWidth;
    return SizedBox(
      width: panelWidth,
      child: Column(
        children: [
          const SizedBox(height: 12),

          // 1. Problem progress indicator (e.g. [SOAL 1/5])
          if (controller.isChallengeMode) ...[
            Container(
              width: panelWidth,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: SorobanTheme.frameColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: SorobanTheme.frameColor.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'SOAL',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: SorobanTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${controller.challengeIndex + 1}/${controller.totalChallengeProblems}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: SorobanTheme.textDark,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18), // Tambah jarak di antara mereka dikit lagi

            // 2. Timer info
            Container(
              width: panelWidth,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: SorobanTheme.frameColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: SorobanTheme.frameColor.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    size: 15,
                    color: SorobanTheme.textMuted,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _formatTime(controller.elapsedMilliseconds),
                    style: SorobanTheme.timerStyle.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

          // 3. Reset / Retri button, dinaikkan lebih tinggi lagi (bottom padding 44px)
          Padding(
            padding: const EdgeInsets.only(bottom: 44.0),
            child: _buildResetButton(controller, panelWidth),
          ),
        ],
      ),
    );
  }

  /// Compact Reset / Retri button (↺) positioned in the left panel
  Widget _buildResetButton(SorobanController controller, double width) {
    final enabled = controller.canReset;
    return Tooltip(
      message: 'Retri (Kembali ke checkpoint sebelumnya)',
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        color: enabled ? SorobanTheme.frameColor : Colors.grey.shade400,
        borderRadius: BorderRadius.circular(8),
        elevation: enabled ? 1 : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? () => controller.executeReset() : null,
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.restart_alt_rounded,
                  size: 18,
                  color: SorobanTheme.backgroundColor,
                ),
                SizedBox(height: 1),
                Text(
                  'Reset',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: SorobanTheme.backgroundColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final minStr = minutes.toString().padLeft(2, '0');
    final secStr = seconds.toString().padLeft(2, '0');
    return '$minStr:$secStr';
  }
}
