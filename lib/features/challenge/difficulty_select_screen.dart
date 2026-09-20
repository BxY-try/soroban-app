import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/problem.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';
import 'challenge_screen.dart';

/// Screen allowing the user to select the difficulty level (Easy, Medium, Hard).
/// Displays existing best-time records for each level.
class DifficultySelectScreen extends StatelessWidget {
  final ProblemCategory category;

  const DifficultySelectScreen({
    super.key,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SorobanController>();

    return Scaffold(
      backgroundColor: SorobanTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: SorobanTheme.frameColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Tingkat Kesulitan: ${_categoryTitle(category)}',
          style: const TextStyle(
            color: SorobanTheme.frameColor,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 12.0),
          child: Row(
            children: [
              Expanded(
                child: _buildDifficultyCard(
                  context,
                  controller: controller,
                  difficulty: Difficulty.easy,
                  title: 'EASY',
                  description: _difficultySpec(category, Difficulty.easy),
                  color: const Color(0xFF4A7C59),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _buildDifficultyCard(
                  context,
                  controller: controller,
                  difficulty: Difficulty.medium,
                  title: 'MEDIUM',
                  description: _difficultySpec(category, Difficulty.medium),
                  color: const Color(0xFFC07D38),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _buildDifficultyCard(
                  context,
                  controller: controller,
                  difficulty: Difficulty.hard,
                  title: 'HARD',
                  description: _difficultySpec(category, Difficulty.hard),
                  color: const Color(0xFF9E3838),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDifficultyCard(
    BuildContext context, {
    required SorobanController controller,
    required Difficulty difficulty,
    required String title,
    required String description,
    required Color color,
  }) {
    final bestTimeMs = controller.getBestTime(category, difficulty);

    return Card(
      elevation: 3,
      color: Colors.white.withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.35), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          controller.startChallengeSession(category, difficulty);
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ChallengeScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: SorobanTheme.textDark,
                  height: 1.3,
                ),
              ),
              const Spacer(),
              // Best record section
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: SorobanTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emoji_events_outlined, size: 18, color: SorobanTheme.beadActiveColor),
                    const SizedBox(width: 6),
                    Text(
                      bestTimeMs != null
                          ? 'Rekor: ${_formatTime(bestTimeMs)}'
                          : 'Belum ada rekor',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: SorobanTheme.textDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  controller.startChallengeSession(category, difficulty);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChallengeScreen()),
                  );
                },
                child: const Text('Mulai (5 Soal)', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _categoryTitle(ProblemCategory cat) {
    return switch (cat) {
      ProblemCategory.addition => 'Penjumlahan',
      ProblemCategory.mixed => 'Campuran (+ / -)',
      ProblemCategory.multiplication1 => 'Perkalian I (1 Digit)',
      ProblemCategory.multiplication2 => 'Perkalian II (2 Digit)',
    };
  }

  String _difficultySpec(ProblemCategory cat, Difficulty diff) {
    return switch (cat) {
      ProblemCategory.addition => switch (diff) {
          Difficulty.easy => '3 suku × 2 digit\n(Contoh: 34 + 52 + 18)',
          Difficulty.medium => '3 suku × 3 digit\n(Contoh: 342 + 581 + 219)',
          Difficulty.hard => '4 suku × 4 digit\n(Contoh: 1824 + 4091 + ...)',
        },
      ProblemCategory.mixed => switch (diff) {
          Difficulty.easy => '3 suku × 2 digit (+ / -)\nRunning total anti-negatif',
          Difficulty.medium => '3 suku × 3 digit (+ / -)\nRunning total anti-negatif',
          Difficulty.hard => '4 suku × 4 digit (+ / -)\nKombinasi acak simpan/pinjam',
        },
      ProblemCategory.multiplication1 => switch (diff) {
          Difficulty.easy => '3 digit × 1 digit\n(Contoh: 482 × 6)',
          Difficulty.medium => '4 digit × 1 digit\n(Contoh: 3918 × 7)',
          Difficulty.hard => '5 digit × 1 digit\n(Contoh: 49821 × 8)',
        },
      ProblemCategory.multiplication2 => switch (diff) {
          Difficulty.easy => '4 digit × 2 digit\n(Contoh: 2841 × 23)',
          Difficulty.medium => '5 digit × 2 digit\n(Contoh: 38291 × 45)',
          Difficulty.hard => '5 digit × 2 digit (Carry-heavy)\n(Banyak simpanan beruntun)',
        },
    };
  }

  String _formatTime(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
