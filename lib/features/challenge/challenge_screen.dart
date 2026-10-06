import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';
import '../../shared/time_format.dart';
import '../../shared/widgets/problem_equation_text.dart';
import '../settings/settings_screen.dart';
import '../soroban_widget/exercise_layout.dart';
import '../soroban_widget/soroban_view.dart';
import 'result_screen.dart';

/// The core exercise & challenge screen.
/// Implements the compact landscape layout:
/// - Top strip: Back button (left), Centered Problem text (center), Settings (right).
/// - Main area: Left panel (problem number, timer, reset) + Central Soroban.
///
/// The layout geometry and the equation widget are shared with the Practice
/// screen via [ExerciseLayout] / [ProblemEquationText], so both modes stay
/// centred on the same abacus axis.
class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key});

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  /// The session this screen navigates on, held by the completion listener so
  /// it can run without a [context] lookup on every notification.
  late final SorobanController _controller;

  /// The result transition happens once: the best-time write settles after it
  /// and notifies the controller again, which must not push a second result
  /// screen.
  bool _resultNavigated = false;

  @override
  void initState() {
    super.initState();
    _controller = context.read<SorobanController>();
    _controller.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// Navigates to the result screen the moment the controller reports a
  /// finished session.
  ///
  /// Lives here instead of [build] on purpose: [build] must stay free of side
  /// effects (it runs every frame the controller notifies), and a one-shot
  /// transition must not re-arm itself on those later notifications.
  void _onSessionChanged() {
    if (_resultNavigated) return;
    if (!_controller.isChallengeMode || !_controller.isChallengeCompleted) {
      return;
    }
    _resultNavigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ResultScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SorobanController>();

    return PopScope(
      canPop: !controller.isChallengeMode || controller.isChallengeCompleted,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmExit(context, controller);
      },
      child: Scaffold(
        backgroundColor: SorobanTheme.backgroundColor,
        body: GestureDetector(
          // While the split card is up, tapping anywhere on the screen
          // dismisses it and moves on to the next problem.
          behavior: HitTestBehavior.opaque,
          onTap: controller.isShowingSplitOverlay
              ? () => controller.dismissSplitOverlay()
              : null,
          child: SafeArea(
            child: Column(
              children: [
                // Top Row: Back button (matching SettingsScreen exact position), Problem Text (aligned with Soroban), Settings button
                _buildTopRow(context, controller),

                const SizedBox(height: 4),

                // Main Interactive Group: Left controls (SOAL, Timer, Reset) + Central Soroban View
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ExerciseLayout.groupHorizontalPadding,
                      vertical: 2.0,
                    ),
                    child: Center(
                      child: FractionallySizedBox(
                        widthFactor: ExerciseLayout.groupScale,
                        heightFactor: ExerciseLayout.groupScale,
                        child: Row(
                          children: [
                            _buildLeftPanel(context, controller),

                            const SizedBox(width: ExerciseLayout.leftPanelGap),

                            // Central Soroban View. It is centred inside this slot;
                            // the problem text above is what chases the painted
                            // frame centre, not the other way round.
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 2.0),
                                child: Center(
                                  child: Transform.translate(
                                    offset: const Offset(
                                      0,
                                      -ExerciseLayout.sorobanLift,
                                    ),
                                    child: FractionallySizedBox(
                                      widthFactor:
                                          ExerciseLayout.sorobanScale,
                                      heightFactor:
                                          ExerciseLayout.sorobanScale,
                                      child: AspectRatio(
                                        aspectRatio: 2.05,
                                        child:
                                            _buildSorobanWithSplitOverlay(
                                          context,
                                          controller,
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
      controller.cancelChallengeSession();
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
          // ExerciseLayout.problemTextLeftFor instead of a hard-coded 78.0.
          // With symmetric gutters that helper returns 78.0 again, so this is
          // a no-op then.
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: EdgeInsets.only(
                  left: ExerciseLayout.problemTextLeftFor(
                    constraints.maxWidth,
                  ),
                  right: ExerciseLayout.problemTextRightInset,
                ),
                child: Center(
                  child: ProblemEquationText(
                    controller: controller,
                    textKey: const Key('challenge_problem_text'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Left panel containing the interactive badges and reset button:
  /// 1. Badge posisi soal ("SOAL 1/5")
  /// 2. Badge waktu ("00:12") dengan jarak napas yang ditambah lebih lega (18px)
  /// 3. Spacer mendorong tombol Reset ke bawah
  /// 4. Tombol Reset dinaikkan lagi (bottom padding 44px)
  Widget _buildLeftPanel(BuildContext context, SorobanController controller) {
    const panelWidth = ExerciseLayout.leftPanelWidth;
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
                  // Only this label listens to the clock. Watching the whole
                  // controller for it meant rebuilding the entire screen on
                  // every tick.
                  ValueListenableBuilder<int>(
                    valueListenable: controller.elapsedSeconds,
                    builder: (context, seconds, _) => Text(
                      formatTimeMs(seconds * 1000),
                      style: SorobanTheme.timerStyle.copyWith(fontSize: 12),
                    ),
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

  Widget _buildSorobanWithSplitOverlay(
    BuildContext context,
    SorobanController controller,
  ) {
    final isOverlayShowing = controller.isShowingSplitOverlay;

    // The overlay stays in the tree at all times so both the fade-in and the
    // fade-out can animate; only its opacity flips with the controller state.
    // It is clipped to the wooden frame rect by SorobanView's ClipRRect so
    // nothing bleeds outside.
    final Widget frameOverlay = IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: isOverlayShowing ? 1.0 : 0.0,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Dim layer covering the board
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.32),
              ),
            ),
            // Split time text floating directly over the dimmed board
            Center(child: _buildSplitOverlayCard(controller)),
          ],
        ),
      ),
    );

    return AbsorbPointer(
      absorbing: isOverlayShowing,
      child: SorobanView(
        travelBoost: ExerciseLayout.sorobanTravelBoost,
        frameOverlay: frameOverlay,
      ),
    );
  }

  Widget _buildSplitOverlayCard(SorobanController controller) {
    final split = controller.currentSplit;
    final problemNum = split?.problemNumber ?? 1;
    final durationMs = split?.durationMs ?? 0;
    final timeFormatted = formatTimeMs(durationMs);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
      decoration: BoxDecoration(
        color: SorobanTheme.splitCardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: SorobanTheme.beadActiveColor.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 22,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF5DBB63),
                size: 26,
              ),
              const SizedBox(width: 10),
              Text(
                'SOAL $problemNum SELESAI',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            timeFormatted,
            style: SorobanTheme.monospaceDigitStyle.copyWith(
              fontSize: 46,
              fontWeight: FontWeight.bold,
              color: SorobanTheme.beadActiveColor,
              letterSpacing: 2.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'KETUK LAYAR UNTUK MELANJUTKAN',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
