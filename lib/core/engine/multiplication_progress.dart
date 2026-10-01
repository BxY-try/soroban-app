import '../models/problem.dart';

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}

int _multiplicandIndexOf(MultiplicationContribution c) => c.multiplicandIndex;
int _multiplierIndexOf(MultiplicationContribution c) => c.multiplierIndex;

/// One digit-by-digit product that the board has to accumulate: the multiplicand
/// digit at [multiplicandIndex] times the multiplier digit at [multiplierIndex],
/// placed at [rodIndex].
///
/// `1234 × 23` is the sum of eight of these (`1 × 2` at rod 4, `2 × 2` at rod 3,
/// ... `4 × 3` at rod 0). The board is correct when it holds *some subset* of
/// them, in whatever order the user chose to add them: addition is commutative,
/// so the order is a habit, not a rule.
class MultiplicationContribution {
  const MultiplicationContribution({
    required this.index,
    required this.multiplicandIndex,
    required this.multiplierIndex,
    required this.multiplicandDigit,
    required this.multiplierDigit,
    required this.rodIndex,
  });

  /// Position in the canonical teaching order (see [decompose]). Also the
  /// identity of the contribution everywhere else.
  final int index;

  /// Position of the multiplicand digit (0 = leftmost).
  final int multiplicandIndex;

  /// Position of the multiplier digit (0 = leftmost).
  final int multiplierIndex;

  final int multiplicandDigit;
  final int multiplierDigit;

  /// Rod the units digit of the digit product lands on (0 = units). A product
  /// of 10 or more also touches the rod above it.
  final int rodIndex;

  /// The digit product, 1..81.
  int get partial => multiplicandDigit * multiplierDigit;

  /// What this contribution adds to the board.
  int get value => partial * _pow10(rodIndex);

  /// Splits `multiplicand × multiplier` into contributions, in the canonical
  /// teaching order: multiplier digits left to right and, within each, the
  /// multiplicand digits left to right. Digit products of zero add nothing and
  /// are left out, as is anything that would not fit on [rodCount] rods.
  ///
  /// Both operands must be non-negative.
  static List<MultiplicationContribution> decompose({
    required int multiplicand,
    required int multiplier,
    int rodCount = 7,
  }) {
    assert(
      multiplicand >= 0 && multiplier >= 0,
      'operands must not be negative',
    );
    final a = multiplicand.toString();
    final b = multiplier.toString();
    final contributions = <MultiplicationContribution>[];

    for (var j = 0; j < b.length; j++) {
      final multiplierDigit = int.parse(b[j]);
      final multiplierExponent = b.length - 1 - j;

      for (var i = 0; i < a.length; i++) {
        final multiplicandDigit = int.parse(a[i]);
        final partial = multiplicandDigit * multiplierDigit;
        if (partial == 0) continue;

        final rodIndex = (a.length - 1 - i) + multiplierExponent;
        final topRod = partial >= 10 ? rodIndex + 1 : rodIndex;
        if (topRod >= rodCount) continue;

        contributions.add(MultiplicationContribution(
          index: contributions.length,
          multiplicandIndex: i,
          multiplierIndex: j,
          multiplicandDigit: multiplicandDigit,
          multiplierDigit: multiplierDigit,
          rodIndex: rodIndex,
        ));
      }
    }

    return List.unmodifiable(contributions);
  }

  @override
  String toString() => 'MultiplicationContribution($partial @ rod $rodIndex)';
}

/// Progress through a multiplication, read from the board instead of from a
/// chain.
///
/// A multiplication is a *set* of [MultiplicationContribution]s. The board is a
/// valid intermediate state when its value equals the sum of some subset of
/// them, and that value is all it takes: `SorobanState.value` encodes every rod,
/// so there is nothing else to check. Which subset it is, and what to suggest
/// next, are the two questions this class answers ([explain], [nextContribution]).
///
/// Nothing here enumerates the orders a user might work in. Recognition is a
/// subset-sum lookup over the contributions themselves: there is at most one per
/// pair of digits, so 10 for the hardest difficulty in the app and 16 at the
/// very most on 7 rods. The search is pruned by a largest-first bound, and it
/// costs the same however the user got to the board.
///
/// Pure Dart with no Flutter and no bead mechanics: turning a contribution into
/// finger movements is `MultiplicationEngine.contributionMoves`.
class MultiplicationProgress {
  /// Contributions of `multiplicand × multiplier`, see
  /// [MultiplicationContribution.decompose].
  MultiplicationProgress({
    required int multiplicand,
    required int multiplier,
    int rodCount = 7,
  }) : this._(MultiplicationContribution.decompose(
          multiplicand: multiplicand,
          multiplier: multiplier,
          rodCount: rodCount,
        ));

  MultiplicationProgress._(this.contributions)
      : _rows = _groupIndices(contributions, _multiplierIndexOf),
        _columns = _groupIndices(contributions, _multiplicandIndexOf);

  /// The progress model of [problem], or null when [problem] is not one this
  /// class can speak for.
  ///
  /// That is the case for anything but a two-operand multiplication, and also
  /// for a multiplication whose checkpoint chain is not the canonical chain of
  /// its own operands: the checkpoints then describe some other board sequence
  /// and the operands cannot be trusted to explain them. Callers fall back to
  /// the linear chain, as they always did.
  static MultiplicationProgress? forProblem(Problem problem, {int rodCount = 7}) {
    final isMultiplication =
        problem.category == ProblemCategory.multiplication1 ||
            problem.category == ProblemCategory.multiplication2;
    if (!isMultiplication || problem.terms.length != 2) return null;

    final multiplicand = problem.terms[0];
    final multiplier = problem.terms[1];
    if (multiplicand <= 0 || multiplier <= 0) return null;

    final progress = MultiplicationProgress(
      multiplicand: multiplicand,
      multiplier: multiplier,
      rodCount: rodCount,
    );
    final checkpoints = problem.checkpoints;
    if (progress.contributions.isEmpty ||
        checkpoints.length != progress.contributions.length) {
      return null;
    }

    // Each canonical checkpoint adds exactly one contribution, so its target is
    // the running sum of the contribution values.
    var running = 0;
    for (var k = 0; k < checkpoints.length; k++) {
      running += progress.contributions[k].value;
      if (checkpoints[k].targetValue != running) return null;
    }
    return progress;
  }

  final List<MultiplicationContribution> contributions;

  /// Contribution indices grouped by multiplier digit / multiplicand digit.
  final List<List<int>> _rows;
  final List<List<int>> _columns;

  /// What the board holds once every contribution is on it: the product.
  int get total => valueOf([for (final c in contributions) c.index]);

  /// Sum of the given contributions.
  int valueOf(Iterable<int> credited) {
    var sum = 0;
    for (final k in credited) {
      sum += contributions[k].value;
    }
    return sum;
  }

  /// Which contributions a board of [boardValue] represents, or null when it is
  /// not an accumulation of contributions at all (a stray bead, a half-done
  /// digit, a wrong product).
  ///
  /// [preferred] is what the caller already credited, in the order it was
  /// credited. It is only ever a preference: the board decides. When the board
  /// is the preferred set plus more contributions, exactly that is returned; when
  /// it is not (the user took the work apart and built something else) the
  /// closest valid explanation is, which may drop contributions from
  /// [preferred].
  ///
  /// Several contributions can share a value (`3 × 2` and `2 × 3` both put 6 on
  /// rod 2), and then the board cannot say which one the user meant. Ties are
  /// broken toward the user's own pattern: the contribution
  /// [nextContribution] expects, then whole multiplier rows and multiplicand
  /// columns, then fewer contributions.
  Set<int>? explain(int boardValue, {Iterable<int> preferred = const <int>[]}) {
    if (boardValue < 0) return null;

    final order = preferred.toList();
    final credited = order.toSet();
    final creditedValue = valueOf(credited);
    if (boardValue == creditedValue) return credited;

    if (boardValue > creditedValue) {
      final added = _bestCompletion(
        boardValue - creditedValue,
        base: credited,
        order: order,
      );
      if (added != null) return <int>{...credited, ...added};
    }

    return _bestCompletion(boardValue, base: const <int>{}, order: order);
  }

  /// [previous] with everything not in [completed] removed and whatever is new
  /// in [completed] appended in canonical order: the order in which the caller
  /// should now consider the contributions credited.
  List<int> ordered(Iterable<int> previous, Set<int> completed) {
    final kept = [
      for (final k in previous)
        if (completed.contains(k)) k,
    ];
    final keptSet = kept.toSet();
    final added = [
      for (final c in contributions)
        if (completed.contains(c.index) && !keptSet.contains(c.index)) c.index,
    ];
    return [...kept, ...added];
  }

  /// The contribution to do after [order] (the ones already on the board, oldest
  /// first), or null when there is nothing left.
  ///
  /// It continues the user's own pattern instead of a fixed script. The pattern
  /// is read off the last contributions: worked row by row (one multiplier digit
  /// at a time) or column by column (one multiplicand digit at a time), and in
  /// which direction along the row and along the next. Finished the current row,
  /// it moves to the nearest unfinished one in the direction the user was going,
  /// entering it from the same end. With nothing to read a pattern from (an
  /// empty board, or a board reached in one jump) it falls back to the canonical
  /// order, so a user following the canonical chain is followed exactly.
  MultiplicationContribution? nextContribution(Iterable<int> order) {
    final worked = [for (final k in order) contributions[k]];
    final done = worked.map((c) => c.index).toSet();
    final remaining = [
      for (final c in contributions)
        if (!done.contains(c.index)) c,
    ];
    if (remaining.isEmpty) return null;
    if (worked.isEmpty) return remaining.first;

    var rowPairs = 0;
    var columnPairs = 0;
    for (var k = 1; k < worked.length; k++) {
      final before = worked[k - 1];
      final after = worked[k];
      if (before.multiplierIndex == after.multiplierIndex &&
          before.multiplicandIndex != after.multiplicandIndex) {
        rowPairs++;
      } else if (before.multiplicandIndex == after.multiplicandIndex &&
          before.multiplierIndex != after.multiplierIndex) {
        columnPairs++;
      }
    }

    // `major` is the axis the user finishes one group of at a time, `minor` the
    // axis they walk along inside it.
    final columnMajor = columnPairs > rowPairs;
    final int Function(MultiplicationContribution) major =
        columnMajor ? _multiplicandIndexOf : _multiplierIndexOf;
    final int Function(MultiplicationContribution) minor =
        columnMajor ? _multiplierIndexOf : _multiplicandIndexOf;

    final minorStep = _direction(
      worked,
      (a, b) => major(a) == major(b) && minor(a) != minor(b),
      minor,
    );
    final majorStep = _direction(
      worked,
      (a, b) => major(a) != major(b),
      major,
    );

    final last = worked.last;
    final sameGroup = [
      for (final c in remaining)
        if (major(c) == major(last)) c,
    ];
    if (sameGroup.isNotEmpty) {
      return _closest(sameGroup, from: minor(last), step: minorStep, axis: minor);
    }

    final nextGroupKey = major(
      _closest(remaining, from: major(last), step: majorStep, axis: major),
    );
    final nextGroup = [
      for (final c in remaining)
        if (major(c) == nextGroupKey) c,
    ];
    // `remaining` is in canonical order, so a group is ascending along `minor`.
    return minorStep >= 0 ? nextGroup.first : nextGroup.last;
  }

  /// Whether every contribution that involves one digit of the problem is in
  /// [completed]. [termIndex] 0 is the multiplicand, 1 the multiplier;
  /// [digitIndex] counts from the left. A digit that never contributes anything
  /// (a zero) counts as complete.
  bool isDigitComplete(
    Iterable<int> completed, {
    required int termIndex,
    required int digitIndex,
  }) {
    final done = completed.toSet();
    for (final c in contributions) {
      final involved = termIndex == 0
          ? c.multiplicandIndex == digitIndex
          : c.multiplierIndex == digitIndex;
      if (involved && !done.contains(c.index)) return false;
    }
    return true;
  }

  // --- Internals -------------------------------------------------------------

  static List<List<int>> _groupIndices(
    List<MultiplicationContribution> contributions,
    int Function(MultiplicationContribution) key,
  ) {
    final groups = <int, List<int>>{};
    for (final c in contributions) {
      groups.putIfAbsent(key(c), () => <int>[]).add(c.index);
    }
    return groups.values.toList(growable: false);
  }

  /// Contributions outside [base] that add up to exactly [target], chosen among
  /// all the ways to do so, or null when there is none.
  Set<int>? _bestCompletion(
    int target, {
    required Set<int> base,
    required List<int> order,
  }) {
    if (target == 0) return <int>{};

    // Largest first, so the running bound below cuts whole branches early.
    final pool = <int>[
      for (final c in contributions)
        if (!base.contains(c.index)) c.index,
    ]..sort((a, b) {
        final byValue = contributions[b].value.compareTo(contributions[a].value);
        return byValue != 0 ? byValue : a.compareTo(b);
      });

    // suffix[p] = the most the contributions from pool[p] onward can still add.
    final suffix = List<int>.filled(pool.length + 1, 0);
    for (var p = pool.length - 1; p >= 0; p--) {
      suffix[p] = suffix[p + 1] + contributions[pool[p]].value;
    }

    final found = <List<int>>[];
    final chosen = <int>[];

    void search(int at, int remaining) {
      if (remaining == 0) {
        found.add(List<int>.of(chosen));
        return;
      }
      if (at == pool.length || suffix[at] < remaining) return;

      final k = pool[at];
      final value = contributions[k].value;
      if (value <= remaining) {
        chosen.add(k);
        search(at + 1, remaining - value);
        chosen.removeLast();
      }
      search(at + 1, remaining);
    }

    search(0, target);
    if (found.isEmpty) return null;

    // Only equal-valued contributions (or coincidental sums) make more than one
    // way; asking where the user is heading is only worth it then.
    final expected = found.length > 1 ? nextContribution(order) : null;
    final credited = order.toSet();

    List<int>? best;
    List<int>? bestScore;
    for (final candidate in found) {
      final whole = <int>{...base, ...candidate};
      final score = [
        whole.where(credited.contains).length,
        expected != null && whole.contains(expected.index) ? 1 : 0,
        _rows.where((row) => row.every(whole.contains)).length,
        _columns.where((column) => column.every(whole.contains)).length,
        -whole.length,
      ];
      if (bestScore == null || _compareScores(score, bestScore) > 0) {
        best = candidate;
        bestScore = score;
      }
    }
    return best?.toSet();
  }

  static int _compareScores(List<int> a, List<int> b) {
    for (var i = 0; i < a.length; i++) {
      final byKey = a[i].compareTo(b[i]);
      if (byKey != 0) return byKey;
    }
    return 0;
  }

  /// Which way the user last moved along [axis] between two consecutive
  /// contributions that satisfy [applies]: +1 up, -1 down, +1 when they never did.
  static int _direction(
    List<MultiplicationContribution> worked,
    bool Function(MultiplicationContribution, MultiplicationContribution) applies,
    int Function(MultiplicationContribution) axis,
  ) {
    for (var k = worked.length - 1; k > 0; k--) {
      final before = worked[k - 1];
      final after = worked[k];
      if (applies(before, after)) return axis(after) > axis(before) ? 1 : -1;
    }
    return 1;
  }

  static const int _wrapAround = 1 << 16;

  /// The item nearest to [from] along [axis] in the direction of [step]; items
  /// behind it count as further away than anything ahead.
  static MultiplicationContribution _closest(
    List<MultiplicationContribution> items, {
    required int from,
    required int step,
    required int Function(MultiplicationContribution) axis,
  }) {
    int rank(MultiplicationContribution c) {
      final offset = (axis(c) - from) * step;
      return offset > 0 ? offset : _wrapAround - offset;
    }

    return items.reduce((a, b) => rank(b) < rank(a) ? b : a);
  }
}
