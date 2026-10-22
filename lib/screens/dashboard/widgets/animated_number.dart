import 'package:flutter/material.dart';

import '../../../core/theme/theme_x.dart';

/// A figure that counts to its new value when it changes — and up from zero
/// the first time [countUpId] is shown this session. Without movement in the
/// motion setting it simply shows the value.
class AnimatedNumber extends StatefulWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.countUpId,
    this.maxLines = 1,
  });

  final double value;
  final String Function(double value) format;
  final TextStyle? style;
  final String? countUpId;
  final int maxLines;

  static final Set<String> _counted = {};

  @visibleForTesting
  static void reset() => _counted.clear();

  @override
  State<AnimatedNumber> createState() => _AnimatedNumberState();
}

class _AnimatedNumberState extends State<AnimatedNumber> {
  late final double _begin;

  @override
  void initState() {
    super.initState();
    final id = widget.countUpId;
    _begin = id != null && AnimatedNumber._counted.add(id) ? 0 : widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    final text = widget.format(widget.value);
    final style = (widget.style ?? const TextStyle())
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    // No margin without revenue: nothing to count to.
    if (!widget.value.isFinite) {
      return Text(text,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
          style: style);
    }
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: motion.allowsMovement ? _begin : widget.value,
            end: widget.value),
        duration: motion.allowsMovement
            ? const Duration(milliseconds: 900)
            : Duration.zero,
        curve: AppMotion.emphasized,
        builder: (context, v, _) => Text(
          // Land on the exact text, not a rounding of the animated double.
          v == widget.value ? text : widget.format(v),
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}
