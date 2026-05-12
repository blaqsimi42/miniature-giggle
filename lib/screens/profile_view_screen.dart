import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/chat_access_service.dart';
import '../services/interactions_service.dart';
import '../services/profile_completion_gate_service.dart';
import '../services/user_service.dart';
import '../widgets/app_notice.dart';
import 'home_dashboard.dart';
import '../core/utils/validation_service.dart';
import '../core/utils/currency_formatter.dart';

class ProfileViewScreen extends StatefulWidget {
  final String userId;
  final UserModel? initialProfile;

  const ProfileViewScreen({
    super.key,
    required this.userId,
    this.initialProfile,
  });

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  bool _sendingInterest = false;
  late Future<UserModel?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = UserService().getUser(widget.userId);
  }

  @override
  void didUpdateWidget(covariant ProfileViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _profileFuture = UserService().getUser(widget.userId);
    }
  }

  Future<void> _openDirectChat(UserModel profile) async {
    final currentUser = AuthService().getCurrentUser();
    if (currentUser == null) {
      AppNotice.showError(context, 'Sign in to start a chat.');
      return;
    }

    final allowed = await ProfileCompletionGateService.ensureDiscoveryAccess(
      context,
    );
    if (!allowed || !mounted) {
      return;
    }

    final canChat = await ChatAccessService().canCurrentUserChat();
    if (!mounted) {
      return;
    }
    if (!canChat) {
      AppNotice.showError(
        context,
        'Premium membership is required before you can chat.',
      );
      return;
    }

    final userName = currentUser.displayName?.trim().isNotEmpty == true
        ? currentUser.displayName!.trim()
        : (currentUser.email?.split('@').first ?? 'User');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserHomeScreen(
          userName: userName,
          initialIndex: 2,
          initialChatTarget: ChatLaunchTarget(
            uid: profile.uid,
            displayName: profile.fullName,
            photoUrl: profile.profilePictureUrl,
          ),
        ),
      ),
    );
  }

  Future<void> _sendInterest(UserModel profile) async {
    if (_sendingInterest) return;

    final currentUser = AuthService().getCurrentUser();
    if (currentUser == null) {
      AppNotice.showError(context, 'Sign in to send interest.');
      return;
    }

    final allowed = await ProfileCompletionGateService.ensureDiscoveryAccess(
      context,
    );
    if (!allowed || !mounted) {
      return;
    }

    setState(() => _sendingInterest = true);
    try {
      await InteractionsService().sendInterest(currentUser.uid, profile.uid);
      if (!mounted) return;
      AppNotice.showSuccess(context, 'Interest sent');
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(
        context,
        e,
        fallbackMessage: 'Could not send interest right now.',
      );
    } finally {
      if (mounted) {
        setState(() => _sendingInterest = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use a cached future initialized in initState to avoid triggering
    // repeated Firestore reads on every rebuild.
    final profileFuture = _profileFuture;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F2),
      body: FutureBuilder<UserModel?>(
        future: profileFuture,
        initialData: widget.initialProfile,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final profile = snapshot.data;
          if (profile == null) {
            return _ProfileViewMessage(
              title: 'Profile unavailable',
              message: 'We could not load this profile right now.',
            );
          }

          final allImages = <String>{
            if (profile.profilePictureUrl?.trim().isNotEmpty == true)
              profile.profilePictureUrl!.trim(),
            ...?profile.profileImages
                ?.map((image) => image.trim())
                .where((image) => image.isNotEmpty),
          }.toList();

          final age = profile.dateOfBirth == null
              ? null
              : _calculateAge(profile.dateOfBirth!);
          final location = [
            if (profile.location?['city']?.trim().isNotEmpty == true)
              profile.location!['city']!.trim(),
            if (profile.location?['country']?.trim().isNotEmpty == true)
              profile.location!['country']!.trim(),
          ].join(', ');
          final headline = [
            if (profile.occupation?.trim().isNotEmpty == true)
              profile.occupation!.trim(),
            if (location.isNotEmpty) location,
          ].join(' | ');

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 360,
                backgroundColor: const Color(0xFF0F5C2E),
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (allImages.isNotEmpty)
                        Image.network(
                          allImages.first,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _ProfileHeroPlaceholder(
                            name: profile.fullName,
                          ),
                        )
                      else
                        _ProfileHeroPlaceholder(name: profile.fullName),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.08),
                              Colors.black.withValues(alpha: 0.68),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 24,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    age == null
                                        ? profile.fullName
                                        : '${profile.fullName}, $age',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (profile.isVerified)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.24),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.verified_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Verified',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            if (headline.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                headline,
                                style: const TextStyle(
                                  color: Color(0xFFF7F7F7),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF7F5F2),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProfileHighlightRow(
                          items: [
                            _HighlightData(
                              icon: Icons.person_outline,
                              label: 'Created For',
                              value: _valueOrFallback(profile.profileCreatedFor),
                            ),
                            _HighlightData(
                              icon: Icons.height,
                              label: 'Height',
                              value: profile.height == null
                                  ? 'Not shared'
                                  : ValidationService.formatHeight(profile.height, profile.heightUnit)!,
                            ),
                            _HighlightData(
                              icon: profile.isOnline ? Icons.circle : Icons.schedule,
                              label: 'Status',
                              value: profile.isOnline ? 'Online now' : 'Recently active',
                            ),
                          ],
                        ),
                        if (profile.aboutMe?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 18),
                          _ProfileSectionCard(
                            title: 'About',
                            child: Text(
                              profile.aboutMe!.trim(),
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.6,
                                color: Color(0xFF374151),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _ProfileSectionCard(
                          title: 'Basic Information',
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              _InfoChip(label: 'Gender', value: _valueOrFallback(profile.gender)),
                              _InfoChip(label: 'Religion', value: _valueOrFallback(profile.religion)),
                              _InfoChip(label: 'Caste', value: _valueOrFallback(profile.caste)),
                              _InfoChip(label: 'Education', value: _valueOrFallback(profile.education)),
                              _InfoChip(label: 'Occupation', value: _valueOrFallback(profile.occupation)),
                              _InfoChip(
                                label: 'Income',
                                value: profile.income == null || profile.income!.trim().isEmpty
                                    ? _valueOrFallback(profile.income)
                                    : CurrencyFormatter.format(profile.income),
                              ),
                              Builder(builder: (ctx) {
                                if (location.isEmpty) {
                                  return _InfoChip(label: 'Location', value: 'Not shared');
                                }
                                // split location into city and country if present
                                final parts = location.split(',').map((s) => s.trim()).toList();
                                final countryPart = parts.length > 1 ? parts.sublist(1).join(', ') : '';
                                return Container(
                                  constraints: const BoxConstraints(minWidth: 140),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFAF8F4),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: const Color(0xFFE7E0D5)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Location',
                                        style: TextStyle(
                                          color: Color(0xFF6B7280),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          if (countryPart.toLowerCase() == 'india') ...[
                                            SvgPicture.asset('assets/flags/india.svg', width: 20, height: 14),
                                            const SizedBox(width: 8),
                                          ],
                                          Expanded(
                                            child: Text(
                                              location,
                                              style: const TextStyle(
                                                color: Color(0xFF111827),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                        if (profile.familyDetails?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 18),
                          _ProfileSectionCard(
                            title: 'Family Details',
                            child: Text(
                              profile.familyDetails!.trim(),
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.6,
                                color: Color(0xFF374151),
                              ),
                            ),
                          ),
                        ],
                        if ((profile.hobbies ?? const <String>[]).isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _ProfileSectionCard(
                            title: 'Hobbies & Interests',
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: (profile.hobbies ?? const <String>[])
                                  .map((hobby) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF0ECE5),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          hobby,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF374151),
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                        ],
                        if (allImages.length > 1) ...[
                          const SizedBox(height: 18),
                          _ProfileSectionCard(
                            title: 'Photos',
                            child: SizedBox(
                              height: 108,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: allImages.length,
                                separatorBuilder: (context, index) => const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: AspectRatio(
                                      aspectRatio: 0.82,
                                      child: Image.network(
                                        allImages[index],
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => Container(
                                          color: const Color(0xFFE7E5E4),
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.broken_image_outlined,
                                            color: Color(0xFF9CA3AF),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: FutureBuilder<UserModel?>(
        future: profileFuture,
        initialData: widget.initialProfile,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          if (profile == null) {
            return const SizedBox.shrink();
          }

          return SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Color(0xFF16A34A),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.white,
                    ),
                    onPressed: () => _openDirectChat(profile),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: _sendingInterest
                          ? null
                          : () => _sendInterest(profile),
                      icon: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: _sendingInterest
                            ? const Padding(
                                padding: EdgeInsets.all(9),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF16A34A),
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.favorite,
                                color: Color(0xFF16A34A),
                                size: 18,
                              ),
                      ),
                      label: Text(
                        _sendingInterest ? 'Sending...' : 'Send Interest',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    final hasHadBirthday =
        now.month > birthDate.month ||
        (now.month == birthDate.month && now.day >= birthDate.day);
    if (!hasHadBirthday) age--;
    return age;
  }

  static String _valueOrFallback(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? 'Not shared' : trimmed;
  }
}

class _ProfileHeroPlaceholder extends StatelessWidget {
  final String name;

  const _ProfileHeroPlaceholder({required this.name});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B7A46), Color(0xFF0F5C2E)],
        ),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'U',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 84,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ProfileHighlightRow extends StatelessWidget {
  final List<_HighlightData> items;

  const _ProfileHighlightRow({required this.items});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: items
          .map(
            (item) => Expanded(
              child: Container(
                margin: EdgeInsets.only(
                  right: item == items.last ? 0 : 10,
                ),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.icon, color: const Color(0xFF0F5C2E), size: 20),
                    const SizedBox(height: 12),
                    Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.value,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _HighlightData {
  final IconData icon;
  final String label;
  final String value;

  const _HighlightData({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _ProfileSectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ProfileSectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8F4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7E0D5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileViewMessage extends StatelessWidget {
  final String title;
  final String message;

  const _ProfileViewMessage({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_off_outlined,
              size: 48,
              color: Color(0xFF9CA3AF),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
