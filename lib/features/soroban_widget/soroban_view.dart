import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/soroban_state.dart';
import '../../core/state/soroban_controller.dart';
import 'soroban_painter.dart';

/// Interactive Soroban widget that displays the procedural abacus
/// and translates touch/pointer gestures into natural bead motions.
/// Uses AnimationController to smoothly slide beads between positions.
class SorobanView extends StatefulWidget {
  const SorobanView({super.key});

  @override
  State<SorobanView> createState() => _SorobanViewState();
}

class _SorobanViewState extends State<SorobanView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _curvedAnim;

  /// Previous soroban state (before current animation).
  SorobanState? _previousState;
  /// Target soroban state (what we're animating towards).
  SorobanState? _targetState;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _curvedAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _animController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<SorobanController>();
    final newState = controller.state;

    // Initialize on first build
    if (_targetState == null) {
      _previousState = newState;
      _targetState = newState;
    }
  }

  /// Detects state changes and triggers slide animation.
  void _onStateChanged(SorobanState newState) {
    if (_targetState == null || newState == _targetState) return;

    // Snapshot current animated position as the new "previous"
    _previousState = _getInterpolatedState();
    _targetState = newState;

    // Reset and start the animation
    _animController.forward(from: 0.0);
  }

  /// Builds an interpolated SorobanState between _previousState and _targetState
  /// based on the current animation progress.
  SorobanState _getInterpolatedState() {
    if (_previousState == null || _targetState == null) {
      return _targetState ?? SorobanState.zero();
    }

    final t = _curvedAnim.value;
    if (t >= 1.0) return _targetState!;
    if (t <= 0.0) return _previousState!;

    // For rendering, we don't actually interpolate the Rod values (they're discrete).
    // Instead, the painter will use the target state for logic, and we pass the
    // animation progress so the painter can interpolate Y positions.
    // Since our painter uses Rod state directly (heaven bool, earth int),
    // we return the target state — the smooth animation is handled at paint level.
    return _targetState!;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SorobanController>();

    // Detect state changes and trigger animation
    _onStateChanged(controller.state);

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) {
            _handleTap(details.localPosition, constraints.biggest, controller);
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: SorobanPainter(
              state: controller.state,
              perRodColor: controller.perRodColor,
              animatingBeadKey: controller.animatingBeadKey,
              trailBeads: controller.trailBeads,
              // Pass animation data for smooth sliding
              previousState: _previousState,
              animationProgress: _curvedAnim.value,
            ),
          ),
        );
      },
    );
  }

  void _handleTap(
    Offset localPos,
    Size size,
    SorobanController controller,
  ) {
    if (controller.isAnimating) return;

    const frameBorder = 12.0;
    const beamHeight = 14.0;

    final frameInnerRect = Rect.fromLTWH(
      frameBorder,
      frameBorder,
      size.width - (frameBorder * 2),
      size.height - (frameBorder * 2),
    );

    if (!frameInnerRect.contains(localPos)) return;

    final totalRods = controller.state.rods.length;
    final usableWidth = frameInnerRect.width;
    final rodSpacing = usableWidth / totalRods;

    // Determine column clicked
    final relX = localPos.dx - frameInnerRect.left;
    final col = (relX / rodSpacing).floor().clamp(0, totalRods - 1);

    // Rod index from right: (totalRods - 1 - col)
    final rodIndex = totalRods - 1 - col;

    // Determine deck
    final innerHeight = frameInnerRect.height;
    final upperDeckHeight = (innerHeight - beamHeight) * 0.26;
    final beamTop = frameInnerRect.top + upperDeckHeight;
    final beamBottom = beamTop + beamHeight;

    final y = localPos.dy;

    if (y < beamTop) {
      // Clicked in Upper Deck -> Toggle Heaven Bead
      controller.tapHeavenBead(rodIndex);
    } else if (y > beamBottom) {
      // Clicked in Lower Deck -> Earth Beads
      final lowerDeckHeight = frameInnerRect.bottom - beamBottom;
      final relLowerY = y - beamBottom;
      final normalizedFraction = (relLowerY / lowerDeckHeight).clamp(0.0, 1.0);

      // Top of lower deck is 1, bottom is 4
      int targetCount;
      if (normalizedFraction < 0.28) {
        targetCount = 1;
      } else if (normalizedFraction < 0.52) {
        targetCount = 2;
      } else if (normalizedFraction < 0.76) {
        targetCount = 3;
      } else {
        targetCount = 4;
      }

      controller.tapEarthBead(rodIndex, targetCount);
    }
  }
}
