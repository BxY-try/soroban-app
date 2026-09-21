import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Service managing tactile wooden bead clack sound playback for manual
/// and animated Soroban movements.
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  AudioPlayer? _player;
  bool enabled = true;
  bool _isInitialized = false;

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

  /// Returns the next asset path using a non-repeating shuffle (round-robin)
  /// to ensure consecutive clicks never play the exact same sample.
  @visibleForTesting
  String getNextSoundPath() {
    if (soundAssetPaths.length <= 1) return soundAssetPaths.first;
    int nextIndex;
    do {
      nextIndex = _random.nextInt(soundAssetPaths.length);
    } while (nextIndex == _lastPlayedIndex);
    _lastPlayedIndex = nextIndex;
    return soundAssetPaths[nextIndex];
  }

  /// Initializes player mode for low-latency tactile response.
  Future<void> init() async {
    try {
      _player = AudioPlayer();
      if (!kIsWeb) {
        await _player?.setPlayerMode(PlayerMode.lowLatency);
      }
      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      debugPrint('SoundService init error: $e');
    }
  }

  /// Plays the crisp stapler / bead clack audio effect with subtle dynamic variation.
  Future<void> playClack() async {
    if (!enabled || !_isInitialized || _player == null) return;
    try {
      final String assetPath = getNextSoundPath();
      // Subtle volume jitter between 0.80 and 0.88 for natural physical response
      final double volume = 0.80 + _random.nextDouble() * 0.08;
      await _player!.stop();
      await _player!.play(
        AssetSource(assetPath),
        volume: volume,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('SoundService play error: $e');
      }
    }
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }
}
