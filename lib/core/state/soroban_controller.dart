import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../engine/addition_engine.dart';
import '../engine/hint_engine.dart';
import '../engine/problem_generator.dart';
import '../models/bead_move.dart';
import '../models/problem.dart';
import '../models/soroban_state.dart';

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

  // --- Settings & Records ---
  bool _perRodColor = false;
  bool get perRodColor => _perRodColor;

  final Map<String, int> _bestTimes = {}; // key: "category_difficulty" -> ms

  /// Initializes persistence.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _perRodColor = prefs.getBool('per_rod_color') ?? false;

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

  void togglePerRodColor() async {
    _perRodColor = !_perRodColor;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('per_rod_color', _perRodColor);
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
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _elapsedMilliseconds = _stopwatch.elapsedMilliseconds;
      notifyListeners();
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
    notifyListeners();
  }

  // --- Manual Bead Gestures ---
  void tapHeavenBead(int rodIndex) {
    if (_isAnimating) return;
    if (rodIndex < 0 || rodIndex >= _state.rods.length) return;

    final currentRod = _state.rods[rodIndex];
    final newHeaven = !currentRod.heaven;
    _state = _state.updateRod(rodIndex, currentRod.copyWith(heaven: newHeaven));

    _recordTrail('rod_${rodIndex}_heaven');
    _checkCheckpointAdvancement();
    notifyListeners();
  }

  void tapEarthBead(int rodIndex, int targetCount) {
    if (_isAnimating) return;
    if (rodIndex < 0 || rodIndex >= _state.rods.length) return;

    final currentRod = _state.rods[rodIndex];
    // If tapping the currently active earth bead count, decrement by 1
    final newCount = (currentRod.earth == targetCount)
        ? (targetCount > 0 ? targetCount - 1 : 0)
        : targetCount;

    _state = _state.updateRod(rodIndex, currentRod.copyWith(earth: newCount));

    _recordTrail('rod_${rodIndex}_earth_$newCount');
    _checkCheckpointAdvancement();
    notifyListeners();
  }

  void _recordTrail(String beadKey) {
    _trailBeads[beadKey] = DateTime.now();
    // Clean up older trail items
    final now = DateTime.now();
    _trailBeads.removeWhere(
      (_, time) => now.difference(time).inMilliseconds > 1500,
    );
  }

  void _checkCheckpointAdvancement() {
    if (_currentProblem == null) return;
    final curVal = _state.value;

    // Check if this matches the next expected checkpoint
    final checkpoints = _currentProblem!.checkpoints;
    if (_activeCheckpointIndex < checkpoints.length) {
      if (curVal == checkpoints[_activeCheckpointIndex].targetValue) {
        _checkpointSnapshots.add(_state.clone());
        _activeCheckpointIndex++;

        // If all checkpoints completed:
        if (_activeCheckpointIndex >= checkpoints.length) {
          _handleProblemCompleted();
        }
      }
    }
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

  // --- Hint Execution (Chained Animation) ---
  Future<void> executeHint() async {
    if (_isAnimating || _currentProblem == null) return;

    final hintResult = hintEngine.getNextHint(
      currentState: _state,
      problem: _currentProblem!,
      checkpointSnapshots: _checkpointSnapshots,
    );

    if (hintResult == null) return;

    _isAnimating = true;
    notifyListeners();

    // If recovering from divergence, restore valid snapshot first
    if (hintResult.recoveredFromDivergence) {
      _state = hintResult.fromState.clone();
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    await _playChainedMoves(hintResult.moves);

    _checkpointSnapshots.add(_state.clone());
    _activeCheckpointIndex = hintResult.checkpointIndex + 1;
    _animatingBeadKey = null;
    _isAnimating = false;

    if (_activeCheckpointIndex >= _currentProblem!.checkpoints.length) {
      _handleProblemCompleted();
    }

    notifyListeners();
  }

  // --- Replay Execution ---
  Future<void> executeReplay() async {
    if (_isAnimating || _currentProblem == null) return;
    if (_currentProblem!.checkpoints.isEmpty) return;

    final replayIdx = (_activeCheckpointIndex > 0)
        ? _activeCheckpointIndex - 1
        : 0;

    final replayResult = hintEngine.getReplay(
      activeCheckpointIndex: replayIdx,
      problem: _currentProblem!,
      checkpointSnapshots: _checkpointSnapshots,
    );

    if (replayResult == null) return;

    _isAnimating = true;
    // 1. Rollback to state before this digit
    _state = replayResult.fromState.clone();
    _activeCheckpointIndex = replayIdx;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 300));

    // 2. Play chained animation again
    await _playChainedMoves(replayResult.moves);

    _checkpointSnapshots.add(_state.clone());
    _activeCheckpointIndex = replayIdx + 1;
    _animatingBeadKey = null;
    _isAnimating = false;

    if (_activeCheckpointIndex >= _currentProblem!.checkpoints.length) {
      _handleProblemCompleted();
    }

    notifyListeners();
  }

  // --- Reset Execution ---
  void executeReset() {
    if (_isAnimating) return;
    // Balikkan state ke snapshot checkpoint terakhir yang valid
    if (_checkpointSnapshots.isNotEmpty) {
      _state = _checkpointSnapshots.last.clone();
      _trailBeads.clear();
      _animatingBeadKey = null;
      notifyListeners();
    }
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
      notifyListeners();

      await Future.delayed(move.delay);
    }
    _animatingBeadKey = null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopwatch.stop();
    super.dispose();
  }
}
