import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';
import '../settings/settings_screen.dart';
import '../soroban_widget/soroban_view.dart';
import 'result_screen.dart';

/// The core exercise & challenge screen.
/// Implements the landscape layout:
/// - Thin top strip: problem text + timer + settings.
/// - Big Soroban: occupies central focal point.
/// - Thin bottom strip: control button Reset (↺).
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
            onPressed: () => _confirmExit(context, controller),
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

  /// Displays the mathematical problem equation
  Widget _buildProblemText(SorobanController controller) {
    final problem = controller.currentProblem;
    if (problem == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Text(
        problem.displayText,
        style: SorobanTheme.monospaceDigitStyle.copyWith(fontSize: 26),
      ),
    );
  }

  /// Bottom strip: compact icon-only control button (Reset / Retri)
  Widget _buildBottomStrip(BuildContext context, SorobanController controller) {
    return SizedBox(
      height: 36,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Reset / Retri Button (↺)
          _buildControlButton(
            icon: Icons.restart_alt_rounded,
            tooltip: 'Retri (Kembali ke checkpoint sebelumnya)',
            enabled: controller.canReset,
            onPressed: () => controller.executeReset(),
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
