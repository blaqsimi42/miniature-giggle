import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/profile_header_card.dart';
import '../utils/profile_completion.dart';
import '../widgets/premium_card.dart';
import '../widgets/settings_section_card.dart';
import '../widgets/settings_tile.dart';
class ProfileHub extends StatelessWidget {
  final dynamic controller; // keep generic to accept UserDashboardController
  final String fallbackName;

  const ProfileHub({super.key, required this.controller, required this.fallbackName});

  @override
  Widget build(BuildContext context) {
    final authUser = AuthService().getCurrentUser();
    final imageUrl = controller.profile?.profilePictureUrl?.trim().isNotEmpty == true
        ? controller.profile!.profilePictureUrl
        : authUser?.photoURL;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F2),
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileHeaderCard(
                imageUrl: imageUrl,
                imageProvider: null,
                displayName: controller.profile?.fullName ?? fallbackName,
                subtitle: controller.profile?.email ?? controller.profile?.phone ?? 'View Profile',
                completionPercent: calculateProfileCompletion(controller.profile).percent,
                onEdit: () {
                  final u = AuthService().getCurrentUser();
                  Navigator.of(context).pushNamed('/edit-profile', arguments: u?.uid ?? '');
                },
                onTapAvatar: () {
                  final profile = controller.profile;
                  final u = AuthService().getCurrentUser();
                  Navigator.of(context).pushNamed(
                    '/view-profile',
                    arguments: profile ?? (u?.uid ?? ''),
                  );
                },
              ),
              const SizedBox(height: 20),
              PremiumCard(
                onTap: () => Navigator.of(context).pushNamed(
                  '/payment',
                  arguments: const {
                    'initialPlanId': 'premium',
                  },
                ),
              ),
              const SizedBox(height: 20),
              SettingsSectionCard(
                title: 'Account & Settings',
                children: [
                  SettingsTile(icon: Icons.person, title: 'Edit Profile', subtitle: 'Update your personal information', onTap: () { final u = AuthService().getCurrentUser(); Navigator.of(context).pushNamed('/edit-profile', arguments: u?.uid ?? ''); }),
                  const Divider(height: 1),
                  SettingsTile(icon: Icons.lock, title: 'Privacy & Safety', subtitle: 'Manage who can see your info', onTap: () => Navigator.of(context).pushNamed('/privacy-safety')),
                  const Divider(height: 1),
                  SettingsTile(icon: Icons.notifications, title: 'Notifications', subtitle: 'Manage notification preferences', onTap: () => Navigator.of(context).pushNamed('/notification-settings')),
                ],
              ),
              const SizedBox(height: 20),
              SettingsSectionCard(
                title: 'Support & Legal',
                children: [
                  SettingsTile(icon: Icons.help_outline, title: 'Help & Support', subtitle: 'Get help with your account', onTap: () {}),
                  const Divider(height: 1),
                  SettingsTile(icon: Icons.info_outline, title: 'About App', subtitle: 'Version & legal information', onTap: () {}),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // Profile completion calculation moved to utils/profile_completion.dart
}
