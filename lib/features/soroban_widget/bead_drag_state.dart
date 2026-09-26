/// Floating bead positions of a single rod while a finger is holding it.
///
/// Multi-touch: `SorobanView` keeps one of these per held rod, so several rods
/// can be dragged at the same time. Only the deck the finger actually grabbed
/// is overridden — [earthY] for the lower deck, [heavenY] for the upper one —
/// while the other deck keeps rendering from the (possibly animated) state.
class BeadDragState {
  /// Exact floating Y positions of the 4 earth beads, or null when the lower
  /// deck is not being dragged.
  final List<double>? earthY;

  /// Exact floating Y position of the heaven bead, or null when the upper deck
  /// is not being dragged.
  final double? heavenY;

  const BeadDragState({this.earthY, this.heavenY});
}
