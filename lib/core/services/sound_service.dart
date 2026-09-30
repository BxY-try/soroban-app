import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Service managing tactile wooden bead clack sound playback for manual
/// and animated Soroban movements.
///
/// How playback is built (audioplayers 6.x):
///
/// * One [AudioPool] per clack variant. The package documents the pool as the
///   tool for "extremely quick firing, repetitive or simultaneous sounds": its
///   players are created up front with the asset already loaded, so a clack is
///   a `resume()` on a prepared player rather than a fresh source load.
/// * The pools use the default [PlayerMode.mediaPlayer]. In `lowLatency` mode the backend
///   fires no completion events, so *the caller* must stop every player; a pool
///   that is not stopped never gets its players back. The previous single
///   `lowLatency` player, re-pointed at a different asset on every clack and
///   never stopped, is the most likely reason the sound faded after a few
///   moves. `mediaPlayer` pools recycle their players on their own.
/// * The audio context is `mixWithOthers`, so a clack never requests (and later
///   abandons) audio focus, which would pause music from other apps.
/// * If playback keeps failing, the pools are rebuilt (rate limited) instead of
///   staying silent for the rest of the session.
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  bool enabled = true;

  /// Players kept per clack variant. A gesture asks for one clack and variants
  /// rotate round-robin, so two per variant is comfortably more than needed.
  static const int _playersPerVariant = 2;

  /// Consecutive failed clacks before the pools are rebuilt.
  static const int _failuresBeforeRecovery = 2;

  /// Minimum gap between two rebuilds, so a broken audio stack cannot turn
  /// into a rebuild loop.
  static const Duration _recoveryCooldown = Duration(seconds: 3);

  /// One pool per entry of [soundAssetPaths], same order. A slot is null when
  /// that asset failed to load; the others keep working.
  List<AudioPool?> _pools = const [];

  Future<void>? _initFuture;
  bool _initRequested = false;
  bool _ready = false;

  /// Whether the pools have ever loaded. Only a service that has worked once
  /// rebuilds itself after a failure; one that never loaded (no plugin, missing
  /// asset) stays quiet instead of retrying a hopeless init on every clack.
  bool _hasBeenReady = false;
  bool _recovering = false;
  int _consecutiveFailures = 0;
  DateTime? _lastRecoveryAt;

  int _lastPlayedIndex = -1;
  final math.Random _random = math.Random();

  /// Multiple audio variations to prevent repetitive "machine-gun effect".
  static const List<String> soundAssetPaths = [
    'sounds/stapler_1.wav',
    'sounds/stapler_2.wav',
    'sounds/stapler_3.wav',
    'sounds/stapler_4.wav',
  ];

  /// Backward-compatible single asset path fallback.
  static const String soundAssetPath = 'sounds/stapler_1.wav';

  /// Non-repeating shuffle: consecutive clicks never use the same sample.
  int _nextIndex() {
    if (soundAssetPaths.length <= 1) return 0;
    int nextIndex;
    do {
      nextIndex = _random.nextInt(soundAssetPaths.length);
    } while (nextIndex == _lastPlayedIndex);
    _lastPlayedIndex = nextIndex;
    return nextIndex;
  }

  /// Returns the next asset path using a non-repeating shuffle (round-robin)
  /// to ensure consecutive clicks never play the exact same sample.
  @visibleForTesting
  String getNextSoundPath() => soundAssetPaths[_nextIndex()];

  /// Loads every clack into its own pool.
  ///
  /// Safe to call more than once and never throws: a failed init leaves the
  /// service silent but retryable. Do it once at startup; loading here is what
  /// keeps the first clack of a session from paying for the asset copy.
  Future<void> init() {
    _initRequested = true;
    final existing = _initFuture;
    if (existing != null) return existing;

    final future = _createPools().whenComplete(() {
      // A failed init must not be remembered as "done", or it could never be
      // retried.
      if (!_ready) _initFuture = null;
    });
    return _initFuture = future;
  }

  Future<void> _createPools() async {
    try {
      final context = AudioContextConfig(
        focus: AudioContextConfigFocus.mixWithOthers,
      ).build();

      // One at a time on purpose: creating players concurrently was a source
      // of races in older audioplayers releases, and this only runs once.
      final pools = <AudioPool?>[];
      var loaded = 0;
      for (final path in soundAssetPaths) {
        try {
          pools.add(
            await AudioPool.create(
              source: AssetSource(path),
              maxPlayers: _playersPerVariant,
              minPlayers: 1,
              audioContext: context,
            ),
          );
          loaded++;
        } catch (e) {
          pools.add(null);
          debugPrint('SoundService: could not load $path: $e');
        }
      }

      _pools = pools;
      _ready = loaded > 0;
      if (_ready) _hasBeenReady = true;
      _consecutiveFailures = 0;
    } catch (e) {
      _ready = false;
      debugPrint('SoundService init error: $e');
    }
  }

  /// Counts clack requests, whether or not a player was ready to make a noise.
  ///
  /// Exposed for tests: whether a speaker produced sound cannot be observed from
  /// a unit test, but "one gesture asks for one clack" can, and that is the part
  /// this service is responsible for.
  @visibleForTesting
  int clackRequestCount = 0;

  /// Plays the crisp stapler / bead clack audio effect with subtle dynamic variation.
  Future<void> playClack() async {
    clackRequestCount++;
    // `_initRequested` keeps tests (which never call init) silent and
    // side-effect free: nothing here may touch a platform channel before the
    // app asked for audio.
    if (!enabled || !_initRequested) return;

    if (!_ready) {
      // Init is still loading, a rebuild is in flight, or audio broke earlier.
      // Stay silent for this clack; bring audio back for the next one if it
      // ever worked.
      if (_hasBeenReady && _initFuture == null) unawaited(_recover());
      return;
    }

    final pool = _pickPool();
    if (pool == null) return;

    try {
      // Subtle volume jitter between 0.80 and 0.88 for natural physical response
      final double volume = 0.80 + _random.nextDouble() * 0.08;
      await pool.start(volume: volume);
      _consecutiveFailures = 0;
    } catch (e) {
      _consecutiveFailures++;
      if (kDebugMode) {
        debugPrint('SoundService play error: $e');
      }
      if (_consecutiveFailures >= _failuresBeforeRecovery) {
        unawaited(_recover());
      }
    }
  }

  /// Rebuilds the pools now (still rate limited). For callers that know audio
  /// may have been taken away, e.g. after a long time in the background.
  Future<void> recover() {
    if (!_initRequested) return Future<void>.value();
    return _recover();
  }

  AudioPool? _pickPool() {
    final index = _nextIndex();
    if (index < _pools.length) {
      final pool = _pools[index];
      if (pool != null) return pool;
    }
    // The chosen variant failed to load: any working one is better than none.
    for (final pool in _pools) {
      if (pool != null) return pool;
    }
    return null;
  }

  /// Throws the pools away and builds them again, at most once per
  /// [_recoveryCooldown].
  Future<void> _recover() async {
    if (_recovering) return;
    final now = DateTime.now();
    final last = _lastRecoveryAt;
    if (last != null && now.difference(last) < _recoveryCooldown) return;

    _recovering = true;
    _lastRecoveryAt = now;
    try {
      _ready = false;
      await _disposePools();
      _initFuture = null;
      await init();
    } finally {
      _recovering = false;
    }
  }

  Future<void> _disposePools() async {
    final pools = _pools;
    _pools = const [];
    for (final pool in pools) {
      if (pool == null) continue;
      try {
        await pool.dispose();
      } catch (_) {
        // Already gone; nothing left to release.
      }
    }
  }

  void dispose() {
    _ready = false;
    _initRequested = false;
    _initFuture = null;
    unawaited(_disposePools());
  }
}
