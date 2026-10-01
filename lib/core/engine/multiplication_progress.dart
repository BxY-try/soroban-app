import '../models/problem.dart';

int _pow10(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}

/// The most rods the arithmetic below is exact for. `10^15 - 1` is the largest
/// all-nines value a JavaScript number holds exactly (the app also targets the
/// web), and a product that fits on the board then fits in an `int` everywhere.
const int _maxRodCount = 15;

/// The largest value a board of [rodCount] rods can show: 9, 99, 999, ...
///
/// The one place a rod count is turned into a capacity, and the one place a
/// nonsensical rod count is refused.
int _capacity(int rodCount) {
  if (rodCount < 1 || rodCount > _maxRodCount) {
    throw ArgumentError.value(
      rodCount,
      'rodCount',
      'must be between 1 and $_maxRodCount',
    );
  }
  return _pow10(rodCount) - 1;
}

/// Refuses [problem] as a multiplication. Plain message on purpose: a
/// malformed problem may not even have a printable equation.
Never _rejectProblem(Problem problem, String reason) {
  throw ArgumentError(
    'not a playable multiplication (terms ${problem.terms}, expected '
    '${problem.expectedResult}): $reason',
  );
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
  ///
  /// Two contributions can have the same value on the same rod (`12 × 12` has
  /// `2 × 1` and `1 × 2`, both 20 on rod 1) and are still two contributions:
  /// the product needs both, and they are told apart by this index and by their
  /// digit positions, never by `(value, rodIndex)`. Merging them would make the
  /// board expect fewer contributions than the user has to execute.
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

  /// Whether `multiplicand × multiplier` can be shown on a board of [rodCount]
  /// rods, which is to say whether it is at most `10^rodCount - 1`. False for a
  /// negative operand.
  ///
  /// This is the whole representability rule and the only place it is written
  /// down: [decompose], [MultiplicationProgress.forProblem] and the problem
  /// generator all ask it, so they cannot disagree.
  ///
  /// It is a statement about the *product*, not about each contribution. A
  /// contribution is never larger than the product, so a product that fits
  /// takes every contribution with it; and the contributions add up to the
  /// product, so one that does not fit cannot be held by the board however the
  /// pieces are cut. Looking at the contributions one by one (what [decompose]
  /// used to do) is therefore not enough: `3 × 34` on two rods has no
  /// contribution that sticks out, yet it needs a board that shows 102 and
  /// this one stops at 99.
  static bool fitsOnBoard({
    required int multiplicand,
    required int multiplier,
    int rodCount = 7,
  }) {
    final capacity = _capacity(rodCount);
    if (multiplicand < 0 || multiplier < 0) return false;
    if (multiplicand == 0 || multiplier == 0) return true;
    // `a × b <= capacity` written as `a <= capacity ~/ b`: the same answer for
    // positive integers, and it cannot overflow.
    return multiplicand <= capacity ~/ multiplier;
  }

  /// Splits `multiplicand × multiplier` into contributions, in the canonical
  /// teaching order: multiplier digits left to right and, within each, the
  /// multiplicand digits left to right. Digit products of zero add nothing and
  /// are left out; nothing else is.
  ///
  /// The contributions therefore always add up to exactly the product. When
  /// that cannot be so, because a negative operand or because the product does
  /// not fit on [rodCount] rods ([fitsOnBoard]), this throws an
  /// [ArgumentError] instead of returning part of the answer: a decomposition
  /// that silently left something out would still look consistent, and
  /// everything built on it (checkpoints, Hint, "solved") would agree on the
  /// wrong product. Thrown, not asserted, because assertions are ignored in
  /// release builds.
  static List<MultiplicationContribution> decompose({
    required int multiplicand,
    required int multiplier,
    int rodCount = 7,
  }) {
    if (multiplicand < 0 || multiplier < 0) {
      throw ArgumentError(
        'operands must not be negative: $multiplicand × $multiplier',
      );
    }
    if (!fitsOnBoard(
      multiplicand: multiplicand,
      multiplier: multiplier,
      rodCount: rodCount,
    )) {
      throw ArgumentError(
        '$multiplicand × $multiplier does not fit on $rodCount rods '
        '(the board tops out at ${_capacity(rodCount)})',
      );
    }

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

        contributions.add(MultiplicationContribution(
          index: contributions.length,
          multiplicandIndex: i,
          multiplierIndex: j,
          multiplicandDigit: multiplicandDigit,
          multiplierDigit: multiplierDigit,
          rodIndex: (a.length - 1 - i) + multiplierExponent,
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
///
/// What this class can rely on, because it cannot be built without it:
///
///  * the product fits on the board ([MultiplicationContribution.fitsOnBoard]);
///  * the contributions add up to exactly the product ([total]).
///
/// So "every contribution is on the board" and "the board shows the product"
/// are the same statement, which is what makes solved-state trustworthy.
class MultiplicationProgress {
  /// Contributions of `multiplicand × multiplier`, see
  /// [MultiplicationContribution.decompose]. Throws an [ArgumentError] when the
  /// product does not fit on [rodCount] rods.
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

  /// The progress model of [problem]: null for a problem that is not a
  /// multiplication, a verified model for one that is, and an [ArgumentError]
  /// for one that claims to be a multiplication and is not a playable one.
  ///
  /// There is deliberately no third answer. A multiplication that cannot be
  /// explained used to fall back to the linear chain, which trusts the
  /// problem's own checkpoints: a chain that stops short of the product (or is
  /// someone else's) would then be "solved" at a board that is not the answer.
  /// So a multiplication is refused here, once, at the boundary where problems
  /// enter, and nothing downstream has to wonder.
  ///
  /// Playable means, for [rodCount] rods:
  ///
  ///  * two positive operands whose product fits on the board;
  ///  * `expectedResult` is that product;
  ///  * the contributions add up to it;
  ///  * the checkpoints are the canonical chain of those very operands, one per
  ///    contribution, each target the running sum.
  ///
  /// The last one is why the final checkpoint, `expectedResult`, the product
  /// and the board a solved problem shows are all the same number.
  static MultiplicationProgress? forProblem(Problem problem, {int rodCount = 7}) {
    final isMultiplication =
        problem.category == ProblemCategory.multiplication1 ||
            problem.category == ProblemCategory.multiplication2;
    if (!isMultiplication) return null;

    if (problem.terms.length != 2) {
      _rejectProblem(problem, 'a multiplication has exactly two operands');
    }
    final multiplicand = problem.terms[0];
    final multiplier = problem.terms[1];
    if (multiplicand <= 0 || multiplier <= 0) {
      _rejectProblem(problem, 'both operands must be positive');
    }
    // Before the product is computed, not after: two huge operands multiply
    // into an `int` that wraps around without a sound, and the comparison
    // below would then be made against a number that is not the product.
    if (!MultiplicationContribution.fitsOnBoard(
      multiplicand: multiplicand,
      multiplier: multiplier,
      rodCount: rodCount,
    )) {
      _rejectProblem(problem, 'the product does not fit on $rodCount rods');
    }

    final product = multiplicand * multiplier;
    if (problem.expectedResult != product) {
      _rejectProblem(problem, 'expectedResult must be the product, $product');
    }

    final progress = MultiplicationProgress(
      multiplicand: multiplicand,
      multiplier: multiplier,
      rodCount: rodCount,
    );
    if (progress.total != product) {
      _rejectProblem(
        problem,
        'its contributions add up to ${progress.total}, not $product',
      );
    }

    final checkpoints = problem.checkpoints;
    if (checkpoints.length != progress.contributions.length) {
      _rejectProblem(
        problem,
        '${checkpoints.length} checkpoints for '
        '${progress.contributions.length} contributions',
      );
    }

    // Each canonical checkpoint adds exactly one contribution, so its target is
    // the running sum of the contribution values.
    var running = 0;
    for (var k = 0; k < checkpoints.length; k++) {
      running += progress.contributions[k].value;
      if (checkpoints[k].targetValue != running) {
        _rejectProblem(
          problem,
          'checkpoint $k targets ${checkpoints[k].targetValue}, '
          'the canonical chain reaches $running',
        );
      }
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
  /// rod 2), and then the board cannot say which one the user meant. That is
  /// not a defect to repair: the board is the only truth there is, and both
  /// explanations are correct about everything the board can show (value,
  /// count, what is left to do). They differ only in which digit is dimmed and
  /// which contribution Hint suggests next, so the choice just has to be sound
  /// and, above all, stable. Ties are broken toward the user's own pattern: the
  /// contribution [nextContribution] expects, then whole multiplier rows and
  /// multiplicand columns, then fewer contributions, and finally the one whose
  /// contributions come first in the canonical teaching order. That last step
  /// makes the answer a function of the inputs alone, not of the order in which
  /// the search happens to stumble on the candidates.
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
      final ascending = [...candidate]..sort();
      final score = [
        whole.where(credited.contains).length,
        expected != null && whole.contains(expected.index) ? 1 : 0,
        _rows.where((row) => row.every(whole.contains)).length,
        _columns.where((column) => column.every(whole.contains)).length,
        -whole.length,
        // Last resort: the candidate that comes first in canonical order wins
        // (earlier indices score higher). Two candidates only get here when
        // they have the same size, so these tails are the same length.
        for (final k in ascending) -k,
      ];
      if (bestScore == null || _compareScores(score, bestScore) > 0) {
        best = candidate;
        bestScore = score;
      }
    }
    return best?.toSet();
  }

  static int _compareScores(List<int> a, List<int> b) {
    final shared = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < shared; i++) {
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
