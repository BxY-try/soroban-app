import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';
import '../settings/settings_screen.dart';
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
            child: Column(
              children: [
                // 1. Top Strip
                _buildTopStrip(context, controller),

                const SizedBox(height: 4),

                // 2. Main Area: Left panel + Soroban focal point
                Expanded(
                  child: Row(
                    children: [
                      // Left Panel (underneath "Kembali ke App" button)
                      _buildLeftPanel(context, controller),

                      const SizedBox(width: 12),

                      // Soroban Focal Point (Enlarged and shifted towards right with safe margin)
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: 8.0, right: 18.0, bottom: 2.0),
                          child: Align(
                            alignment: Alignment(0.40, 0.0),
                            child: AspectRatio(
                              aspectRatio: 2.05,
                              child: SorobanView(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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

  /// Top strip:
  /// - Left: Back button ("Kembali ke App")
  /// - Center: Centered problem equation
  /// - Right: Settings button
  Widget _buildTopStrip(BuildContext context, SorobanController controller) {
    const leftPanelWidth = 56.0;
    return SizedBox(
      height: 38,
      child: Stack(
        children: [
          // Back button
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: leftPanelWidth,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                tooltip: 'Kembali ke App',
                onPressed: () => _confirmExit(context, controller),
              ),
            ),
          ),

          // Problem text (centered in display area)
          Positioned.fill(
            left: leftPanelWidth + 8,
            right: leftPanelWidth + 8,
            child: Center(
              child: _buildProblemText(controller),
            ),
          ),

          // Settings button
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: leftPanelWidth,
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
        ],
      ),
    );
  }

  /// Displays the mathematical problem equation, centered with a slightly smaller font size
  Widget _buildProblemText(SorobanController controller) {
    final problem = controller.currentProblem;
    if (problem == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text(
        problem.displayText,
        textAlign: TextAlign.center,
        style: SorobanTheme.monospaceDigitStyle.copyWith(fontSize: 20),
      ),
    );
  }

  /// Left panel under "Kembali ke App" button:
  /// - Problem progress indicator (e.g. [1/5])
  /// - Elapsed time (Timer)
  /// - Reset button (↺)
  Widget _buildLeftPanel(BuildContext context, SorobanController controller) {
    const panelWidth = 56.0;
    return SizedBox(
      width: panelWidth,
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Problem progress indicator
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
                const SizedBox(height: 8),

                // Timer info
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
                const SizedBox(height: 10),
              ],

              // Reset / Retri button
              _buildResetButton(controller, panelWidth),
            ],
          ),
        ),
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
