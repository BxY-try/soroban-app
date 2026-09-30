import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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
/// lifts; a deck that is already held ignores further fingers instead of
/// letting two of them fight over the same beads.
///
/// Pointer gestures resolve into one of two modes:
/// - **Quick tap** (short, and barely moved): toggles the targeted bead. Opt-in
///   via `SorobanController.tapToToggleEnabled` (off by default), so this mode
///   is simply not honoured when the user keeps beads drag-only.
/// - **Drag** (anything else): beads follow the finger in real time with 1D
///   rigid body push physics from the first pixel of movement, commit on
///   release, and glide the last few pixels into their slot.
///
/// Rendering is split so that nothing here rebuilds the widget tree while a
/// finger moves: pointer events and animations only ping a [Listenable] that
/// the bead layer listens to, and the static frame sits in its own
/// `RepaintBoundary`.
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// Longest press that still counts as a tap. Mirrors the old arena deadline:
  /// a held-down finger lifts without toggling, it just does nothing.
  static const Duration _tapWindow = Duration(milliseconds: 400);

  /// A finger must move at least this far (logical px) before the beads follow
  /// it. Deliberately tiny: the old gate was `kTouchSlop`, 18 logical px, which
  /// is a *tap-vs-scroll* threshold. On a bead it meant a dead zone (the bead
  /// sat still under a moving finger) followed by a jump, and a quick flick
  /// shorter than that never registered at all.
  static const double _followSlop = 1.0;

  /// With tap-to-toggle on, a press that ends within this distance still counts
  /// as a tap even though the beads followed the finger a little.
  static const double _tapSlop = 8.0;

  /// How long a released bead takes to glide from where the finger left it to
  /// its slot.
  static const Duration _settleDuration = Duration(milliseconds: 130);

  // ── Animation ──────────────────────────────────────────────
  /// Slide animation for state changes that did not come from a finger
  /// (hints, replay, reset, tap-to-toggle).
  late final AnimationController _slide;
  late final CurvedAnimation _slideCurve;

  /// Drives the release glide. One ticker for every gliding bead; it stops
  /// itself when the last one arrives, so nothing keeps scheduling frames.
  late final Ticker _settleTicker;
  Duration _settleElapsed = Duration.zero;
  final Map<int, _SettleGhost> _ghosts = {};

  /// Pinged by pointer events and the settle ticker: "the bead layer changed".
  final _Signal _repaint = _Signal();

  /// Pinged only when the board or a visual setting changed: "the readout
  /// changed". Kept apart from [_repaint] so a drag never rebuilds the readout.
  final _Signal _board = _Signal();

  late final Listenable _paintListenable;

  // ── Controller mirror ──────────────────────────────────────
  SorobanController? _controller;

  /// Previous soroban state (before current animation).
  SorobanState? _previousState;

  /// Target soroban state (what we're animating towards).
  SorobanState? _targetState;

  bool _lastPerRodColor = false;
  String? _lastAnimatingKey;

  /// True while this view is committing a drag to the controller. That change
  /// already happened on screen (the finger showed it), so it must not slide.
  bool _committing = false;

  // ── Multi-touch drag state ─────────────────────────────────
  /// Live pointer sessions keyed by pointer id. Empty when nobody touches the
  /// abacus, which is the common case and costs nothing to keep.
  final Map<int, _BeadPointerSession> _sessions = {};

  // Layout cache
  Size _lastSize = Size.zero;
  SorobanLayout? _layout;
  Size _layoutSize = Size.zero;
  int _layoutRods = 0;
  double _layoutBoost = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _slide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slideCurve = CurvedAnimation(
      parent: _slide,
      curve: Curves.easeInOut,
    );
    _settleTicker = createTicker(_onSettleTick);
    _paintListenable = Listenable.merge([_slide, _repaint]);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<SorobanController>();
    if (identical(controller, _controller)) return;

    _controller?.removeListener(_onControllerChanged);
    _controller = controller;
    controller.addListener(_onControllerChanged);

    _sessions.clear();
    _ghosts.clear();
    _previousState = controller.state;
    _targetState = controller.state;
    _lastPerRodColor = controller.perRodColor;
    _lastAnimatingKey = controller.animatingBeadKey;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onControllerChanged);
    _settleTicker.dispose();
    _slideCurve.dispose();
    _slide.dispose();
    _repaint.dispose();
    _board.dispose();
    super.dispose();
  }

  /// A gesture that gets cut off by the app leaving the foreground is void, but
  /// the beads are not: whatever the fingers left stays, and the next touch
  /// reconciles whatever the board then says.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    if (_sessions.isEmpty) return;
    _clearSessions();
  }

  // ── Controller → view ──────────────────────────────────────

  /// Runs on every controller notification, including the 10 Hz challenge timer
  /// tick, so it only compares a few fields and pings the layers when one of
  /// them actually changed. Nothing is rebuilt for a notification that changes
  /// nothing this view shows.
  void _onControllerChanged() {
    final controller = _controller;
    if (controller == null || !mounted) return;

    // A notification that lands in the middle of a frame (build/layout/paint)
    // cannot mark widgets dirty; replay it right after the frame instead.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onControllerChanged();
      });
      return;
    }

    var changed = false;

    final newState = controller.state;
    if (_targetState == null || newState != _targetState) {
      if (_committing) {
        // The finger already showed this exact board; no slide.
        _previousState = newState;
        _targetState = newState;
      } else {
        // Snapshot current target position as the new "previous"
        _previousState = _targetState;
        _targetState = newState;
        _slide.forward(from: 0.0);
      }
      changed = true;
    }

    if (controller.perRodColor != _lastPerRodColor ||
        controller.animatingBeadKey != _lastAnimatingKey) {
      _lastPerRodColor = controller.perRodColor;
      _lastAnimatingKey = controller.animatingBeadKey;
      changed = true;
    }

    if (changed) {
      _board.ping();
      _repaint.ping();
    }
  }

  SorobanLayout _getLayout(int totalRods) {
    final cached = _layout;
    if (cached != null &&
        _layoutSize == _lastSize &&
        _layoutRods == totalRods &&
        _layoutBoost == widget.travelBoost) {
      return cached;
    }
    final layout = SorobanLayout(
      size: _lastSize,
      totalRods: totalRods,
      travelBoost: widget.travelBoost,
    );
    _layout = layout;
    _layoutSize = _lastSize;
    _layoutRods = totalRods;
    _layoutBoost = widget.travelBoost;
    return layout;
  }

  // ── Per-frame scene data ───────────────────────────────────

  /// Per-rod floating positions of every deck a finger is dragging, plus the
  /// decks that are still gliding to rest after a release.
  ///
  /// Pointer-down only claims a deck; a session contributes here once the finger
  /// has moved. Two fingers on one rod (heaven and earth) merge into a single
  /// entry, which is what lets a `9` be set with both decks moving at once.
  Map<int, BeadDragState> _dragStates(
    SorobanLayout layout,
    SorobanState state,
  ) {
    if (_sessions.isEmpty && _ghosts.isEmpty) return const {};

    final earth = <int, List<double>>{};
    final heaven = <int, double>{};

    // Gliding decks first, so a live finger on the same deck overrides them.
    for (final ghost in _ghosts.values) {
      if (ghost.rodIndex >= state.rods.length) continue;
      final rod = state.rods[ghost.rodIndex];
      final t = _ghostProgress(ghost);
      if (ghost.isEarth) {
        final from = ghost.earthFrom!;
        earth[ghost.rodIndex] = List<double>.generate(
          4,
          (b) => _lerp(from[b], layout.computeEarthY(b, rod.earth), t),
        );
      } else {
        heaven[ghost.rodIndex] = _lerp(
          ghost.heavenFrom!,
          layout.computeHeavenY(rod.heaven),
          t,
        );
      }
    }

    for (final session in _sessions.values) {
      if (!session.dragging) continue;
      if (session.isEarthDeck) {
        final y = session.currentEarthY;
        if (y != null) earth[session.rodIndex] = y;
      } else {
        final y = session.currentHeavenY;
        if (y != null) heaven[session.rodIndex] = y;
      }
    }

    if (earth.isEmpty && heaven.isEmpty) return const {};
    return {
      for (final rod in {...earth.keys, ...heaven.keys})
        rod: BeadDragState(earthY: earth[rod], heavenY: heaven[rod]),
    };
  }

  /// What every live finger is touching, from the moment it lands.
  Map<int, RodTouch> _touches() {
    if (_sessions.isEmpty) return const {};
    final result = <int, RodTouch>{};
    for (final session in _sessions.values) {
      final previous = result[session.rodIndex];
      result[session.rodIndex] = RodTouch(
        heavenHeld: (previous?.heavenHeld ?? false) || !session.isEarthDeck,
        earthGrabbedIndex: session.isEarthDeck
            ? session.startEarthIndex
            : previous?.earthGrabbedIndex,
      );
    }
    return result;
  }

  double _ghostProgress(_SettleGhost ghost) {
    final elapsed = _settleElapsed - ghost.startedAt;
    final raw = elapsed.inMicroseconds / _settleDuration.inMicroseconds;
    return Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0).toDouble());
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static int _ghostKey(int rodIndex, bool isEarth) =>
      rodIndex * 2 + (isEarth ? 1 : 0);

  // ── Settle (release glide) ─────────────────────────────────

  /// Lets the deck [session] was dragging glide from where the finger left it
  /// to wherever the board says it belongs. Call it *before* committing, so the
  /// glide starts from the finger's position, and whatever the commit decides
  /// (move or spring back) is where it lands.
  void _startSettle(_BeadPointerSession session) {
    if (!session.dragging) return;
    final earthFrom = session.currentEarthY;
    final heavenFrom = session.currentHeavenY;
    if (session.isEarthDeck ? earthFrom == null : heavenFrom == null) return;

    final startedAt = _settleTicker.isActive ? _settleElapsed : Duration.zero;
    _ghosts[_ghostKey(session.rodIndex, session.isEarthDeck)] = _SettleGhost(
      rodIndex: session.rodIndex,
      isEarth: session.isEarthDeck,
      earthFrom: earthFrom == null ? null : List<double>.of(earthFrom),
      heavenFrom: heavenFrom,
      startedAt: startedAt,
    );

    if (!_settleTicker.isActive) {
      _settleElapsed = Duration.zero;
      _settleTicker.start();
    }
  }

  void _onSettleTick(Duration elapsed) {
    _settleElapsed = elapsed;
    _ghosts.removeWhere(
      (_, ghost) => elapsed - ghost.startedAt >= _settleDuration,
    );
    if (_ghosts.isEmpty) _settleTicker.stop();
    _repaint.ping();
  }

  /// Drops every live session, e.g. because a hint animation or the platform
  /// took the abacus over. The board is left exactly as the fingers left it and
  /// the chain is left for the next real gesture to reconcile.
  void _clearSessions() {
    if (_sessions.isEmpty) return;
    _sessions.clear();
    _ghosts.clear();
    _repaint.ping();
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final abacus = _buildAbacus();

    if (!widget.showDigitalReadout) {
      return abacus;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(child: abacus),
        const SizedBox(height: 6),
        _buildDigitalReadout(),
      ],
    );
  }

  Widget _buildAbacus() {
    final totalRods = _controller!.state.rods.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        _lastSize = constraints.biggest;
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return Listener(
          // Multi-touch: raw pointer events instead of an arena-based
          // recogniser, because a VerticalDragGestureRecognizer only ever
          // reports the first pointer it wins. One finger per deck, many rods
          // at once, resolved in _handlePointerDown/Move/Up.
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Static frame: rasterised once, reused every frame.
              RepaintBoundary(
                child: CustomPaint(
                  size: size,
                  painter: SorobanFramePainter(
                    totalRods: totalRods,
                    travelBoost: widget.travelBoost,
                  ),
                ),
              ),
              // Beads: the only layer that changes while a finger moves. The
              // builder below is the *only* thing that runs per frame.
              RepaintBoundary(
                child: ListenableBuilder(
                  listenable: _paintListenable,
                  builder: (context, _) => CustomPaint(
                    size: size,
                    painter: _buildBeadPainter(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  SorobanPainter _buildBeadPainter() {
    final controller = _controller!;
    final state = controller.state;
    final layout = _getLayout(state.rods.length);

    return SorobanPainter(
      state: state,
      perRodColor: controller.perRodColor,
      animatingBeadKey: controller.animatingBeadKey,
      travelBoost: widget.travelBoost,
      // Slide animation data
      previousState: _previousState,
      animationProgress: _slideCurve.value,
      // Drag floating + release glide data
      dragStates: _dragStates(layout, state),
      // "A finger is on this" data
      touches: _touches(),
    );
  }

  Widget _buildDigitalReadout() {
    return ListenableBuilder(
      listenable: _board,
      builder: (context, _) {
        final state = _controller!.state;
        final totalRods = state.rods.length;

        // The readout Row is laid out on its own so it can use the same
        // available width the abacus got. Padding both sides by the matching
        // frame gutter keeps every badge centred exactly under its rod,
        // whichever side the frame was shrunk from.
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
                  final rodValue = state.rods[rodIndex].value;
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
      },
    );
  }

  // ── Touch resolution ────────────────────────────────────────

  /// Works out which rod and deck a finger at [position] means.
  ///
  /// `SorobanLayout.hitTest` already maps every point of the board to a rod and
  /// a deck; the only place it answers "nothing" is the beam (14 px) and the
  /// frame around the board. Real fingers land on the beam often enough to
  /// matter, so that one case is resolved here instead of being dropped:
  ///
  /// * A touch on the beam belongs to the nearest rod, on the side of the beam
  ///   centre it is closest to.
  /// * Two fingers on one rod is the normal soroban technique (index on the
  ///   heaven bead, thumb pushing earth beads up). If a beam touch resolves to
  ///   a deck that is already held while the *other* deck is free, it goes to
  ///   the free one.
  ///
  /// Touches on a bead or in the gap around one are never re-interpreted: what
  /// the finger is over is what it gets.
  ({int rodIndex, bool isEarth})? _resolveTouch(
    SorobanLayout layout,
    Offset position,
    int totalRods,
  ) {
    final hit = layout.hitTest(position);
    if (hit != null) {
      return (rodIndex: hit.rodIndex, isEarth: hit.deck == 'earth');
    }

    if (!layout.innerRect.contains(position)) return null;

    final beamCenter = layout.beamTop + SorobanLayout.beamHeight / 2;
    final rodIndex = _nearestRod(layout, position.dx, totalRods);
    var isEarth = position.dy > beamCenter;

    if (_isDeckHeld(rodIndex, isEarth) && !_isDeckHeld(rodIndex, !isEarth)) {
      isEarth = !isEarth;
    }
    return (rodIndex: rodIndex, isEarth: isEarth);
  }

  int _nearestRod(SorobanLayout layout, double x, int totalRods) {
    var best = 0;
    var bestDistance = double.infinity;
    for (var rod = 0; rod < totalRods; rod++) {
      final distance = (x - layout.rodCenterX(rod)).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = rod;
      }
    }
    return best;
  }

  /// One finger per rod *deck*. Two fingers on the same deck would fight over
  /// the same beads, but heaven and earth on one rod are two different decks and
  /// are meant to be set together.
  bool _isDeckHeld(int rodIndex, bool isEarthDeck) {
    for (final session in _sessions.values) {
      if (session.rodIndex == rodIndex && session.isEarthDeck == isEarthDeck) {
        return true;
      }
    }
    return false;
  }

  // ── Pointer Handlers (one per finger) ──────────────────────

  /// Claims the rod and deck under [event] for that finger alone, and shows it
  /// right away (deck band, lifted bead, a light haptic tick).
  ///
  /// The board is a physical abacus, so every rod is available at all times:
  /// nothing here consults the checkpoint chain. A pointer is only dropped when
  /// it lands outside the board, or on a deck another finger already holds —
  /// two fingers on the same beads would fight over them, which is a property
  /// of the beads, not of the exercise.
  void _handlePointerDown(PointerDownEvent event) {
    final controller = _controller;
    if (controller == null || controller.isAnimating) return;

    final totalRods = controller.state.rods.length;
    final layout = _getLayout(totalRods);
    final target = _resolveTouch(layout, event.localPosition, totalRods);
    if (target == null) {
      _debugNote('pointer ${event.pointer} ignored: outside the board');
      return;
    }

    final isEarth = target.isEarth;
    if (_isDeckHeld(target.rodIndex, isEarth)) {
      _debugNote(
        'pointer ${event.pointer} ignored: rod ${target.rodIndex} '
        '${isEarth ? 'earth' : 'heaven'} deck is already held',
      );
      return;
    }

    final rod = controller.state.rods[target.rodIndex];
    final currentEarth = rod.earth;

    // A new finger takes the deck over from any glide still in flight.
    _ghosts.remove(_ghostKey(target.rodIndex, isEarth));

    _sessions[event.pointer] = _BeadPointerSession(
      rodIndex: target.rodIndex,
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

    _hapticTick();
    _repaint.ping();
  }

  /// Moves the beads of the rod this finger grabbed.
  void _handlePointerMove(PointerMoveEvent event) {
    final controller = _controller;
    final session = _sessions[event.pointer];
    if (controller == null || session == null) return;

    // A hint/replay animation grabbed the abacus: drop the finger's session
    // rather than fighting it for the same beads.
    if (controller.isAnimating) {
      _clearSessions();
      return;
    }

    final layout = _getLayout(controller.state.rods.length);
    if (_updateSession(session, event.localPosition, layout)) {
      _repaint.ping();
    }
  }

  /// Follows the finger: recomputes the floating positions for [position].
  /// Returns whether anything moved.
  bool _updateSession(
    _BeadPointerSession session,
    Offset position,
    SorobanLayout layout,
  ) {
    final deltaY = position.dy - session.downPosition.dy;

    if (!session.dragging) {
      if (deltaY.abs() < _followSlop) return false;
      session.dragging = true;
    }

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
    return true;
  }

  /// Commits this finger's rod: the drag lands where it was released, and a
  /// short press is the optional tap-to-toggle shortcut. Rods held by other
  /// fingers are untouched, so they keep floating until their own finger lifts.
  ///
  /// When the last finger of the gesture goes up, the controller gets its one
  /// chance to reconcile the checkpoint chain. Two fingers lifting in the same
  /// frame therefore produce exactly one reconciliation, not one per commit.
  void _handlePointerUp(PointerUpEvent event) {
    final controller = _controller;
    final session = _sessions.remove(event.pointer);
    if (controller == null || session == null) return;

    if (controller.isAnimating) {
      _clearSessions();
      return;
    }

    final layout = _getLayout(controller.state.rods.length);

    final travelled = (event.localPosition - session.downPosition).distance;
    final isTap = controller.tapToToggleEnabled &&
        event.timeStamp - session.downTime <= _tapWindow &&
        travelled <= _tapSlop;

    if (isTap) {
      // A tap can still have jittered the bead by a pixel or two; let it glide
      // from there to its new slot instead of popping.
      _startSettle(session);
      _handleTap(session, controller, layout);
    } else if (session.dragging) {
      // The up event can be a step ahead of the last move; land on it.
      _updateSession(session, event.localPosition, layout);
      _commitDrag(session, controller, layout);
    }

    if (_sessions.isEmpty) {
      controller.onGestureSettled();
    }

    _repaint.ping();
  }

  /// The gesture was taken away (e.g. the platform claimed it). The board is
  /// not touched and the chain is not reconciled: a gesture that never finished
  /// is not a gesture that was completed. The bead glides back to its slot.
  void _handlePointerCancel(PointerCancelEvent event) {
    final session = _sessions.remove(event.pointer);
    if (session == null) return;
    _startSettle(session);
    _repaint.ping();
  }

  void _commitDrag(
    _BeadPointerSession session,
    SorobanController controller,
    SorobanLayout layout,
  ) {
    final rodIndex = session.rodIndex;

    // Glide from the finger's position to wherever the commit puts the deck
    // (or back where it was, if the drag did not move it far enough).
    _startSettle(session);

    _committing = true;
    try {
      if (session.isEarthDeck) {
        final floating = session.currentEarthY;
        if (floating == null) return;
        final targetCount = layout.resolveEarthActiveCount(floating);
        final currentEarth = controller.state.rods[rodIndex].earth;
        if (targetCount != currentEarth) {
          controller.tapEarthBead(rodIndex, targetCount);
        }
      } else {
        final floating = session.currentHeavenY;
        if (floating == null) return;
        final targetActive = layout.resolveHeavenActive(floating);
        if (targetActive != session.startHeavenActive) {
          controller.tapHeavenBead(rodIndex);
        }
      }
    } finally {
      _committing = false;
    }

    // The finger already showed the beads in their final resting place, so the
    // slide animation is skipped — per finger, not once for the whole abacus.
    _previousState = controller.state;
    _targetState = controller.state;
  }

  // ── Quick Tap Handler ───────────────────────────────────────

  /// Tap-to-toggle. Uses the rod and deck the finger claimed on pointer-down,
  /// so a tap means exactly what the touch feedback showed.
  void _handleTap(
    _BeadPointerSession session,
    SorobanController controller,
    SorobanLayout layout,
  ) {
    if (controller.isAnimating) return;

    if (!session.isEarthDeck) {
      controller.tapHeavenBead(session.rodIndex);
      return;
    }

    final currentEarth = controller.state.rods[session.rodIndex].earth;
    final tappedBead = session.startEarthIndex;

    // Tapping an active bead (b < currentEarth) deactivates it and beads below it -> target = b
    // Tapping an inactive bead (b >= currentEarth) activates it and beads above it -> target = b + 1
    final targetCount = tappedBead < currentEarth ? tappedBead : tappedBead + 1;

    if (targetCount != currentEarth) {
      controller.tapEarthBead(session.rodIndex, targetCount);
    }
  }

  // ── Small helpers ───────────────────────────────────────────

  /// A very light tick when a finger grabs a deck: the physical "it's yours".
  void _hapticTick() {
    try {
      unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    } catch (_) {
      // No haptics on this platform; the visual cue still covers it.
    }
  }

  /// Debug-only breadcrumb for touches that were not accepted, so a "my second
  /// finger did nothing" report can be told apart from a real bug in
  /// `flutter run` output. Compiled out of release builds.
  void _debugNote(String message) {
    assert(() {
      debugPrint('[SorobanView] $message');
      return true;
    }());
  }
}

/// A [ChangeNotifier] that exists only to be pinged. Lets pointer events and
/// tickers repaint one layer without a `setState` on the whole view.
class _Signal extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// A deck that is gliding from where a finger left it to its slot.
class _SettleGhost {
  final int rodIndex;
  final bool isEarth;

  /// Floating positions at release; only the one matching [isEarth] is set.
  final List<double>? earthFrom;
  final double? heavenFrom;

  /// Settle-ticker time at which this glide began.
  final Duration startedAt;

  const _SettleGhost({
    required this.rodIndex,
    required this.isEarth,
    required this.earthFrom,
    required this.heavenFrom,
    required this.startedAt,
  });
}

/// One finger's claim on one deck of one rod, from pointer-down to pointer-up.
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

  /// Set once the finger moves, from then on this is a drag.
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
