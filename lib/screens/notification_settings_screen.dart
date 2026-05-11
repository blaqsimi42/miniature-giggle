import 'package:flutter/material.dart';

import '../services/notification_preferences_service.dart';
import '../widgets/app_notice.dart';

const Color _kNotifBg = Color(0xFFF7F5F2);
const Color _kNotifText = Color(0xFF171717);
const Color _kNotifMuted = Color(0xFF6B7280);
const Color _kNotifGreen = Color(0xFF0F5C2E);
const Color _kNotifBorder = Color(0xFFF0E9DE);

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final NotificationPreferencesService _service =
      NotificationPreferencesService();

  Future<void> _update(Map<String, dynamic> data) async {
    try {
      await _service.savePreferences(data);
      if (!mounted) return;
      AppNotice.showSuccess(context, 'Notification preferences updated');
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(
        context,
        e,
        fallbackMessage: 'Could not update notification settings.',
      );
    }
  }

  Future<void> _pickMuteTime({
    required bool isStart,
    required int currentMinutes,
  }) async {
    final initialTime = TimeOfDay(
      hour: currentMinutes ~/ 60,
      minute: currentMinutes % 60,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    await _update({
      isStart ? 'muteStartMinutes' : 'muteEndMinutes': minutes,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kNotifBg,
      appBar: AppBar(
        title: const Text('Notification Settings'),
        centerTitle: true,
        backgroundColor: _kNotifBg,
        foregroundColor: _kNotifText,
        elevation: 0,
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _service.streamPreferences(),
        builder: (context, snapshot) {
          final data = snapshot.data ??
              {
                'notificationsEnabled': true,
                'pushEnabled': true,
                'emailEnabled': false,
                'soundEnabled': true,
                'vibrationEnabled': true,
                'muteMode': 'off',
                'muteStartMinutes': 1320,
                'muteEndMinutes': 420,
                'interestsEnabled': true,
                'matchesEnabled': true,
                'messagesEnabled': true,
                'profileActivityEnabled': true,
                'savedProfilesEnabled': true,
                'billingEnabled': true,
                'securityEnabled': true,
              };

          final notificationsEnabled =
              data['notificationsEnabled'] == true;
          final muteMode = (data['muteMode'] ?? 'off').toString();
          final muteStartMinutes = (data['muteStartMinutes'] as num?)?.toInt() ?? 1320;
          final muteEndMinutes = (data['muteEndMinutes'] as num?)?.toInt() ?? 420;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _SettingsHeroCard(
                title: 'Stay in control',
                subtitle:
                    'Choose which alerts matter, when they can reach you, and when the app should stay quiet.',
              ),
              const SizedBox(height: 18),
              _SettingsSection(
                title: 'Master Control',
                child: Column(
                  children: [
                    _SwitchTile(
                      icon: Icons.notifications_active_outlined,
                      title: 'Allow notifications',
                      subtitle: 'Turn all alerts on or off across the app',
                      value: notificationsEnabled,
                      onChanged: (value) => _update({
                        'notificationsEnabled': value,
                      }),
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      icon: Icons.phone_android_outlined,
                      title: 'Push notifications',
                      subtitle: 'Receive alerts on this device',
                      value: data['pushEnabled'] == true,
                      onChanged: notificationsEnabled
                          ? (value) => _update({'pushEnabled': value})
                          : null,
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      icon: Icons.alternate_email_outlined,
                      title: 'Email notifications',
                      subtitle: 'Get important account updates by email',
                      value: data['emailEnabled'] == true,
                      onChanged: notificationsEnabled
                          ? (value) => _update({'emailEnabled': value})
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: 'Mute & Quiet Hours',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MuteModeCard(
                      selected: muteMode == 'off',
                      title: 'No mute',
                      subtitle: 'Notifications arrive normally',
                      onTap: notificationsEnabled
                          ? () => _update({'muteMode': 'off'})
                          : null,
                    ),
                    const SizedBox(height: 10),
                    _MuteModeCard(
                      selected: muteMode == 'until_changed',
                      title: 'Mute until I change it',
                      subtitle: 'Pause all alerts until you manually turn them back on',
                      onTap: notificationsEnabled
                          ? () => _update({'muteMode': 'until_changed'})
                          : null,
                    ),
                    const SizedBox(height: 10),
                    _MuteModeCard(
                      selected: muteMode == 'scheduled',
                      title: 'Scheduled quiet hours',
                      subtitle: 'Mute notifications daily between set times',
                      onTap: notificationsEnabled
                          ? () => _update({'muteMode': 'scheduled'})
                          : null,
                    ),
                    if (muteMode == 'scheduled') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _TimeChip(
                              label: 'From',
                              value: _formatMinutes(muteStartMinutes),
                              onTap: () => _pickMuteTime(
                                isStart: true,
                                currentMinutes: muteStartMinutes,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TimeChip(
                              label: 'Until',
                              value: _formatMinutes(muteEndMinutes),
                              onTap: () => _pickMuteTime(
                                isStart: false,
                                currentMinutes: muteEndMinutes,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: 'Alert Types',
                child: Column(
                  children: [
                    _SwitchTile(
                      icon: Icons.favorite_outline_rounded,
                      title: 'Interest requests',
                      subtitle: 'When someone sends you an interest',
                      value: data['interestsEnabled'] == true,
                      onChanged: notificationsEnabled
                          ? (value) => _update({'interestsEnabled': value})
                          : null,
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      icon: Icons.people_outline_rounded,
                      title: 'Matches',
                      subtitle: 'When you get a new match or a match changes state',
                      value: data['matchesEnabled'] == true,
                      onChanged: notificationsEnabled
                          ? (value) => _update({'matchesEnabled': value})
                          : null,
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Messages',
                      subtitle: 'For new chats, replies, and message reminders',
                      value: data['messagesEnabled'] == true,
                      onChanged: notificationsEnabled
                          ? (value) => _update({'messagesEnabled': value})
                          : null,
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      icon: Icons.visibility_outlined,
                      title: 'Profile activity',
                      subtitle: 'For likes, views, and profile-related activity',
                      value: data['profileActivityEnabled'] == true,
                      onChanged: notificationsEnabled
                          ? (value) => _update({'profileActivityEnabled': value})
                          : null,
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      icon: Icons.bookmark_outline_rounded,
                      title: 'Saved profiles',
                      subtitle: 'For updates connected to profiles you saved',
                      value: data['savedProfilesEnabled'] == true,
                      onChanged: notificationsEnabled
                          ? (value) => _update({'savedProfilesEnabled': value})
                          : null,
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      icon: Icons.workspace_premium_outlined,
                      title: 'Billing & premium',
                      subtitle: 'For purchases, renewals, and subscription reminders',
                      value: data['billingEnabled'] == true,
                      onChanged: notificationsEnabled
                          ? (value) => _update({'billingEnabled': value})
                          : null,
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      icon: Icons.shield_outlined,
                      title: 'Security & verification',
                      subtitle: 'For login alerts, verification, and account protection',
                      value: data['securityEnabled'] == true,
                      onChanged: notificationsEnabled
                          ? (value) => _update({'securityEnabled': value})
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsSection(
                title: 'Experience',
                child: Column(
                  children: [
                    _SwitchTile(
                      icon: Icons.music_note_outlined,
                      title: 'Sound',
                      subtitle: 'Play a sound when a notification arrives',
                      value: data['soundEnabled'] == true,
                      onChanged: notificationsEnabled
                          ? (value) => _update({'soundEnabled': value})
                          : null,
                    ),
                    const Divider(height: 1),
                    _SwitchTile(
                      icon: Icons.vibration_outlined,
                      title: 'Vibration',
                      subtitle: 'Vibrate your device for new alerts',
                      value: data['vibrationEnabled'] == true,
                      onChanged: notificationsEnabled
                          ? (value) => _update({'vibrationEnabled': value})
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatMinutes(int minutes) {
    final hour = (minutes ~/ 60) % 24;
    final minute = minutes % 60;
    final time = TimeOfDay(hour: hour, minute: minute);
    return time.format(context);
  }
}

class _SettingsHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SettingsHeroCard({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kNotifBorder),
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _kNotifText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _kNotifMuted,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kNotifBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _kNotifText,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F7F4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: _kNotifGreen, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: _kNotifText,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: _kNotifMuted,
          height: 1.35,
        ),
      ),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: _kNotifGreen,
        activeTrackColor: const Color(0xFFB9DEC5),
      ),
    );
  }
}

class _MuteModeCard extends StatelessWidget {
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _MuteModeCard({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF4EE) : const Color(0xFFF9FAF9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _kNotifGreen : _kNotifBorder,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _kNotifText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _kNotifMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? _kNotifGreen : const Color(0xFF98A2B3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TimeChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAF9),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _kNotifBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: _kNotifMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(
                        color: _kNotifText,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.schedule_rounded,
                color: _kNotifGreen,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
