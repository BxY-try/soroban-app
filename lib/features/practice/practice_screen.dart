import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/problem.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';
import '../settings/settings_screen.dart';
import '../soroban_widget/soroban_view.dart';

/// Free-play Practice Mode (Mode Latihan Bebas):
/// - No timer, no pressure.
/// - Switch categories & difficulty on the fly.
/// - Full-digit chained hints, replay, and reset controls.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  ProblemCategory _selectedCategory = ProblemCategory.addition;
  Difficulty _selectedDifficulty = Difficulty.easy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<SorobanController>();
      controller.startPracticeProblem(_selectedCategory, _selectedDifficulty);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SorobanController>();
    final problem = controller.currentProblem;

    return Scaffold(
      backgroundColor: SorobanTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: Column(
            children: [
              // Top Strip (Stack-based, back button matches SettingsScreen position)
              _buildTopStrip(context, controller, problem),

              const SizedBox(height: 4),

              // Big Soroban Focal Point (Scaled slightly for elegant margins)
              const Expanded(
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.94,
                    heightFactor: 0.94,
                    child: AspectRatio(
                      aspectRatio: 2.05,
                      child: SorobanView(),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 4),

              // Compact Bottom Strip: 3 Icon-only buttons
              SizedBox(
                height: 36,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 1. Reset / Retri
                    _buildControlButton(
                      icon: Icons.restart_alt_rounded,
                      tooltip: 'Retri (Kembali ke checkpoint sebelumnya)',
                      enabled: controller.canReset,
                      onPressed: () => controller.executeReset(),
                    ),
                    const SizedBox(width: 20),

                    // 2. Hint
                    _buildControlButton(
                      icon: Icons.lightbulb_rounded,
                      tooltip: 'Hint digit berikutnya',
                      isPrimary: true,
                      enabled: !controller.isAnimating &&
                          problem != null &&
                          controller.activeCheckpointIndex < problem.checkpoints.length,
                      onPressed: () => controller.executeHint(),
                    ),
                    const SizedBox(width: 20),

                    // 3. Replay Hint
                    _buildControlButton(
                      icon: Icons.repeat_rounded,
                      tooltip: 'Replay Hint (Putar ulang animasi langkah digit ini)',
                      enabled: controller.canReplay,
                      onPressed: () => controller.executeReplay(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Top strip with Stack-based layout:
  /// - Back button at exact SettingsScreen position (left: 4.0)
  /// - Dropdowns, problem text, next & settings buttons in the remaining area
  Widget _buildTopStrip(BuildContext context, SorobanController controller, Problem? problem) {
    return SizedBox(
      height: 48,
      child: Stack(
        children: [
          // 1. Back button matching SettingsScreen exact position (left: 4.0)
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
                tooltip: 'Kembali',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),

          // 2. Controls: dropdowns + problem text + action buttons
          Positioned(
            left: 52.0,
            right: 0,
            top: 0,
            bottom: 0,
            child: Row(
              children: [
                // Category dropdown (compact)
                DropdownButton<ProblemCategory>(
                  value: _selectedCategory,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(fontSize: 13, color: SorobanTheme.textDark),
                  items: const [
                    DropdownMenuItem(
                      value: ProblemCategory.addition,
                      child: Text('Penjumlahan', style: TextStyle(fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: ProblemCategory.mixed,
                      child: Text('Campuran (+/-)', style: TextStyle(fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: ProblemCategory.multiplication1,
                      child: Text('Perkalian I', style: TextStyle(fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: ProblemCategory.multiplication2,
                      child: Text('Perkalian II', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                  onChanged: (cat) {
                    if (cat != null) {
                      setState(() => _selectedCategory = cat);
                      controller.startPracticeProblem(cat, _selectedDifficulty);
                    }
                  },
                ),

                const SizedBox(width: 6),

                // Difficulty dropdown (compact)
                DropdownButton<Difficulty>(
                  value: _selectedDifficulty,
                  underline: const SizedBox.shrink(),
                  style: const TextStyle(fontSize: 13, color: SorobanTheme.textDark),
                  items: const [
                    DropdownMenuItem(value: Difficulty.easy, child: Text('Easy', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: Difficulty.medium, child: Text('Medium', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: Difficulty.hard, child: Text('Hard', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (diff) {
                    if (diff != null) {
                      setState(() => _selectedDifficulty = diff);
                      controller.startPracticeProblem(_selectedCategory, diff);
                    }
                  },
                ),

                const SizedBox(width: 8),

                // Problem Display (Outfit font with per-digit dimmed, matching Challenge)
                if (problem != null)
                  Expanded(child: _buildProblemText(controller))
                else
                  const Spacer(),

                // Next problem button
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, size: 28),
                  tooltip: 'Soal Berikutnya',
                  onPressed: () {
                    controller.startPracticeProblem(_selectedCategory, _selectedDifficulty);
                  },
                ),

                // Settings button
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 24),
                  tooltip: 'Pengaturan',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Displays the mathematical problem equation with dynamic font sizing
  /// and faded visual feedback for completed checkpoint digits (identical to Challenge mode).
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

  Widget _buildControlButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        color: isPrimary
            ? (enabled ? SorobanTheme.beadActiveColor : Colors.grey.shade400)
            : (enabled ? SorobanTheme.frameColor : Colors.grey.shade400),
        borderRadius: BorderRadius.circular(18),
        elevation: enabled ? (isPrimary ? 2 : 1) : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: enabled ? onPressed : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Icon(
              icon,
              size: 18,
              color: isPrimary ? SorobanTheme.frameColor : SorobanTheme.backgroundColor,
            ),
          ),
        ),
      ),
    );
  }
}
