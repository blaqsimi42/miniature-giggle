import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? labelText;
  final IconData? icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final String? hintText;
  final int? maxLines;
  final ValueChanged<String>? onChanged;

  const CustomTextField({
    required this.controller,
    this.labelText,
    this.icon,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
    this.hintText,
    this.maxLines,
    this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLines: maxLines ?? 1,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, height: 1.3),
      decoration: InputDecoration(
        prefixIcon: icon != null ? Icon(icon, color: Colors.black54, size: 20) : null,
        labelText: labelText,
        hintText: hintText,
        labelStyle: const TextStyle(fontSize: 13, color: Colors.black54),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 12,
        ),
      ),
    );
  }
}
