import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';
import '../settings/settings_screen.dart';
import '../soroban_widget/soroban_view.dart';
import 'result_screen.dart';

/// The core exercise & challenge screen.
/// Implements the landscape layout defined in §5:
/// - Thin top strip: problem text with checkpoint breadcrumbs + timer + settings.
/// - Big Soroban: occupies 75-80% of screen height as the central focal point.
/// - Thin bottom strip: 3 icon-only control buttons: Replay (🔁), Hint (💡), Reset (↺).
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

    return Scaffold(
      backgroundColor: SorobanTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
          child: Column(
            children: [
              // 1. Thin Top Strip
              _buildTopStrip(context, controller),

              const SizedBox(height: 4),

              // 2. Big Soroban Focal Point (Expanded with large aspect ratio)
              const Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 2.1, // Expanded widescreen aspect ratio for larger beads
                    child: SorobanView(),
                  ),
                ),
              ),

              const SizedBox(height: 4),

              // 3. Compact Bottom Strip
              _buildBottomStrip(context, controller),
            ],
          ),
        ),
      ),
    );
  }

  /// Top strip: problem text with tabular monospace figures, checkpoint breadcrumbs, timer, settings
  Widget _buildTopStrip(BuildContext context, SorobanController controller) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 24),
            tooltip: 'Kembali',
            onPressed: () => Navigator.of(context).pop(),
          ),

          const SizedBox(width: 8),

          // Problem progress indicator (e.g. [1/5]) if challenge mode
          if (controller.isChallengeMode)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: SorobanTheme.frameColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${controller.challengeIndex + 1}/${controller.totalChallengeProblems}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: SorobanTheme.textDark,
                ),
              ),
            ),

          const SizedBox(width: 12),

          // Problem text with checkpoint breadcrumbs
          Expanded(
            child: _buildProblemText(controller),
          ),

          // Timer (if challenge mode)
          if (controller.isChallengeMode) ...[
            const Icon(Icons.timer_outlined, size: 20, color: SorobanTheme.textDark),
            const SizedBox(width: 4),
            Text(
              _formatTime(controller.elapsedMilliseconds),
              style: SorobanTheme.timerStyle,
            ),
            const SizedBox(width: 16),
          ],

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
    );
  }

  /// Displays the mathematical problem equation with completed checkpoints marked
  Widget _buildProblemText(SorobanController controller) {
    final problem = controller.currentProblem;
    if (problem == null) return const SizedBox.shrink();

    // Checkpoints reached count
    final activeCpIdx = controller.activeCheckpointIndex;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Equation display
          Text(
            problem.displayText,
            style: SorobanTheme.monospaceDigitStyle.copyWith(fontSize: 26),
          ),
          const SizedBox(width: 12),
          const Text('=', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: SorobanTheme.textMuted)),
          const SizedBox(width: 12),
          // Current abacus value display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: SorobanTheme.beadActiveColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: SorobanTheme.beadActiveColor.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Text(
              controller.state.value.toString(),
              style: SorobanTheme.monospaceDigitStyle.copyWith(
                fontSize: 26,
                color: SorobanTheme.textDark,
              ),
            ),
          ),
          if (activeCpIdx > 0 && activeCpIdx <= problem.checkpoints.length) ...[
            const SizedBox(width: 8),
            Text(
              '(${problem.checkpoints[activeCpIdx - 1].label})',
              style: const TextStyle(
                fontSize: 14,
                color: SorobanTheme.beadDefaultColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Bottom strip: 3 icon-only buttons as specified in §5
  /// Bottom strip: 3 compact icon-only control buttons
  Widget _buildBottomStrip(BuildContext context, SorobanController controller) {
    final bool isAnimating = controller.isAnimating;

    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 1. Reset / Retri Button (↺)
          _buildControlButton(
            icon: Icons.restart_alt_rounded,
            tooltip: 'Retri (Kembali ke checkpoint sebelumnya)',
            enabled: controller.canReset,
            onPressed: () => controller.executeReset(),
          ),

          const SizedBox(width: 20),

          // 2. Hint Button (💡)
          _buildControlButton(
            icon: Icons.lightbulb_rounded,
            tooltip: 'Hint (Jalankan animasi langkah berikutnya)',
            isPrimary: true,
            enabled: !isAnimating &&
                controller.currentProblem != null &&
                controller.activeCheckpointIndex <
                    controller.currentProblem!.checkpoints.length,
            onPressed: () => controller.executeHint(),
          ),

          const SizedBox(width: 20),

          // 3. Replay Hint Button (🔁)
          _buildControlButton(
            icon: Icons.repeat_rounded,
            tooltip: 'Replay Hint (Putar ulang animasi langkah digit ini)',
            enabled: controller.canReplay,
            onPressed: () => controller.executeReplay(),
          ),
        ],
      ),
    );
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

  String _formatTime(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final minStr = minutes.toString().padLeft(2, '0');
    final secStr = seconds.toString().padLeft(2, '0');
    return '$minStr:$secStr';
  }
}
