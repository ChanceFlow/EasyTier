import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';

/// Staggered entrance: fades and lifts [child] from a small offset over the
/// slice of [animation] described by [interval]. Used to choreograph the hero
/// and full-page transitions without a package.
class EtEnter extends StatelessWidget {
  const EtEnter({
    super.key,
    required this.animation,
    required this.child,
    this.interval = const Interval(0, 1, curve: EtCurves.enter),
    this.offset = 10,
  });

  final Animation<double> animation;
  final Widget child;
  final Interval interval;

  /// Vertical travel in logical pixels (positive = rises into place).
  final double offset;

  @override
  Widget build(BuildContext context) {
    if (context.etReducedMotion) return child;
    final curved = CurvedAnimation(parent: animation, curve: interval);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0, offset / 100),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Press feedback for large tappable surfaces: a 2% inward scale on pointer
/// down, sprung back on release. Purely tactile polish; semantics unchanged.
class EtPressScale extends StatefulWidget {
  const EtPressScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<EtPressScale> createState() => _EtPressScaleState();
}

class _EtPressScaleState extends State<EtPressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || context.etReducedMotion) return widget.child;
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: EtCurves.exit,
        child: widget.child,
      ),
    );
  }
}

/// Haptics with a guard: widget tests and desktop have no vibrator, and a
/// missing platform channel must never bubble into the UI.
abstract final class EtHaptics {
  static void selection() {
    try {
      HapticFeedback.selectionClick();
    } catch (_) {
      // No haptic engine (tests, desktop): ignore.
    }
  }

  static void impact() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {
      // No haptic engine (tests, desktop): ignore.
    }
  }
}
