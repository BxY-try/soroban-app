import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/problem.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';
import '../../shared/time_format.dart';
import 'challenge_screen.dart';
import 'difficulty_select_screen.dart';

/// Screen displayed upon completing a 5-problem Challenge session.
/// Shows the total elapsed time, best record, per-problem split times,
/// and restart actions in a single compact scene without vertical scrolling.
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  static const Color _cardBgColor = Color(0xFFF7F2EB);

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SorobanController>();
    final problem = controller.currentProblem;
    final splitTimes = controller.splitTimes;
    final totalTimeMs = controller.elapsedMilliseconds;

    final hasSplits = splitTimes.isNotEmpty;

    const double splitCardOuterMargin = 18.0;
    const double leftPadding = 34.0;
    const double columnGap = 24.0;

    return Scaffold(
      backgroundColor: SorobanTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 770),
                padding: hasSplits
                    ? const EdgeInsets.only(
                        left: leftPadding,
                        top: splitCardOuterMargin,
                        right: splitCardOuterMargin,
                        bottom: splitCardOuterMargin,
                      )
                    : const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: SorobanTheme.frameColor.withValues(alpha: 0.10),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: hasSplits
                    ? IntrinsicHeight(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 410),
                              child: _buildSummaryColumn(
                                context,
                                controller,
                                problem,
                                totalTimeMs,
                              ),
                            ),
                            const SizedBox(width: columnGap),
                            _buildSplitTimesCard(splitTimes, totalTimeMs),
                          ],
                        ),
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 410),
                        child: _buildSummaryColumn(
                          context,
                          controller,
                          problem,
                          totalTimeMs,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Compact trophy with sparkle burst header.
  Widget _buildTrophyHeader() {
    return const SizedBox(
      width: 96,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(96, 48),
            painter: _TrophySparklePainter(),
          ),
          Icon(
            Icons.emoji_events_rounded,
            size: 42,
            color: SorobanTheme.beadActiveColor,
          ),
        ],
      ),
    );
  }

  /// Left column: trophy, heading, subtitle, stats card, and pill action buttons.
  Widget _buildSummaryColumn(
    BuildContext context,
    SorobanController controller,
    Problem? problem,
    int totalTimeMs,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildTrophyHeader(),
        const SizedBox(height: 3),
        const Text(
          'Tantangan selesai!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 23.5,
            fontWeight: FontWeight.bold,
            color: SorobanTheme.textDark,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Hebat! Kamu telah menuntaskan 5 soal sempoa berturut-turut.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.8,
            color: SorobanTheme.textMuted,
          ),
        ),
        const SizedBox(height: 11),
        _buildStatsCard(controller, problem, totalTimeMs),
        const SizedBox(height: 13),
        _buildActionButtons(context, controller, problem),
      ],
    );
  }

  /// Two-column summary card: best record vs this run's time, with category & level.
  Widget _buildStatsCard(
    SorobanController controller,
    Problem? problem,
    int totalTimeMs,
  ) {
    final bestTimeMs = problem != null
        ? controller.getBestTime(problem.category, problem.difficulty)
        : null;
    final bestTimeFormatted =
        bestTimeMs != null ? formatTimeMs(bestTimeMs) : '00:00';
    // This run matched or beat the stored best: wear the NEW sticker.
    final isNewRecord = bestTimeMs != null && totalTimeMs <= bestTimeMs;

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      clipBehavior: Clip.none,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: _cardBgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _buildStatsColumn(
                  const CustomPaint(
                    size: Size(13, 11),
                    painter: _CrownPainter(),
                  ),
                  'Rekor Terbaik',
                  bestTimeFormatted,
                  isNewRecord: isNewRecord,
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: SorobanTheme.frameColor.withValues(alpha: 0.15),
              ),
              Expanded(
                child: _buildStatsColumn(
                  const Icon(
                    Icons.access_time_rounded,
                    size: 13,
                    color: SorobanTheme.beadActiveColor,
                  ),
                  'Waktu Kamu',
                  formatTimeMs(totalTimeMs),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(
            height: 1,
            thickness: 1,
            color: Color(0x183D2B1F),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.bolt_rounded,
                size: 13,
                color: SorobanTheme.beadActiveColor,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  problem != null
                      ? '${_categoryTitle(problem.category)} - ${_difficultyTitle(problem.difficulty)}'
                      : '5 soal selesai',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: SorobanTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsColumn(
    Widget icon,
    String label,
    String time, {
    bool isNewRecord = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: SorobanTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        // The time is the only non-positioned child, so the Stack sizes to
        // the number itself; the NEW sticker is positioned, which means it
        // paints over the number without contributing any size of its own —
        // it can never shift the stats card or anything around it.
        Stack(
          clipBehavior: Clip.none,
          children: [
            Text(
              time,
              style: SorobanTheme.monospaceDigitStyle.copyWith(
                fontSize: 20,
                color: SorobanTheme.textDark,
              ),
            ),
            if (isNewRecord)
              const Positioned(
                right: -4,
                bottom: -3,
                child: _NewRecordBadge(),
              ),
          ],
        ),
      ],
    );
  }

  /// Right panel: per-problem split times plus session total.
  /// Scaled down slightly, with comfortable padding and subtle dividers between questions.
  Widget _buildSplitTimesCard(
    List<int> splitTimes,
    int totalTimeMs,
  ) {
    return Container(
      width: 210,
      padding: const EdgeInsets.symmetric(horizontal: 13.5, vertical: 11),
      decoration: BoxDecoration(
        color: _cardBgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Scales down instead of overflowing on narrow cards / wide test
          // fonts; at the usual font metrics it never activates.
          const FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 15,
                  color: SorobanTheme.beadActiveColor,
                ),
                SizedBox(width: 5),
                Text(
                  'Waktu per Soal',
                  style: TextStyle(
                    fontSize: 12.8,
                    fontWeight: FontWeight.bold,
                    color: SorobanTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < splitTimes.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 12,
                    thickness: 0.6,
                    color: Color(0x143D2B1F),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.8),
                  child: Row(
                    children: [
                      Container(
                        width: 13.5,
                        height: 13.5,
                        decoration: const BoxDecoration(
                          color: SorobanTheme.beadActiveColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 9.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Soal ${i + 1}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: SorobanTheme.textDark,
                          ),
                        ),
                      ),
                      Text(
                        formatTimeMs(splitTimes[i]),
                        style: SorobanTheme.monospaceDigitStyle.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: SorobanTheme.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(
                height: 10,
                thickness: 1,
                color: Color(0x183D2B1F),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 12.8,
                        fontWeight: FontWeight.bold,
                        color: SorobanTheme.textDark,
                      ),
                    ),
                  ),
                  Text(
                    formatTimeMs(totalTimeMs),
                    style: SorobanTheme.monospaceDigitStyle.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: SorobanTheme.textDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Action buttons matching the reference pill style:
  /// [Main lagi] in solid amber, [Beranda] in white outline, [Level] in white outline.
  Widget _buildActionButtons(
    BuildContext context,
    SorobanController controller,
    Problem? problem,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 1. "Main lagi"
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: SorobanTheme.beadActiveColor,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            minimumSize: const Size(0, 35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, size: 15, color: Colors.white),
              SizedBox(width: 5),
              Text(
                'Main lagi',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 9),

        // 2. "Beranda"
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: SorobanTheme.textDark,
            side: const BorderSide(
              color: SorobanTheme.beadInactiveBorderColor,
              width: 1.2,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            minimumSize: const Size(0, 35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: () {
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.home_rounded, size: 15, color: SorobanTheme.textDark),
              SizedBox(width: 5),
              Text(
                'Beranda',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SorobanTheme.textDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 9),

        // 3. "Level": goes to the level picker of the category that was just
        // played, not to the global settings screen.
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: SorobanTheme.textDark,
            side: const BorderSide(
              color: SorobanTheme.beadInactiveBorderColor,
              width: 1.2,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            minimumSize: const Size(0, 35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: () {
            if (problem != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DifficultySelectScreen(category: problem.category),
                ),
              );
            } else {
              Navigator.of(context).pop();
            }
          },
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune_rounded, size: 15, color: SorobanTheme.textDark),
              SizedBox(width: 5),
              Text(
                'Level',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: SorobanTheme.textDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _categoryTitle(ProblemCategory category) {
    return switch (category) {
      ProblemCategory.addition => 'Penjumlahan',
      ProblemCategory.mixed => 'Campuran (+ / -)',
      ProblemCategory.multiplication1 => 'Perkalian I (1 Digit)',
      ProblemCategory.multiplication2 => 'Perkalian II (2 Digit)',
      ProblemCategory.division1 => 'Pembagian I (1 Digit)',
      ProblemCategory.division2 => 'Pembagian II (2 Digit)',
      ProblemCategory.divisionDecimal => 'Pembagian Desimal',
    };
  }

  String _difficultyTitle(Difficulty difficulty) {
    return switch (difficulty) {
      Difficulty.easy => 'MUDAH',
      Difficulty.medium => 'SEDANG',
      Difficulty.hard => 'SULIT',
    };
  }
}

/// Compact radiating strokes around the trophy celebration burst.
class _TrophySparklePainter extends CustomPainter {
  const _TrophySparklePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SorobanTheme.beadActiveColor
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2 - 1);
    const startRadius = 26.0;
    const strokeLength = 6.5;
    const angles = [35.0, 5.0, -25.0];

    for (final side in const [-1.0, 1.0]) {
      for (final angle in angles) {
        final radians = angle * math.pi / 180.0;
        final direction = Offset(side * math.cos(radians), -math.sin(radians));
        canvas.drawLine(
          center + direction * startRadius,
          center + direction * (startRadius + strokeLength),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small filled crown used next to the best-record label.
class _CrownPainter extends CustomPainter {
  const _CrownPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = SorobanTheme.beadActiveColor
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(0.06 * w, h)
      ..lineTo(0.06 * w, 0.38 * h)
      ..lineTo(0.30 * w, 0.58 * h)
      ..lineTo(0.50 * w, 0.14 * h)
      ..lineTo(0.70 * w, 0.58 * h)
      ..lineTo(0.94 * w, 0.38 * h)
      ..lineTo(0.94 * w, h)
      ..close();
    canvas.drawPath(path, paint);

    canvas.drawCircle(Offset(0.06 * w, 0.30 * h), 0.11 * h, paint);
    canvas.drawCircle(Offset(0.50 * w, 0.08 * h), 0.11 * h, paint);
    canvas.drawCircle(Offset(0.94 * w, 0.30 * h), 0.11 * h, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Tiny tilted "NEW" sticker worn by the best-record number when this run
/// set (or tied) the record.
///
/// It is only ever used as a [Positioned] child of the [Stack] that anchors
/// it to the number. Positioned children do not contribute to a Stack's size
/// (see the Stack docs: "The stack sizes itself to contain all the
/// non-positioned children"), so the sticker paints over the number without
/// ever taking layout space or shifting the layout around it.
class _NewRecordBadge extends StatelessWidget {
  const _NewRecordBadge();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.15,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
        decoration: BoxDecoration(
          color: SorobanTheme.beadActiveColor,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white, width: 1.0),
        ),
        child: const Text(
          'NEW',
          style: TextStyle(
            fontSize: 6.5,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
