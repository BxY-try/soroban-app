import 'dart:math';
import 'rod.dart';

/// Represents the overall state of the Soroban.
/// Standard configuration has 7 rods.
/// Index 0 = units (satuan, rightmost column)
/// Index 6 = millions (jutaan, leftmost column)
class SorobanState {
  final List<Rod> rods;

  const SorobanState(this.rods);

  /// Creates a blank Soroban with all beads reset to 0.
  factory SorobanState.zero({int rodCount = 7}) {
    return SorobanState(List<Rod>.generate(rodCount, (_) => const Rod()));
  }

  /// Creates a Soroban state initialized to a specific integer value.
  factory SorobanState.fromValue(int value, {int rodCount = 7}) {
    assert(value >= 0, 'Soroban cannot represent negative values');
    final List<Rod> rods = [];
    int remaining = value;
    for (int i = 0; i < rodCount; i++) {
      rods.add(Rod.fromValue(remaining % 10));
      remaining ~/= 10;
    }
    return SorobanState(rods);
  }

  /// Total integer value represented across all rods.
  int get value {
    int sum = 0;
    int multiplier = 1;
    for (int i = 0; i < rods.length; i++) {
      sum += rods[i].value * multiplier;
      multiplier *= 10;
    }
    return sum;
  }

  /// Maximum integer that can be displayed on this soroban (e.g. 9,999,999 for 7 rods).
  int get maxValue => pow(10, rods.length).toInt() - 1;

  /// Returns a new state with a specific rod updated.
  SorobanState updateRod(int rodIndex, Rod newRod) {
    final updated = List<Rod>.from(rods);
    updated[rodIndex] = newRod;
    return SorobanState(List.unmodifiable(updated));
  }

  /// Helper to get a copy of this state.
  SorobanState clone() {
    return SorobanState(List<Rod>.from(rods));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SorobanState) return false;
    if (rods.length != other.rods.length) return false;
    for (int i = 0; i < rods.length; i++) {
      if (rods[i] != other.rods[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(rods);

  @override
  String toString() => 'SorobanState(value: $value, rods: $rods)';
}
