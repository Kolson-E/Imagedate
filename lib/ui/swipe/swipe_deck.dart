import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/settings.dart';
import '../../platform/images.dart';
import '../../platform/library.dart';
import '../theme.dart';
import 'card_image.dart';

/// A stack of image cards. Drag the top card right to keep, left to pass, and
/// up (round 1 only) to Super Like. Pinch, double-tap or scroll to zoom.
/// Press and hold to see the whole image.
class SwipeDeck extends StatefulWidget {
  const SwipeDeck({
    super.key,
    required this.library,
    required this.items,
    required this.round,
    required this.settings,
    required this.onDecide,
    this.onTap,
    this.borderRadius = 20,
  });

  final Library library;

  /// Remaining images, in order. The first one is on top.
  final List<Item> items;
  final int round;
  final AppSettings settings;
  final void Function(Item item, Decision decision) onDecide;
  final VoidCallback? onTap;
  final double borderRadius;

  @override
  State<SwipeDeck> createState() => SwipeDeckState();
}

class SwipeDeckState extends State<SwipeDeck> with TickerProviderStateMixin {
  Offset _drag = Offset.zero;
  double _zoom = 1;
  Offset _pan = Offset.zero;
  bool _gestureIsZoom = false;
  double _zoomAtStart = 1;
  bool _showWhole = false;
  bool _busy = false;
  Decision? _armed; // decision that a release would make now (for haptics)
  Size _size = Size.zero;

  late final AnimationController _move = AnimationController(vsync: this);
  Animation<Offset>? _moveAnim;
  late final AnimationController _zoomCtl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<double>? _zoomAnim;
  Animation<Offset>? _panAnim;

  bool get _canSuper => widget.round == 1;

  @override
  void initState() {
    super.initState();
    _move.addListener(() {
      final a = _moveAnim;
      if (a != null) setState(() => _drag = a.value);
    });
    _zoomCtl.addListener(() {
      setState(() {
        _zoom = _zoomAnim?.value ?? _zoom;
        _pan = _panAnim?.value ?? _pan;
      });
    });
  }

  @override
  void didUpdateWidget(SwipeDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldTop = oldWidget.items.isEmpty ? null : oldWidget.items.first.id;
    final newTop = widget.items.isEmpty ? null : widget.items.first.id;
    if (oldTop != newTop && !_busy) _resetCard();
  }

  @override
  void dispose() {
    _move.dispose();
    _zoomCtl.dispose();
    super.dispose();
  }

  void _resetCard() {
    _drag = Offset.zero;
    _zoom = 1;
    _pan = Offset.zero;
    _showWhole = false;
    _armed = null;
  }

  int get _displayPixels {
    final mq = MediaQuery.of(context);
    final px = (mq.size.longestSide * mq.devicePixelRatio).ceil();
    // Round up so both orientations share one cached image.
    return ((px + 255) ~/ 256 * 256).clamp(1024, 3072);
  }

  void _haptic(void Function() f) {
    if (widget.settings.haptics) f();
  }

  // ------------------------------------------------------------ public API

  /// Swipes the top card away (buttons and keyboard).
  Future<void> swipe(Decision d) async {
    if (_busy || widget.items.isEmpty) return;
    if (d == Decision.superLike && !_canSuper) return;
    if (_zoom > 1.01) _resetZoom(animated: false);
    await _flyOut(d, velocity: Offset.zero);
  }

  /// Brings a card back in from the side it left (after undo).
  Future<void> flyIn(Decision from) async {
    if (_size == Size.zero) return;
    _busy = true;
    _resetCard();
    final start = _offscreen(from, Offset.zero);
    await _animateDrag(start, Offset.zero, const Duration(milliseconds: 320), Curves.easeOutCubic);
    _busy = false;
  }

  /// Zoom in or out (keyboard and toolbar).
  void toggleZoom() {
    if (_zoom > 1.01) {
      _resetZoom();
    } else {
      _animateZoom(2.5, Offset.zero);
    }
  }

  // ------------------------------------------------------------ animation

  Offset _offscreen(Decision d, Offset velocity) {
    final w = _size.width, h = _size.height;
    switch (d) {
      case Decision.keep:
        return Offset(w * 1.5, _drag.dy + velocity.dy * 0.08);
      case Decision.reject:
        return Offset(-w * 1.5, _drag.dy + velocity.dy * 0.08);
      case Decision.superLike:
        return Offset(_drag.dx + velocity.dx * 0.05, -h * 1.4);
    }
  }

  Future<void> _animateDrag(Offset from, Offset to, Duration duration, Curve curve) async {
    _move.stop();
    _move.duration = duration;
    _moveAnim = Tween(begin: from, end: to).animate(CurvedAnimation(parent: _move, curve: curve));
    _move.value = 0;
    await _move.forward().orCancel.catchError((_) {});
  }

  Future<void> _flyOut(Decision d, {required Offset velocity}) async {
    final item = widget.items.first;
    _busy = true;
    _haptic(d == Decision.superLike ? HapticFeedback.heavyImpact : HapticFeedback.lightImpact);
    final speed = velocity.distance;
    final ms = speed > 1500 ? 180 : 260;
    await _animateDrag(_drag, _offscreen(d, velocity), Duration(milliseconds: ms), Curves.easeOut);
    if (!mounted) return;
    setState(_resetCard);
    _busy = false;
    widget.onDecide(item, d);
  }

  void _snapBack() {
    _animateDrag(_drag, Offset.zero, const Duration(milliseconds: 380), Curves.elasticOut);
  }

  void _animateZoom(double zoom, Offset pan) {
    _zoomAnim = Tween(begin: _zoom, end: zoom).animate(CurvedAnimation(parent: _zoomCtl, curve: Curves.easeOutCubic));
    _panAnim = Tween(begin: _pan, end: pan).animate(CurvedAnimation(parent: _zoomCtl, curve: Curves.easeOutCubic));
    _zoomCtl.forward(from: 0);
  }

  void _resetZoom({bool animated = true}) {
    if (animated) {
      _animateZoom(1, Offset.zero);
    } else {
      setState(() {
        _zoom = 1;
        _pan = Offset.zero;
      });
    }
  }

  Offset _clampPan(Offset pan, double zoom) {
    final maxX = (zoom - 1) * _size.width / 2;
    final maxY = (zoom - 1) * _size.height / 2;
    return Offset(pan.dx.clamp(-maxX, maxX), pan.dy.clamp(-maxY, maxY));
  }

  // ------------------------------------------------------------ gestures

  Decision? _decisionFor(Offset drag, Offset velocity) {
    final w = _size.width, h = _size.height;
    if (_canSuper &&
        -drag.dy > drag.dx.abs() &&
        (-drag.dy > h * 0.2 || (velocity.dy < -1000 && -drag.dy > 30))) {
      return Decision.superLike;
    }
    if (drag.dx > w * 0.28 || (velocity.dx > 900 && drag.dx > 24)) return Decision.keep;
    if (drag.dx < -w * 0.28 || (velocity.dx < -900 && drag.dx < -24)) return Decision.reject;
    return null;
  }

  void _onScaleStart(ScaleStartDetails d) {
    if (_busy) return;
    _move.stop();
    _zoomCtl.stop();
    _zoomAtStart = _zoom;
    _gestureIsZoom = d.pointerCount > 1 || _zoom > 1.01;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_busy) return;
    if (d.pointerCount > 1 && !_gestureIsZoom) {
      _gestureIsZoom = true;
      _zoomAtStart = _zoom;
      if (_drag != Offset.zero) _snapBack();
    }
    if (_gestureIsZoom) {
      final zoom = (_zoomAtStart * d.scale).clamp(1.0, 8.0);
      setState(() {
        _zoom = zoom;
        _pan = _clampPan(_pan + d.focalPointDelta, zoom);
      });
      return;
    }
    setState(() => _drag += d.focalPointDelta);
    final armed = _decisionFor(_drag, Offset.zero);
    if (armed != _armed) {
      if (armed != null) _haptic(HapticFeedback.selectionClick);
      _armed = armed;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_busy) return;
    if (_gestureIsZoom) {
      _gestureIsZoom = false;
      if (_zoom < 1.05) _resetZoom();
      return;
    }
    final v = d.velocity.pixelsPerSecond;
    final decision = _decisionFor(_drag, v);
    _armed = null;
    if (decision != null) {
      _flyOut(decision, velocity: v);
    } else {
      _snapBack();
    }
  }

  void _onDoubleTapDown(TapDownDetails d) => _doubleTapAt = d.localPosition;
  Offset _doubleTapAt = Offset.zero;

  void _onDoubleTap() {
    if (_busy) return;
    if (_zoom > 1.01) {
      _resetZoom();
    } else {
      const z = 2.5;
      final center = _size.center(Offset.zero);
      final pan = _clampPan((center - _doubleTapAt) * (z - 1), z);
      _animateZoom(z, pan);
    }
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || _busy) return;
    final zoom = (_zoom * math.pow(2, -e.scrollDelta.dy / 300)).clamp(1.0, 8.0).toDouble();
    setState(() {
      _zoom = zoom;
      _pan = zoom <= 1.0 ? Offset.zero : _clampPan(_pan, zoom);
    });
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final px = _displayPixels;
    // Decode the next images early so the next card is ready at once.
    for (final next in items.skip(1).take(3)) {
      precacheImage(ItemImage(widget.library, next, px), context, onError: (_, _) {});
    }

    return LayoutBuilder(builder: (context, c) {
      _size = c.biggest;
      final w = _size.width;
      final progress = (_drag.distance / (w * 0.35)).clamp(0.0, 1.0);
      final angle = (_drag.dx / w) * 0.32;
      final superT = _canSuper && -_drag.dy > _drag.dx.abs()
          ? (-_drag.dy / (_size.height * 0.2)).clamp(0.0, 1.0)
          : 0.0;
      final keepT = superT > 0 ? 0.0 : (_drag.dx / (w * 0.28)).clamp(0.0, 1.0);
      final nopeT = superT > 0 ? 0.0 : (-_drag.dx / (w * 0.28)).clamp(0.0, 1.0);

      return Stack(
        clipBehavior: Clip.none,
        children: [
          if (items.length > 1)
            Positioned.fill(
              child: Transform.scale(
                scale: 0.93 + 0.07 * progress,
                child: _CardFrame(
                  radius: widget.borderRadius,
                  child: CardImage(
                    key: ValueKey('card-${items[1].id}'),
                    library: widget.library,
                    item: items[1],
                    displayPixels: px,
                    settings: widget.settings,
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: Transform.translate(
              offset: _drag,
              child: Transform.rotate(
                angle: angle,
                alignment: const Alignment(0, 1.6),
                child: Listener(
                  onPointerSignal: _onPointerSignal,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    onDoubleTapDown: _onDoubleTapDown,
                    onDoubleTap: _onDoubleTap,
                    onTap: widget.onTap,
                    onLongPressStart: (_) {
                      if (_drag == Offset.zero && _zoom <= 1.01) setState(() => _showWhole = true);
                    },
                    onLongPressEnd: (_) => setState(() => _showWhole = false),
                    child: _CardFrame(
                      radius: widget.borderRadius,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CardImage(
                            key: ValueKey('card-${items[0].id}'),
                            library: widget.library,
                            item: items[0],
                            displayPixels: px,
                            settings: widget.settings,
                            zoom: _zoom,
                            pan: _pan,
                            showWhole: _showWhole,
                          ),
                          _Stamp(
                            label: 'KEEP',
                            color: Palette.keep,
                            opacity: keepT,
                            angle: -0.26,
                            alignment: const Alignment(-0.82, -0.8),
                          ),
                          _Stamp(
                            label: 'NOPE',
                            color: Palette.nope,
                            opacity: nopeT,
                            angle: 0.26,
                            alignment: const Alignment(0.82, -0.8),
                          ),
                          if (_canSuper)
                            _Stamp(
                              label: 'SUPER LIKE',
                              color: Palette.superLike,
                              opacity: superT,
                              angle: -0.12,
                              alignment: const Alignment(0, 0.65),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child, required this.radius});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: radius == 0
            ? null
            : [BoxShadow(color: p.cardShadow, blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({
    required this.label,
    required this.color,
    required this.opacity,
    required this.angle,
    required this.alignment,
  });

  final String label;
  final Color color;
  final double opacity;
  final double angle;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (opacity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: angle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.18),
                border: Border.all(color: color, width: 4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
