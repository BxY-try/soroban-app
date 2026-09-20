/// Identifies whether a bead move affects the heaven bead or earth beads.
enum BeadKind {
  heaven,
  earth,
}

/// Represents an atomic physical motion on the Soroban.
/// One atomic move corresponds to a single finger flick:
/// - Toggling the upper heaven bead (from 0 to 5, or 5 to 0), OR
/// - Sliding earth beads from [from] count to [to] count (0..4).
class BeadMove {
  /// Index of the rod affected (0 = units, rightmost).
  final int rodIndex;

  /// Kind of bead being moved.
  final BeadKind kind;

  /// Previous state:
  /// For heaven: 0 (inactive/up) or 5 (active/down)
  /// For earth: 0..4 (number of active beads before move)
  final int from;

  /// New state:
  /// For heaven: 0 (inactive/up) or 5 (active/down)
  /// For earth: 0..4 (number of active beads after move)
  final int to;

  /// Pause duration before or after this motion in chained animations (~300-400ms).
  final Duration delay;

  /// Optional explanatory note for tutorials or debugging.
  final String? description;

  const BeadMove({
    required this.rodIndex,
    required this.kind,
    required this.from,
    required this.to,
    this.delay = const Duration(milliseconds: 550),
    this.description,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BeadMove &&
          runtimeType == other.runtimeType &&
          rodIndex == other.rodIndex &&
          kind == other.kind &&
          from == other.from &&
          to == other.to;

  @override
  int get hashCode => Object.hash(rodIndex, kind, from, to);

  @override
  String toString() =>
      'BeadMove(rod: $rodIndex, $kind: $from -> $to, delay: ${delay.inMilliseconds}ms${description != null ? ', "$description"' : ''})';
}
