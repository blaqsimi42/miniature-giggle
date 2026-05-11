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

  Widget _buildDot(Animation<double> anim, Color color, double size) {
    return ScaleTransition(
      scale: anim,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final size = widget.dotSize ?? (screenW * 0.048).clamp(8.0, 18.0);

    final a1 = Tween(begin: 0.7, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeInOut)));
    final a2 = Tween(begin: 0.7, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.2, 0.8, curve: Curves.easeInOut)));
    final a3 = Tween(begin: 0.7, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0, curve: Curves.easeInOut)));

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDot(a1, widget.deepGreen, size),
        SizedBox(width: size * 0.9),
        _buildDot(a2, widget.gold, size),
        SizedBox(width: size * 0.9),
        _buildDot(a3, widget.deepGreen, size),
      ],
    );
  }
}
