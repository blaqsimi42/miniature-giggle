import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  static TextStyle heading({Color? color}) => TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary);
  static TextStyle title2({Color? color}) => TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color ?? AppColors.textPrimary);
  static TextStyle body({Color? color}) => TextStyle(fontSize: 14, color: color ?? AppColors.textPrimary);
  static TextStyle caption({Color? color}) => TextStyle(fontSize: 12, color: color ?? AppColors.textSecondary);
}
