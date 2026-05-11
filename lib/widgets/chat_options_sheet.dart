import 'package:flutter/material.dart';

Future<void> showChatOptionsSheet({
  required BuildContext context,
  required VoidCallback onViewProfile,
  required VoidCallback onShareProfile,
  required VoidCallback onReport,
  required VoidCallback onBlockUser,
  required VoidCallback onClearChat,
}) {
  final colorScheme = Theme.of(context).colorScheme;

  void handleTap(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('View Profile'),
              onTap: () => handleTap(onViewProfile),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Share Profile'),
              onTap: () => handleTap(onShareProfile),
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Row(
                children: [
                  const Text('Add Guardian'),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'New',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).pushNamed('/guardian/add');
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report'),
              onTap: () => handleTap(onReport),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Block User'),
              onTap: () => handleTap(onBlockUser),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: colorScheme.error),
              title: Text(
                'Clear Chat',
                style: TextStyle(color: colorScheme.error),
              ),
              onTap: () => handleTap(onClearChat),
            ),
          ],
        ),
      );
    },
  );
}
