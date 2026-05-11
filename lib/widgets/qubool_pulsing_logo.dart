import 'package:flutter/material.dart';

class QuboolPulsingLogo extends StatefulWidget {
  final String assetPath;
  final double? width;
  final double minScale;
  final double maxScale;
  final Duration duration;

  const QuboolPulsingLogo({
    super.key,
    required this.assetPath,
    this.width,
    this.minScale = 0.998,
    this.maxScale = 1.002,
    this.duration = const Duration(milliseconds: 2200),
  });

  @override
  State<QuboolPulsingLogo> createState() => _QuboolPulsingLogoState();
}

class _QuboolPulsingLogoState extends State<QuboolPulsingLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween(begin: widget.minScale, end: widget.maxScale).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _anim,
      child: Image.asset(
        widget.assetPath,
        width: widget.width,
        fit: BoxFit.contain,
      ),
    );
  }
}
