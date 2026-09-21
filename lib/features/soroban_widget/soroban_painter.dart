import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../core/models/soroban_state.dart';
import '../../shared/theme.dart';
import 'soroban_layout.dart';

/// Procedural CustomPainter that renders a 7-rod Japanese Soroban (sempoa)
/// with natural wood textures, bi-conical diamond beads, brass accents,
/// dividing beam with unit dots, and trail glow effects.
///
/// Supports smooth sliding animation via [previousState] and [animationProgress]:
/// when animationProgress is between 0..1, bead Y positions are interpolated
/// between their previous and target positions.
class SorobanPainter extends CustomPainter {
  final SorobanState state;
  final bool perRodColor;
  final String? animatingBeadKey;
  final Map<String, DateTime> trailBeads;

  /// Previous soroban state for interpolating bead positions during animation.
  final SorobanState? previousState;

  /// Animation progress 0.0 (at previousState) to 1.0 (at state). Values >= 1 mean no animation.
  final double animationProgress;

  /// Rod index currently being dragged by the user (null when not dragging).
  final int? dragRodIndex;

  /// Exact floating Y positions of the 4 earth beads during drag.
  final List<double>? dragEarthY;

  /// Exact floating Y position of the heaven bead during drag.
  final double? dragHeavenY;

  SorobanPainter({
    required this.state,
    required this.perRodColor,
    required this.animatingBeadKey,
    required this.trailBeads,
    this.previousState,
    this.animationProgress = 1.0,
    this.dragRodIndex,
    this.dragEarthY,
    this.dragHeavenY,
  });

  // Layout constants forwarded from SorobanLayout for backward compatibility
  static const double frameBorder = SorobanLayout.frameBorder;
  static const double beamHeight = SorobanLayout.beamHeight;
  static const double beadGap = SorobanLayout.beadGap;
  static const double deckPadding = SorobanLayout.deckPadding;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final totalRods = state.rods.length;
    final layout = SorobanLayout(size: size, totalRods: totalRods);

    // Draw background
    final bgPaint = Paint()..color = SorobanTheme.backgroundColor;
    canvas.drawRect(Offset.zero & size, bgPaint);

    // Soroban outer frame bounds
    final sorobanRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(10),
    );

    // Frame paint (Dark Walnut)
    final framePaint = Paint()..color = SorobanTheme.frameColor;
    final frameInnerRect = layout.innerRect;

    // Draw outer wood frame
    canvas.drawRRect(sorobanRect, framePaint);

    // Draw inner board background
    final innerBoardPaint = Paint()..color = const Color(0xFFF7F1E5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameInnerRect, const Radius.circular(4)),
      innerBoardPaint,
    );

    final beamRect = Rect.fromLTWH(
      frameInnerRect.left,
      layout.beamTop,
      frameInnerRect.width,
      SorobanLayout.beamHeight,
    );

    // Draw vertical rods
    final rodPaint = Paint()
      ..color = SorobanTheme.rodColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    for (int col = 0; col < totalRods; col++) {
      final rodIndex = totalRods - 1 - col;
      final rodCenterX = layout.rodCenterX(rodIndex);
      // Draw rod passing through upper deck, beam, and lower deck
      canvas.drawLine(
        Offset(rodCenterX, frameInnerRect.top),
        Offset(rodCenterX, frameInnerRect.bottom),
        rodPaint,
      );
    }

    // Draw dividing beam
    canvas.drawRect(beamRect, framePaint);

    // Draw unit alignment dots on the beam (white dots on every 3rd rod, e.g. units rod 0, rod 3, rod 6)
    final dotPaint = Paint()..color = SorobanTheme.beamDotColor;
    for (int col = 0; col < totalRods; col++) {
      final rodIndex = totalRods - 1 - col;
      if (rodIndex % 3 == 0) {
        final rodCenterX = layout.rodCenterX(rodIndex);
        canvas.drawCircle(
          Offset(rodCenterX, layout.beamTop + (SorobanLayout.beamHeight / 2)),
          2.5,
          dotPaint,
        );
      }
    }

    // Animation progress (clamped)
    final t = animationProgress.clamp(0.0, 1.0);
    final isAnimating = t < 1.0 && previousState != null;

    for (int col = 0; col < totalRods; col++) {
      final rodIndex = totalRods - 1 - col;
      final rod = state.rods[rodIndex];
      final rodCenterX = layout.rodCenterX(rodIndex);

      // Previous rod state for interpolation
      final prevRod = (isAnimating && rodIndex < previousState!.rods.length)
          ? previousState!.rods[rodIndex]
          : rod;

      // Base color for this rod
      final Color baseColor = perRodColor
          ? SorobanTheme.perRodColors[rodIndex % SorobanTheme.perRodColors.length]
          : SorobanTheme.beadDefaultColor;

      // Is this the rod currently being dragged?
      final isDragRod = rodIndex == dragRodIndex;

      // 1. Heaven Bead — drag-float or smooth slide
      double heavenY;
      bool heavenActive;

      if (isDragRod && dragHeavenY != null) {
        heavenY = dragHeavenY!;
        heavenActive = layout.resolveHeavenActive(heavenY);
      } else {
        final targetHeavenY = layout.computeHeavenY(rod.heaven);
        final prevHeavenY = layout.computeHeavenY(prevRod.heaven);
        heavenY = isAnimating
            ? ui.lerpDouble(prevHeavenY, targetHeavenY, t)!
            : targetHeavenY;
        heavenActive = rod.heaven;
      }

      final heavenKey = 'rod_${rodIndex}_heaven';
      final isHeavenAnimating = animatingBeadKey == heavenKey;

      _drawBead(
        canvas: canvas,
        centerX: rodCenterX,
        y: heavenY,
        width: layout.beadWidth,
        height: layout.beadHeight,
        baseColor: baseColor,
        isActive: heavenActive,
        isHighlightGlow: isHeavenAnimating,
      );

      // 2. Earth Beads (4 beads) — drag-float or smooth slide
      if (isDragRod && dragEarthY != null) {
        for (int b = 0; b < 4; b++) {
          final beadY = dragEarthY![b];
          final midY = (layout.computeEarthY(b, 4) + layout.computeEarthY(b, 0)) / 2.0;
          final isActive = beadY < midY;

          _drawBead(
            canvas: canvas,
            centerX: rodCenterX,
            y: beadY,
            width: layout.beadWidth,
            height: layout.beadHeight,
            baseColor: baseColor,
            isActive: isActive,
            isHighlightGlow: false,
          );
        }
      } else {
        // Normal rendering: discrete state with optional slide animation
        final activeCount = rod.earth;
        final prevActiveCount = prevRod.earth;

        for (int b = 0; b < 4; b++) {
          final bool isThisBeadActive = b < activeCount;
          final targetY = layout.computeEarthY(b, activeCount);
          final prevY = layout.computeEarthY(b, prevActiveCount);
          final beadY = isAnimating
              ? ui.lerpDouble(prevY, targetY, t)!
              : targetY;

          // Only active bead being animated gets isHighlightGlow.
          // Inactive beads NEVER light up!
          final earthKey = 'rod_${rodIndex}_earth_$activeCount';
          final isEarthAnimating =
              isThisBeadActive && (animatingBeadKey == earthKey);

          _drawBead(
            canvas: canvas,
            centerX: rodCenterX,
            y: beadY,
            width: layout.beadWidth,
            height: layout.beadHeight,
            baseColor: baseColor,
            isActive: isThisBeadActive,
            isHighlightGlow: isEarthAnimating,
          );
        }
      }
    }
  }

  /// Draws a single Soroban bead with bi-conical (diamond-beveled) geometry.
  void _drawBead({
    required Canvas canvas,
    required double centerX,
    required double y,
    required double width,
    required double height,
    required Color baseColor,
    required bool isActive,
    required bool isHighlightGlow,
  }) {
    final halfW = width / 2;
    final halfH = height / 2;
    final centerY = y + halfH;

    // Bi-conical diamond polygon path
    // Points: Left sharp tip, Top apex, Right sharp tip, Bottom apex
    final path = Path()
      ..moveTo(centerX - halfW, centerY)
      ..lineTo(centerX, y)
      ..lineTo(centerX + halfW, centerY)
      ..lineTo(centerX, y + height)
      ..close();

    // Determine bead display color:
    // Inactive beads ALWAYS stay in baseColor (no glowing/tinting on the whole rod).
    // Active beads get beadActiveColor.
    // Animating beads get brass glow.
    Color displayColor;
    if (isHighlightGlow) {
      displayColor = SorobanTheme.brassGlowColor;
    } else if (isActive) {
      displayColor = SorobanTheme.beadActiveColor;
    } else {
      displayColor = baseColor;
    }

    // 1. Subtle drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.drawPath(path.shift(const Offset(0.5, 1.5)), shadowPaint);

    // 2. Brass glow halo ONLY if actively animating during hint
    if (isHighlightGlow) {
      final glowPaint = Paint()
        ..color = SorobanTheme.brassGlowColor.withValues(alpha: 0.75)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawPath(path, glowPaint);
    }

    // 3. Main bead body gradient (gives volumetric bi-conical bevel feel)
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(displayColor, Colors.white, 0.38)!, // Top highlight ridge
          displayColor,
          Color.lerp(displayColor, Colors.black, 0.32)!, // Bottom shadow bevel
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(Rect.fromLTWH(centerX - halfW, y, width, height));

    canvas.drawPath(path, gradientPaint);

    // 4. Center horizontal ridge seam
    final seamPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.24)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(centerX - halfW + 1.5, centerY),
      Offset(centerX + halfW - 1.5, centerY),
      seamPaint,
    );

    // 5. Border outline
    final borderPaint = Paint()
      ..color = Color.lerp(displayColor, Colors.black, 0.45)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant SorobanPainter oldDelegate) {
    return true; // Always repaint when controller or animation notifies
  }
}
