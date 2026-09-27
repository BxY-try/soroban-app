import 'bead_move.dart';
import 'soroban_state.dart';

/// Record of one *physical* gesture: from the moment the first finger claims a
/// rod until the last finger lifts.
///
/// The board stays the single source of truth. This class is an observation of
/// what happened, not a container for progress — which is exactly why an
/// interrupted gesture can be thrown away without rolling the board back, and
/// why progress made by earlier gestures of the same checkpoint survives: it
/// lives in the beads, not here.
///
/// [moves] is intentionally *not* replayed by the reconciler. Reconciliation
/// compares the board against the active `CheckpointPlan`, so a gesture that
/// reordered two equivalent moves (heaven before earth, or the reverse) is
/// treated identically to any other order.
class GestureTransaction {
  /// Monotonic id, only used for debugging.
  final String id;

  /// Board as it stood when the first finger of this gesture claimed a rod.
  ///
  /// Groups already satisfied by an earlier gesture are not re-checked against
  /// this baseline, so a fresh baseline per gesture is enough to enforce
  /// "do not touch a later group's rod yet".
  final SorobanState baselineState;

  /// Commits in the order they happened. Diagnostics only.
  final List<BeadMove> moves = [];

  /// Rods that received at least one commit during this gesture.
  final Set<int> touchedRods = {};

  /// Pointers that participated. Diagnostics only.
  final Set<int> pointerIds = {};

  GestureTransaction({required this.id, required this.baselineState});

  /// A gesture that committed nothing (finger went down, never moved) still
  /// reconciles — harmlessly, since the board is unchanged.
  bool get isEmpty => moves.isEmpty;

  @override
  String toString() =>
      'GestureTransaction($id, rods: $touchedRods, moves: ${moves.length})';
}
