import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/soroban_state.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';
import 'soroban_layout.dart';
import 'soroban_painter.dart';

/// Interactive Soroban widget that displays the procedural abacus
/// and translates touch/pointer gestures into natural bead motions.
///
/// Supports two gesture modes that resolve automatically via Flutter's
/// gesture arena:
/// - **Quick tap** (pointer up before drag slop): toggles targeted bead.
///   Opt-in via `SorobanController.tapToToggleEnabled` (off by default), so
///   this mode is simply not registered when the user keeps beads drag-only.
/// - **Sustained drag** (pointer moves beyond slop): beads follow the
///   cursor/finger in real-time with 1D rigid body push physics, committing on release.
class SorobanView extends StatefulWidget {
  final bool showDigitalReadout;

  /// Extra bead travel (px) granted to each deck. Pair it with a widget that is
  /// exactly `2 * travelBoost` taller than the un-boosted variant to grow the
  /// empty gap between the heaven/earth decks and the beam without resizing the
  /// beads. 0.0 keeps the default behaviour where travel follows bead size.
  final double travelBoost;

  const SorobanView({
    super.key,
    this.showDigitalReadout = true,
    this.travelBoost = 0.0,
  });

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

  // ── Drag state ──────────────────────────────────────────────
  int? _dragRodIndex;
  bool _isDraggingEarth = false;
  bool _isDraggingHeaven = false;
  double _dragStartY = 0;

  // Earth drag state (per-bead floating positions)
  int? _grabbedEarthIndex;
  List<double>? _dragStartEarthY;
  List<double>? _currentEarthY;

  // Heaven drag state (floating Y position)
  bool _dragStartHeavenActive = false;
  double? _currentHeavenY;

  // Layout cache (updated every build via LayoutBuilder)
  Size _lastSize = Size.zero;

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

    // Snapshot current target position as the new "previous"
    _previousState = _targetState;
    _targetState = newState;

    // Reset and start the animation
    _animController.forward(from: 0.0);
  }

  SorobanLayout _getLayout(int totalRods) {
    return SorobanLayout(
      size: _lastSize,
      totalRods: totalRods,
      travelBoost: widget.travelBoost,
    );
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SorobanController>();

    // Detect state changes and trigger animation
    _onStateChanged(controller.state);

    if (!widget.showDigitalReadout) {
      return _buildAbacus(controller);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: _buildAbacus(controller),
        ),
        const SizedBox(height: 6),
        _buildDigitalReadout(controller),
      ],
    );
  }

  Widget _buildAbacus(SorobanController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastSize = constraints.biggest;

        return GestureDetector(
          // Quick tap: fires when pointer lifts before exceeding drag slop.
          // Opt-in only (default OFF): beads are drag-only unless the user
          // enables "Klik Manik" in Settings.
          onTapUp: controller.tapToToggleEnabled
              ? (details) => _handleTap(details.localPosition, controller)
              : null,
          // Sustained drag: fires when pointer moves beyond drag slop
          onVerticalDragStart: (details) =>
              _onDragStart(details, controller),
          onVerticalDragUpdate: (details) =>
              _onDragUpdate(details, controller),
          onVerticalDragEnd: (details) =>
              _onDragEnd(details, controller),
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: SorobanPainter(
              state: controller.state,
              perRodColor: controller.perRodColor,
              animatingBeadKey: controller.animatingBeadKey,
              trailBeads: controller.trailBeads,
              travelBoost: widget.travelBoost,
              // Slide animation data
              previousState: _previousState,
              animationProgress: _curvedAnim.value,
              // Drag floating data
              dragRodIndex: _dragRodIndex,
              dragEarthY: _isDraggingEarth ? _currentEarthY : null,
              dragHeavenY: _isDraggingHeaven ? _currentHeavenY : null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDigitalReadout(SorobanController controller) {
    final totalRods = controller.state.rods.length;

    // The readout Row is laid out on its own so it can use the same available
    // width the abacus got. Padding both sides by the matching frame gutter
    // keeps every badge centred exactly under its rod, whichever side the
    // frame was shrunk from.
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: EdgeInsets.only(
            left: SorobanLayout.frameBorder +
                SorobanLayout.leftShrinkFor(constraints.maxWidth),
            right: SorobanLayout.frameBorder +
                SorobanLayout.rightShrinkFor(constraints.maxWidth),
          ),
          child: Row(
            children: List.generate(totalRods, (col) {
              final rodIndex = totalRods - 1 - col;
              final rodValue = controller.state.rods[rodIndex].value;
              final hasValue = rodValue > 0;

              return Expanded(
                child: Center(
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      maxWidth: 36,
                      minHeight: 26,
                      maxHeight: 28,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: hasValue
                          ? SorobanTheme.frameColor.withValues(alpha: 0.10)
                          : SorobanTheme.frameColor.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: hasValue
                            ? SorobanTheme.frameColor.withValues(alpha: 0.28)
                            : SorobanTheme.frameColor.withValues(alpha: 0.12),
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      '$rodValue',
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontSize: 16,
                        fontWeight:
                            hasValue ? FontWeight.bold : FontWeight.w500,
                        color: hasValue
                            ? SorobanTheme.textDark
                            : SorobanTheme.textMuted,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  // ── Quick Tap Handler ───────────────────────────────────────

  void _handleTap(Offset localPos, SorobanController controller) {
    if (controller.isAnimating) return;

    final layout = _getLayout(controller.state.rods.length);
    final hit = layout.hitTest(localPos);
    if (hit == null) return;

    if (hit.deck == 'heaven') {
      controller.tapHeavenBead(hit.rodIndex);
    } else if (hit.deck == 'earth') {
      final currentEarth = controller.state.rods[hit.rodIndex].earth;
      final tappedBead =
          layout.earthBeadIndexAt(currentEarth, localPos.dy);

      // Tapping an active bead (b < currentEarth) deactivates it and beads below it -> target = b
      // Tapping an inactive bead (b >= currentEarth) activates it and beads above it -> target = b + 1
      final targetCount =
          tappedBead < currentEarth ? tappedBead : tappedBead + 1;

      if (targetCount != currentEarth) {
        controller.tapEarthBead(hit.rodIndex, targetCount);
      }
    }
  }

  // ── Drag Handlers ──────────────────────────────────────────

  void _onDragStart(
    DragStartDetails details,
    SorobanController controller,
  ) {
    if (controller.isAnimating) return;

    final layout = _getLayout(controller.state.rods.length);
    final hit = layout.hitTest(details.localPosition);
    if (hit == null) return;

    _dragRodIndex = hit.rodIndex;
    _dragStartY = details.localPosition.dy;

    if (hit.deck == 'heaven') {
      _isDraggingHeaven = true;
      _isDraggingEarth = false;
      _dragStartHeavenActive =
          controller.state.rods[hit.rodIndex].heaven;
      _currentHeavenY = layout.computeHeavenY(_dragStartHeavenActive);
    } else {
      _isDraggingEarth = true;
      _isDraggingHeaven = false;
      final currentEarth = controller.state.rods[hit.rodIndex].earth;
      _grabbedEarthIndex = layout.earthBeadIndexAt(
        currentEarth,
        details.localPosition.dy,
      );
      _dragStartEarthY = List<double>.generate(
        4,
        (b) => layout.computeEarthY(b, currentEarth),
      );
      _currentEarthY = List<double>.from(_dragStartEarthY!);
    }

    setState(() {});
  }

  void _onDragUpdate(
    DragUpdateDetails details,
    SorobanController controller,
  ) {
    if (_dragRodIndex == null) return;

    final layout = _getLayout(controller.state.rods.length);
    final deltaY = details.localPosition.dy - _dragStartY;

    if (_isDraggingEarth &&
        _grabbedEarthIndex != null &&
        _dragStartEarthY != null) {
      _currentEarthY = layout.computeEarthDragPositions(
        grabbedIndex: _grabbedEarthIndex!,
        initialEarthY: _dragStartEarthY!,
        deltaY: deltaY,
      );
      setState(() {});
    } else if (_isDraggingHeaven) {
      _currentHeavenY = layout.computeHeavenDragY(
        _dragStartHeavenActive,
        deltaY,
      );
      setState(() {});
    }
  }

  void _onDragEnd(
    DragEndDetails details,
    SorobanController controller,
  ) {
    if (_dragRodIndex == null) return;
    final rodIndex = _dragRodIndex!;
    final layout = _getLayout(controller.state.rods.length);

    if (_isDraggingEarth && _currentEarthY != null) {
      final targetCount =
          layout.resolveEarthActiveCount(_currentEarthY!);
      final currentEarth = controller.state.rods[rodIndex].earth;
      if (targetCount != currentEarth) {
        controller.tapEarthBead(rodIndex, targetCount);
        _previousState = controller.state;
        _targetState = controller.state;
      }
    } else if (_isDraggingHeaven && _currentHeavenY != null) {
      final targetActive =
          layout.resolveHeavenActive(_currentHeavenY!);
      if (targetActive != _dragStartHeavenActive) {
        controller.tapHeavenBead(rodIndex);
        _previousState = controller.state;
        _targetState = controller.state;
      }
    }

    // Reset drag state
    _dragRodIndex = null;
    _isDraggingEarth = false;
    _isDraggingHeaven = false;
    _grabbedEarthIndex = null;
    _dragStartEarthY = null;
    _currentEarthY = null;
    _currentHeavenY = null;
    setState(() {});
  }
}
