/// Floating bead positions of a single rod while a finger is holding it.
///
/// Multi-touch: `SorobanView` keeps one of these per held rod, so several rods
/// can be dragged at the same time. Only the deck the finger actually grabbed
/// is overridden — [earthY] for the lower deck, [heavenY] for the upper one —
/// while the other deck keeps rendering from the (possibly animated) state.
///
/// The same type also carries the "settling" positions a bead glides through
/// after its finger lifts, so a release never pops a bead into its slot.
class BeadDragState {
  /// Exact floating Y positions of the 4 earth beads, or null when the lower
  /// deck is not being dragged.
  final List<double>? earthY;

  /// Exact floating Y position of the heaven bead, or null when the upper deck
  /// is not being dragged.
  final double? heavenY;

  const BeadDragState({this.earthY, this.heavenY});
}

/// What fingers are touching on one rod, from the moment they land.
///
/// Pointer-down claims a deck immediately, long before the beads move past any
/// threshold. This is what lets the painter show *which* deck each finger owns
/// from the very first frame: a fingertip covers the bead it grabbed, so the
/// cue has to extend past the bead itself (a highlighted deck band) as well as
/// mark the grabbed bead.
class RodTouch {
  /// A finger holds the heaven (upper) deck of this rod.
  final bool heavenHeld;

  /// Index (0..3) of the earth bead a finger grabbed, or null when no finger
  /// holds the earth (lower) deck of this rod.
  final int? earthGrabbedIndex;

  const RodTouch({this.heavenHeld = false, this.earthGrabbedIndex});

  /// A finger holds the earth (lower) deck of this rod.
  bool get earthHeld => earthGrabbedIndex != null;
}
