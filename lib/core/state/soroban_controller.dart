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

  final Map<String, int> _bestTimes = {}; // key: "category_difficulty" -> ms

  /// Initializes persistence and audio service.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _perRodColor = prefs.getBool('per_rod_color') ?? false;
    _soundEnabled = prefs.getBool('sound_enabled') ?? true;

    SoundService().enabled = _soundEnabled;
    await SoundService().init();

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
    _lastHintCheckpointIndex = null;
    notifyListeners();
  }

  // --- Manual Bead Gestures ---
  void tapHeavenBead(int rodIndex) {
    if (_isAnimating) return;
    if (rodIndex < 0 || rodIndex >= _state.rods.length) return;

    final currentRod = _state.rods[rodIndex];
    final newHeaven = !currentRod.heaven;
    _state = _state.updateRod(rodIndex, currentRod.copyWith(heaven: newHeaven));

    SoundService().playClack();
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

    SoundService().playClack();
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

  bool get canReset =>
      !_isAnimating && (_activeCheckpointIndex > 0 || _state.value != 0);

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

    // Sync snapshot without duplicates
    final newIdx = hintResult.checkpointIndex + 1;
    if (_checkpointSnapshots.length <= newIdx) {
      _checkpointSnapshots.add(_state.clone());
    } else {
      _checkpointSnapshots[newIdx] = _state.clone();
    }
    _activeCheckpointIndex = newIdx;
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

    _isAnimating = true;
    // 1. Rollback to state before this digit
    _state = replayResult.fromState.clone();
    _activeCheckpointIndex = replayIdx;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 1200));

    // 2. Play chained animation again
    await _playChainedMoves(replayResult.moves);

    // Update snapshot without duplicating
    final targetIdx = replayIdx + 1;
    if (_checkpointSnapshots.length <= targetIdx) {
      _checkpointSnapshots.add(_state.clone());
    } else {
      _checkpointSnapshots[targetIdx] = _state.clone();
    }
    _activeCheckpointIndex = targetIdx;
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
    super.dispose();
  }
}
