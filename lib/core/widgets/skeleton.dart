import 'package:flutter/material.dart';
import '../theme/colors.dart';

class Shimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const Shimmer({super.key, required this.child, this.enabled = true});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        final c = context.cBgElevated;
        final shimmer = Color.lerp(c, Colors.white.withValues(alpha: 0.05),
            0.5 + 0.5 * (_controller.value * 2 - 1).abs())!;
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [c, shimmer, c],
            stops: const [0.0, 0.5, 1.0],
            begin: Alignment(-1 + _controller.value * 2, 0),
            end: Alignment(1 + _controller.value * 2, 0),
          ).createShader(bounds),
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class SkeletonBlock extends StatelessWidget {
  final double width, height;
  final double borderRadius;
  const SkeletonBlock({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.cBgElevated,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class SkeletonCircle extends StatelessWidget {
  final double size;
  const SkeletonCircle({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: context.cBgElevated,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class SkeletonText extends StatelessWidget {
  final double width, height;
  const SkeletonText({super.key, this.width = 120, this.height = 12});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.cBgElevated,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
