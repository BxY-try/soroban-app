import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soroban_app/features/soroban_widget/soroban_layout.dart';

void main() {
  group('SorobanLayout Physics & Geometry', () {
    const size = Size(800, 400);
    const totalRods = 7;
    late SorobanLayout layout;

    setUp(() {
      layout = SorobanLayout(size: size, totalRods: totalRods);
    });

    test('Initial positions are monotonically ordered with minimum pitch spacing', () {
      for (int count = 0; count <= 4; count++) {
        for (int b = 0; b < 3; b++) {
          final y1 = layout.computeEarthY(b, count);
          final y2 = layout.computeEarthY(b + 1, count);
          expect(y2 - y1, greaterThanOrEqualTo(layout.beadPitch - 0.001));
        }
      }
    });

    test('Heaven and Earth beads have 100% identical travel distance', () {
      final heavenTravel = layout.computeHeavenY(true) - layout.computeHeavenY(false);
      expect(heavenTravel, closeTo(layout.travelDistance, 0.001));

      for (int b = 0; b < 4; b++) {
        final earthTravel = layout.computeEarthY(b, 0) - layout.computeEarthY(b, 4);
        expect(earthTravel, closeTo(layout.travelDistance, 0.001));
      }
    });

    test('Dragging single bead (bead 0) UP when count=0 moves ONLY bead 0', () {
      final initialY = List<double>.generate(4, (b) => layout.computeEarthY(b, 0));
      final deltaY = -(layout.travelDistance * 0.5); // Intermediate upward drag

      final newY = layout.computeEarthDragPositions(
        grabbedIndex: 0,
        initialEarthY: initialY,
        deltaY: deltaY,
      );

      // Bead 0 must move upward
      expect(newY[0], closeTo(initialY[0] + deltaY, 0.001));

      // Beads 1, 2, 3 must stay completely stationary
      expect(newY[1], equals(initialY[1]));
      expect(newY[2], equals(initialY[2]));
      expect(newY[3], equals(initialY[3]));
    });

    test('Dragging bead 2 UP when count=0 pushes beads 0 and 1, bead 3 stays down', () {
      final initialY = List<double>.generate(4, (b) => layout.computeEarthY(b, 0));
      final deltaY = -(layout.travelDistance * 0.6); // Intermediate upward drag

      final newY = layout.computeEarthDragPositions(
        grabbedIndex: 2,
        initialEarthY: initialY,
        deltaY: deltaY,
      );

      // Bead 2 moved up
      expect(newY[2], closeTo(initialY[2] + deltaY, 0.001));

      // Beads 0 and 1 were pushed up by bead 2
      expect(newY[1], closeTo(newY[2] - layout.beadPitch, 0.001));
      expect(newY[0], closeTo(newY[1] - layout.beadPitch, 0.001));

      // Bead 3 stayed resting at bottom
      expect(newY[3], equals(initialY[3]));
    });

    test('Dragging bead 2 DOWN when count=3 moves ONLY bead 2, beads 0 and 1 stay at beam', () {
      final initialY = List<double>.generate(4, (b) => layout.computeEarthY(b, 3));
      final deltaY = layout.travelDistance * 0.5; // Intermediate downward drag

      final newY = layout.computeEarthDragPositions(
        grabbedIndex: 2,
        initialEarthY: initialY,
        deltaY: deltaY,
      );

      // Beads 0 and 1 stay at beam
      expect(newY[0], equals(initialY[0]));
      expect(newY[1], equals(initialY[1]));

      // Bead 2 moves down
      expect(newY[2], closeTo(initialY[2] + deltaY, 0.001));

      // Bead 3 stays at bottom (since bead 2 hasn't reached it yet)
      expect(newY[3], equals(initialY[3]));
    });

    test('Dragging bead 1 DOWN when count=3 pushes bead 2, bead 0 stays at beam', () {
      final initialY = List<double>.generate(4, (b) => layout.computeEarthY(b, 3));
      final deltaY = layout.travelDistance * 0.5; // Intermediate downward drag

      final newY = layout.computeEarthDragPositions(
        grabbedIndex: 1,
        initialEarthY: initialY,
        deltaY: deltaY,
      );

      // Bead 0 stays at beam
      expect(newY[0], equals(initialY[0]));

      // Bead 1 moves down
      expect(newY[1], closeTo(initialY[1] + deltaY, 0.001));

      // Bead 2 is pushed down by bead 1
      expect(newY[2], closeTo(newY[1] + layout.beadPitch, 0.001));
    });

    test('Bead cannot be dragged beyond beam or bottom boundary', () {
      final initialY = List<double>.generate(4, (b) => layout.computeEarthY(b, 0));

      // Massive upward drag
      final newYUp = layout.computeEarthDragPositions(
        grabbedIndex: 3,
        initialEarthY: initialY,
        deltaY: -10000.0,
      );
      final active0 = layout.computeEarthY(0, 4);
      expect(newYUp[0], closeTo(active0, 0.001));

      // Massive downward drag
      final newYDown = layout.computeEarthDragPositions(
        grabbedIndex: 0,
        initialEarthY: initialY,
        deltaY: 10000.0,
      );
      final inactive3 = layout.computeEarthY(3, 0);
      expect(newYDown[3], closeTo(inactive3, 0.001));
    });

    test('resolveEarthActiveCount accurately detects count threshold', () {
      final initialY = List<double>.generate(4, (b) => layout.computeEarthY(b, 0));

      // Initial state is 0 active
      expect(layout.resolveEarthActiveCount(initialY), equals(0));

      // Pull bead 0 all the way to beam
      final draggedToBeam = layout.computeEarthDragPositions(
        grabbedIndex: 0,
        initialEarthY: initialY,
        deltaY: -500.0,
      );
      expect(layout.resolveEarthActiveCount(draggedToBeam), equals(1));
    });

    test('Heaven drag 1-to-1 tracking and active threshold', () {
      final inactiveY = layout.computeHeavenY(false);
      final activeY = layout.computeHeavenY(true);

      expect(layout.resolveHeavenActive(inactiveY), isFalse);
      expect(layout.resolveHeavenActive(activeY), isTrue);

      final draggedY = layout.computeHeavenDragY(false, 20.0);
      expect(draggedY, equals(inactiveY + 20.0));
    });
  });
}
