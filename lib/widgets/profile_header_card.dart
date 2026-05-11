import 'package:flutter/material.dart';

const Color _creamBg = Color(0xFFF7F5F2);

class ProfileHeaderCard extends StatelessWidget {
  final String? imageUrl;
  final ImageProvider? imageProvider;
  final String displayName;
  final String subtitle;
  final int completionPercent;
  final VoidCallback? onEdit;
  final VoidCallback? onTapAvatar;
  final IconData? editIcon;

  const ProfileHeaderCard({
    super.key,
    this.imageUrl,
    this.imageProvider,
    required this.displayName,
    required this.subtitle,
    required this.completionPercent,
    this.onEdit,
    this.onTapAvatar,
    this.editIcon,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final avatarBg = primary.withAlpha((0.08 * 255).round());
    final progressColor = primary;
    final trimmedUrl = imageUrl?.trim();
    final normalizedImageProvider = imageProvider ?? (trimmedUrl != null && trimmedUrl.isNotEmpty ? NetworkImage(trimmedUrl) : null);
    // Debug: surface the normalized URL to help trace missing-avatar issues
    final normalizedPresent = trimmedUrl != null && trimmedUrl.isNotEmpty;
    if (trimmedUrl != null) {
      // ignore: avoid_print
      debugPrint('[ProfileHeaderCard] imageUrl raw="$imageUrl" trimmed="$trimmedUrl" normalizedPresent=$normalizedPresent');
    }
    return Card(
      color: _creamBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: onTapAvatar,
                  child: CircleAvatar(
                    radius: 36,
                    backgroundImage: normalizedImageProvider,
                    backgroundColor: avatarBg,
                    child: (imageUrl == null && imageProvider == null)
                        ? Text(displayName.isNotEmpty ? displayName[0] : 'U', style: const TextStyle(color: Colors.white))
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A))),
                      const SizedBox(height: 4),
                      Text(subtitle, style: const TextStyle(color: Color(0xFF6B6B6B))),
                    ],
                  ),
                ),
                if (onEdit != null)
                  FilledButton(
                    onPressed: onEdit,
                    style: FilledButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    child: editIcon != null
                        ? Icon(editIcon, size: 20)
                        : const Text('Edit'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Profile Completion', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
              ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LinearProgressIndicator(
                value: completionPercent / 100.0,
                minHeight: 10,
                color: progressColor,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text('$completionPercent% complete', style: const TextStyle(color: Color(0xFF6B6B6B))),
          ],
        ),
      ),
    );
  }
}
