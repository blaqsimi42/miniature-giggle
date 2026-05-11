import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? elevation;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.elevation});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: elevation ?? 6,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.cardRadius)),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}
