import 'package:flutter/material.dart';

import '../core/config/service_locator.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/premium_service.dart';
import '../utils/profile_completion.dart';
import 'edit_profile_screen.dart';

const Color _kProfileBg = Color(0xFFF7F5F2);
const Color _kProfileText = Color(0xFF171717);
const Color _kProfileMuted = Color(0xFF6B7280);
const Color _kProfileGreen = Color(0xFF0F5C2E);
const Color _kPremiumBg = Color(0xFFFFF7E8);
const Color _kPremiumBorder = Color(0xFFF3CC7A);

class CurrentUserScreen extends StatelessWidget {
  final dynamic controller;
  final String fallbackName;
  final VoidCallback? onBack;

  const CurrentUserScreen({
    super.key,
    required this.controller,
    required this.fallbackName,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final profile = controller.profile;
    final authUser = AuthService().getCurrentUser();
    final displayName = profile?.fullName?.trim().isNotEmpty == true
        ? profile.fullName as String
        : fallbackName;
    final completion = calculateProfileCompletion(profile);
    final String? imageUrl = profile?.profilePictureUrl?.trim().isNotEmpty == true
        ? profile!.profilePictureUrl
        : authUser?.photoURL;

    return Container(
      color: _kProfileBg,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_ios_new, color: _kProfileText, size: 20),
                  ),
                  const Spacer(),
                  const Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _kProfileText,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pushNamed('/app-settings'),
                    icon: const Icon(Icons.settings_outlined, color: _kProfileGreen),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ProfileOverviewCard(
                displayName: displayName,
                imageUrl: imageUrl,
                completionPercent: completion.percent,
                onImproveProfile: completion.percent < 100
                    ? () => Navigator.of(context).pushNamed(
                          '/profile-setup',
                          arguments: {'initialStep': inferJourneyStep(profile)},
                        )
                    : null,
                onTap: () => _openViewProfile(context),
              ),
              const SizedBox(height: 16),
              _PremiumUpsellCard(
                onTap: () async {
                  final result = await Navigator.of(context).pushNamed(
                    '/payment',
                    arguments: const {
                      'initialPlanId': 'premium',
                    },
                  );
                  if (!context.mounted || result == null) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Premium unlocked')),
                  );
                },
              ),
              const SizedBox(height: 18),
              const Text(
                'Account',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _kProfileText,
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                children: [
                  _ProfileMenuTile(
                    icon: Icons.edit_outlined,
                    title: 'Edit Profile',
                    subtitle: 'Update your personal information',
                    onTap: () => _openEditProfile(context),
                  ),
                  _divider(),
                  _ProfileMenuTile(
                    icon: Icons.lock_outline,
                    title: 'Privacy & Safety',
                    subtitle: 'Manage your privacy settings',
                    onTap: () => Navigator.of(context).pushNamed('/privacy-safety'),
                  ),
                  _divider(),
                  _ProfileMenuTile(
                    icon: Icons.notifications_none,
                    title: 'Notifications',
                    subtitle: 'Manage your notification preferences',
                    onTap: () => Navigator.of(context).pushNamed('/notification-settings'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Support & Legal',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _kProfileText,
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                children: [
                  _ProfileMenuTile(
                    icon: Icons.help_outline,
                    title: 'Help & Support',
                    subtitle: 'Get help and support',
                    onTap: () async {
                      final openedSupportChat = await Navigator.of(context).pushNamed('/help-support');
                      if (openedSupportChat != true || !context.mounted) return;
                      Navigator.of(context).pushReplacementNamed(
                        '/home',
                        arguments: {
                          'userName': displayName,
                          'initialIndex': 2,
                          'initialChatTarget': const {
                            'uid': ChatService.supportUid,
                            'displayName': ChatService.supportDisplayName,
                          },
                        },
                      );
                    },
                  ),
                  _divider(),
                  _ProfileMenuTile(
                    icon: Icons.info_outline,
                    title: 'About Qubool Nikah',
                    subtitle: 'App information and more',
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'Qubool Nikah',
                        applicationVersion: '1.0.0',
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, color: Color(0xFFF0ECE5));

  void _openEditProfile(BuildContext context) {
    final u = AuthService().getCurrentUser();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(userId: u?.uid ?? ''),
      ),
    );
  }

  void _openViewProfile(BuildContext context) {
    final profile = controller.profile;
    final userId = profile?.uid ?? AuthService().getCurrentUser()?.uid ?? '';
    Navigator.of(context).pushNamed(
      '/view-profile',
      arguments: profile ?? userId,
    );
  }
}

class _ProfileOverviewCard extends StatelessWidget {
  final String displayName;
  final String? imageUrl;
  final int completionPercent;
  final VoidCallback? onImproveProfile;
  final VoidCallback onTap;

  const _ProfileOverviewCard({
    required this.displayName,
    required this.imageUrl,
    required this.completionPercent,
    this.onImproveProfile,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = imageUrl?.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF1ECE4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: const Color(0xFFF2F2F2),
                backgroundImage: normalizedUrl != null && normalizedUrl.isNotEmpty
                    ? NetworkImage(normalizedUrl)
                    : null,
                child: normalizedUrl == null || normalizedUrl.isEmpty
                    ? Text(
                        displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U',
                        style: const TextStyle(
                          color: _kProfileGreen,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _kProfileText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: onTap,
                      child: const Text(
                        'View Profile',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _kProfileGreen,
                        ),
                      ),
                    ),
                    if (onImproveProfile != null) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 38,
                        child: FilledButton(
                          onPressed: onImproveProfile,
                          style: FilledButton.styleFrom(
                            backgroundColor: _kProfileGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('Complete Profile'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Text(
                'Profile Completion',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _kProfileText,
                ),
              ),
              const Spacer(),
              Text(
                '$completionPercent%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kProfileText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: completionPercent / 100,
              minHeight: 6,
              backgroundColor: const Color(0xFFF0ECE5),
              color: _kProfileGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumUpsellCard extends StatelessWidget {
  final VoidCallback onTap;

  const _PremiumUpsellCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: getIt<PremiumService>().isPremiumStream,
      initialData: false,
      builder: (context, snapshot) {
        final isPremium = snapshot.data ?? false;
        return InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: isPremium ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: isPremium ? const Color(0xFFE8F7EE) : _kPremiumBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isPremium ? const Color(0xFFC5E8D1) : _kPremiumBorder,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isPremium ? const Color(0xFFD3F0DE) : const Color(0xFFFFF0C8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isPremium ? Icons.verified_outlined : Icons.workspace_premium_outlined,
                    color: isPremium ? _kProfileGreen : const Color(0xFFB88300),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isPremium ? 'Premium Active' : 'Go Premium',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _kProfileText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isPremium ? 'All premium features are unlocked' : 'Unlock all features',
                        style: const TextStyle(
                          fontSize: 14,
                          color: _kProfileMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: _kProfileMuted),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  final List<Widget> children;

  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF1ECE4)),
      ),
      child: Column(children: children),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileMenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(icon, color: _kProfileGreen, size: 24),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _kProfileText,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            color: _kProfileMuted,
          ),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: _kProfileMuted),
      onTap: onTap,
    );
  }
}
