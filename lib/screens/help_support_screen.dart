import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/chat_service.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F2),
      appBar: AppBar(
        title: const Text('Help & Support'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFFF7F5F2),
        foregroundColor: const Color(0xFF171717),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 14,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      _SupportMenuTile(
                        title: 'FAQs',
                        onTap: () => _showComingSoon(context, 'FAQs'),
                      ),
                      _SupportMenuTile(
                        title: 'How Qubool Nikah Works',
                        onTap: () => _showComingSoon(context, 'How Qubool Nikah Works'),
                      ),
                      _SupportMenuTile(
                        title: 'Safety Tips',
                        onTap: () => _showComingSoon(context, 'Safety Tips'),
                      ),
                      _SupportMenuTile(
                        title: 'Report a Problem',
                        onTap: () => _showComingSoon(context, 'Report a Problem'),
                      ),
                      _SupportMenuTile(
                        title: 'Contact Us',
                        onTap: () => _showComingSoon(context, 'Contact Us'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _openSupportChat(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F5C2E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      'Chat with Support',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _showComingSoon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label coming soon')),
    );
  }

  static Future<void> _openSupportChat(BuildContext context) async {
    final currentUser = AuthService().getCurrentUser();
    if (currentUser == null) return;

    final displayName = currentUser.displayName?.trim().isNotEmpty == true
        ? currentUser.displayName!.trim()
        : (currentUser.email?.split('@').first ?? 'User');

    await ChatService().ensureSupportConversationForUser(
      userId: currentUser.uid,
      userDisplayName: displayName,
      userPhotoUrl: currentUser.photoURL,
    );

    if (!context.mounted) return;
    Navigator.of(context).pop(true);
  }
}

class _SupportMenuTile extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const _SupportMenuTile({
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F5F2),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              Icons.help_outline_rounded,
              color: Color(0xFF6B7280),
              size: 20,
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF171717),
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFF98A2B3),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
