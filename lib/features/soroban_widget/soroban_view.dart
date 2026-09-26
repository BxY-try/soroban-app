import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/soroban_state.dart';
import '../../core/state/soroban_controller.dart';
import '../../shared/theme.dart';
import 'bead_drag_state.dart';
import 'soroban_layout.dart';
import 'soroban_painter.dart';

/// Interactive Soroban widget that displays the procedural abacus
/// and translates touch/pointer gestures into natural bead motions.
///
/// Every finger is tracked independently through its own pointer id, so
/// several rods can be manipulated at the same time (multi-touch). Each
/// pointer picks the rod it touched on pointer-down and keeps it until it
/// lifts; a rod that is already held ignores further fingers instead of
/// letting two of them fight over the same beads.
///
/// Pointer gestures resolve into one of two modes, mirroring the arena rules
/// the old single-pointer recognisers used:
/// - **Quick tap** (pointer up before drag slop): toggles targeted bead.
///   Opt-in via `SorobanController.tapToToggleEnabled` (off by default), so
///   this mode is simply not honoured when the user keeps beads drag-only.
/// - **Sustained drag** (pointer moves beyond slop): beads follow the
///   finger in real-time with 1D rigid body push physics, committing on release.
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
  /// Longest press that still counts as a tap. Mirrors the old arena deadline:
  /// a held-down finger lifts without toggling, it just does nothing.
  static const Duration _tapWindow = Duration(milliseconds: 400);

  late AnimationController _animController;
  late Animation<double> _curvedAnim;

  /// Previous soroban state (before current animation).
  SorobanState? _previousState;

  /// Target soroban state (what we're animating towards).
  SorobanState? _targetState;

  // ── Multi-touch drag state ─────────────────────────────────
  /// Live pointer sessions keyed by pointer id. Empty when nobody touches the
  /// abacus, which is the common case and costs nothing to keep.
  final Map<int, _BeadPointerSession> _sessions = {};

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

  /// Per-rod floating positions of every rod a finger is currently dragging.
  ///
  /// Pointer-down only claims a rod; the session contributes to this map once
  /// it has travelled past the slop, which is the same moment the beads used to
  /// detach from the frame.
  Map<int, BeadDragState> _dragStates() {
    if (_sessions.isEmpty) return const {};

    Map<int, BeadDragState>? states;
    for (final session in _sessions.values) {
      if (!session.dragging) continue;
      states ??= <int, BeadDragState>{};
      states[session.rodIndex] = BeadDragState(
        earthY: session.currentEarthY,
        heavenY: session.currentHeavenY,
      );
    }
    return states ?? const {};
  }

  /// Drops every live session without committing, e.g. because the controller
  /// took the abacus over for a hint animation.
  void _clearSessions() {
    if (_sessions.isEmpty) return;
    _sessions.clear();
    setState(() {});
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

        return Listener(
          // Multi-touch: raw pointer events instead of an arena-based
          // recogniser, because a VerticalDragGestureRecognizer only ever
          // reports the first pointer it wins. One finger per rod, many rods
          // at once, resolved in _handlePointerDown/Move/Up.
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _handlePointerDown(event, controller),
          onPointerMove: (event) => _handlePointerMove(event, controller),
          onPointerUp: (event) => _handlePointerUp(event, controller),
          onPointerCancel: _handlePointerCancel,
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
              dragStates: _dragStates(),
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

  // ── Pointer Handlers (one per finger) ──────────────────────

  /// Claims the rod under [event] for that finger alone.
  ///
  /// Landing on the beam, on the frame, or on a rod another finger already
  /// holds does nothing: the session is simply never created, so its later
  /// move/up events fall through untouched.
  void _handlePointerDown(
    PointerDownEvent event,
    SorobanController controller,
  ) {
    if (controller.isAnimating) return;

    final layout = _getLayout(controller.state.rods.length);
    final hit = layout.hitTest(event.localPosition);
    if (hit == null) return;
    if (_isRodHeld(hit.rodIndex)) return;

    final rod = controller.state.rods[hit.rodIndex];
    final isEarth = hit.deck == 'earth';
    final currentEarth = rod.earth;

    _sessions[event.pointer] = _BeadPointerSession(
      rodIndex: hit.rodIndex,
      isEarthDeck: isEarth,
      downPosition: event.localPosition,
      downTime: event.timeStamp,
      startHeavenActive: rod.heaven,
      startEarthIndex: isEarth
          ? layout.earthBeadIndexAt(currentEarth, event.localPosition.dy)
          : 0,
      startEarthY: isEarth
          ? List<double>.generate(
              4,
              (b) => layout.computeEarthY(b, currentEarth),
            )
          : const [],
    );
  }

  /// Moves the beads of the rod this finger grabbed, once it has travelled far
  /// enough to be a drag rather than a tap.
  void _handlePointerMove(
    PointerMoveEvent event,
    SorobanController controller,
  ) {
    final session = _sessions[event.pointer];
    if (session == null) return;

    // A hint/replay animation grabbed the abacus: drop the finger's session
    // rather than fighting it for the same beads.
    if (controller.isAnimating) {
      _clearSessions();
      return;
    }

    final layout = _getLayout(controller.state.rods.length);

    if (!session.dragging) {
      final travelled = event.localPosition - session.downPosition;
      // Same gate the vertical drag recogniser used: past touch slop, and
      // vertical, so a sideways swipe across the frame is not a bead move.
      if (travelled.distance < kTouchSlop) return;
      if (travelled.dy.abs() < travelled.dx.abs()) return;
      session.dragging = true;
    }

    final deltaY = event.localPosition.dy - session.downPosition.dy;
    if (session.isEarthDeck) {
      session.currentEarthY = layout.computeEarthDragPositions(
        grabbedIndex: session.startEarthIndex,
        initialEarthY: session.startEarthY,
        deltaY: deltaY,
      );
    } else {
      session.currentHeavenY = layout.computeHeavenDragY(
        session.startHeavenActive,
        deltaY,
      );
    }

    setState(() {});
  }

  /// Commits this finger's rod: the drag lands where it was released, and a
  /// short press is the optional tap-to-toggle shortcut. Rods held by other
  /// fingers are untouched, so they keep floating until their own finger lifts.
  void _handlePointerUp(
    PointerUpEvent event,
    SorobanController controller,
  ) {
    final session = _sessions.remove(event.pointer);
    if (session == null) return;

    if (controller.isAnimating) {
      setState(() {});
      return;
    }

    if (session.dragging) {
      _commitDrag(session, controller);
    } else if (controller.tapToToggleEnabled &&
        event.timeStamp - session.downTime <= _tapWindow) {
      _handleTap(session, event.localPosition, controller);
    }

    setState(() {});
  }

  /// The gesture was taken away (e.g. the platform claimed it), so the beads
  /// snap back without committing.
  void _handlePointerCancel(PointerCancelEvent event) {
    if (_sessions.remove(event.pointer) == null) return;
    setState(() {});
  }

  bool _isRodHeld(int rodIndex) {
    for (final session in _sessions.values) {
      if (session.rodIndex == rodIndex) return true;
    }
    return false;
  }

  void _commitDrag(
    _BeadPointerSession session,
    SorobanController controller,
  ) {
    final layout = _getLayout(controller.state.rods.length);
    final rodIndex = session.rodIndex;

    if (session.isEarthDeck && session.currentEarthY != null) {
      final targetCount =
          layout.resolveEarthActiveCount(session.currentEarthY!);
      final currentEarth = controller.state.rods[rodIndex].earth;
      if (targetCount == currentEarth) return;
      controller.tapEarthBead(rodIndex, targetCount);
    } else if (!session.isEarthDeck && session.currentHeavenY != null) {
      final targetActive = layout.resolveHeavenActive(session.currentHeavenY!);
      if (targetActive == session.startHeavenActive) return;
      controller.tapHeavenBead(rodIndex);
    } else {
      return;
    }

    // The finger already showed the beads in their final resting place, so the
    // slide animation is skipped — exactly what the old drag handler did, only
    // now per finger instead of once for the whole abacus.
    _previousState = controller.state;
    _targetState = controller.state;
  }

  // ── Quick Tap Handler ───────────────────────────────────────

  void _handleTap(
    _BeadPointerSession session,
    Offset localPos,
    SorobanController controller,
  ) {
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
}

/// One finger's claim on one rod, from pointer-down to pointer-up.
///
/// Immutable geometry (which rod, which deck, where the finger landed, the rest
/// positions captured at grab time) plus the mutable floating positions the
/// painter renders while the drag is in flight.
class _BeadPointerSession {
  /// Rod this finger owns for the whole gesture.
  final int rodIndex;

  /// Whether the finger grabbed the lower (earth) deck or the upper one.
  final bool isEarthDeck;

  /// Pointer-down position in the abacus' local coordinates.
  final Offset downPosition;

  /// Pointer-down timestamp, used to tell a tap from a press-and-hold.
  final Duration downTime;

  /// Heaven bead state when the finger landed, i.e. what a release that moves
  /// nothing should leave alone.
  final bool startHeavenActive;

  /// Earth bead (0..3) under the finger at grab time.
  final int startEarthIndex;

  /// Resting Y positions of all 4 earth beads at grab time, the baseline the
  /// rigid-body push physics resolves against.
  final List<double> startEarthY;

  /// Set once the finger travels past the slop, from then on this is a drag.
  bool dragging = false;

  /// Live floating positions, null until the drag starts.
  List<double>? currentEarthY;
  double? currentHeavenY;

  _BeadPointerSession({
    required this.rodIndex,
    required this.isEarthDeck,
    required this.downPosition,
    required this.downTime,
    required this.startHeavenActive,
    required this.startEarthIndex,
    required this.startEarthY,
  });
}

