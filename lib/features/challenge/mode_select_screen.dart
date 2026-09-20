import 'package:flutter/material.dart';
import '../../core/models/problem.dart';
import '../../shared/theme.dart';
import '../practice/practice_screen.dart';
import '../settings/settings_screen.dart';
import 'difficulty_select_screen.dart';

/// Screen allowing the user to select the math operation mode.
class ModeSelectScreen extends StatelessWidget {
  const ModeSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SorobanTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'SOROBAN JAPANESE ABACUS',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: SorobanTheme.frameColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SorobanTheme.frameColor,
                          foregroundColor: SorobanTheme.backgroundColor,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        icon: const Icon(Icons.fitness_center_rounded, size: 20),
                        label: const Text('Mode Practice'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PracticeScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.settings_outlined, size: 26),
                        tooltip: 'Pengaturan',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pilih Kategori Tantangan (5 Soal):',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: SorobanTheme.textMuted,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 4 Category Cards in responsive grid
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 2.3,
                  children: [
                    _buildModeCard(
                      context,
                      title: 'Penjumlahan',
                      subtitle: 'Latihan dasar manik bumi, langit, dan kawan kecil/besar (+)',
                      icon: Icons.add_circle_outline_rounded,
                      category: ProblemCategory.addition,
                      accentColor: const Color(0xFF5A7247),
                    ),
                    _buildModeCard(
                      context,
                      title: 'Campuran (+ / -)',
                      subtitle: 'Kombinasi penjumlahan & pengurangan anti-negatif',
                      icon: Icons.sync_alt_rounded,
                      category: ProblemCategory.mixed,
                      accentColor: const Color(0xFF9E5738),
                    ),
                    _buildModeCard(
                      context,
                      title: 'Perkalian I',
                      subtitle: 'Multiplicand 3–5 digit × Pengali 1 digit',
                      icon: Icons.close_rounded,
                      category: ProblemCategory.multiplication1,
                      accentColor: const Color(0xFF4A6B82),
                    ),
                    _buildModeCard(
                      context,
                      title: 'Perkalian II',
                      subtitle: 'Multiplicand 4–5 digit × Pengali 2 digit (Carry-heavy)',
                      icon: Icons.filter_2_rounded,
                      category: ProblemCategory.multiplication2,
                      accentColor: const Color(0xFF8B5E3C),
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

  Widget _buildModeCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required ProblemCategory category,
    required Color accentColor,
  }) {
    return Card(
      elevation: 2,
      color: Colors.white.withValues(alpha: 0.85),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: SorobanTheme.frameColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DifficultySelectScreen(category: category),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: SorobanTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SorobanTheme.textMuted,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: SorobanTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
