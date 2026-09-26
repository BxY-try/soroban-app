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

  static const double travelRatio = 0.65;

  /// Proportional scaling factor for beads to keep them compact,
  /// aesthetically balanced, and comfortably spaced.
  static const double beadScale = 0.90;

  // ── Horizontal gutters ─────────────────────────────────────────────
  // Two INDEPENDENT knobs, one per side. Each one insets the frame from its own
  // side only, and the opposite edge stays pinned exactly where it is today:
  //
  //   rodSpacingScaleRight < 1  ->  left edge stays at 0,  right edge moves left
  //   rodSpacingScaleLeft  < 1  ->  right edge stays at w, left edge moves right
  //   both < 1                  ->  narrows from both sides at once
  //   both == 1                 ->  the original layout, frame fills the box
  //
  // The inset of a side is `(1 - value) * innerWidth` px, and the pixels it
  // frees become empty space on that side.
  //
  // Bead size is deliberately NOT affected by either value: [beadWidth] is
  // derived from the un-shrunk reference inner width, so the beads keep the
  // exact same size and only their X positions shift.

  /// Shrink applied from the RIGHT side. 1.0 = right edge stays on the box edge.
  static const double rodSpacingScaleRight = 0.97;

  /// Shrink applied from the LEFT side. 1.0 = left edge stays on the box edge.
  static const double rodSpacingScaleLeft = 0.99;

  /// Hard floor for the rod pitch, as a fraction of the un-shrunk pitch.
  ///
  /// Bead width is frozen at 84% of that pitch, so shrinking the combined pitch
  /// below this ratio would make neighbouring beads overlap sideways. If both
  /// gutters together would break the floor, [guttersFor] scales them both down
  /// proportionally instead of letting the beads collide.
  static const double minPitchRatio = 0.84;

  final Size size;
  final int totalRods;

  /// Extra bead travel (px) added to EACH deck on top of the proportional
  /// [travelRatio], taken from the bead budget so bead size stays put.
  ///
  /// The vertical budget is exactly saturated:
  /// `h = 2*frameBorder + beamHeight + 3*beadGap + 4*deckPadding + 5*beadHeight + 2*travel`
  /// so any extra height handed to the widget would otherwise inflate the beads.
  /// Growing the widget by `2 * travelBoost` therefore widens the empty gap
  /// between each deck and the beam while [beadHeight] and [beadWidth] remain
  /// exactly the same — and because the boost is a fixed pixel value the result
  /// is identical on every screen size.
  ///
  /// 0.0 keeps the original behaviour: travel is purely proportional to bead size.
  final double travelBoost;

  final Rect frameRect;
  final Rect innerRect;
  final double rodSpacing;
  final double upperDeckHeight;
  final double lowerDeckHeight;
  final double beamTop;
  final double beamBottom;
  final double beadWidth;
  final double beadHeight;
  final double beadPitch;
  final double travelDistance;

  /// Empty space freed on the LEFT of the frame, i.e. its left inset.
  double get leftShrink => frameRect.left;

  /// Empty space freed on the RIGHT of the frame, i.e. how much the right edge
  /// was pulled in from the box edge.
  double get rightShrink => size.width - frameRect.right;

  /// Inner board width BEFORE any gutter is applied. This is the reference used
  /// for the bead size, so the beads never resize when the gutters are tweaked.
  static double _referenceInnerWidth(double sizeWidth) {
    return math.max(0.0, sizeWidth - frameBorder * 2);
  }

  /// Pixels removed from EACH side of the frame for a widget box [sizeWidth] px
  /// wide, honouring the pitch floor.
  ///
  /// [scaleLeft] / [scaleRight] default to [rodSpacingScaleLeft] /
  /// [rodSpacingScaleRight]; they are injectable so callers (and tests) can
  /// evaluate any combination without editing the configured constants.
  static ({double left, double right}) guttersFor(
    double sizeWidth, {
    double? scaleLeft,
    double? scaleRight,
  }) {
    final ref = _referenceInnerWidth(sizeWidth);
    final ls = (scaleLeft ?? rodSpacingScaleLeft).clamp(0.05, 1.0).toDouble();
    final rs = (scaleRight ?? rodSpacingScaleRight).clamp(0.05, 1.0).toDouble();

    // Proportional correction keeping both gutters combined from pushing the rod
    // pitch below [minPitchRatio]. Scaling both by the same factor preserves the
    // left/right balance the caller asked for.
    final total = (1.0 - ls) + (1.0 - rs);
    final allowed = 1.0 - minPitchRatio;
    final factor = total <= allowed ? 1.0 : allowed / total;

    return (
      left: ref * (1.0 - ls) * factor,
      right: ref * (1.0 - rs) * factor,
    );
  }

  /// Pixels removed from the LEFT edge of the frame, using the configured
  /// [rodSpacingScaleLeft]. The RIGHT edge is unaffected by that value.
  static double leftShrinkFor(double sizeWidth) {
    return guttersFor(sizeWidth).left;
  }

  /// Pixels removed from the RIGHT edge of the frame, using the configured
  /// [rodSpacingScaleRight]. The LEFT edge is unaffected by that value.
  static double rightShrinkFor(double sizeWidth) {
    return guttersFor(sizeWidth).right;
  }

  static double _computeAvailableDeckHeight(double sizeHeight) {
    return math.max(
      0.0,
      math.max(0.0, sizeHeight - frameBorder * 2) - beamHeight,
    );
  }

  static double _computeBeadHeight(double sizeHeight, double travelBoost) {
    final available = _computeAvailableDeckHeight(sizeHeight);
    final fixedSpace = 3 * beadGap + 4 * deckPadding;
    // Both decks donate their travel boost to the bead budget, which is what
    // keeps bead size constant while the widget grows.
    final raw =
        (available - fixedSpace - 2 * travelBoost) / (5.0 + 2.0 * travelRatio);
    return math.max(16.0, raw);
  }

  static double _computeTravelDistance(double sizeHeight, double travelBoost) {
    return _computeBeadHeight(sizeHeight, travelBoost) * travelRatio +
        travelBoost;
  }

  /// Outer wooden frame for a widget box [size] px wide, inset by the gutters.
  ///
  /// The left offset and the width both come from the same gutter pair, so the
  /// right edge stays pinned at [Size].width unless [rodSpacingScaleRight] is
  /// below 1, and the left edge stays pinned at 0 unless [rodSpacingScaleLeft]
  /// is below 1.
  static Rect _frameRectFor(Size size, double? scaleLeft, double? scaleRight) {
    final g = guttersFor(size.width, scaleLeft: scaleLeft, scaleRight: scaleRight);
    return Rect.fromLTWH(
      g.left,
      0.0,
      math.max(0.0, size.width - g.left - g.right),
      math.max(0.0, size.height),
    );
  }

  /// Width of the inner board, i.e. the reference width minus both gutters.
  static double _innerBoardWidth(Size size, double? scaleLeft, double? scaleRight) {
    final g = guttersFor(size.width, scaleLeft: scaleLeft, scaleRight: scaleRight);
    return math.max(0.0, _referenceInnerWidth(size.width) - g.left - g.right);
  }

  /// Inner board, inset by the frame border on top of the gutters.
  static Rect _innerRectFor(Size size, double? scaleLeft, double? scaleRight) {
    final g = guttersFor(size.width, scaleLeft: scaleLeft, scaleRight: scaleRight);
    return Rect.fromLTWH(
      g.left + frameBorder,
      frameBorder,
      _innerBoardWidth(size, scaleLeft, scaleRight),
      math.max(0.0, size.height - frameBorder * 2),
    );
  }

  SorobanLayout({
    required this.size,
    required this.totalRods,
    this.travelBoost = 0.0,
    double? spacingScaleLeft,
    double? spacingScaleRight,
  })  : frameRect = _frameRectFor(size, spacingScaleLeft, spacingScaleRight),
        innerRect = _innerRectFor(size, spacingScaleLeft, spacingScaleRight),
        rodSpacing = totalRods > 0
            ? _innerBoardWidth(size, spacingScaleLeft, spacingScaleRight) / totalRods
            : 0.0,
        beadHeight = _computeBeadHeight(size.height, travelBoost),
        travelDistance = _computeTravelDistance(size.height, travelBoost),
        beadPitch = _computeBeadHeight(size.height, travelBoost) + beadGap,
        // Bead width is intentionally measured against the UN-scaled reference
        // width: tightening the rod spacing must never resize the beads.
        beadWidth = ((totalRods > 0
                    ? _referenceInnerWidth(size.width) / totalRods
                    : 0.0) *
                0.84)
            .clamp(18.0, 125.0),
        upperDeckHeight = _computeBeadHeight(size.height, travelBoost) +
            _computeTravelDistance(size.height, travelBoost) +
            2 * deckPadding,
        lowerDeckHeight = 4 * _computeBeadHeight(size.height, travelBoost) +
            3 * beadGap +
            _computeTravelDistance(size.height, travelBoost) +
            2 * deckPadding,
        beamTop = frameBorder +
            _computeBeadHeight(size.height, travelBoost) +
            _computeTravelDistance(size.height, travelBoost) +
            2 * deckPadding,
        beamBottom = frameBorder +
            _computeBeadHeight(size.height, travelBoost) +
            _computeTravelDistance(size.height, travelBoost) +
            2 * deckPadding +
            beamHeight;

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
