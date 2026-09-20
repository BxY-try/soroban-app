import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';
import 'challenge_screen.dart';

/// Screen displayed upon completing a 5-problem Challenge session.
/// Shows the total elapsed time, best record status, and restart actions.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SorobanController>();
    final problem = controller.currentProblem;

    final totalTimeFormatted = _formatTime(controller.elapsedMilliseconds);

    return Scaffold(
      backgroundColor: SorobanTheme.backgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 580),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: SorobanTheme.frameColor.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.emoji_events_rounded,
                    size: 64,
                    color: SorobanTheme.beadActiveColor,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'TANTANGAN SELESAI!',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: SorobanTheme.frameColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hebat! Kamu telah menuntaskan 5 soal sempoa berturut-turut.',
                    style: TextStyle(
                      fontSize: 14,
                      color: SorobanTheme.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  // Time banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: SorobanTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_rounded, size: 28, color: SorobanTheme.frameColor),
                        const SizedBox(width: 10),
                        Text(
                          totalTimeFormatted,
                          style: SorobanTheme.monospaceDigitStyle.copyWith(
                            fontSize: 32,
                            color: SorobanTheme.frameColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: SorobanTheme.frameColor,
                          side: const BorderSide(color: SorobanTheme.frameColor, width: 1.5),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.home_rounded),
                        label: const Text('Menu Utama'),
                        onPressed: () {
                          Navigator.of(context).popUntil((route) => route.isFirst);
                        },
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SorobanTheme.beadActiveColor,
                          foregroundColor: SorobanTheme.frameColor,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text(
                          'Coba Lagi',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          if (problem != null) {
                            controller.startChallengeSession(
                              problem.category,
                              problem.difficulty,
                            );
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const ChallengeScreen()),
                            );
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
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
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
