import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/soroban_controller.dart';
import 'soroban_painter.dart';

/// Interactive Soroban widget that displays the procedural abacus
/// and translates touch/pointer gestures into natural bead motions.
class SorobanView extends StatelessWidget {
  const SorobanView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SorobanController>();

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) {
            _handleTap(details.localPosition, constraints.biggest, controller);
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: SorobanPainter(
              state: controller.state,
              perRodColor: controller.perRodColor,
              animatingBeadKey: controller.animatingBeadKey,
              trailBeads: controller.trailBeads,
            ),
          ),
        );
      },
    );
  }

  void _handleTap(
    Offset localPos,
    Size size,
    SorobanController controller,
  ) {
    if (controller.isAnimating) return;

    const frameBorder = 14.0;
    const beamHeight = 16.0;

    final frameInnerRect = Rect.fromLTWH(
      frameBorder,
      frameBorder,
      size.width - (frameBorder * 2),
      size.height - (frameBorder * 2),
    );

    if (!frameInnerRect.contains(localPos)) return;

    final totalRods = controller.state.rods.length;
    final usableWidth = frameInnerRect.width;
    final rodSpacing = usableWidth / totalRods;

    // Determine column clicked
    final relX = localPos.dx - frameInnerRect.left;
    final col = (relX / rodSpacing).floor().clamp(0, totalRods - 1);

    // Rod index from right: (totalRods - 1 - col)
    final rodIndex = totalRods - 1 - col;

    // Determine deck
    final innerHeight = frameInnerRect.height;
    final upperDeckHeight = (innerHeight - beamHeight) * 0.30;
    final beamTop = frameInnerRect.top + upperDeckHeight;
    final beamBottom = beamTop + beamHeight;

    final y = localPos.dy;

    if (y < beamTop) {
      // Clicked in Upper Deck -> Toggle Heaven Bead
      controller.tapHeavenBead(rodIndex);
    } else if (y > beamBottom) {
      // Clicked in Lower Deck -> Earth Beads
      final lowerDeckHeight = frameInnerRect.bottom - beamBottom;
      final relLowerY = y - beamBottom;
      final normalizedFraction = (relLowerY / lowerDeckHeight).clamp(0.0, 1.0);

      // Top of lower deck is 1, bottom is 4
      int targetCount;
      if (normalizedFraction < 0.25) {
        targetCount = 1;
      } else if (normalizedFraction < 0.50) {
        targetCount = 2;
      } else if (normalizedFraction < 0.75) {
        targetCount = 3;
      } else {
        targetCount = 4;
      }

      controller.tapEarthBead(rodIndex, targetCount);
    }
  }
}
