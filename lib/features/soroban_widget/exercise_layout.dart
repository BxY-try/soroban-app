import 'soroban_layout.dart';

/// Shared geometry for the exercise screens (Challenge & Practice).
///
/// Both screens lay out the same skeleton — a scaled group holding a fixed
/// left control panel and the Soroban, with the problem text centred on the
/// painted abacus frame — so the numbers that describe that skeleton and the
/// frame maths live here once, instead of being duplicated per screen. That
/// is what keeps both modes centred on the same axis: any change to the
/// layout chain must go through these constants, and the problem text always
/// follows [abacusFrameFor].
class ExerciseLayout {
  ExerciseLayout._();

  /// Scale factor for the main interactive group (left panel + Soroban)
  /// to provide gentle breathing room towards the center without shrinking
  /// excessively.
  static const double groupScale = 0.98;

  /// Scale factor for the Soroban itself inside the group, so the abacus
  /// reads slightly larger than the surrounding chrome while keeping safe
  /// margins.
  static const double sorobanScale = 0.992;

  /// Lifts the whole Soroban block (abacus frame + digital readout) upward by
  /// this many pixels so the space below it is no longer cramped.
  ///
  /// Applied as a paint transform on purpose: the box keeps the exact layout
  /// constraints it had before, so the frame dimensions and the bead size are
  /// untouched — unlike a bottom/top padding change, which would take the
  /// height away from the abacus and shrink the beads.
  static const double sorobanLift = 5.0;

  /// Extra bead travel (px) granted to each deck, widening the heaven↔beam and
  /// beam↔earth gaps at the cost of bead height.
  ///
  /// Sized so the beads land at ~8% above the pre-scale-bump baseline (the
  /// bigger scale requested in 457418a would otherwise inflate them by ~10%,
  /// because the vertical budget is exactly saturated). Both exercise screens
  /// use the same scale chain, so both share the same boost.
  static const double sorobanTravelBoost = 3.92;

  // ── Main area layout chain ─────────────────────────────────────────
  // These values define how the Soroban is positioned horizontally.
  // They are used BOTH by the layout chain itself and by [abacusFrameFor], so
  // the problem text can be centred on the abacus without duplicating numbers.

  /// Horizontal padding around the whole left-panel + Soroban group.
  static const double groupHorizontalPadding = 10.0;

  /// Fixed width of the left control panel.
  static const double leftPanelWidth = 56.0;

  /// Gap between the left control panel and the Soroban.
  static const double leftPanelGap = 12.0;

  /// Margin kept between the problem text and the right screen edge.
  static const double problemTextRightInset = 10.0;

  /// Horizontal geometry of the painted Soroban for a content area
  /// [contentWidth] px wide.
  ///
  /// Mirrors, value for value, the layout chain that positions the SorobanView:
  /// group padding, [groupScale] on the whole group, the fixed left panel plus
  /// [leftPanelGap], then [sorobanScale] on the Soroban itself.
  ///
  /// Both the layout chain and this function read the constants above, and
  /// `widget_test.dart` asserts the problem text lands on the *actually laid
  /// out* frame centre at several screen sizes. That assertion is the drift
  /// guard: if the chain ever changes shape, the text follows this function
  /// instead of the real box, and that test fails.
  ///
  /// [frameCenter] is the centre of the *painted frame*, which is NOT the
  /// centre of the box whenever the left and right gutters differ. That is
  /// exactly the value the problem text should sit on.
  static ({double left, double width, double frameCenter}) abacusFrameFor(
    double contentWidth,
  ) {
    final avail = contentWidth - 2 * groupHorizontalPadding;
    final groupWidth = avail * groupScale;
    final groupLeft = groupHorizontalPadding + (avail - groupWidth) / 2;

    final slotWidth = groupWidth - leftPanelWidth - leftPanelGap;
    final boxWidth = slotWidth > 0.0 ? slotWidth * sorobanScale : 0.0;
    final boxLeft = groupLeft + leftPanelWidth + leftPanelGap +
        (slotWidth - boxWidth) / 2;

    // The frame is inset by the SorobanLayout gutters, which may be asymmetric.
    final gutters = SorobanLayout.guttersFor(boxWidth);
    final frameCenter =
        boxLeft + boxWidth / 2 + (gutters.left - gutters.right) / 2;

    return (left: boxLeft, width: boxWidth, frameCenter: frameCenter);
  }

  /// Left inset of the problem text band that centres it on the abacus frame
  /// while keeping [problemTextRightInset] free on the right.
  ///
  /// With symmetric gutters this returns the historical 78.0 exactly, so
  /// turning both gutter scales to 1.0 restores the previous layout bit for
  /// bit.
  static double problemTextLeftFor(double contentWidth) {
    return 2 * abacusFrameFor(contentWidth).frameCenter -
        contentWidth +
        problemTextRightInset;
  }
}
