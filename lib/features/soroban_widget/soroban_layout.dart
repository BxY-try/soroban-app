import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Encapsulates geometric calculations, coordinate mappings, hit-testing,
/// and 1D rigid-body bead physics for the Soroban widget.
class SorobanLayout {
  // Shared frame and bead constants
  static const double frameBorder = 12.0;
  static const double beamHeight = 14.0;
  static const double beadGap = 2.0;
  static const double deckPadding = 3.0;

  final Size size;
  final int totalRods;

  final Rect innerRect;
  final double rodSpacing;
  final double upperDeckHeight;
  final double lowerDeckHeight;
  final double beamTop;
  final double beamBottom;
  final double beadWidth;
  final double beadHeight;
  final double beadPitch;

  SorobanLayout({
    required this.size,
    required this.totalRods,
  })  : innerRect = Rect.fromLTWH(
          frameBorder,
          frameBorder,
          math.max(0.0, size.width - frameBorder * 2),
          math.max(0.0, size.height - frameBorder * 2),
        ),
        rodSpacing = totalRods > 0
            ? math.max(0.0, size.width - frameBorder * 2) / totalRods
            : 0.0,
        upperDeckHeight = math.max(
          0.0,
          (math.max(0.0, size.height - frameBorder * 2) - beamHeight) * 0.26,
        ),
        lowerDeckHeight = math.max(
          0.0,
          (math.max(0.0, size.height - frameBorder * 2) - beamHeight) * 0.74,
        ),
        beamTop = frameBorder +
            math.max(
              0.0,
              (math.max(0.0, size.height - frameBorder * 2) - beamHeight) * 0.26,
            ),
        beamBottom = frameBorder +
            math.max(
              0.0,
              (math.max(0.0, size.height - frameBorder * 2) - beamHeight) * 0.26,
            ) +
            beamHeight,
        beadWidth = ((totalRods > 0
                    ? math.max(0.0, size.width - frameBorder * 2) / totalRods
                    : 0.0) *
                0.88)
            .clamp(20.0, 96.0),
        beadHeight = (((math.max(
                            0.0,
                            (math.max(0.0, size.height - frameBorder * 2) -
                                    beamHeight) *
                                0.74,
                          ) *
                          0.55 -
                      3 * beadGap -
                      2 * deckPadding) /
                  4.0))
            .clamp(14.0, 36.0),
        beadPitch = (((math.max(
                            0.0,
                            (math.max(0.0, size.height - frameBorder * 2) -
                                    beamHeight) *
                                0.74,
                          ) *
                          0.55 -
                      3 * beadGap -
                      2 * deckPadding) /
                  4.0))
            .clamp(14.0, 36.0) +
            beadGap;

  /// X coordinate of rod center for a given [rodIndex] (0 = rightmost / units).
  double rodCenterX(int rodIndex) {
    final col = totalRods - 1 - rodIndex;
    return innerRect.left + (col + 0.5) * rodSpacing;
  }

  /// Y coordinate of the heaven bead.
  /// When active: pushed down against beam.
  /// When inactive: pushed up against top inner frame.
  double computeHeavenY(bool isActive) {
    return isActive
        ? (beamTop - deckPadding - beadHeight)
        : (innerRect.top + deckPadding);
  }

  /// Y coordinate of the earth bead at [beadIndex] (0 = closest to beam, 3 = closest to bottom)
  /// given the current [activeCount] (0..4).
  double computeEarthY(int beadIndex, int activeCount) {
    if (beadIndex < activeCount) {
      // Active: anchored from beam bottom downward
      return beamBottom + deckPadding + (beadIndex * beadPitch);
    } else {
      // Inactive: anchored from lower frame border upward
      final totalInactive = 4 - activeCount;
      final inactiveIndex = beadIndex - activeCount;
      return innerRect.bottom -
          deckPadding -
          ((totalInactive - inactiveIndex) * beadPitch) +
          beadGap;
    }
  }

  /// Hit-tests a coordinate to determine rod index and deck ('heaven' or 'earth').
  /// Returns null if outside the frame or on the beam.
  ({int rodIndex, String deck})? hitTest(Offset localPos) {
    if (!innerRect.contains(localPos)) return null;
    if (rodSpacing <= 0) return null;

    final relX = localPos.dx - innerRect.left;
    final col = (relX / rodSpacing).floor().clamp(0, totalRods - 1);
    final rodIndex = totalRods - 1 - col;

    final y = localPos.dy;
    if (y < beamTop) return (rodIndex: rodIndex, deck: 'heaven');
    if (y > beamBottom) return (rodIndex: rodIndex, deck: 'earth');
    return null; // On the beam
  }

  /// Identifies which earth bead (0..3) is closest to [y] in the current state.
  int earthBeadIndexAt(int activeCount, double y) {
    int closestIndex = 0;
    double minDistance = double.infinity;
    for (int b = 0; b < 4; b++) {
      final centerY = computeEarthY(b, activeCount) + (beadHeight / 2.0);
      final dist = (centerY - y).abs();
      if (dist < minDistance) {
        minDistance = dist;
        closestIndex = b;
      }
    }
    return closestIndex;
  }

  /// Simulates 1D rigid-body collision physics when dragging an earth bead.
  ///
  /// - [grabbedIndex]: The bead the user is actively touching (0..3).
  /// - [initialEarthY]: Starting resting Y positions of all 4 beads [y0, y1, y2, y3].
  /// - [deltaY]: Pointer vertical travel (negative = upward / toward beam, positive = downward / away from beam).
  ///
  /// Physical Rules:
  /// 1. Solid beads cannot penetrate each other; adjacent beads maintain at least [beadPitch] spacing.
  /// 2. Moving UP: [grabbedIndex] moves toward beam. If it hits beads ABOVE it (0..grabbedIndex-1),
  ///    it pushes them upward. Beads BELOW [grabbedIndex] are left resting in place.
  /// 3. Moving DOWN: [grabbedIndex] moves away from beam. If it hits beads BELOW it (grabbedIndex+1..3),
  ///    it pushes them downward. Beads ABOVE [grabbedIndex] remain in place.
  /// 4. Boundary clamping prevents pushing beyond beam or frame borders.
  List<double> computeEarthDragPositions({
    required int grabbedIndex,
    required List<double> initialEarthY,
    required double deltaY,
  }) {
    assert(initialEarthY.length == 4);
    assert(grabbedIndex >= 0 && grabbedIndex < 4);

    final minY = List<double>.generate(4, (b) => computeEarthY(b, 4));
    final maxY = List<double>.generate(4, (b) => computeEarthY(b, 0));

    final result = List<double>.from(initialEarthY);
    result[grabbedIndex] = (initialEarthY[grabbedIndex] + deltaY)
        .clamp(minY[grabbedIndex], maxY[grabbedIndex]);

    // Upward push: dragged bead pushes beads above it (b = grabbedIndex - 1 down to 0)
    for (int b = grabbedIndex - 1; b >= 0; b--) {
      if (result[b] > result[b + 1] - beadPitch) {
        result[b] = (result[b + 1] - beadPitch).clamp(minY[b], maxY[b]);
      }
    }

    // Downward push: dragged bead pushes beads below it (b = grabbedIndex + 1 up to 3)
    for (int b = grabbedIndex + 1; b < 4; b++) {
      if (result[b] < result[b - 1] + beadPitch) {
        result[b] = (result[b - 1] + beadPitch).clamp(minY[b], maxY[b]);
      }
    }

    return result;
  }

  /// Resolves the final committed active earth count (0..4) based on final bead Y positions.
  int resolveEarthActiveCount(List<double> currentEarthY) {
    int count = 0;
    for (int b = 0; b < 4; b++) {
      final midY = (computeEarthY(b, 4) + computeEarthY(b, 0)) / 2.0;
      if (currentEarthY[b] < midY) {
        count = b + 1;
      }
    }
    return count;
  }

  /// Computes heaven bead Y position during drag with direct 1-to-1 pixel tracking.
  double computeHeavenDragY(bool initialActive, double deltaY) {
    final minY = computeHeavenY(false); // Inactive (top)
    final maxY = computeHeavenY(true); // Active (near beam)
    final startY = computeHeavenY(initialActive);
    return (startY + deltaY).clamp(minY, maxY);
  }

  /// Resolves final heaven active state based on position relative to midpoint.
  bool resolveHeavenActive(double currentHeavenY) {
    final midY = (computeHeavenY(false) + computeHeavenY(true)) / 2.0;
    return currentHeavenY > midY;
  }
}
