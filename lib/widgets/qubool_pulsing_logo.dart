import 'package:flutter/material.dart';

class QuboolPulsingLogo extends StatefulWidget {
  final String assetPath;
  final double? width;
  final double minScale;
  final double maxScale;
  final Duration duration;
  final double glowBlur;
  final double glowSpread;
  final Color glowColor;

  const QuboolPulsingLogo({
    super.key,
    required this.assetPath,
    this.width,
    this.minScale = 0.94,
    this.maxScale = 1.04,
    this.duration = const Duration(milliseconds: 1500),
    this.glowBlur = 28,
    this.glowSpread = 3,
    this.glowColor = const Color(0x66FFFFFF),
  });

  @override
  State<QuboolPulsingLogo> createState() => _QuboolPulsingLogoState();
}

class _QuboolPulsingLogoState extends State<QuboolPulsingLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _anim = Tween(begin: widget.minScale, end: widget.maxScale).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _glowAnim = Tween(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _anim.value,
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: widget.glowColor.withValues(alpha: _glowAnim.value * 0.7),
                  blurRadius: widget.glowBlur * _glowAnim.value,
                  spreadRadius: widget.glowSpread * _glowAnim.value,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Image.asset(
        widget.assetPath,
        width: widget.width,
        fit: BoxFit.contain,
      ),
    );
  }
}
