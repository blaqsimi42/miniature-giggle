import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PresenceAvatar extends StatelessWidget {
  final String? userId;
  final String name;
  final String? imageUrl;
  final ImageProvider<Object>? imageProvider;
  final double radius;
  final bool showOnlineIndicator;

  const PresenceAvatar({
    super.key,
    this.userId,
    required this.name,
    this.imageUrl,
    this.imageProvider,
    this.radius = 20,
    this.showOnlineIndicator = true,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = imageUrl?.trim();
    if (imageUrl != null) {
      // ignore: avoid_print
      debugPrint('[PresenceAvatar] id=${userId ?? 'anon'} rawUrl="$imageUrl" normalizedPresent=${normalizedUrl?.isNotEmpty}');
    }
    final effectiveImageProvider =
        imageProvider ??
        ((normalizedUrl != null && normalizedUrl.isNotEmpty)
            ? NetworkImage(normalizedUrl)
            : null);

    final avatar = CircleAvatar(
      radius: radius,
      backgroundImage: effectiveImageProvider,
      child: effectiveImageProvider == null
          ? Text(name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?')
          : null,
    );

    if (kIsWeb || !showOnlineIndicator || userId == null || userId!.trim().isEmpty) {
      return avatar;
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final isOnlineFlag = data?['isOnline'] as bool? ?? false;
        final lastSeenAt = data?['lastSeenAt'] as Timestamp?;
        final isRecentlyActive =
            lastSeenAt != null &&
            DateTime.now().difference(lastSeenAt.toDate()) <
                const Duration(minutes: 2);
        final isOnline = isOnlineFlag || isRecentlyActive;
        if (!isOnline) {
          return avatar;
        }

        return SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: avatar),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: radius * 0.7,
                  height: radius * 0.7,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
