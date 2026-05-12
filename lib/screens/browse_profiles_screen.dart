import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../bloc/discover_profile_bloc.dart';
import '../models/interaction_models.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../services/storage_service.dart';
import '../core/config/service_locator.dart';
import '../services/premium_service.dart';
import '../widgets/upgrade_flow.dart';
import '../services/interactions_service.dart';
import '../services/auth_service.dart';
import '../services/route_persistence.dart';
import '../services/notification_service.dart';
import '../services/profile_completion_gate_service.dart';
import '../widgets/app_notice.dart';
import '../widgets/primary_button.dart';
import '../core/utils/validation_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
// 'dart:math' was previously used for stacked card transforms; no longer required.

const Color kPrimaryGreen = Color(0xFF16A34A);
const Color kBackgroundCream = Color(0xFFF7F5F2);
const Color kDeepGreen = Color(0xFF0F3D2E);
const Color kAccentGreen = Color(0xFF1F6F54);
const double kCardRadius = 22.0;

// File-scoped cache to dedupe profile fetches used by drawer helpers.
final UserService _browseUserService = UserService();
final Map<String, Future<UserModel?>> _browseProfileFutures = {};

Future<UserModel?> _browseCachedProfileFuture(String uid) {
  if (uid.trim().isEmpty) return Future.value(null);
  return _browseProfileFutures.putIfAbsent(uid, () => _browseUserService.getUser(uid));
}

class BrowseProfilesScreen extends StatefulWidget {
  final ValueChanged<int>? onNavTap;
  final bool allowSwipe;
  final bool showBottomNav;

  const BrowseProfilesScreen({
    super.key,
    this.onNavTap,
    this.allowSwipe = true,
    this.showBottomNav = true,
  });

  @override
  State<BrowseProfilesScreen> createState() => _BrowseProfilesScreenState();
}

class _BrowseProfilesScreenState extends State<BrowseProfilesScreen> {
  late DiscoverProfileBloc _bloc;
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();
  String? _selectedGender;
  String? _selectedReligion;
  int? _minAge;
  int? _maxAge;
  UserModel? _currentUserProfile;
  int _profileStackRefreshVersion = 0;
  // (removed unused per-state cache)


  @override
  void initState() {
    super.initState();
    _bloc = DiscoverProfileBloc(
      userService: _userService,
      interactionsService: InteractionsService(),
      authService: _authService,
    );
    _bloc.add(const LoadDiscoverProfiles());
    _loadCurrentUserProfile();
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  Future<void> _loadCurrentUserProfile() async {
    final currentUser = _authService.getCurrentUser();
    if (currentUser == null) return;
    final seededName = (currentUser.displayName ?? '').trim().isNotEmpty
        ? currentUser.displayName!.trim()
        : (currentUser.email?.split('@').first ?? 'Member');
    setState(() {
      _currentUserProfile = _mergeCurrentUserProfile(
        existing: _currentUserProfile,
        incoming: UserModel(
          uid: currentUser.uid,
          fullName: seededName,
          email: currentUser.email,
          phone: currentUser.phoneNumber,
          profilePictureUrl: currentUser.photoURL,
        ),
        authPhotoUrl: currentUser.photoURL,
      );
    });
    try {
      final profile = await _userService.getUser(currentUser.uid);
      if (!mounted) return;
      setState(() {
        _currentUserProfile = _mergeCurrentUserProfile(
          existing: _currentUserProfile,
          incoming: profile,
          authPhotoUrl: currentUser.photoURL,
        );
      });
    } catch (_) {}
  }

  Future<bool> _ensureProfileEligibleForDiscovery() async {
    final profile = await ProfileCompletionGateService.loadCurrentProfile() ??
        _currentUserProfile;
    if (profile != null && mounted) {
      setState(() {
        _currentUserProfile = _mergeCurrentUserProfile(
          existing: _currentUserProfile,
          incoming: profile,
          authPhotoUrl: _authService.getCurrentUser()?.photoURL,
        );
      });
    }
    if (!mounted) return false;
    return ProfileCompletionGateService.ensureDiscoveryAccess(
      context,
      profile: _currentUserProfile,
    );
  }

  UserModel _mergeCurrentUserProfile({
    required UserModel? existing,
    required UserModel? incoming,
    required String? authPhotoUrl,
  }) {
    final resolvedPhoto = (incoming?.profilePictureUrl ?? '').trim().isNotEmpty
        ? incoming!.profilePictureUrl
        : (existing?.profilePictureUrl ?? '').trim().isNotEmpty
            ? existing!.profilePictureUrl
            : authPhotoUrl;

    return UserModel.fromMaps({
      ...?existing?.toMap(),
      ...?incoming?.toMap(),
      'uid': incoming?.uid ?? existing?.uid ?? '',
      'fullName': (incoming?.fullName ?? '').trim().isNotEmpty
          ? incoming!.fullName
          : existing?.fullName ?? 'Member',
      'email': (incoming?.email ?? '').trim().isNotEmpty
          ? incoming!.email
          : existing?.email,
      'phone': (incoming?.phone ?? '').trim().isNotEmpty
          ? incoming!.phone
          : existing?.phone,
      'profilePictureUrl': resolvedPhoto,
      'profilePhotoUrl':
          (incoming?.profilePhotoUrl ?? '').trim().isNotEmpty
              ? incoming!.profilePhotoUrl
              : (existing?.profilePhotoUrl ?? '').trim().isNotEmpty
                  ? existing!.profilePhotoUrl
                  : resolvedPhoto,
    });
  }

  Future<void> _refreshDiscoverProfiles() async {
    if (!mounted) return;

    setState(() {
      _profileStackRefreshVersion++;
    });

    _bloc.add(
      LoadDiscoverProfiles(
        gender: _selectedGender,
        minAge: _minAge,
        maxAge: _maxAge,
        religion: _selectedReligion,
      ),
    );

    await _bloc.stream.firstWhere(
      (state) =>
          state is DiscoverProfileLoaded || state is DiscoverProfileError,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _bloc,
      child: BlocConsumer<DiscoverProfileBloc, DiscoverProfileState>(
        listener: (context, state) {
          if (state is! DiscoverProfileLoaded || state.feedbackMessage == null) {
            return;
          }

          if (state.feedbackIsError) {
            AppNotice.showError(
              context,
              state.feedbackMessage!,
              fallbackMessage: state.feedbackMessage!,
            );
            return;
          }

          AppNotice.showSuccess(context, state.feedbackMessage!);
        },
        builder: (context, state) {
          if (state is DiscoverProfileLoading) {
            return const Center(
              child: CircularProgressIndicator(color: kPrimaryGreen),
            );
          }

          if (state is DiscoverProfileError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    state.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'Retry',
                    onPressed: () => _bloc.add(const LoadDiscoverProfiles()),
                  ),
                ],
              ),
            );
          }

          if (state is DiscoverProfileLoaded) {
            final visibleProfiles = state.profiles;

            return Scaffold(
              backgroundColor: kBackgroundCream,
              body: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: _TopBar(
                        onMenu: _openDiscoverSidebar,
                        onNotifications: () => Navigator.pushNamed(context, '/notifications'),
                        onBoost: _showBoostAction,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: _showFilterAction,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: kPrimaryGreen,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Discover',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                            final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
                            final navBarExtra = bottomPadding > 0
                              ? bottomPadding
                              : (widget.showBottomNav ? 22.0 : 124.0);
                            final stackHeight = constraints.maxHeight - navBarExtra;
                          if (visibleProfiles.isEmpty) {
                            return RefreshIndicator(
                              color: kPrimaryGreen,
                              onRefresh: _refreshDiscoverProfiles,
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: constraints.maxHeight,
                                    child: _EmptyProfilesState(
                                      label: 'All',
                                      onReset: null,
                                      onAdjustFilters: _showFilterAction,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return RefreshIndicator(
                            color: kPrimaryGreen,
                            onRefresh: _refreshDiscoverProfiles,
                            child: ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.zero,
                              children: [
                                SizedBox(
                                  height: constraints.maxHeight,
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: _ProfileCardStack(
                                        key: ValueKey(
                                          'discover-stack-$_profileStackRefreshVersion',
                                        ),
                                        availableWidth: constraints.maxWidth,
                                        availableHeight: stackHeight,
                                        profiles: visibleProfiles,
                                        likedMap: state.likedProfiles,
                                        shortlistedMap: state.shortlistedProfiles,
                                        onLike: (uid) async {
                                          final allowed = await _ensureProfileEligibleForDiscovery();
                                          if (!allowed) return;
                                          _bloc.add(LikeProfile(uid));
                                        },
                                        onUnlike: (uid) => _bloc.add(
                                          UnlikeProfile(
                                            uid,
                                            successMessage: 'Profile unliked',
                                          ),
                                        ),
                                        onReject: (uid) => _bloc.add(
                                          UnlikeProfile(
                                            uid,
                                            successMessage: 'Profile removed',
                                          ),
                                        ),
                                        onShortlistToggle: (uid, isShortlisted) {
                                          _bloc.add(
                                            isShortlisted
                                                ? RemoveFromShortlist(
                                                    uid,
                                                    successMessage: 'Profile unsaved',
                                                  )
                                                : AddToShortlist(uid),
                                          );
                                        },
                                        onView: (uid) => _bloc.add(RecordProfileView(uid)),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    // Bottom Nav Bar — prefer parent-controlled navigation when provided
                    if (widget.showBottomNav)
                      _DiscoverBottomNavBar(currentIndex: 0, onTap: (i) {
                        if (widget.onNavTap != null) {
                          widget.onNavTap!(i);
                          return;
                        }
                        _openStandaloneTab(i);
                      }),
                  ],
                ),
              ),
            );
          }

          return const SizedBox();
        },
      ),
    );
  }

  Future<void> _showFilterAction() async {
    final isPremium = await getIt<PremiumService>().isPremium();
    if (isPremium) {
      if (!mounted) return;
      _showFilterDialog();
      return;
    }
    if (!mounted) return;
    final ok = await showUpgradeFlow(context);
    if (!mounted || !ok) return;
    _showFilterDialog();
  }

  Future<void> _showBoostAction() async {
    final result = await Navigator.pushNamed(
      context,
      '/payment',
      arguments: const {
        'initialPlanId': 'boost',
        'includeBoostPlan': true,
      },
    );
    if (!mounted || result == null) return;
    final selectedPlan = result.toString();
    if (selectedPlan == 'boost') {
      AppNotice.showSuccess(
        context,
        'Boost activated. Your profile will get extra visibility for 24 hours.',
      );
      return;
    }
    AppNotice.showSuccess(
      context,
      'Your ${selectedPlan.replaceAll('_', ' ')} plan is now active.',
    );
  }

  void _openStandaloneTab(int index) {
    if (index == 0) return;
    final user = _authService.getCurrentUser();
    final userName = user?.displayName ?? user?.email?.split('@').first ?? 'User';
    Navigator.pushReplacementNamed(
      context,
      '/home',
      arguments: {
        'userName': userName,
        'initialIndex': index,
      },
    );
  }

  Future<void> _copyValue({
    required String label,
    required String? value,
  }) async {
    if (value == null || value.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No $label available')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: value.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  Future<void> _logout() async {
    await RoutePersistence.clear();
    if (!mounted) return;
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/onboarding', (route) => false);
  }

  void _showDrawerPhotoActions() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_a_photo_outlined),
              title: const Text('New Profile Picture'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndUploadDrawerPhoto(setAsProfilePicture: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Add Photos'),
              onTap: () {
                Navigator.of(context).pop();
                _pickAndUploadDrawerPhoto(setAsProfilePicture: false);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDiscoverSidebar() async {
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Discover sidebar',
      barrierDismissible: true,
      barrierColor: Colors.black.withAlpha((0.24 * 255).round()),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.84,
              child: _DiscoverDrawer(
                profile: _currentUserProfile,
                onCopyEmail: () => _copyValue(label: 'Email', value: _currentUserProfile?.email),
                onCopyPhone: () => _copyValue(label: 'Phone number', value: _currentUserProfile?.phone),
                onOpenPhotoActions: () {
                  Navigator.of(dialogContext).pop();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _showDrawerPhotoActions();
                    }
                  });
                },
                onLogout: () async {
                  Navigator.of(dialogContext).pop();
                  await _logout();
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  Future<void> _pickAndUploadDrawerPhoto({required bool setAsProfilePicture}) async {
    final currentUser = _authService.getCurrentUser();
    if (currentUser == null) return;

    try {
      final image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;

      FocusManager.instance.primaryFocus?.unfocus();
      AppNotice.showLoading(
        context,
        setAsProfilePicture
            ? 'Uploading profile picture'
            : 'Uploading photo',
      );

      final bytes = await image.readAsBytes();
      if (!mounted) return;
      final pathParts = image.path.split(RegExp(r'[\\/]'));
      final filename =
          '${DateTime.now().millisecondsSinceEpoch}_${pathParts.isNotEmpty ? pathParts.last : 'profile.jpg'}';
      if (!mounted) return;
      final url = await _storageService.uploadProfileImage(
        bytes: bytes,
        uid: currentUser.uid,
        filename: filename,
      );

      final currentImages = _currentUserProfile?.profileImages ?? const <String>[];
      final updatedImages = [...currentImages, url];
      final data = <String, dynamic>{
        'profileImages': updatedImages,
      };
      if (setAsProfilePicture) {
        data['profilePictureUrl'] = url;
      }

      if (!mounted) return;
      await _userService.updateUser(currentUser.uid, data);
      await _loadCurrentUserProfile();
      if (!mounted) return;
      AppNotice.showSuccess(
        context,
        setAsProfilePicture
            ? 'Profile picture uploaded successfully.'
            : 'Photo successfully uploaded.',
      );
    } catch (error) {
      if (!mounted) return;
      AppNotice.showError(
        context,
        error,
        fallbackMessage: setAsProfilePicture
            ? 'Profile picture upload failed.'
            : 'Photo upload failed.',
      );
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
        builder: (context) => AlertDialog(
        title: const Text('Filters'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Gender filter
              DropdownButton<String>(
                value: _selectedGender,
                hint: const Text('Select Gender'),
                onChanged: (value) => setState(() => _selectedGender = value),
                items: const ['Male', 'Female', 'Other']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
              ),
              const SizedBox(height: 18),

              // Religion filter
              DropdownButton<String>(
                value: _selectedReligion,
                hint: const Text('Select Religion'),
                onChanged: (value) => setState(() => _selectedReligion = value),
                items: const ['Islam', 'Christianity', 'Hinduism', 'Sikhism', 'Other']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
              ),
              const SizedBox(height: 18),

              // Age range
              const Text('Age Range', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Min Age',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) =>
                          _minAge = int.tryParse(value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'Max Age',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) =>
                          _maxAge = int.tryParse(value),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryGreen,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _bloc.add(
                      LoadDiscoverProfiles(
                        gender: _selectedGender,
                        minAge: _minAge,
                        maxAge: _maxAge,
                        religion: _selectedReligion,
                      ),
                    );
                  },
                  child: const Text('Apply', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

 

// ===== Custom widgets for Discover screen =====

class _TopBar extends StatelessWidget {
  final VoidCallback onMenu;
  final VoidCallback onNotifications;
  final VoidCallback? onBoost;
  const _TopBar({required this.onMenu, required this.onNotifications, this.onBoost});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.menu_outlined),
          onPressed: onMenu,
        ),
        const Expanded(
          child: Center(
            child: Text('Qubool Nikah', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kDeepGreen)),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onBoost != null)
              IconButton(
                icon: const Icon(Icons.rocket_launch_rounded),
                tooltip: 'Get a Boost',
                onPressed: onBoost,
              ),
            Stack(
              children: [
                StreamBuilder<int>(
                  stream: FirebaseAuth.instance.currentUser == null
                      ? null
                      : NotificationService().streamUnreadCount(
                          FirebaseAuth.instance.currentUser!.uid,
                        ),
                  builder: (context, snapshot) {
                    final count = snapshot.data ?? 0;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.notifications_outlined),
                          onPressed: onNotifications,
                        ),
                        if (count > 0)
                          Positioned(
                            right: 7,
                            top: 7,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: const BoxDecoration(
                                color: Color(0xFF16A34A),
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 20,
                                minHeight: 20,
                              ),
                              child: Center(
                                child: Text(
                                  count > 99 ? '99+' : '$count',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _DiscoverDrawer extends StatelessWidget {
  final UserModel? profile;
  final VoidCallback onCopyEmail;
  final VoidCallback onCopyPhone;
  final VoidCallback onOpenPhotoActions;
  final Future<void> Function() onLogout;

  const _DiscoverDrawer({
    required this.profile,
    required this.onCopyEmail,
    required this.onCopyPhone,
    required this.onOpenPhotoActions,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final name = profile?.fullName.trim().isNotEmpty == true ? profile!.fullName : 'Member';
    final email = profile?.email?.trim().isNotEmpty == true ? profile!.email! : 'No email added';
    final phone = profile?.phone?.trim().isNotEmpty == true ? profile!.phone! : 'No phone added';
    final imageUrl = profile?.profilePictureUrl;
    final hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;
    final currentUserId = profile?.uid.isNotEmpty == true
        ? profile!.uid
        : FirebaseAuth.instance.currentUser?.uid;
    final completion = (profile?.profileCompletion ?? 0).round().clamp(0, 100);
    final location = _formatDiscoverLocation(profile?.location);
    final subtitleParts = [
      if (profile?.isVerified == true) 'Verified',
      if (location.isNotEmpty) location,
    ];

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(32),
            bottomRight: Radius.circular(32),
          ),
          child: Container(
            color: kBackgroundCream,
            height: MediaQuery.of(context).size.height,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A6241), Color(0xFF0D3F2F)],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22000000),
                      blurRadius: 24,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GestureDetector(
                              onTap: hasImage
                                  ? () => _showProfileImagePreview(
                                        context,
                                        imageUrl.trim(),
                                      )
                                  : null,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.24),
                                    width: 2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x33000000),
                                      blurRadius: 18,
                                      offset: Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: CircleAvatar(
                                  radius: 40,
                                  backgroundColor: Colors.white24,
                                  backgroundImage: hasImage
                                      ? CachedNetworkImageProvider(
                                          imageUrl.trim(),
                                        )
                                      : null,
                                  child: !hasImage
                                      ? const Icon(
                                          Icons.person,
                                          size: 38,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                            Positioned(
                              right: -4,
                              bottom: -4,
                              child: Material(
                                color: Colors.white,
                                shape: const CircleBorder(),
                                elevation: 8,
                                child: InkWell(
                                  onTap: onOpenPhotoActions,
                                  customBorder: const CircleBorder(),
                                  child: const Padding(
                                    padding: EdgeInsets.all(9),
                                    child: Icon(
                                      Icons.camera_alt_outlined,
                                      color: kDeepGreen,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (subtitleParts.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  subtitleParts.join('  -  '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.84),
                                    fontSize: 13,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
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
                        Expanded(
                          child: _DiscoverDrawerHeroStat(
                            label: 'Profile',
                            value: '$completion%',
                            helper: 'Completed',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DiscoverDrawerHeroStat(
                            label: 'Status',
                            value: profile?.isOnline == true ? 'Online' : 'Active',
                            helper: profile?.isPremium == true
                                ? 'Premium member'
                                : 'Ready to discover',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                  ),
                  const SizedBox(height: 12),
                  // Compact action grid — all items visible at a glance
                  Builder(builder: (ctx) {
                    final smallStyle = const TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
                    final subtitleStyle = const TextStyle(fontSize: 11, color: Color(0xFF6B7280));
                    Widget actionItem(IconData icon, String label, VoidCallback? onTap, {Color? color}) {
                      return InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                          ),
                          child: Row(
                            children: [
                              Icon(icon, size: 18, color: color ?? kPrimaryGreen),
                              const SizedBox(width: 10),
                              Flexible(child: Text(label, style: smallStyle, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Primary actions
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              actionItem(Icons.star_outline, 'Go Premium', () {
                                Navigator.of(ctx).pushNamed('/premium');
                              }, color: const Color(0xFFFFB020)),
                              actionItem(Icons.favorite, 'Who liked you', currentUserId == null ? null : () => _showInterestRequestsSheet(ctx, currentUserId)),
                              actionItem(Icons.bookmark, 'Saved profiles', currentUserId == null ? null : () => _showSavedProfilesSheet(ctx, currentUserId)),
                              actionItem(Icons.person_add_alt_1_outlined, 'Add guardian', () => Navigator.of(ctx).pushNamed('/add-guardian')),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        // Secondary actions
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              actionItem(Icons.settings_outlined, 'Settings', () => Navigator.of(ctx).pushNamed('/settings')),
                              actionItem(Icons.help_outline, 'Help & Support', () => Navigator.of(ctx).pushNamed('/help')),
                              actionItem(Icons.share_outlined, 'Invite friends', () => Navigator.of(ctx).pushNamed('/invite')),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        // Compact account row
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(email, style: smallStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(phone, style: subtitleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                              onPressed: onLogout,
                              tooltip: 'Logout',
                            ),
                          ],
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showInterestRequestsSheet(BuildContext context, String currentUserId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DiscoverDrawerSheet(
        title: 'Interest Requests',
        subtitle: 'People who are waiting to hear back from you.',
        child: StreamBuilder<List<InterestModel>>(
          stream: InteractionsService().getIncomingInterests(currentUserId),
          builder: (context, snapshot) {
            final requests = snapshot.data ?? const <InterestModel>[];
            if (requests.isEmpty) {
              return const _DiscoverDrawerEmptyState(
                icon: Icons.favorite_outline_rounded,
                title: 'No interest requests yet',
                subtitle: 'When someone sends interest, it will appear here.',
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: requests.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final request = requests[index];
                return FutureBuilder<UserModel?>(
                  future: _browseCachedProfileFuture(request.senderId),
                  builder: (context, profileSnapshot) {
                    final sender = profileSnapshot.data;
                    final senderName =
                        sender?.fullName.trim().isNotEmpty == true
                            ? sender!.fullName
                            : 'Member';
                    final senderPhoto = sender?.profilePictureUrl?.trim();
                    return _DiscoverDrawerProfileCard(
                      title: senderName,
                      subtitle: request.message?.trim().isNotEmpty == true
                          ? request.message!.trim()
                          : 'Sent you an interest request',
                      trailingLabel: _formatShortDate(request.sentAt),
                      imageUrl: senderPhoto,
                      onTap: sender == null
                          ? null
                          : () => Navigator.of(context).pushNamed(
                                '/view-profile',
                                arguments: sender,
                              ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showSavedProfilesSheet(BuildContext context, String currentUserId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DiscoverDrawerSheet(
        title: 'Saved Profiles',
        subtitle: 'Profiles you bookmarked to revisit later.',
        child: StreamBuilder<List<ShortlistModel>>(
          stream: InteractionsService().getShortlistedProfiles(currentUserId),
          builder: (context, snapshot) {
            final savedProfiles = snapshot.data ?? const <ShortlistModel>[];
            if (savedProfiles.isEmpty) {
              return const _DiscoverDrawerEmptyState(
                icon: Icons.bookmark_outline_rounded,
                title: 'No saved profiles yet',
                subtitle: 'Profiles you bookmark will show up here.',
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: savedProfiles.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final saved = savedProfiles[index];
                return FutureBuilder<UserModel?>(
                  future: _browseCachedProfileFuture(saved.shortlistedUserId),
                  builder: (context, profileSnapshot) {
                    final user = profileSnapshot.data;
                    final title = user?.fullName.trim().isNotEmpty == true
                        ? user!.fullName
                        : 'Saved profile';
                    final city = user?.location?['city']?.trim();
                    final subtitle = [
                      if (user?.occupation?.trim().isNotEmpty == true)
                        user!.occupation!.trim(),
                      if (city?.isNotEmpty == true) city!,
                    ].join('  -  ');
                    return _DiscoverDrawerProfileCard(
                      title: title,
                      subtitle: subtitle.isEmpty
                          ? 'Tap to view profile'
                          : subtitle,
                      trailingLabel: _formatShortDate(saved.addedAt),
                      imageUrl: user?.profilePictureUrl?.trim(),
                      onTap: user == null
                          ? null
                          : () => Navigator.of(context).pushNamed(
                                '/view-profile',
                                arguments: user,
                              ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  static String _formatShortDate(DateTime date) {
    final month = _monthLabel(date.month);
    return '$month ${date.day}';
  }

  static String _monthLabel(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  void _showProfileImagePreview(BuildContext context, String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}




class _DiscoverDrawerSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _DiscoverDrawerSheet({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        decoration: const BoxDecoration(
          color: kBackgroundCream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 46,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: kDeepGreen,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscoverDrawerProfileCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String trailingLabel;
  final String? imageUrl;
  final VoidCallback? onTap;

  const _DiscoverDrawerProfileCard({
    required this.title,
    required this.subtitle,
    required this.trailingLabel,
    this.imageUrl,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl?.isNotEmpty == true;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFE8DD),
                  borderRadius: BorderRadius.circular(18),
                  image: hasImage
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(imageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: !hasImage
                    ? const Icon(
                        Icons.person_rounded,
                        color: Colors.white70,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF171717),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trailingLabel,
                    style: const TextStyle(
                      color: Color(0xFF16A34A),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoverDrawerEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DiscoverDrawerEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6F1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: kDeepGreen, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: kDeepGreen,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF667085),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoverDrawerHeroStat extends StatelessWidget {
  final String label;
  final String value;
  final String helper;

  const _DiscoverDrawerHeroStat({
    required this.label,
    required this.value,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            helper,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}



class _EmptyProfilesState extends StatelessWidget {
  final String label;
  final VoidCallback? onReset;
  final Future<void> Function() onAdjustFilters;

  const _EmptyProfilesState({
    required this.label,
    required this.onReset,
    required this.onAdjustFilters,
  });

  @override
  Widget build(BuildContext context) {
    final message = label == 'All' ? 'No profiles found' : 'No $label found';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            if (onReset != null)
              PrimaryButton(label: 'Show All', onPressed: onReset!),
            if (onReset != null) const SizedBox(height: 12),
            PrimaryButton(label: 'Adjust Filters', onPressed: onAdjustFilters),
          ],
        ),
      ),
    );
  }
}

class _ProfileCardStack extends StatefulWidget {
  final double availableWidth;
  final double availableHeight;
  final List<UserModel> profiles;
  final Map<String, bool> likedMap;
  final Map<String, bool> shortlistedMap;
  final void Function(String) onLike;
  final void Function(String) onUnlike;
  final void Function(String) onReject;
  final void Function(String, bool) onShortlistToggle;
  final void Function(String) onView;

  const _ProfileCardStack({
    super.key,
    required this.availableWidth,
    required this.availableHeight,
    required this.profiles,
    required this.likedMap,
    required this.shortlistedMap,
    required this.onLike,
    required this.onUnlike,
    required this.onReject,
    required this.onShortlistToggle,
    required this.onView,
  });

  @override
  State<_ProfileCardStack> createState() => _ProfileCardStackState();
}

class _ProfileCardStackState extends State<_ProfileCardStack> {
  int _currentIndex = 0;
  late final PageController _pageController;
  final Set<String> _dismissedProfileIds = <String>{};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardWidth = (widget.availableWidth - 24).clamp(280.0, 460.0);
    final cardHeight = widget.availableHeight.clamp(420.0, 900.0);
    final visibleProfiles = widget.profiles
        .where((profile) => !_dismissedProfileIds.contains(profile.uid))
        .toList();

    if (visibleProfiles.isEmpty) {
      return Container(
        width: cardWidth,
        height: cardHeight,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'No more profiles in your current discover list.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kDeepGreen,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    if (_currentIndex >= visibleProfiles.length) {
      _currentIndex = visibleProfiles.length - 1;
    }

    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: PageView.builder(
        controller: _pageController,
        itemCount: visibleProfiles.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          final item = visibleProfiles[index];
          final isLiked = widget.likedMap[item.uid] ?? false;
          final isShortlisted = widget.shortlistedMap[item.uid] ?? false;
          return _ProfileCardLarge(
            key: ValueKey(item.uid),
            profile: item,
            isLiked: isLiked,
            isShortlisted: isShortlisted,
            onLike: () {
              if (isLiked) {
                widget.onUnlike(item.uid);
              } else {
                widget.onLike(item.uid);
              }
            },
            onReject: () {
              if (isLiked) {
                widget.onReject(item.uid);
              }
              setState(() {
                _dismissedProfileIds.add(item.uid);
                if (_currentIndex >= visibleProfiles.length - 1) {
                  _currentIndex = ((_currentIndex - 1)
                          .clamp(0, visibleProfiles.length - 1))
                      .toInt();
                }
              });
            },
            onShortlistToggle: () =>
                widget.onShortlistToggle(item.uid, isShortlisted),
            onView: () => widget.onView(item.uid),
          );
        },
      ),
    );
  }

}

class _ProfileCardLarge extends StatefulWidget {
  final UserModel profile;
  final bool isLiked;
  final bool isShortlisted;
  final VoidCallback onLike;
  final VoidCallback onReject;
  final VoidCallback onShortlistToggle;
  final VoidCallback onView;

  const _ProfileCardLarge({
    super.key,
    required this.profile,
    required this.isLiked,
    required this.isShortlisted,
    required this.onLike,
    required this.onReject,
    required this.onShortlistToggle,
    required this.onView,
  });

  @override
  State<_ProfileCardLarge> createState() => _ProfileCardLargeState();
}

class _ProfileCardLargeState extends State<_ProfileCardLarge> {
  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final age = profile.dateOfBirth != null
        ? DateTime.now().year - profile.dateOfBirth!.year
        : null;
    final location = _formatDiscoverLocation(profile.location);
    final identitySummary = [
      if (age != null) '$age yrs',
      if (location.isNotEmpty) location,
    ].join('  •  ');
    final heightLabel = ValidationService.formatHeight(profile.height, profile.heightUnit);
    final identityPills = <Widget>[
      if (heightLabel != null)
        _DiscoverDetailPill(
          icon: Icons.height_rounded,
          label: heightLabel,
        ),
    ];
    if ((profile.religion ?? '').trim().isNotEmpty) {
      identityPills.add(
        _DiscoverDetailPill(
          icon: Icons.mosque_outlined,
          label: profile.religion!.trim(),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (profile.profilePictureUrl != null &&
                    profile.profilePictureUrl!.trim().isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: profile.profilePictureUrl!.trim(),
                    fit: BoxFit.cover,
                    placeholder: (c, s) => Container(color: Colors.grey[300]),
                    errorWidget: (c, s, e) => Container(
                      color: const Color(0xFFE5E7EB),
                      child: const Icon(Icons.person, size: 72, color: Colors.white54),
                    ),
                  )
                else
                  Container(
                    color: const Color(0xFFE5E7EB),
                    child: const Icon(Icons.person, size: 84, color: Colors.white54),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.10),
                          Colors.black.withValues(alpha: 0.36),
                        ],
                        stops: const [0.0, 0.58, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onView,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: _DiscoverInlineCancelButton(
                    onTap: widget.onReject,
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: _DiscoverBookmarkButton(
                    isSaved: widget.isShortlisted,
                    onTap: widget.onShortlistToggle,
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    decoration: BoxDecoration(
                      color: Color.fromRGBO(11, 31, 23, 0.58),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Color.fromRGBO(255, 255, 255, 0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          profile.fullName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.4,
                                          ),
                                        ),
                                      ),
                                      if (profile.isVerified) ...[
                                        const SizedBox(width: 8),
                                        const _DiscoverVerifiedBadge(),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          identitySummary.isNotEmpty
                                              ? identitySummary
                                              : 'Location not shared yet',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFE5ECE8),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (DateTime.now().difference(profile.createdAt.toDate()).inHours < 24) ...[
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF0D9),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'New',
                                  style: TextStyle(
                                    color: Color(0xFFAA5A00),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: BoxDecoration(
                            color: Color.fromRGBO(255, 255, 255, 0.10),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Color.fromRGBO(255, 255, 255, 0.12),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (identityPills.isNotEmpty) ...[
                                for (var index = 0;
                                    index < identityPills.length;
                                    index++) ...[
                                  Expanded(child: identityPills[index]),
                                  if (index != identityPills.length - 1)
                                    const SizedBox(width: 8),
                                ],
                                const SizedBox(width: 8),
                              ],
                              _DiscoverInlineHeartButton(
                                isLiked: widget.isLiked,
                                onTap: widget.onLike,
                              ),
                            ],
                          ),
                        ),
                      ],
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
}

// ignore: unused_element
class _ActionButtons extends StatelessWidget {
  final VoidCallback onReject;
  final VoidCallback onLikeToggle;
  final VoidCallback onSuperToggle;
  final bool isLiked;
  final bool isShortlisted;

  const _ActionButtons({required this.onReject, required this.onLikeToggle, required this.onSuperToggle, required this.isLiked, required this.isShortlisted});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reject (X) — cancels/unlikes
        _CircleButton(icon: Icons.close, color: Colors.orange.shade400, size: 56, onPressed: onReject),
        const SizedBox(width: 20),
        // Like (heart) — toggles like; when liked: white icon on red bg
        Material(
          shape: const CircleBorder(),
          elevation: 6,
          color: isLiked ? Colors.red : Colors.white,
          child: InkWell(
            onTap: onLikeToggle,
            customBorder: const CircleBorder(),
            child: Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              child: Icon(Icons.favorite, color: isLiked ? Colors.white : Colors.redAccent, size: 32),
            ),
          ),
        ),
        const SizedBox(width: 20),
        // Super/Save (star) — toggles shortlist; when active: white icon on amber bg
        Material(
          shape: const CircleBorder(),
          elevation: 6,
          color: isShortlisted ? Colors.amber.shade700 : Colors.white,
          child: InkWell(
            onTap: onSuperToggle,
            customBorder: const CircleBorder(),
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              child: Icon(Icons.star, color: isShortlisted ? Colors.white : Colors.amber.shade700, size: 24),
            ),
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onPressed;
  const _CircleButton({required this.icon, required this.color, required this.size, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: const CircleBorder(),
      elevation: 6,
      color: Colors.white,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Icon(icon, color: color, size: size * 0.45),
        ),
      ),
    );
  }
}

class _DiscoverVerifiedBadge extends StatelessWidget {
  const _DiscoverVerifiedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFFE6F6EB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Icon(
        Icons.verified_rounded,
        color: kPrimaryGreen,
        size: 18,
      ),
    );
  }
}

class _DiscoverInlineHeartButton extends StatelessWidget {
  final bool isLiked;
  final VoidCallback onTap;

  const _DiscoverInlineHeartButton({
    required this.isLiked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isLiked ? const Color(0xFFE54D5E) : Colors.white,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: isLiked ? Colors.white : const Color(0xFFE54D5E),
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _DiscoverInlineCancelButton extends StatelessWidget {
  final VoidCallback onTap;

  const _DiscoverInlineCancelButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            Icons.close_rounded,
            color: Color(0xFFAD5E34),
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _DiscoverBookmarkButton extends StatelessWidget {
  final bool isSaved;
  final VoidCallback onTap;

  const _DiscoverBookmarkButton({
    required this.isSaved,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSaved
          ? const Color(0xFF0F5C2E)
          : Color.fromRGBO(255, 255, 255, 0.92),
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: isSaved ? Colors.white : kDeepGreen,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _DiscoverDetailPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DiscoverDetailPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE6E0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: kAccentGreen),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kDeepGreen,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDiscoverLocation(Map<String, String>? location) {
  if (location == null) {
    return '';
  }
  final parts = [
    location['city']?.trim(),
    location['state']?.trim(),
    location['country']?.trim(),
  ].where((part) => part != null && part.isNotEmpty).cast<String>().toList();
  return parts.join(', ');
}



class _DiscoverBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;
  const _DiscoverBottomNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      // sit flush to bottom; SafeArea(bottom: false) is used by parent
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _NavItem(index: 0, active: currentIndex == 0, icon: Icons.search, label: 'Discover', onTap: onTap),
          _NavItem(index: 1, active: currentIndex == 1, icon: Icons.favorite_border, label: 'Matches', onTap: onTap),
          _NavItem(index: 2, active: currentIndex == 2, icon: Icons.chat_bubble_outline, label: 'Chats', onTap: onTap),
          _NavItem(index: 3, active: currentIndex == 3, icon: Icons.person_outline, label: 'Profile', onTap: onTap),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final bool active;
  final IconData icon;
  final String label;
  final void Function(int) onTap;

  const _NavItem({required this.index, required this.active, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: active ? kPrimaryGreen : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: active ? Colors.white : Colors.grey[700], size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: active ? kDeepGreen : Colors.grey[600],
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}




