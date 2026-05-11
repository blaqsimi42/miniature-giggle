import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../services/user_service.dart';
import '../widgets/settings_section_card.dart';
import '../widgets/settings_tile.dart';

class PrivacySafetyScreen extends StatefulWidget {
  const PrivacySafetyScreen({super.key});

  @override
  State<PrivacySafetyScreen> createState() => _PrivacySafetyScreenState();
}

class _PrivacySafetyScreenState extends State<PrivacySafetyScreen> {
  final _firestore = FirebaseFirestore.instance;
  String? _uid;
  bool _loading = true;
  Map<String, dynamic> _settings = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSubscription;

  @override
  void initState() {
    super.initState();
    final u = FirebaseAuth.instance.currentUser;
    _uid = u?.uid;
    if (_uid != null) {
      _settingsSubscription = _firestore
          .collection('users')
          .doc(_uid)
          .snapshots()
          .listen((snap) {
            if (!mounted) return;
            final data = snap.data() ?? {};
            setState(() {
              _settings = Map<String, dynamic>.from(data['settings'] ?? {});
              _loading = false;
            });
          }, onError: (_) {
            if (!mounted) return;
            setState(() => _loading = false);
          });
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _save(Map<String, dynamic> partial) async {
    if (_uid == null) return;
    try {
      final messenger = ScaffoldMessenger.of(context);
      await UserService().updateUser(_uid!, {'settings': {..._settings, ...partial}});
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Privacy settings saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibility = _settings['visibility'] as String? ?? 'matches';
    final hidePhotos = _settings['hidePhotos'] as bool? ?? false;
    final showLastSeen = _settings['showLastSeen'] as bool? ?? true;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F2),
      appBar: AppBar(
        title: const Text('Privacy & Safety'),
        centerTitle: true,
        backgroundColor: const Color(0xFFF7F5F2),
        foregroundColor: const Color(0xFF171717),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x08000000),
                          blurRadius: 12,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withAlpha((0.10 * 255).round()),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.shield_outlined,
                                color: Theme.of(context).colorScheme.primary,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Stay In Control',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF171717),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Choose who sees your profile and how much information is visible.',
                                    style: TextStyle(
                                      color: Color(0xFF6B7280),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _PrivacyChip(
                              icon: Icons.visibility_outlined,
                              label: _visibilityLabel(visibility),
                            ),
                            _PrivacyChip(
                              icon: hidePhotos ? Icons.no_photography_outlined : Icons.photo_library_outlined,
                              label: hidePhotos ? 'Photos hidden' : 'Photos visible',
                            ),
                            _PrivacyChip(
                              icon: showLastSeen ? Icons.schedule : Icons.visibility_off_outlined,
                              label: showLastSeen ? 'Last seen visible' : 'Last seen hidden',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SettingsSectionCard(
                    title: 'Visibility',
                    children: [
                      _PrivacyRadioTile(
                        title: 'Visible to everyone',
                        subtitle: 'Anyone browsing can discover your profile.',
                        value: 'everyone',
                        groupValue: visibility,
                        onChanged: (value) {
                          setState(() => _settings['visibility'] = value);
                          _save({'visibility': value});
                        },
                      ),
                      const Divider(height: 1),
                      _PrivacyRadioTile(
                        title: 'Visible to matches only',
                        subtitle: 'Keep discovery focused on stronger connections.',
                        value: 'matches',
                        groupValue: visibility,
                        onChanged: (value) {
                          setState(() => _settings['visibility'] = value);
                          _save({'visibility': value});
                        },
                      ),
                      const Divider(height: 1),
                      _PrivacyRadioTile(
                        title: 'Private',
                        subtitle: 'Hide your profile from search and discovery.',
                        value: 'private',
                        groupValue: visibility,
                        onChanged: (value) {
                          setState(() => _settings['visibility'] = value);
                          _save({'visibility': value});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SettingsSectionCard(
                    title: 'Safety Preferences',
                    children: [
                      _PrivacySwitchTile(
                        icon: Icons.photo_outlined,
                        title: 'Hide Photos',
                        subtitle: 'Blur or hide your photos for extra privacy.',
                        value: hidePhotos,
                        onChanged: (value) {
                          setState(() => _settings['hidePhotos'] = value);
                          _save({'hidePhotos': value});
                        },
                      ),
                      const Divider(height: 1),
                      _PrivacySwitchTile(
                        icon: Icons.history_toggle_off,
                        title: 'Show Last Seen',
                        subtitle: 'Let others know when you were recently active.',
                        value: showLastSeen,
                        onChanged: (value) {
                          setState(() => _settings['showLastSeen'] = value);
                          _save({'showLastSeen': value});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SettingsSectionCard(
                    title: 'Safety Tools',
                    children: [
                      SettingsTile(
                        icon: Icons.block,
                        title: 'Block List',
                        subtitle: 'Review and manage blocked accounts.',
                        onTap: () {},
                      ),
                      const Divider(height: 1),
                      SettingsTile(
                        icon: Icons.report_gmailerrorred,
                        title: 'Report & Safety',
                        subtitle: 'Learn how to report behavior and stay safe.',
                        onTap: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SettingsSectionCard(
                    title: 'Policies',
                    children: [
                      SettingsTile(
                        icon: Icons.policy_outlined,
                        title: 'Privacy Policy',
                        subtitle: 'See how your data is handled.',
                        onTap: () {},
                      ),
                      const Divider(height: 1),
                      SettingsTile(
                        icon: Icons.description_outlined,
                        title: 'Terms & Conditions',
                        subtitle: 'Review the rules and terms of use.',
                        onTap: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  static String _visibilityLabel(String visibility) {
    switch (visibility) {
      case 'everyone':
        return 'Visible to everyone';
      case 'private':
        return 'Private profile';
      case 'matches':
      default:
        return 'Matches only';
    }
  }
}

class _PrivacyChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PrivacyChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5F2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF6B7280)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyRadioTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final String groupValue;
  final ValueChanged<String> onChanged;

  const _PrivacyRadioTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? primary : const Color(0xFFD1D5DB),
            width: 2,
          ),
        ),
        child: selected
            ? Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primary,
                  ),
                ),
              )
            : null,
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF6B6B6B)),
      ),
      trailing: selected
          ? const Icon(Icons.check_circle, color: Color(0xFF0F5C2E))
          : null,
      onTap: () => onChanged(value),
    );
  }
}

class _PrivacySwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrivacySwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      secondary: CircleAvatar(
        radius: 20,
        backgroundColor: primary.withAlpha((0.08 * 255).round()),
        child: Icon(icon, color: primary),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF6B6B6B)),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
