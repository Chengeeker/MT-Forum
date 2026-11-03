import 'dart:async';

import 'package:flutter/gestures.dart' show kTouchSlop, VelocityTracker;
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../utils/haptic_feedback_util.dart';

// Review's liquid navigation, adapted only for MT's width and destinations.
class ReviewLiquidNavigationBar extends StatefulWidget {
  const ReviewLiquidNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.hasBottomInset,
    required this.width,
    required this.tabs,
  });

  static LiquidGlassSettings liquidGlassSettingsFor(
    BuildContext context, [
    LiquidGlassSettings? settings,
  ]) {
    final base = settings ?? liquidGlassSettings;
    return Theme.of(context).brightness == Brightness.light
        ? base.copyWith(glassColor: const Color(0xF0FFFFFF), rimLight: 1)
        : base;
  }

  static const liquidGlassSettings = LiquidGlassSettings(
    glassColor: Color(0x66000000),
    bodyMode: GlassBodyMode.clear,
    thickness: 10,
    blur: 2.0,
    lightIntensity: 0.25,
    ambientStrength: 0,
    refractiveIndex: 1.19,
    chromaticAberration: 0.008,
    shadowElevation: 0,
  );
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool hasBottomInset;
  final double width;
  final List<GlassTab> tabs;

  @override
  State<ReviewLiquidNavigationBar> createState() =>
      _ReviewLiquidNavigationBarState();
}

class _ReviewLiquidNavigationBarState extends State<ReviewLiquidNavigationBar> {
  static const _longPressThreshold = Duration(milliseconds: 220);
  static const _flickVelocityThreshold = 1000.0;

  int? _activePointer;
  VelocityTracker? _velocityTracker;
  Duration? _pointerDownAt;
  Offset? _pointerDownPosition;
  Timer? _longPressTimer;
  bool _isJellyDragging = false;
  bool _longPressTriggered = false;
  int _selectedIndexAtPointerDown = 0;
  int? _pendingIndex;
  bool _movedBeyondSlop = false;
  bool _draggedHorizontally = false;
  bool _cancelled = false;
  int _gestureId = 0;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    _pointerDownAt = event.timeStamp;
    _pointerDownPosition = event.position;
    _longPressTriggered = false;
    _selectedIndexAtPointerDown = widget.selectedIndex;
    _pendingIndex = null;
    _movedBeyondSlop = false;
    _draggedHorizontally = false;
    _cancelled = false;
    _gestureId++;

    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressThreshold, () {
      if (!mounted || _activePointer != event.pointer) return;
      _longPressTriggered = true;
      setState(() {
        _isJellyDragging = true;
      });
      HapticFeedbackUtil.light();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    final delta = event.position - _pointerDownPosition!;
    if (delta.distance > kTouchSlop) {
      _movedBeyondSlop = true;
      if (delta.dx.abs() > delta.dy.abs()) {
        _draggedHorizontally = true;
        if (!_isJellyDragging) {
          _longPressTimer?.cancel();
          setState(() {
            _isJellyDragging = true;
          });
        }
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) => _finishPointer(
    event.pointer,
    event.timeStamp,
    horizontalVelocity: _velocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0,
  );

  void _onPointerCancel(PointerCancelEvent event) =>
      _finishPointer(event.pointer, event.timeStamp, cancelled: true);

  void _finishPointer(
    int pointer,
    Duration releasedAt, {
    bool cancelled = false,
    double horizontalVelocity = 0,
  }) {
    if (pointer != _activePointer) return;
    _longPressTimer?.cancel();
    _cancelled |= cancelled;
    final gestureId = _gestureId;
    final wasJelly = _isJellyDragging;
    final longPressTriggered = _longPressTriggered;

    scheduleMicrotask(() {
      if (!mounted || gestureId != _gestureId) return;

      final target = _pendingIndex;
      final wasLongPress =
          longPressTriggered ||
          releasedAt - _pointerDownAt! >= _longPressThreshold;
      final wasDrag = _draggedHorizontally;
      final movedVertically = _movedBeyondSlop && !wasDrag;
      final wasCancelled = _cancelled;
      final startingIndex = _selectedIndexAtPointerDown;

      _activePointer = null;
      _velocityTracker = null;
      _pointerDownAt = null;
      _pointerDownPosition = null;
      _pendingIndex = null;
      _movedBeyondSlop = false;
      _draggedHorizontally = false;
      _cancelled = false;

      if (wasJelly) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) {
            setState(() => _isJellyDragging = false);
          }
        });
      }

      if (wasCancelled || movedVertically || target == null) return;

      final isFastFlick =
          wasDrag && horizontalVelocity.abs() >= _flickVelocityThreshold;
      final selectedTarget = isFastFlick
          ? target.clamp(startingIndex - 1, startingIndex + 1).toInt()
          : target;
      if ((wasDrag || wasLongPress) && selectedTarget == startingIndex) return;
      _select(selectedTarget);
    });
  }

  void _onTabSelected(int index) {
    if (_activePointer != null) {
      _pendingIndex = index;
    } else {
      _select(index);
    }
  }

  void _select(int index) {
    HapticFeedbackUtil.light();
    widget.onSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLightMode = theme.brightness == Brightness.light;
    final glassSettings = ReviewLiquidNavigationBar.liquidGlassSettingsFor(
      context,
    ).copyWith(shadowElevation: isLightMode ? 0.55 : 0);
    final selectedContentColor = theme.colorScheme.primary;
    final unselectedContentColor = isLightMode
        ? theme.colorScheme.onSurfaceVariant
        : Colors.white;

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: widget.hasBottomInset ? 6 : 14),
          child: RepaintBoundary(
            child: SizedBox(
              width: widget.width,
              height: 56,
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: Stack(
                  children: [
                    GlassTabBar.bottom(
                      tabs: widget.tabs,
                      selectedIndex: widget.selectedIndex,
                      onTabSelected: _onTabSelected,
                      barHeight: 56,
                      horizontalPadding: 0,
                      verticalPadding: 0,
                      barBorderRadius: 9999,
                      indicatorBorderRadius: 9999,
                      settings: glassSettings,
                      indicatorSettings: LiquidGlassSettings(
                        glassColor: isLightMode
                            ? const Color(0x18000000)
                            : const Color(0x26FFFFFF),
                        bodyMode: GlassBodyMode.clear,
                        refractiveIndex: 1.18,
                        chromaticAberration: 0.025,
                        rimShade: isLightMode ? 0.12 : 0,
                        rimLight: isLightMode ? 0.35 : 0,
                      ),
                      quality: GlassQuality.premium,
                      backgroundQuality: GlassQuality.premium,
                      maskingQuality: MaskingQuality.high,
                      enableBlend: true,
                      indicatorColor: isLightMode
                          ? const Color(0x26000000)
                          : const Color(0x26FFFFFF),
                      interactionGlowColor: const Color(0x20FFFFFF),
                      indicatorPinchStrength: _isJellyDragging ? 0.7 : 0.0,
                      indicatorExpansion: _isJellyDragging
                          ? const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            )
                          : EdgeInsets.zero,
                      innerBlur: 6,
                      pressScale: 1.06,
                      selectedIconColor: selectedContentColor,
                      selectedLabelColor: selectedContentColor,
                      unselectedIconColor: unselectedContentColor,
                      unselectedLabelColor: unselectedContentColor,
                    ),
                    if (isLightMode)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            key: const ValueKey('liquid-glass-light-rim'),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9999),
                              border: Border.all(
                                color: const Color(0xF5FFFFFF),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
