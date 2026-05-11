import 'package:flutter/material.dart';

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const SettingsTile({super.key, required this.icon, required this.title, this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF0F5C2E);
    final bg = primary.withAlpha((0.08 * 255).round());
    return ListTile(
      leading: CircleAvatar(radius: 20, backgroundColor: bg, child: Icon(icon, color: primary)),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF171717),
        ),
      ),
      subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(color: Color(0xFF6B6B6B))) : null,
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF6B7280)),
      onTap: onTap,
    );
  }
}
