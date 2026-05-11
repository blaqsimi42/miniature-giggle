import 'package:flutter/material.dart';
import '../widgets/presence_avatar.dart';

class ProfileHeader extends StatelessWidget {
  final String? userId;
  final String displayName;
  final String subtitle;
  final String? imageUrl;
  final ImageProvider? imageProvider;
  final bool hasPhoto;
  final bool processingPhoto;
  final bool savingProfile;
  final bool isVerified;
  final bool isPremium;
  final int? age;
  final String? heightLabel;
  final List<String> hobbies;
  final VoidCallback onPickPhoto;
  final VoidCallback onRemovePhoto;

  const ProfileHeader({
    super.key,
    required this.userId,
    required this.displayName,
    required this.subtitle,
    required this.imageUrl,
    required this.imageProvider,
    required this.hasPhoto,
    required this.processingPhoto,
    required this.savingProfile,
    required this.isVerified,
    required this.isPremium,
    required this.age,
    required this.heightLabel,
    required this.hobbies,
    required this.onPickPhoto,
    required this.onRemovePhoto,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PresenceAvatar(
              userId: userId,
              name: displayName,
              imageUrl: imageUrl,
              imageProvider: imageProvider,
              radius: 30,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (isVerified) const Chip(label: Text('Verified')),
                      if (isPremium) const Chip(label: Text('Premium')),
                      if (age != null) Chip(label: Text('Age $age')),
                      if (heightLabel != null) Chip(label: Text(heightLabel!)),
                      Chip(label: Text(hobbies.isNotEmpty ? hobbies.first : 'Location pending')),
                    ],
                  ),
                  if (hobbies.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Interests', style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: hobbies.map((h) => Chip(label: Text(h))).toList()),
                  ],
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: processingPhoto || savingProfile ? null : onPickPhoto,
                      icon: processingPhoto
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.photo_camera_back),
                      label: const Text('Upload photo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: (!hasPhoto || savingProfile) ? null : onRemovePhoto,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove photo'),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
