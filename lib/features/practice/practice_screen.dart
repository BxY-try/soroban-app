import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/problem.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';
import '../../shared/widgets/problem_equation_text.dart';
import '../settings/settings_screen.dart';
import '../soroban_widget/exercise_layout.dart';
import '../soroban_widget/soroban_view.dart';

/// Free-play Practice Mode (Mode Latihan Bebas):
/// - No timer, no pressure.
/// - Switch categories & difficulty on the fly.
/// - Full-digit chained hints, replay, and reset controls.
///
/// The layout mirrors the challenge screen through the shared [ExerciseLayout]
/// geometry: same top strip (back left, settings right, equation centred on
/// the abacus frame), same main group (left control panel + Soroban). The
/// category & difficulty dropdowns stay in the top strip, pinned to their own
/// [Positioned] child so their width can never shift the equation centre.
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

    return Scaffold(
      backgroundColor: SorobanTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top strip: back left, settings right, equation centred on the
            // abacus frame — exactly like the challenge screen.
            _buildTopStrip(context, controller),

            const SizedBox(height: 4),

            // Main interactive group: left controls + central Soroban View.
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
                                child: const FractionallySizedBox(
                                  widthFactor: ExerciseLayout.sorobanScale,
                                  heightFactor: ExerciseLayout.sorobanScale,
                                  child: AspectRatio(
                                    aspectRatio: 2.05,
                                    child: SorobanView(
                                      travelBoost:
                                          ExerciseLayout.sorobanTravelBoost,
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
    );
  }

  /// Top strip with Stack-based layout, matching the challenge screen:
  /// - Back button at exact SettingsScreen position (left: 4.0)
  /// - Category & difficulty dropdowns pinned at left: 52.0 (practice only)
  /// - Equation band centred on the abacus frame via
  ///   [ExerciseLayout.problemTextLeftFor] (same source as Challenge)
  /// - Next & settings buttons pinned to the right edge
  ///
  /// Everything except the equation band is absolutely positioned, so neither
  /// the dropdowns' width nor the equation's length can move the equation's
  /// centre: the band is derived from the full content width alone.
  Widget _buildTopStrip(BuildContext context, SorobanController controller) {
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

          // 2. Category & difficulty selectors, pinned to the left of the
          //    equation band. Kept as their own Positioned child (not part of
          //    the band) so resizing them never shifts the equation.
          Positioned(
            left: 52.0,
            top: 0,
            bottom: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Category dropdown (compact)
                  DropdownButton<ProblemCategory>(
                    value: _selectedCategory,
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: SorobanTheme.textDark,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ProblemCategory.addition,
                        child:
                            Text('Penjumlahan', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: ProblemCategory.mixed,
                        child: Text('Campuran (+/-)',
                            style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: ProblemCategory.multiplication1,
                        child:
                            Text('Perkalian I', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: ProblemCategory.multiplication2,
                        child: Text('Perkalian II',
                            style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: ProblemCategory.division1,
                        child:
                            Text('Pembagian I', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: ProblemCategory.division2,
                        child: Text('Pembagian II',
                            style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: ProblemCategory.divisionDecimal,
                        child: Text('Pembagian Desimal',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: (cat) {
                      if (cat != null) {
                        setState(() => _selectedCategory = cat);
                        controller.startPracticeProblem(
                          cat,
                          _selectedDifficulty,
                        );
                      }
                    },
                  ),

                  const SizedBox(width: 6),

                  // Difficulty dropdown (compact)
                  DropdownButton<Difficulty>(
                    value: _selectedDifficulty,
                    underline: const SizedBox.shrink(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: SorobanTheme.textDark,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: Difficulty.easy,
                        child: Text('Easy', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: Difficulty.medium,
                        child: Text('Medium', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: Difficulty.hard,
                        child: Text('Hard', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: (diff) {
                      if (diff != null) {
                        setState(() => _selectedDifficulty = diff);
                        controller.startPracticeProblem(
                          _selectedCategory,
                          diff,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // 3. Next problem + settings, pinned to the right edge. Settings
          //    lands on the same right: 10.0 position as the challenge screen.
          Positioned(
            right: 10.0,
            top: 0,
            bottom: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, size: 28),
                    tooltip: 'Soal Berikutnya',
                    onPressed: () {
                      controller.startPracticeProblem(
                        _selectedCategory,
                        _selectedDifficulty,
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 22),
                    tooltip: 'Pengaturan',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // 4. Equation band centred on the abacus FRAME centre — the same
          //    helper the challenge screen uses, so both modes share one
          //    source of truth for the centre. A long equation shrinks via
          //    ProblemEquationText's FittedBox instead of moving its centre.
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
                    textKey: const Key('practice_problem_text'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Left panel with the practice controls, styled like the challenge
  /// screen's left panel (fixed 56px column, badges, actions pinned low):
  /// 1. Spacer pushes the controls to the bottom
  /// 2. Bantuan button (primary)
  /// 3. Putar Ulang button
  /// 4. Reset button, same badge style as the challenge's Reset
  Widget _buildLeftPanel(BuildContext context, SorobanController controller) {
    const panelWidth = ExerciseLayout.leftPanelWidth;
    final problem = controller.currentProblem;
    final hintEnabled = !controller.isAnimating &&
        problem != null &&
        controller.activeCheckpointIndex < problem.checkpoints.length;

    return SizedBox(
      width: panelWidth,
      child: Column(
        children: [
          const Spacer(),

          _buildControlButton(
            width: panelWidth,
            icon: Icons.lightbulb_rounded,
            label: 'Bantuan',
            tooltip: problem?.division == null
                ? 'Bantuan: digit berikutnya'
                : 'Bantuan: langkah pembagian berikutnya',
            isPrimary: true,
            enabled: hintEnabled,
            onPressed: () => controller.executeHint(),
          ),

          const SizedBox(height: 8),

          _buildControlButton(
            width: panelWidth,
            icon: Icons.play_arrow_rounded,
            label: 'Putar Ulang',
            tooltip: 'Putar ulang animasi langkah digit ini',
            enabled: !controller.isAnimating && controller.canReplay,
            onPressed: () => controller.executeReplay(),
          ),

          const SizedBox(height: 8),

          // 4. Reset button, pinned low like the challenge's Reset.
          Padding(
            padding: const EdgeInsets.only(bottom: 44.0),
            child: _buildControlButton(
              width: panelWidth,
              icon: Icons.restart_alt_rounded,
              label: 'Reset',
              tooltip: 'Reset (Kembali ke checkpoint sebelumnya)',
              enabled: controller.canReset,
              onPressed: () => controller.executeReset(),
            ),
          ),
        ],
      ),
    );
  }

  /// Compact icon+label control badge for the practice left panel, matching
  /// the challenge screen's Reset button style (rounded 8px, full panel
  /// width, icon over label).
  Widget _buildControlButton({
    required double width,
    required IconData icon,
    required String label,
    required String tooltip,
    required bool enabled,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    final baseColor =
        isPrimary ? SorobanTheme.beadActiveColor : SorobanTheme.frameColor;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        color: enabled ? baseColor : Colors.grey.shade400,
        borderRadius: BorderRadius.circular(8),
        elevation: enabled ? (isPrimary ? 2 : 1) : 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? onPressed : null,
          child: Container(
            width: width,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isPrimary
                      ? SorobanTheme.frameColor
                      : SorobanTheme.backgroundColor,
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isPrimary
                        ? SorobanTheme.frameColor
                        : SorobanTheme.backgroundColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
