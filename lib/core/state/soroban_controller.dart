import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../engine/addition_engine.dart';
import '../engine/hint_engine.dart';
import '../engine/problem_generator.dart';
import '../models/bead_move.dart';
import '../models/problem.dart';
import '../models/soroban_state.dart';
import '../services/sound_service.dart';

/// Single source of truth managing Soroban state, chained animations,
/// trail highlights, hint execution, replay rollback, and challenge sessions.
class SorobanController extends ChangeNotifier {
  final AdditionEngine additionEngine;
  final HintEngine hintEngine;
  final ProblemGenerator problemGenerator;

  SorobanController({
    this.additionEngine = const AdditionEngine(),
    this.hintEngine = const HintEngine(),
    ProblemGenerator? generator,
  }) : problemGenerator = generator ?? ProblemGenerator();

  // --- Abacus State ---
  SorobanState _state = SorobanState.zero();
  SorobanState get state => _state;

  /// Snapshots saved at the beginning of each checkpoint for reset & replay.
  final List<SorobanState> _checkpointSnapshots = [SorobanState.zero()];
  List<SorobanState> get checkpointSnapshots =>
      List.unmodifiable(_checkpointSnapshots);

  // --- Active Problem & Session ---
  Problem? _currentProblem;
  Problem? get currentProblem => _currentProblem;

  List<Problem> _challengeProblems = [];
  int _challengeIndex = 0;
  int get challengeIndex => _challengeIndex;
  int get totalChallengeProblems => _challengeProblems.length;

  int _activeCheckpointIndex = 0;
  int get activeCheckpointIndex => _activeCheckpointIndex;

  bool _isChallengeMode = false;
  bool get isChallengeMode => _isChallengeMode;

  bool _isChallengeCompleted = false;
  bool get isChallengeCompleted => _isChallengeCompleted;

  // --- Timer ---
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  int _elapsedMilliseconds = 0;
  int get elapsedMilliseconds => _elapsedMilliseconds;

  /// Whole seconds of the running challenge, for the on-screen clock.
  ///
  /// The clock face only changes once a second, so it listens to this instead
  /// of the controller: a [ValueNotifier] tells its listeners only when the
  /// value actually changes. The 100 ms tick used to call [notifyListeners],
  /// which rebuilt every `context.watch` on the screen ten times a second to
  /// redraw a label that changes once.
  final ValueNotifier<int> _elapsedSeconds = ValueNotifier<int>(0);
  ValueListenable<int> get elapsedSeconds => _elapsedSeconds;

  // --- Animation & Interaction Lock ---
  bool _isAnimating = false;
  bool get isAnimating => _isAnimating;

  /// Currently highlighted bead during chained animation: 'rod_heaven' or 'rod_earth_N'
  String? _animatingBeadKey;
  String? get animatingBeadKey => _animatingBeadKey;

  // --- Trail Highlight (Fades out over 1.5s) ---
  /// Map of bead key -> timestamp when touched
  final Map<String, DateTime> _trailBeads = {};
  Map<String, DateTime> get trailBeads => Map.unmodifiable(_trailBeads);

  // --- Hint Execution Tracking (for Replay gating) ---
  /// Tracks the checkpoint index of the last successfully executed hint.
  /// null means no hint has been executed yet for the current problem/checkpoint.
  int? _lastHintCheckpointIndex;

  // --- Settings & Records ---
  bool _perRodColor = false;
  bool get perRodColor => _perRodColor;

  bool _soundEnabled = true;
  bool get soundEnabled => _soundEnabled;

  /// Whether a bead can be moved by a simple tap/click instead of a drag.
  ///
  /// Off by default: beads are drag-only, the way a real soroban is used. The
  /// user can opt in from Settings ("Klik Manik"), and the choice is persisted.
  /// Drag stays available in both cases, this only gates the tap shortcut.
  bool _tapToToggleEnabled = false;
  bool get tapToToggleEnabled => _tapToToggleEnabled;

  final Map<String, int> _bestTimes = {}; // key: "category_difficulty" -> ms

  /// Initializes persistence and audio service.
  ///
  /// [initAudio] exists because the audio plugin bootstrap is a platform
  /// channel call that never resolves inside `testWidgets`' fake-async zone,
  /// hanging the whole test. Widget tests pass `false` and get the preference
  /// restore only.
  Future<void> init({bool initAudio = true}) async {
    final prefs = await SharedPreferences.getInstance();
    _perRodColor = prefs.getBool('per_rod_color') ?? false;
    _soundEnabled = prefs.getBool('sound_enabled') ?? true;
    _tapToToggleEnabled = prefs.getBool('tap_to_toggle_enabled') ?? false;

    SoundService().enabled = _soundEnabled;
    if (initAudio) {
      // Not awaited on purpose. Loading the four clack pools takes real time
      // (asset copy plus a platform round trip each), and nothing about
      // starting the app depends on it: a clack requested before it finishes
      // is simply skipped. SoundService.init never throws.
      unawaited(SoundService().init());
    }

    for (final cat in ProblemCategory.values) {
      for (final diff in Difficulty.values) {
        final key = 'best_${cat.name}_${diff.name}';
        final val = prefs.getInt(key);
        if (val != null) {
          _bestTimes['${cat.name}_${diff.name}'] = val;
        }
      }
    }
    notifyListeners();
  }

  void toggleSound() async {
    _soundEnabled = !_soundEnabled;
    SoundService().enabled = _soundEnabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound_enabled', _soundEnabled);
  }

  void togglePerRodColor() async {
    _perRodColor = !_perRodColor;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('per_rod_color', _perRodColor);
  }

  /// Enables/disables the tap-to-toggle shortcut. Does NOT gate [tapHeavenBead]
  /// / [tapEarthBead] themselves, because the drag handler commits its moves
  /// through those very same methods.
  void toggleTapToToggle() async {
    _tapToToggleEnabled = !_tapToToggleEnabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tap_to_toggle_enabled', _tapToToggleEnabled);
  }

  int? getBestTime(ProblemCategory cat, Difficulty diff) {
    return _bestTimes['${cat.name}_${diff.name}'];
  }

  Future<bool> recordTimeIfBest(
    ProblemCategory cat,
    Difficulty diff,
    int timeMs,
  ) async {
    final key = '${cat.name}_${diff.name}';
    final currentBest = _bestTimes[key];
    if (currentBest == null || timeMs < currentBest) {
      _bestTimes[key] = timeMs;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('best_$key', timeMs);
      notifyListeners();
      return true; // New record!
    }
    return false;
  }

  // --- Setup Modes ---
  void startPracticeProblem(ProblemCategory category, Difficulty difficulty) {
    _isChallengeMode = false;
    _isChallengeCompleted = false;
    _stopwatch.reset();
    _stopwatch.stop();
    _ticker?.cancel();
    _elapsedMilliseconds = 0;
    _elapsedSeconds.value = 0;

    _currentProblem = problemGenerator.generateProblem(
      category: category,
      difficulty: difficulty,
    );
    _resetToNewProblem();
  }

  void startChallengeSession(ProblemCategory category, Difficulty difficulty) {
    _isChallengeMode = true;
    _isChallengeCompleted = false;
    _challengeIndex = 0;
    _challengeProblems = problemGenerator.generateChallengeSession(
      category: category,
      difficulty: difficulty,
      count: 5,
    );

    _stopwatch.reset();
    _stopwatch.start();
    _ticker?.cancel();
    _elapsedMilliseconds = 0;
    _elapsedSeconds.value = 0;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _elapsedMilliseconds = _stopwatch.elapsedMilliseconds;
      // Deliberately no notifyListeners(): see [elapsedSeconds]. Everything
      // else that changes (beads, checkpoints, completion) notifies for itself.
      _elapsedSeconds.value = _elapsedMilliseconds ~/ 1000;
    });

    _currentProblem = _challengeProblems[0];
    _resetToNewProblem();
  }

  void _resetToNewProblem() {
    _state = SorobanState.zero();
    _checkpointSnapshots.clear();
    _checkpointSnapshots.add(SorobanState.zero());
    _activeCheckpointIndex = 0;
    _trailBeads.clear();
    _animatingBeadKey = null;
    _lastHintCheckpointIndex = null;
    notifyListeners();
  }

  // --- Manual Bead Gestures ---
  //
  // A manual move and an animated move share one write path: both describe the
  // change as a BeadMove and both go through AdditionEngine.applyMove, so the
  // bounds checks and the resulting Rod cannot drift apart.
  //
  // Nothing here looks at checkpoints. A gesture is free to land anywhere; the
  // chain is read once, at quiescence, in reconcileCheckpoints().
  void tapHeavenBead(int rodIndex) {
    if (_isAnimating) return;
    if (rodIndex < 0 || rodIndex >= _state.rods.length) return;

    final currentRod = _state.rods[rodIndex];
    final newHeaven = !currentRod.heaven;
    _state = additionEngine.applyMove(
      _state,
      BeadMove(
        rodIndex: rodIndex,
        kind: BeadKind.heaven,
        from: currentRod.heaven ? 5 : 0,
        to: newHeaven ? 5 : 0,
      ),
    );

    _recordTrail('rod_${rodIndex}_heaven');
    _clackPending = true;
    notifyListeners();
  }

  void tapEarthBead(int rodIndex, int targetCount) {
    if (_isAnimating) return;
    if (rodIndex < 0 || rodIndex >= _state.rods.length) return;
    if (targetCount < 0 || targetCount > 4) return;

    final currentRod = _state.rods[rodIndex];
    // Asking for the count that is already active means "put that bead back
    // down", i.e. one fewer. The drag path never asks for that, so this stays
    // purely the tap-to-toggle shortcut.
    final newCount = (currentRod.earth == targetCount)
        ? (targetCount > 0 ? targetCount - 1 : 0)
        : targetCount;

    _state = additionEngine.applyMove(
      _state,
      BeadMove(
        rodIndex: rodIndex,
        kind: BeadKind.earth,
        from: currentRod.earth,
        to: newCount,
      ),
    );

    _recordTrail('rod_${rodIndex}_earth_$newCount');
    _clackPending = true;
    notifyListeners();
  }

  // --- Checkpoint Progression ---
  //
  // Progression is derived from the board, never from a plan and never from a
  // per-commit check. SorobanState.value encodes every rod, so a matching value
  // means the board is exactly the one that checkpoint describes — there is
  // nothing else to verify, and nothing to refuse.

  /// Set by any commit, consumed once when the gesture ends.
  bool _clackPending = false;

  /// Ends a physical gesture: the last finger lifted.
  ///
  /// One gesture, one clack. Two fingers landing on two rods commit twice, and a
  /// second clack on top of the first does not add anything you can hear — it
  /// only overlaps on the one player and takes the pair down with it. So the bead
  /// noise is reported once, here, at the same quiescence point the checkpoint
  /// chain is read at, and never per commit.
  void onGestureSettled() {
    reconcileCheckpoints();
    if (!_clackPending) return;
    _clackPending = false;
    SoundService().playClack();
  }

  /// Reconciles the checkpoint chain against the current board.
  ///
  /// Called once per physical gesture, when the last finger lifts. Everything in
  /// between was free-form: any rod, any number of fingers, any number of
  /// commits, landing wherever it landed.
  ///
  /// Takes the *first* checkpoint at or after the active one whose value the
  /// board matches. A user who lands straight on a later value has done that
  /// much work, so the checkpoints in between count as passed — stopping on
  /// every one of them is not a thing a physical abacus asks for. Taking the
  /// first match rather than the furthest is what keeps a repeated target value
  /// (as in `12 + 7 - 7`, whose checkpoints are 10, 12, 19, 12) from resolving
  /// to the wrong one.
  ///
  /// No match means no match: the board stays exactly as the user left it, and
  /// Reset stays their decision.
  void reconcileCheckpoints() {
    final problem = _currentProblem;
    if (problem == null) return;
    final checkpoints = problem.checkpoints;
    if (_activeCheckpointIndex >= checkpoints.length) return;

    final value = _state.value;
    var matched = -1;
    for (var i = _activeCheckpointIndex; i < checkpoints.length; i++) {
      if (checkpoints[i].targetValue == value) {
        matched = i;
        break;
      }
    }

    if (matched < 0) return;

    _recordProgressThrough(matched);
    if (_activeCheckpointIndex >= checkpoints.length) {
      _handleProblemCompleted();
    }
    notifyListeners();
  }

  /// Marks every checkpoint up to and including [through] as passed, keeping the
  /// snapshot chain free of holes.
  ///
  /// `snapshot[i]` is the board at the *start* of checkpoint `i`, which is the
  /// board checkpoint `i - 1` produced — that is the layout Reset and Replay
  /// have always indexed into, so the chain keeps its meaning and gains no
  /// holes. A skipped checkpoint never became a settled board, so its entry is
  /// the canonical board for the previous checkpoint's value: the value encodes
  /// every rod, so that is the exact position, not an approximation. Only the
  /// last entry is the board the user actually has in front of them.
  void _recordProgressThrough(int through) {
    final checkpoints = _currentProblem!.checkpoints;

    while (_checkpointSnapshots.length <= through) {
      final index = _checkpointSnapshots.length;
      _checkpointSnapshots.add(
        SorobanState.fromValue(
          checkpoints[index - 1].targetValue,
          rodCount: _state.rods.length,
        ),
      );
    }

    // The board after the last crossed checkpoint is the start of the next one.
    if (_checkpointSnapshots.length <= through + 1) {
      _checkpointSnapshots.add(_state.clone());
    } else {
      // Replaying a digit the chain already knows: refresh that entry in place
      // rather than appending a duplicate.
      _checkpointSnapshots[through + 1] = _state.clone();
    }

    _activeCheckpointIndex = through + 1;

    assert(
      _checkpointSnapshots.length == _activeCheckpointIndex + 1,
      'snapshot chain out of sync: ${_checkpointSnapshots.length} entries for '
      'checkpoint index $_activeCheckpointIndex',
    );
  }

  void _recordTrail(String beadKey) {
    final now = DateTime.now();
    _trailBeads[beadKey] = now;
    // Clean up older trail items
    _trailBeads.removeWhere(
      (_, time) => now.difference(time).inMilliseconds > 1500,
    );
  }

  void _handleProblemCompleted() {
    if (_isChallengeMode) {
      if (_challengeIndex + 1 < _challengeProblems.length) {
        _challengeIndex++;
        _currentProblem = _challengeProblems[_challengeIndex];
        // Brief pause before displaying next problem
        Future.delayed(const Duration(milliseconds: 600), () {
          _resetToNewProblem();
        });
      } else {
        // Challenge finished!
        _stopwatch.stop();
        _ticker?.cancel();
        _elapsedMilliseconds = _stopwatch.elapsedMilliseconds;
        _elapsedSeconds.value = _elapsedMilliseconds ~/ 1000;
        _isChallengeCompleted = true;
        if (_currentProblem != null) {
          recordTimeIfBest(
            _currentProblem!.category,
            _currentProblem!.difficulty,
            _elapsedMilliseconds,
          );
        }
        notifyListeners();
      }
    }
  }

  bool get canReset =>
      !_isAnimating && (_activeCheckpointIndex > 0 || _state.value != 0);

  /// Number of entries in the checkpoint snapshot chain.
  ///
  /// Exposed for tests: the chain must always hold one entry per reached
  /// checkpoint index, i.e. `checkpointSnapshotCount == activeCheckpointIndex + 1`
  /// after every reconciliation. Replay and Retri index into it, so a gap or a
  /// stale entry means they would roll back to the wrong board.
  @visibleForTesting
  int get checkpointSnapshotCount => _checkpointSnapshots.length;

  /// Replay is only available when a hint has been executed at least once (and not in Challenge Mode).
  bool get canReplay =>
      !_isChallengeMode &&
      !_isAnimating &&
      _currentProblem != null &&
      _lastHintCheckpointIndex != null;

  // --- Hint Execution (Chained Animation) ---
  Future<void> executeHint() async {
    if (_isChallengeMode || _isAnimating || _currentProblem == null) return;

    final hintResult = hintEngine.getNextHint(
      currentState: _state,
      problem: _currentProblem!,
      checkpointSnapshots: _checkpointSnapshots,
    );

    if (hintResult == null) return;

    _clackPending = false;
    _isAnimating = true;
    notifyListeners();

    // If recovering from divergence, restore valid snapshot gradually rod-by-rod
    if (hintResult.recoveredFromDivergence) {
      await _smoothRecoverDivergence(hintResult.fromState);
    }

    // Brief pause before starting the hint animation so user notices it's about to begin
    await Future.delayed(const Duration(milliseconds: 400));

    await _playChainedMoves(hintResult.moves);

    // Track hint execution for Replay gating
    _lastHintCheckpointIndex = hintResult.checkpointIndex;

    // Same bookkeeping as a manual gesture, so the chain can never end up with
    // a hole no matter which path advanced it.
    _recordProgressThrough(hintResult.checkpointIndex);
    _animatingBeadKey = null;
    _isAnimating = false;

    if (_activeCheckpointIndex >= _currentProblem!.checkpoints.length) {
      _handleProblemCompleted();
    }

    notifyListeners();
  }

  // --- Replay Execution ---
  Future<void> executeReplay() async {
    if (_isChallengeMode || _isAnimating || _currentProblem == null) return;
    if (_currentProblem!.checkpoints.isEmpty) return;
    if (_lastHintCheckpointIndex == null) return;

    final replayIdx = _lastHintCheckpointIndex!;

    final replayResult = hintEngine.getReplay(
      activeCheckpointIndex: replayIdx,
      problem: _currentProblem!,
      checkpointSnapshots: _checkpointSnapshots,
    );

    if (replayResult == null) return;

    _clackPending = false;
    _isAnimating = true;
    // 1. Rollback to state before this digit
    _state = replayResult.fromState.clone();
    _activeCheckpointIndex = replayIdx;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 1200));

    // 2. Play chained animation again
    await _playChainedMoves(replayResult.moves);

    // Replay re-runs one digit that was already hinted, so the chain already
    // covers this index; recording it again just refreshes the board.
    _recordProgressThrough(replayIdx);
    _animatingBeadKey = null;
    _isAnimating = false;

    if (_activeCheckpointIndex >= _currentProblem!.checkpoints.length) {
      _handleProblemCompleted();
    }

    notifyListeners();
  }

  // --- Reset Execution ---
  /// Mengembalikan posisi sempoa:
  /// 1. Jika manik sedang salah/divergen dari awal checkpoint aktif: kembalikan ke awal checkpoint aktif.
  /// 2. Jika posisi manik sudah di awal checkpoint aktif (atau ditekan lagi): kembali ke checkpoint sebelumnya ("retri").
  void executeReset() {
    if (_isAnimating) return;
    if (_checkpointSnapshots.isEmpty) return;

    // 1. Jika manik telah digerakkan dan tidak sama dengan snapshot awal digit aktif:
    if (_state.value != _checkpointSnapshots.last.value) {
      _state = _checkpointSnapshots.last.clone();
      _trailBeads.clear();
      _animatingBeadKey = null;
      notifyListeners();
      return;
    }

    // 2. Jika manik sudah pas di snapshot awal digit aktif, mundur ke checkpoint sebelumnya:
    if (_checkpointSnapshots.length > 1 && _activeCheckpointIndex > 0) {
      _checkpointSnapshots.removeLast();
      _activeCheckpointIndex--;
      _state = _checkpointSnapshots.last.clone();
      _trailBeads.clear();
      _animatingBeadKey = null;
      // Reset hint tracking when going back to a previous checkpoint
      _lastHintCheckpointIndex = null;
      notifyListeners();
    }
  }

  /// Smoothly recovers from divergence by restoring each divergent rod one-by-one
  /// with brass glow and delay, so the user can see exactly which rods were wrong.
  /// After all rods are restored, an extra pause gives the user time to register
  /// the correct position before the hint animation begins.
  Future<void> _smoothRecoverDivergence(SorobanState validState) async {
    final totalRods = _state.rods.length;

    // Collect indices of rods that differ from the valid state
    final divergentRods = <int>[];
    for (int i = 0; i < totalRods; i++) {
      if (i < validState.rods.length && _state.rods[i] != validState.rods[i]) {
        divergentRods.add(i);
      }
    }

    if (divergentRods.isEmpty) {
      // No divergence, just set the state
      _state = validState.clone();
      notifyListeners();
      return;
    }

    // Restore each divergent rod one at a time with visual feedback
    for (int i = 0; i < divergentRods.length; i++) {
      final rodIdx = divergentRods[i];
      final validRod = validState.rods[rodIdx];

      // Show brass glow on this rod's beads during recovery
      if (validRod.heaven != _state.rods[rodIdx].heaven) {
        _animatingBeadKey = 'rod_${rodIdx}_heaven';
      } else {
        _animatingBeadKey = 'rod_${rodIdx}_earth_${validRod.earth}';
      }

      // Apply the correction for this rod
      _state = _state.updateRod(rodIdx, validRod);
      notifyListeners();

      // Delay between each rod correction for visual clarity
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _animatingBeadKey = null;
    notifyListeners();

    // Extra pause after all rods are corrected, before hint starts
    // This lets the user register the correct position
    await Future.delayed(const Duration(milliseconds: 600));
  }

  /// Plays a sequence of atomic moves with brass glow and inter-move delay.
  Future<void> _playChainedMoves(List<BeadMove> moves) async {
    for (int i = 0; i < moves.length; i++) {
      final move = moves[i];
      final key = move.kind == BeadKind.heaven
          ? 'rod_${move.rodIndex}_heaven'
          : 'rod_${move.rodIndex}_earth_${move.to}';

      _animatingBeadKey = key;
      _recordTrail(key);

      _state = additionEngine.applyMove(_state, move);
      SoundService().playClack();
      notifyListeners();

      await Future.delayed(move.delay);
    }
    _animatingBeadKey = null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    _elapsedSeconds.dispose();
    super.dispose();
  }
}
