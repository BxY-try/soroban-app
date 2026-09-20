import 'package:flutter/material.dart';
import '../../core/models/soroban_state.dart';
import '../../shared/theme.dart';

/// Procedural CustomPainter that renders a 7-rod Japanese Soroban (sempoa)
/// with natural wood textures, bi-conical diamond beads, brass accents,
/// dividing beam with unit dots, and trail glow effects.
class SorobanPainter extends CustomPainter {
  final SorobanState state;
  final bool perRodColor;
  final String? animatingBeadKey;
  final Map<String, DateTime> trailBeads;

  SorobanPainter({
    required this.state,
    required this.perRodColor,
    required this.animatingBeadKey,
    required this.trailBeads,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // Outer frame padding
    const frameBorder = 14.0;
    const beamHeight = 16.0;

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
    final frameInnerRect = Rect.fromLTWH(
      frameBorder,
      frameBorder,
      size.width - (frameBorder * 2),
      size.height - (frameBorder * 2),
    );

    // Draw outer wood frame
    canvas.drawRRect(sorobanRect, framePaint);

    // Draw inner board background
    final innerBoardPaint = Paint()..color = const Color(0xFFF7F1E5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frameInnerRect, const Radius.circular(4)),
      innerBoardPaint,
    );

    // Calculate dimensions
    final totalRods = state.rods.length;
    final usableWidth = frameInnerRect.width;
    final rodSpacing = usableWidth / totalRods;

    // Heights for upper and lower decks
    // Total inner height:
    final innerHeight = frameInnerRect.height;
    // Upper deck ~28%, Beam ~16px, Lower deck ~64%
    final upperDeckHeight = (innerHeight - beamHeight) * 0.30;

    final beamTop = frameInnerRect.top + upperDeckHeight;
    final beamRect = Rect.fromLTWH(
      frameInnerRect.left,
      beamTop,
      frameInnerRect.width,
      beamHeight,
    );

    // Draw vertical rods
    final rodPaint = Paint()
      ..color = SorobanTheme.rodColor
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    for (int col = 0; col < totalRods; col++) {
      final rodCenterX = frameInnerRect.left + (col + 0.5) * rodSpacing;
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
      // Rod index from right: (totalRods - 1 - col)
      final rodIndex = totalRods - 1 - col;
      if (rodIndex % 3 == 0) {
        final rodCenterX = frameInnerRect.left + (col + 0.5) * rodSpacing;
        canvas.drawCircle(
          Offset(rodCenterX, beamTop + (beamHeight / 2)),
          2.5,
          dotPaint,
        );
      }
    }

    // Now render beads for each rod
    // Index 0 = rightmost (units) -> col = totalRods - 1
    // Index 6 = leftmost (millions) -> col = 0
    final beadWidth = (rodSpacing * 0.88).clamp(24.0, 72.0);
    final beadHeight = (upperDeckHeight * 0.55).clamp(18.0, 44.0);

    final now = DateTime.now();

    for (int col = 0; col < totalRods; col++) {
      final rodIndex = totalRods - 1 - col;
      final rod = state.rods[rodIndex];
      final rodCenterX = frameInnerRect.left + (col + 0.5) * rodSpacing;

      // Base color for this rod
      final Color baseColor = perRodColor
          ? SorobanTheme.perRodColors[rodIndex % SorobanTheme.perRodColors.length]
          : SorobanTheme.beadDefaultColor;

      // 1. Heaven Bead
      // Inactive (heaven == false): resting at top frame (frameInnerRect.top)
      // Active (heaven == true): resting against the beam (beamTop - beadHeight)
      final heavenY = rod.heaven
          ? (beamTop - beadHeight)
          : (frameInnerRect.top + 3.0);

      final heavenKey = 'rod_${rodIndex}_heaven';
      final isHeavenAnimating = animatingBeadKey == heavenKey;
      final heavenTrailTime = trailBeads[heavenKey];
      final double heavenTrailFactor = heavenTrailTime != null
          ? (1.0 - (now.difference(heavenTrailTime).inMilliseconds / 1500.0))
              .clamp(0.0, 1.0)
          : 0.0;

      _drawBead(
        canvas: canvas,
        centerX: rodCenterX,
        y: heavenY,
        width: beadWidth,
        height: beadHeight,
        baseColor: baseColor,
        isActive: rod.heaven,
        isHighlightGlow: isHeavenAnimating,
        trailFactor: heavenTrailFactor,
      );

      // 2. Earth Beads (4 beads)
      // Active count = rod.earth (0..4).
      // Active beads are pushed UP against the beam (beamTop + beamHeight).
      // Inactive beads are pushed DOWN against the bottom frame (frameInnerRect.bottom).
      final activeCount = rod.earth;
      final lowerDeckTop = beamTop + beamHeight;
      final lowerDeckBottom = frameInnerRect.bottom;

      for (int b = 0; b < 4; b++) {
        // b = 0 is the topmost earth bead, b = 3 is the bottommost
        final bool isThisBeadActive = b < activeCount;
        double beadY;

        if (isThisBeadActive) {
          // Pushed up against the beam
          beadY = lowerDeckTop + (b * (beadHeight + 1.0));
        } else {
          // Pushed down against the bottom
          final inactiveIndex = b - activeCount; // 0 .. (4 - activeCount - 1)
          final totalInactive = 4 - activeCount;
          beadY = lowerDeckBottom -
              ((totalInactive - inactiveIndex) * (beadHeight + 1.0));
        }

        final earthKey = 'rod_${rodIndex}_earth_$activeCount';
        final isEarthAnimating = animatingBeadKey == earthKey;
        final earthTrailTime = trailBeads[earthKey];
        final double earthTrailFactor = earthTrailTime != null
            ? (1.0 - (now.difference(earthTrailTime).inMilliseconds / 1500.0))
                .clamp(0.0, 1.0)
            : 0.0;

        _drawBead(
          canvas: canvas,
          centerX: rodCenterX,
          y: beadY,
          width: beadWidth,
          height: beadHeight,
          baseColor: baseColor,
          isActive: isThisBeadActive,
          isHighlightGlow: isEarthAnimating,
          trailFactor: earthTrailFactor,
        );
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
    required double trailFactor,
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

    // Determine bead display color
    Color displayColor;
    if (isHighlightGlow) {
      displayColor = SorobanTheme.brassGlowColor;
    } else if (isActive) {
      displayColor = SorobanTheme.beadActiveColor;
    } else if (trailFactor > 0) {
      displayColor = Color.lerp(
        baseColor,
        SorobanTheme.beadActiveColor,
        trailFactor,
      )!;
    } else {
      displayColor = baseColor;
    }

    // 1. Subtle drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawPath(path.shift(const Offset(1.0, 2.0)), shadowPaint);

    // 2. Brass glow halo if animating or active hint
    if (isHighlightGlow || trailFactor > 0.4) {
      final glowPaint = Paint()
        ..color = SorobanTheme.brassGlowColor.withValues(
          alpha: isHighlightGlow ? 0.7 : (trailFactor * 0.4),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawPath(path, glowPaint);
    }

    // 3. Main bead body gradient (gives volumetric bi-conical bevel feel)
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(displayColor, Colors.white, 0.35)!, // Top highlight ridge
          displayColor,
          Color.lerp(displayColor, Colors.black, 0.3)!, // Bottom shadow bevel
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(Rect.fromLTWH(centerX - halfW, y, width, height));

    canvas.drawPath(path, gradientPaint);

    // 4. Center horizontal ridge seam
    final seamPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(centerX - halfW + 2, centerY),
      Offset(centerX + halfW - 2, centerY),
      seamPaint,
    );

    // 5. Border outline
    final borderPaint = Paint()
      ..color = Color.lerp(displayColor, Colors.black, 0.45)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant SorobanPainter oldDelegate) {
    return true; // Always repaint when controller notifies
  }
}
