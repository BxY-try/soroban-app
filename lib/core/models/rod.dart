/// Represents a single column (rod) on a Japanese Soroban.
/// Each rod contains 1 heaven bead (worth 5) and 4 earth beads (worth 1 each).
class Rod {
  /// Whether the upper/heaven bead is moved down against the beam (active).
  /// false = top/inactive (0), true = bottom/active (5).
  final bool heaven;

  /// Number of lower/earth beads pushed up against the beam (active).
  /// Range: 0 to 4.
  final int earth;

  const Rod({
    this.heaven = false,
    this.earth = 0,
  }) : assert(earth >= 0 && earth <= 4, 'Earth beads must be between 0 and 4');

  /// Total value represented on this rod (0..9).
  int get value => (heaven ? 5 : 0) + earth;

  /// Creates a [Rod] from an integer value between 0 and 9.
  factory Rod.fromValue(int value) {
    assert(value >= 0 && value <= 9, 'Rod value must be between 0 and 9');
    final bool heaven = value >= 5;
    final int earth = value % 5;
    return Rod(heaven: heaven, earth: earth);
  }

  Rod copyWith({
    bool? heaven,
    int? earth,
  }) {
    return Rod(
      heaven: heaven ?? this.heaven,
      earth: earth ?? this.earth,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Rod &&
          runtimeType == other.runtimeType &&
          heaven == other.heaven &&
          earth == other.earth;

  @override
  int get hashCode => heaven.hashCode ^ earth.hashCode;

  @override
  String toString() => 'Rod(val: $value, heaven: $heaven, earth: $earth)';
}
