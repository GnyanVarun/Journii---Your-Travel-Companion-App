import 'package:flutter/material.dart';

class JourniiShimmer extends StatefulWidget {
  final BorderRadiusGeometry? borderRadius;
  const JourniiShimmer({super.key, this.borderRadius});

  @override
  State<JourniiShimmer> createState() => _JourniiShimmerState();
}

class _JourniiShimmerState extends State<JourniiShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // Creates a smooth 1.5 second looping animation
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
    _animation = Tween<double>(begin: -2.0, end: 2.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Adapts the shimmer colors perfectly to your app's theme
    final baseColor = isDark ? Colors.grey.shade900 : Colors.grey.shade200;
    final highlightColor = isDark ? Colors.grey.shade800 : Colors.grey.shade50;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.5, 1.0],
              colors: [baseColor, highlightColor, baseColor],
              transform: _SlidingGradientTransform(slidePercent: _animation.value),
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}