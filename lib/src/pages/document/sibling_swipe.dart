import 'package:flutter/material.dart';

/// Widget that detects horizontal swipes to navigate between sibling files
/// and left edge swipes to open the drawer.
///
/// Uses Listener for raw pointer events that don't compete in the gesture arena.
///
/// Requires TWO swipes in the same direction to navigate:
/// - First swipe: Allows TODO cycle to open (no navigation)
/// - Second swipe (within 2 seconds): Triggers navigation
///
/// Special case: Swipe from left edge (within 60px) opens the drawer.
class SiblingSwipeDetector extends StatefulWidget {
  const SiblingSwipeDetector({
    required this.child,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    this.onOpenDrawer,
    this.onAtStart,
    this.onAtEnd,
    this.canSwipeLeft = true,
    this.canSwipeRight = true,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;
  final VoidCallback? onOpenDrawer;
  final VoidCallback? onAtStart;
  final VoidCallback? onAtEnd;
  final bool canSwipeLeft;
  final bool canSwipeRight;
  final bool enabled;

  /// Reset the swipe tracking state. Call this when a Slidable opens
  /// to prevent the next swipe from being treated as a "second swipe".
  static void resetTracking() {
    debugPrint('Sibling swipe: Resetting tracking (Slidable opened)');
    _SiblingSwipeDetectorState._lastSwipeTime = null;
    _SiblingSwipeDetectorState._lastSwipeWasLeft = null;
  }

  @override
  State<SiblingSwipeDetector> createState() => _SiblingSwipeDetectorState();
}

class _SiblingSwipeDetectorState extends State<SiblingSwipeDetector> {
  // Minimum horizontal distance to trigger sibling navigation
  static const _minDragDistance = 30.0;
  // Maximum vertical distance before cancelling (prevents scroll confusion)
  static const _maxVerticalDistance = 60.0;
  // Time window for second swipe to trigger navigation
  static const _doubleSwipeWindow = Duration(seconds: 3);
  // Left edge width for drawer trigger
  static const _leftEdgeWidth = 60.0;

  double? _startX;
  double? _startY;
  double _currentX = 0;
  bool _isTracking = false;
  bool _isFromLeftEdge = false;

  // Track last swipe for double-swipe detection (static to persist across rebuilds)
  static DateTime? _lastSwipeTime;
  static bool? _lastSwipeWasLeft; // true = left (next), false = right (previous)

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _reset,
      child: widget.child,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enabled) return;
    _startX = event.position.dx;
    _startY = event.position.dy;
    _currentX = _startX!;
    _isTracking = true;
    _isFromLeftEdge = _startX! < _leftEdgeWidth;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_isTracking || _startX == null || _startY == null) return;

    _currentX = event.position.dx;

    // Cancel if too much vertical movement (user is scrolling)
    final verticalDelta = (event.position.dy - _startY!).abs();
    if (verticalDelta > _maxVerticalDistance) {
      _reset(event);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_isTracking || _startX == null) {
      _reset(event);
      return;
    }

    final dragDistance = _currentX - _startX!;
    final now = DateTime.now();

    // Check for left edge swipe to open drawer
    if (_isFromLeftEdge && dragDistance > _minDragDistance && widget.onOpenDrawer != null) {
      debugPrint('Sibling swipe: Opening drawer from left edge');
      widget.onOpenDrawer!();
      _reset(event);
      return;
    }

    // Determine swipe direction based on drag distance
    bool? currentSwipeIsLeft;
    bool hitBoundary = false;

    if (dragDistance < -_minDragDistance) {
      // Swiped left → next file
      if (widget.canSwipeLeft) {
        currentSwipeIsLeft = true;
      } else {
        hitBoundary = true;
        widget.onAtEnd?.call();
      }
    } else if (dragDistance > _minDragDistance) {
      // Swiped right → previous file
      if (widget.canSwipeRight) {
        currentSwipeIsLeft = false;
      } else {
        hitBoundary = true;
        widget.onAtStart?.call();
      }
    }

    if (hitBoundary) {
      // Reset swipe tracking when hitting boundary
      _lastSwipeTime = null;
      _lastSwipeWasLeft = null;
      _reset(event);
      return;
    }

    if (currentSwipeIsLeft != null) {
      // Check if this is a second swipe in the same direction within the window
      final isSecondSwipe = _lastSwipeTime != null &&
          _lastSwipeWasLeft == currentSwipeIsLeft &&
          now.difference(_lastSwipeTime!) < _doubleSwipeWindow;

      debugPrint('Sibling swipe: direction=${currentSwipeIsLeft ? "LEFT/NEXT" : "RIGHT/PREV"}, '
          'distance=${dragDistance.abs().toStringAsFixed(0)}, isSecondSwipe=$isSecondSwipe');

      if (isSecondSwipe) {
        // Second swipe - navigate!
        debugPrint('Sibling swipe: NAVIGATING');
        if (currentSwipeIsLeft) {
          widget.onSwipeLeft();
        } else {
          widget.onSwipeRight();
        }
        // Reset swipe tracking after navigation
        _lastSwipeTime = null;
        _lastSwipeWasLeft = null;
      } else {
        // First swipe - record it, let TODO cycle handle
        debugPrint('Sibling swipe: First swipe recorded, waiting for second');
        _lastSwipeTime = now;
        _lastSwipeWasLeft = currentSwipeIsLeft;
      }
    }

    _reset(event);
  }

  void _reset(PointerEvent? event) {
    _startX = null;
    _startY = null;
    _currentX = 0;
    _isTracking = false;
    _isFromLeftEdge = false;
  }
}
