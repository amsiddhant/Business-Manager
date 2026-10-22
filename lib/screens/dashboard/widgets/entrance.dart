import 'package:flutter/material.dart';

import '../../../core/theme/theme_x.dart';

/// Fades (and, with full motion, lifts) [child] in the first time [id]
/// appears this session, [index] steps after the first item. Coming back to
/// the dashboard later shows it at once.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.id,
    required this.child,
    this.index = 0,
  });

  final String id;
  final int index;
  final Widget child;

  static final Set<String> _shown = {};

  @visibleForTesting
  static void reset() => _shown.clear();

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _lift = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null || !Entrance._shown.add(widget.id)) return;
    final motion = context.motion;
    if (!motion.enabled) return;
    _lift = motion.allowsMovement;
    final controller = AnimationController(
        vsync: this,
        duration: motion.allowsMovement ? motion.slow * 1.5 : motion.base);
    _controller = controller;
    final delay = motion.stagger * widget.index.clamp(0, 12);
    if (delay == Duration.zero) {
      controller.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    final curved =
        CurvedAnimation(parent: controller, curve: AppMotion.emphasized);
    return FadeTransition(
      opacity: curved,
      child: _lift
          ? SlideTransition(
              position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                  .animate(curved),
              child: widget.child,
            )
          : widget.child,
    );
  }
}
