import 'package:flutter/material.dart';

import '../widgets/settings_section_card.dart';
import '../widgets/settings_tile.dart';

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const pageBackground = Color(0xFFF7F5F2);
    const heroBackground = Colors.white;
    const heroBorder = Color(0xFFF0E9DE);
    const titleColor = Color(0xFF171717);
    const mutedColor = Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        backgroundColor: pageBackground,
        foregroundColor: titleColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: heroBackground,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: heroBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 12,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                'Manage your app preferences without repeating privacy controls here.',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: mutedColor,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SettingsSectionCard(
              title: 'Preferences',
              children: [
                SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Review app alerts and message activity',
                  onTap: () => Navigator.of(context).pushNamed('/notification-settings'),
                ),
                const Divider(height: 1),
                SettingsTile(
                  icon: Icons.language_outlined,
                  title: 'Language & Region',
                  subtitle: 'Choose how names, dates, and app text are shown',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Language & Region settings coming soon'),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                SettingsTile(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Manage Subscription',
                  subtitle: 'Review your plan and billing options',
                  onTap: () => Navigator.of(context).pushNamed('/manage-subscription'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
