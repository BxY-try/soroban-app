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
              // Top Strip
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, size: 24),
                      tooltip: 'Kembali',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),

                    // Category dropdown
                    DropdownButton<ProblemCategory>(
                      value: _selectedCategory,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(
                          value: ProblemCategory.addition,
                          child: Text('Penjumlahan'),
                        ),
                        DropdownMenuItem(
                          value: ProblemCategory.mixed,
                          child: Text('Campuran (+/-)'),
                        ),
                        DropdownMenuItem(
                          value: ProblemCategory.multiplication1,
                          child: Text('Perkalian I'),
                        ),
                        DropdownMenuItem(
                          value: ProblemCategory.multiplication2,
                          child: Text('Perkalian II'),
                        ),
                      ],
                      onChanged: (cat) {
                        if (cat != null) {
                          setState(() => _selectedCategory = cat);
                          controller.startPracticeProblem(cat, _selectedDifficulty);
                        }
                      },
                    ),

                    const SizedBox(width: 8),

                    // Difficulty dropdown
                    DropdownButton<Difficulty>(
                      value: _selectedDifficulty,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: Difficulty.easy, child: Text('Easy')),
                        DropdownMenuItem(value: Difficulty.medium, child: Text('Medium')),
                        DropdownMenuItem(value: Difficulty.hard, child: Text('Hard')),
                      ],
                      onChanged: (diff) {
                        if (diff != null) {
                          setState(() => _selectedDifficulty = diff);
                          controller.startPracticeProblem(_selectedCategory, diff);
                        }
                      },
                    ),

                    const SizedBox(width: 12),

                    // Problem Display
                    if (problem != null) ...[
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Text(
                                '${problem.displayText} = ',
                                style: SorobanTheme.monospaceDigitStyle.copyWith(fontSize: 24),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: SorobanTheme.beadActiveColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  controller.state.value.toString(),
                                  style: SorobanTheme.monospaceDigitStyle.copyWith(
                                    fontSize: 24,
                                    color: SorobanTheme.textDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else
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

              const SizedBox(height: 4),

              // Big Soroban Focal Point (Expanded)
              const Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 2.1,
                    child: SorobanView(),
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
