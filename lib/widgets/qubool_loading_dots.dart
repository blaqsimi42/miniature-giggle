import 'package:flutter/material.dart';

class QuboolLoadingDots extends StatefulWidget {
  final double? dotSize;
  final Color deepGreen;
  final Color gold;
  const QuboolLoadingDots({
    super.key,
    this.dotSize,
    this.deepGreen = const Color(0xFF004B2F),
    this.gold = const Color(0xFFC9961A),
  });

  @override
  State<QuboolLoadingDots> createState() => _QuboolLoadingDotsState();
}

class _QuboolLoadingDotsState extends State<QuboolLoadingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildDot(Animation<double> scaleAnim, Animation<double> liftAnim, Color color, double size) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, liftAnim.value),
          child: Transform.scale(
            scale: scaleAnim.value,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.94),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.34),
                    blurRadius: size * 0.9,
                    spreadRadius: size * 0.12,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final size = widget.dotSize ?? (screenW * 0.048).clamp(8.0, 18.0);

    final a1 = Tween(begin: 0.7, end: 1.28).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack)),
    );
    final a2 = Tween(begin: 0.7, end: 1.28).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.18, 0.68, curve: Curves.easeOutBack)),
    );
    final a3 = Tween(begin: 0.7, end: 1.28).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.36, 0.86, curve: Curves.easeOutBack)),
    );
    final y1 = Tween(begin: 0.0, end: -size * 0.42).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeInOut)),
    );
    final y2 = Tween(begin: 0.0, end: -size * 0.42).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.18, 0.68, curve: Curves.easeInOut)),
    );
    final y3 = Tween(begin: 0.0, end: -size * 0.42).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.36, 0.86, curve: Curves.easeInOut)),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDot(a1, y1, widget.deepGreen, size),
        SizedBox(width: size * 1.1),
        _buildDot(a2, y2, widget.gold, size),
        SizedBox(width: size * 1.1),
        _buildDot(a3, y3, widget.deepGreen, size),
      ],
    );
  }
}
