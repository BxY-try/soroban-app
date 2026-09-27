/// One indivisible unit of work inside a checkpoint: the set of rods that must
/// ALL reach their target values before the next group may be touched.
///
/// The grouping is generated explicitly by the engines at plan time. It is
/// never inferred from a flat [BeadMove] list, because "which moves may happen
/// at the same time" is a statement about intent that a move list does not
/// carry: `999 -> 1000` also produces a flat list of three single-bead moves,
/// but they are strictly ordered, whereas the heaven+earth pair of a `9` is
/// free.
///
/// Only the *final* value per rod is stored, not the sequence of flicks that
/// produces it. A rod can always be set directly (toggle heaven, slide earth),
/// so any order that lands on [targets] is equally valid — which is what makes
/// "one rod, two fingers, either order" fall out for free.
class MoveGroup {
  /// Rods this group covers.
  final Set<int> rods;

  /// rodIndex -> the value that rod must hold once this group is finished.
  final Map<int, int> targets;

  MoveGroup(this.rods, this.targets)
      : assert(rods.isNotEmpty, 'a MoveGroup must cover at least one rod'),
        assert(
          rods.every(targets.containsKey),
          'every rod of a MoveGroup needs a target value',
        );

  /// Single-rod group: the common case (one rod, either a heaven+earth pair or
  /// a single bead flick).
  factory MoveGroup.single(int rodIndex, int targetValue) =>
      MoveGroup({rodIndex}, {rodIndex: targetValue});

  @override
  String toString() =>
      targets.entries.map((e) => 'rod${e.key}->${e.value}').join(', ');
}

/// Ordered [MoveGroup]s for one digit checkpoint.
///
/// `groups[i]` must be finished before `groups[i+1]` may be touched. Because
/// one checkpoint may legitimately need several physical gestures
/// (`999 -> 1000` is three groups, therefore three gestures), the group
/// sequence is the progress unit — not the gesture.
class CheckpointPlan {
  /// Ordered groups; later groups belong to later steps of the same digit.
  final List<MoveGroup> groups;

  /// Board value once every group is done. Mirrors the owning
  /// [DigitCheckpoint.targetValue] and is used as a sanity check by the
  /// reconciler, so a mis-grouped engine fails loudly instead of silently
  /// mis-reconciling.
  final int finalTargetValue;

  CheckpointPlan({required this.groups, required this.finalTargetValue})
      : assert(groups.isNotEmpty, 'a CheckpointPlan needs at least one group') {
    // A rod may belong to exactly one group. Without this, the input gating
    // could hand the same rod out twice and "what may be touched next" would
    // stop being well defined.
    assert(
      _rodOwnershipIsUnique(groups),
      'a rod may appear in at most one MoveGroup, got: $groups',
    );
  }

  int get groupCount => groups.length;

  /// Every rod mentioned by the plan, across all groups.
  Set<int> get allRods => {for (final group in groups) ...group.rods};

  static bool _rodOwnershipIsUnique(List<MoveGroup> groups) {
    final seen = <int>{};
    for (final group in groups) {
      for (final rodIndex in group.rods) {
        if (!seen.add(rodIndex)) return false;
      }
    }
    return true;
  }

  @override
  String toString() =>
      'CheckpointPlan(${groups.join(' -> ')} => $finalTargetValue)';
}
