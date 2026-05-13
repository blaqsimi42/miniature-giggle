import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/user_service.dart';

class InviteFriendsScreen extends StatefulWidget {
  const InviteFriendsScreen({super.key});

  @override
  State<InviteFriendsScreen> createState() => _InviteFriendsScreenState();
}

class _InviteFriendsScreenState extends State<InviteFriendsScreen> {
  static const String _playStoreAppId = 'com.example.matrimonial_app';
  final TextEditingController _linkController = TextEditingController();
  bool _loading = true;
  String _displayName = 'Friend';
  String _inviteLink = '';
  String _shareMessage = '';

  @override
  void initState() {
    super.initState();
    _loadInviteData();
  }

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _loadInviteData() async {
    final authUser = AuthService().getCurrentUser();
    final fallbackName = authUser?.displayName?.trim().isNotEmpty == true
        ? authUser!.displayName!.trim()
        : (authUser?.email?.split('@').first ?? 'Friend');

    String resolvedName = fallbackName;
    if (authUser != null) {
      try {
        final profile = await UserService().getUser(authUser.uid);
        final profileName = profile?.fullName.trim();
        if (profileName != null && profileName.isNotEmpty) {
          resolvedName = profileName;
        }
      } catch (_) {
        // Keep fallback name when profile fetch is unavailable.
      }
    }

    final usernameSlug = _slugify(resolvedName);
    final referrer = Uri.encodeQueryComponent(
      'invited_by=$usernameSlug&source=invite',
    );
    final inviteLink =
        'https://play.google.com/store/apps/details?id=$_playStoreAppId&referrer=$referrer';
    final shareMessage =
        'I invited you to Qubool Nikah. Download the app and sign up with my invite link: $inviteLink';

    if (!mounted) return;
    setState(() {
      _displayName = resolvedName;
      _inviteLink = inviteLink;
      _shareMessage = shareMessage;
      _linkController.text = inviteLink;
      _loading = false;
    });
  }

  static String _slugify(String value) {
    final cleaned = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'friend' : cleaned;
  }

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    const pageBg = Color(0xFFF7F5F2);
    const green = Color(0xFF0F5C2E);
    const softGreen = Color(0xFFEAF6EE);
    const muted = Color(0xFF667085);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text('Invite Friends'),
        centerTitle: true,
        backgroundColor: pageBg,
        foregroundColor: const Color(0xFF171717),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF0F5C2E),
                            Color(0xFF17803D),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x19000000),
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.share_outlined,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Bring your people in',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Your invite link is ready, $_displayName. Share it so friends can discover Qubool Nikah through you.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: const [
                              _InviteStatChip(
                                icon: Icons.link_rounded,
                                label: 'Personal invite link',
                              ),
                              _InviteStatChip(
                                icon: Icons.download_rounded,
                                label: 'Play Store ready',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: const Color(0xFFF0E9DE)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x08000000),
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Your invite link',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF171717),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'This link includes your invite identity so people who join through it are marked as invited by you.',
                            style: TextStyle(
                              color: muted,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _linkController,
                            readOnly: true,
                            maxLines: 3,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: softGreen,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.all(16),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _copyText(_inviteLink, 'Invite link'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: green,
                                    side: const BorderSide(color: green),
                                    padding: const EdgeInsets.symmetric(vertical: 15),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  icon: const Icon(Icons.copy_all_rounded),
                                  label: const Text(
                                    'Copy Link',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _copyText(_shareMessage, 'Share message'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 15),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  icon: const Icon(Icons.send_rounded),
                                  label: const Text(
                                    'Copy Share Text',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFF0E9DE)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'How it works',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF171717),
                            ),
                          ),
                          SizedBox(height: 14),
                          _InviteStep(
                            number: '1',
                            title: 'Copy your link',
                            subtitle: 'Grab your personal invite URL or full share message.',
                          ),
                          SizedBox(height: 12),
                          _InviteStep(
                            number: '2',
                            title: 'Send it anywhere',
                            subtitle: 'Paste it into WhatsApp, SMS, Instagram, or any social app.',
                          ),
                          SizedBox(height: 12),
                          _InviteStep(
                            number: '3',
                            title: 'Friends install from Play Store',
                            subtitle: 'When they follow your link and sign up, the invite keeps your name attached.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _InviteStatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InviteStatChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteStep extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;

  const _InviteStep({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF6EE),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFF0F5C2E),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF171717),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF667085),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
