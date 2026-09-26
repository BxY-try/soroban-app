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

    test('Zero travel boost reproduces the original geometry', () {
      final explicit = SorobanLayout(
        size: size,
        totalRods: totalRods,
        travelBoost: 0.0,
      );

      expect(explicit.beadHeight, closeTo(layout.beadHeight, 0.0001));
      expect(explicit.travelDistance, closeTo(layout.travelDistance, 0.0001));
      expect(explicit.beamTop, closeTo(layout.beamTop, 0.0001));
      expect(explicit.beamBottom, closeTo(layout.beamBottom, 0.0001));
    });

    test('Travel boost absorbs 2x its own height without resizing the beads', () {
      const boost = 1.95;
      final boosted = SorobanLayout(
        size: Size(size.width, size.height + 2 * boost),
        totalRods: totalRods,
        travelBoost: boost,
      );

      expect(boosted.beadHeight, closeTo(layout.beadHeight, 0.001));
      expect(boosted.beadWidth, closeTo(layout.beadWidth, 0.001));
      expect(boosted.beadPitch, closeTo(layout.beadPitch, 0.001));
      expect(
        boosted.travelDistance,
        closeTo(layout.travelDistance + boost, 0.001),
      );

      // Symmetry between both decks survives the boost.
      final heavenTravel = boosted.computeHeavenY(true) - boosted.computeHeavenY(false);
      expect(heavenTravel, closeTo(boosted.travelDistance, 0.001));
      for (int b = 0; b < 4; b++) {
        final earthTravel = boosted.computeEarthY(b, 0) - boosted.computeEarthY(b, 4);
        expect(earthTravel, closeTo(boosted.travelDistance, 0.001));
      }
    });

    test('Boosted layout still fills the full inner board height', () {
      final boosted = SorobanLayout(
        size: size,
        totalRods: totalRods,
        travelBoost: 1.95,
      );

      // Upper deck + beam + lower deck must exactly fill the inner board.
      final total = boosted.upperDeckHeight +
          SorobanLayout.beamHeight +
          boosted.lowerDeckHeight;
      expect(total, closeTo(size.height - 2 * SorobanLayout.frameBorder, 0.001));
    });
  });

  group('SorobanLayout horizontal gutters', () {
    // A real phone-sized abacus box (Challenge mode on a 400x800 screen).
    const phoneSize = Size(301.96, 604.0);
    const rods = 7;

    /// The un-shrunk reference the hard constraints are defined against.
    double referenceBeadWidth(Size s, int totalRods) =>
        ((s.width - 2 * SorobanLayout.frameBorder) / totalRods * 0.84)
            .clamp(18.0, 125.0);

    /// Upper deck + beam + lower deck, i.e. the full vertical budget.
    double verticalTotal(SorobanLayout l) =>
        l.upperDeckHeight + SorobanLayout.beamHeight + l.lowerDeckHeight;

    /// Builds a layout with an explicit gutter pair so every mode is testable
    /// without editing the configured constants.
    SorobanLayout build({double? left, double? right}) => SorobanLayout(
          size: phoneSize,
          totalRods: rods,
          spacingScaleLeft: left,
          spacingScaleRight: right,
        );

    group('no gutters (both scales 1.0) reproduces the original layout', () {
      test('the frame fills the whole widget box', () {
        final l = build(left: 1.0, right: 1.0);

        expect(l.frameRect.left, equals(0.0));
        expect(l.frameRect.right, equals(phoneSize.width));
        expect(l.frameRect.width, equals(phoneSize.width));
        expect(l.leftShrink, equals(0.0));
        expect(l.rightShrink, equals(0.0));
        expect(l.innerRect.left, equals(SorobanLayout.frameBorder));
        expect(l.rodSpacing, equals((phoneSize.width - 24) / rods));
      });
    });

    group('right gutter only (left anchored)', () {
      const right = 0.95;
      final l = SorobanLayout(
        size: phoneSize,
        totalRods: rods,
        spacingScaleLeft: 1.0,
        spacingScaleRight: right,
      );

      test('the left edge never moves and the right edge is pulled in', () {
        expect(l.frameRect.left, equals(0.0));
        expect(l.innerRect.left, equals(SorobanLayout.frameBorder));
        expect(l.rightShrink, greaterThan(0.0));
        expect(l.frameRect.right, closeTo(phoneSize.width - l.rightShrink, 0.001));
        expect(l.frameRect.right, lessThan(phoneSize.width));
        expect(l.leftShrink, equals(0.0));
      });

      test('the pitch is scaled by exactly the right scale', () {
        final reference = (phoneSize.width - 2 * SorobanLayout.frameBorder) / rods;
        expect(l.rodSpacing, closeTo(reference * right, 0.0001));
      });
    });

    group('left gutter only (right anchored mirror)', () {
      const left = 0.95;
      final l = SorobanLayout(
        size: phoneSize,
        totalRods: rods,
        spacingScaleLeft: left,
        spacingScaleRight: 1.0,
      );

      test('the right edge never moves and the left edge is pulled in', () {
        expect(l.frameRect.right, equals(phoneSize.width));
        expect(l.rightShrink, equals(0.0));
        expect(l.leftShrink, greaterThan(0.0));
        expect(l.frameRect.left, closeTo(l.leftShrink, 0.001));
        expect(l.frameRect.left, greaterThan(0.0));
        // Inner board follows the frame inset.
        expect(l.innerRect.left, closeTo(l.leftShrink + SorobanLayout.frameBorder, 0.001));
      });

      test('the pitch is scaled by exactly the left scale', () {
        final reference = (phoneSize.width - 2 * SorobanLayout.frameBorder) / rods;
        expect(l.rodSpacing, closeTo(reference * left, 0.0001));
      });

      test('it is a true mirror of the right gutter', () {
        final mirrored = SorobanLayout(
          size: phoneSize,
          totalRods: rods,
          spacingScaleLeft: 1.0,
          spacingScaleRight: left,
        );
        // Same width, same pitch; only the anchored side differs.
        expect(l.frameRect.width, closeTo(mirrored.frameRect.width, 0.001));
        expect(l.rodSpacing, closeTo(mirrored.rodSpacing, 0.0001));
        expect(l.frameRect.right, equals(phoneSize.width));
        expect(mirrored.frameRect.left, equals(0.0));
      });
    });

    group('both gutters active at once', () {
      final l = build(left: 0.95, right: 0.95);

      test('both edges are pulled in by their own gutter', () {
        expect(l.leftShrink, greaterThan(0.0));
        expect(l.rightShrink, greaterThan(0.0));
        expect(l.frameRect.left, closeTo(l.leftShrink, 0.001));
        expect(l.frameRect.right, closeTo(phoneSize.width - l.rightShrink, 0.001));
      });

      test('the two gutters are symmetric and additive', () {
        expect(l.leftShrink, closeTo(l.rightShrink, 0.0001));

        final reference = (phoneSize.width - 2 * SorobanLayout.frameBorder) / rods;
        final shrink = 0.05 * (phoneSize.width - 2 * SorobanLayout.frameBorder);
        expect(l.leftShrink, closeTo(shrink, 0.0001));
        // 5% from each side, so the pitch drops by 10%.
        expect(l.rodSpacing, closeTo(reference * 0.90, 0.0001));
      });
    });

    group('hard constraints hold in every gutter mode', () {
      final modes = <String, ({double? left, double? right})>{
        'none': (left: 1.0, right: 1.0),
        'right only': (left: 1.0, right: 0.95),
        'left only': (left: 0.95, right: 1.0),
        'both': (left: 0.95, right: 0.95),
      };

      modes.forEach((label, mode) {
        test('[$label] bead size is untouched', () {
          final l = build(left: mode.left, right: mode.right);
          expect(l.beadWidth, closeTo(referenceBeadWidth(phoneSize, rods), 0.0001));
        });

        test('[$label] frame height and every vertical metric are untouched', () {
          final plain = build(left: 1.0, right: 1.0);
          final l = build(left: mode.left, right: mode.right);

          expect(l.frameRect.height, equals(phoneSize.height));
          expect(l.innerRect.height, closeTo(plain.innerRect.height, 0.0001));
          expect(l.innerRect.top, equals(SorobanLayout.frameBorder));
          expect(l.beamTop, closeTo(plain.beamTop, 0.0001));
          expect(l.beamBottom, closeTo(plain.beamBottom, 0.0001));
          expect(l.beadHeight, closeTo(plain.beadHeight, 0.0001));
          expect(l.beadPitch, closeTo(plain.beadPitch, 0.0001));
          expect(l.travelDistance, closeTo(plain.travelDistance, 0.0001));
          expect(verticalTotal(l), closeTo(verticalTotal(plain), 0.001));
          expect(l.computeHeavenY(true), closeTo(plain.computeHeavenY(true), 0.0001));
          for (int count = 0; count <= 4; count++) {
            for (int b = 0; b < 4; b++) {
              expect(
                l.computeEarthY(b, count),
                closeTo(plain.computeEarthY(b, count), 0.0001),
              );
            }
          }
        });

        test('[$label] rod count, bead count and rod X positions are consistent', () {
          final l = build(left: mode.left, right: mode.right);

          // Exactly one rod per column, evenly spaced, all inside the frame.
          for (int i = 0; i < rods; i++) {
            final x = l.rodCenterX(i);
            expect(x, greaterThan(l.frameRect.left));
            expect(x, lessThan(l.frameRect.right));
            final hit = l.hitTest(Offset(x, l.computeHeavenY(false) + 1.0));
            expect(hit, isNotNull);
            expect(hit!.rodIndex, equals(i));
          }

          // Rod pitch is exactly frame width / rod count, gutters included.
          final inner = l.innerRect.width;
          expect(l.rodSpacing, closeTo(inner / rods, 0.0001));

          // The rightmost rod sits a half pitch from the right frame edge.
          expect(
            l.rodCenterX(0),
            closeTo(l.innerRect.right - l.rodSpacing / 2, 0.0001),
          );
        });

        test('[$label] the freed strips are outside the frame and map to no rod', () {
          final l = build(left: mode.left, right: mode.right);
          const y = 40.0;

          if (l.leftShrink > 0) {
            expect(l.hitTest(Offset(l.frameRect.left / 2, y)), isNull);
          }
          if (l.rightShrink > 0) {
            expect(
              l.hitTest(Offset((l.innerRect.right + l.frameRect.right) / 2, y)),
              isNull,
            );
          }
        });
      });
    });

    group('pitch floor', () {
      test('both gutters together cannot push the pitch below minPitchRatio', () {
        // 0.90 + 0.90 would mean a 20% total shrink, i.e. a 0.80 pitch.
        final l = build(left: 0.90, right: 0.90);
        final reference = (phoneSize.width - 2 * SorobanLayout.frameBorder) / rods;

        expect(l.rodSpacing / reference, closeTo(SorobanLayout.minPitchRatio, 0.0001));
        // Beads still fit side by side, they never overlap. The floor puts the
        // pitch exactly at the bead width, so compare with a tolerance.
        expect(l.rodSpacing, closeTo(l.beadWidth, 0.0001));
      });

      test('the clamp keeps the requested left/right balance', () {
        final l = build(left: 0.95, right: 0.85);
        // 5% left vs 15% right requested; the ratio must survive the clamp.
        expect(l.leftShrink / l.rightShrink, closeTo(5.0 / 15.0, 0.001));
      });

      test('an out-of-range scale is clamped instead of collapsing the pitch', () {
        final l = build(left: -5.0, right: -5.0);
        expect(l.rodSpacing, greaterThan(0.0));
        expect(l.frameRect.width, greaterThan(0.0));
      });
    });
  });
}
