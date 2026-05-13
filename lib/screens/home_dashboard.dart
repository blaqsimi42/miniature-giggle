import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/chat_access_service.dart';
import '../services/chat_service.dart';
import '../services/interactions_service.dart';
import '../services/profile_completion_gate_service.dart';
import '../services/notification_service.dart';
import '../services/route_persistence.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../widgets/presence_avatar.dart';
import '../core/config/service_locator.dart';
import '../services/premium_service.dart';
import 'browse_profiles_screen.dart';
import 'current_user_screen.dart';
import 'matches_screen.dart';
import '../widgets/upgrade_flow.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_form.dart';
import '../widgets/app_notice.dart';
import '../widgets/chat_options_sheet.dart';
import '../widgets/image_cropper_screen.dart';
import '../core/utils/validation_service.dart';
import '../core/utils/currency_formatter.dart';

// --- ARCHITECTURE: AppBreakpoints ---
class AppBreakpoints {
  static const double mobile = 600;
}

const Color _kChatGreen = Color(0xFF0A5C36);
const Color _kChatGreenSoft = Color(0xFFE8F5EC);
const Color _kChatCream = Color(0xFFFFFBF5);
const Color _kChatSurface = Colors.white;
const Color _kChatMuted = Color(0xFF7D7D7D);
const Color _kChatBorder = Color(0xFFEDE4D8);
const Color _kChatWarmCard = Color(0xFFFFF4E7);
const Color _kChatWarmBorder = Color(0xFFF2E3CC);
const Color _kChatBgTop = Color(0xFFFBF7F0);
const Color _kChatBgBottom = Color(0xFFF5F8F2);

// Lightweight in-file cache to dedupe concurrent profile fetches from UI builders
final UserService _homeUserService = UserService();
final Map<String, Future<UserModel?>> _homeProfileFutures = {};

Future<UserModel?> _homeCachedProfileFuture(String uid) {
  if (uid.trim().isEmpty) return Future.value(null);
  return _homeProfileFutures.putIfAbsent(uid, () => _homeUserService.getUser(uid));
}

// --- ARCHITECTURE: MatchRepository ---
class MatchRepository {
  static List<Map<String, dynamic>> getMockMatches() => List.generate(
    6,
    (i) => {
      'name': ['Amina', 'Sara', 'Hassan', 'Bilal', 'Noor', 'Khalid'][i % 6],
      'age': {0: 27, 1: 25, 2: 30, 3: 28, 4: 26, 5: 31}[i],
      'location': [
        'Lahore',
        'Karachi',
        'Islamabad',
        'Multan',
        'Faisalabad',
        'Peshawar',
      ][i % 6],
      'score': (70 + i * 4),
    },
  );
}

class DashboardActivitySummary {
  final int likes;
  final int matches;
  final int chats;

  const DashboardActivitySummary({
    required this.likes,
    required this.matches,
    required this.chats,
  });

  const DashboardActivitySummary.empty() : likes = 0, matches = 0, chats = 0;
}

int _extractIncomingLikesCount(Map<String, dynamic>? data) {
  if (data == null) {
    return 0;
  }

  for (final value in [
    data['likesCount'],
    data['likesReceivedCount'],
    data['receivedLikesCount'],
    data['totalLikes'],
  ]) {
    if (value is num) {
      return value.toInt();
    }
  }

  for (final value in [
    data['likes'],
    data['likedBy'],
    data['likesReceived'],
    data['receivedLikes'],
  ]) {
    if (value is List) {
      return value.length;
    }
  }

  return 0;
}

class ActivitySummaryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<DashboardActivitySummary> watchSummary(String userId) {
    final controller = StreamController<DashboardActivitySummary>();
    var current = const DashboardActivitySummary.empty();

    void emit({int? likes, int? matches, int? chats}) {
      current = DashboardActivitySummary(
        likes: likes ?? current.likes,
        matches: matches ?? current.matches,
        chats: chats ?? current.chats,
      );
      if (!controller.isClosed) controller.add(current);
    }

    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? likesSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? chatsSub;
    Timer? matchesPoll;

    try {
      // Likes: listen to a user-level summary doc if it exists; otherwise skip.
      likesSub = _firestore.collection('users').doc(userId).snapshots().listen((snap) {
        try {
          final data = snap.data();
          final likes = _extractIncomingLikesCount(data);
          emit(likes: likes);
        } catch (e) {
          controller.addError(e);
        }
      }, onError: (e) => controller.addError(e));

      // Chats: subscribe to chats involving the user and count documents
      chatsSub = _firestore
          .collection('chats')
          .where('participants', arrayContains: userId)
          .snapshots()
          .listen((snapshot) {
        try {
          emit(chats: snapshot.docs.length);
        } catch (e) {
          controller.addError(e);
        }
      }, onError: (e) => controller.addError(e));

      // Matches: poll users collection periodically and count other users
      Future<void> fetchMatches() async {
        try {
          final snap = await _firestore.collection('users').get();
          emit(matches: snap.docs.where((doc) => doc.id != userId).length);
        } catch (e) {
          controller.addError(e);
        }
      }

      fetchMatches();
      matchesPoll = Timer.periodic(const Duration(seconds: 30), (_) => fetchMatches());
    } catch (e) {
      controller.addError(e);
      Future.microtask(() => controller.close());
      return controller.stream;
    }

    controller.onCancel = () async {
      try {
        await likesSub?.cancel();
      } catch (_) {}
      try {
        matchesPoll?.cancel();
      } catch (_) {}
      try {
        await chatsSub?.cancel();
      } catch (_) {}
    };

    return controller.stream;
  }

  // _extractLikesCount was a thin wrapper and is no longer needed.
}

// --- ARCHITECTURE: UserDashboardController ---
class UserDashboardController extends ChangeNotifier {
  UserModel? profile;
  bool loadingProfile = true;
  bool savingProfile = false;
  bool firestoreUnavailable = false;
  static const int _profileLoadAttempts = 6;
  static const Duration _profileLoadRetryDelay = Duration(milliseconds: 350);

  // Apply a local profile update and notify listeners (safe public method)
  void applyLocalProfile(UserModel p) {
    profile = p;
    notifyListeners();
  }

  void seedProfileFromAuth({
    required String fallbackName,
  }) {
    final currentUser = AuthService().getCurrentUser();
    if (currentUser == null) {
      return;
    }

    final displayName = (currentUser.displayName ?? '').trim();
    final email = (currentUser.email ?? '').trim();
    final phone = (currentUser.phoneNumber ?? '').trim();
    final resolvedName = displayName.isNotEmpty
        ? displayName
        : fallbackName.trim().isNotEmpty
            ? fallbackName.trim()
            : email.isNotEmpty
                ? email.split('@').first
                : 'User';

    profile = _mergeProfileData(
      existing: profile,
      incoming: UserModel(
        uid: currentUser.uid,
        fullName: resolvedName,
        email: email.isEmpty ? null : email,
        phone: phone.isEmpty ? null : phone,
        profilePictureUrl: currentUser.photoURL,
      ),
      fallbackName: resolvedName,
      authPhotoUrl: currentUser.photoURL,
    );
    notifyListeners();
  }

  UserModel _mergeProfileData({
    required UserModel? existing,
    required UserModel? incoming,
    required String fallbackName,
    required String? authPhotoUrl,
  }) {
    final resolvedName = (incoming?.fullName ?? '').trim().isNotEmpty
        ? incoming!.fullName
        : (existing?.fullName ?? '').trim().isNotEmpty
            ? existing!.fullName
            : fallbackName;

    final resolvedEmail = (incoming?.email ?? '').trim().isNotEmpty
        ? incoming!.email
        : existing?.email;
    final resolvedPhone = (incoming?.phone ?? '').trim().isNotEmpty
        ? incoming!.phone
        : existing?.phone;
    final resolvedPhoto = (incoming?.profilePictureUrl ?? '').trim().isNotEmpty
        ? incoming!.profilePictureUrl
        : (existing?.profilePictureUrl ?? '').trim().isNotEmpty
            ? existing!.profilePictureUrl
            : authPhotoUrl;

    final mergedMap = <String, dynamic>{
      ...?existing?.toMap(),
      ...?incoming?.toMap(),
      'uid': incoming?.uid ?? existing?.uid ?? '',
      'fullName': resolvedName,
      'email': resolvedEmail,
      'phone': resolvedPhone,
      'profilePictureUrl': resolvedPhoto,
      'profilePhotoUrl':
          (incoming?.profilePhotoUrl ?? '').trim().isNotEmpty
              ? incoming!.profilePhotoUrl
              : (existing?.profilePhotoUrl ?? '').trim().isNotEmpty
                  ? existing!.profilePhotoUrl
                  : resolvedPhoto,
    };

    return UserModel.fromMaps(mergedMap);
  }

  Future<void> loadProfile() async {
    final u = AuthService().getCurrentUser();
    if (u == null) {
      loadingProfile = false;
      notifyListeners();
      return;
    }

    loadingProfile = true;
    notifyListeners();

    try {
      UserModel? p;
      for (var attempt = 0; attempt < _profileLoadAttempts; attempt++) {
        p = await _homeCachedProfileFuture(u.uid);
        if (p != null) {
          break;
        }
        if (attempt < _profileLoadAttempts - 1) {
          await Future.delayed(_profileLoadRetryDelay);
        }
      }
      profile = _mergeProfileData(
        existing: profile,
        incoming: p,
        fallbackName: profile?.fullName ?? u.displayName ?? 'User',
        authPhotoUrl: u.photoURL,
      );
      loadingProfile = false;
      firestoreUnavailable = false;
      notifyListeners();
    } catch (_) {
      loadingProfile = false;
      firestoreUnavailable = true;
      notifyListeners();
    }
  }

  void dismissFirestoreError() {
    firestoreUnavailable = false;
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    final user = AuthService().getCurrentUser();
    if (user == null) {
      throw StateError('No signed-in user found.');
    }

    savingProfile = true;
    notifyListeners();
    try {
      await UserService().updateUser(user.uid, data);
      firestoreUnavailable = false;
      await loadProfile();
    } catch (_) {
      firestoreUnavailable = true;
      rethrow;
    } finally {
      savingProfile = false;
      notifyListeners();
    }
  }
}

void main() {
  const bool isAdmin = false; // set to true to preview Admin dashboard
  runApp(const DashboardDemoApp(isAdmin: isAdmin));
}

class DashboardDemoApp extends StatelessWidget {
  final bool isAdmin;
  const DashboardDemoApp({super.key, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Qubool Nikah Dashboard',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: HomeScreen(isAdmin: isAdmin, userName: 'Aisha'),
    );
  }
}

class HomeScreen extends StatelessWidget {
  final bool isAdmin;
  final String userName;
  const HomeScreen({super.key, required this.isAdmin, required this.userName});

  @override
  Widget build(BuildContext context) {
    return isAdmin
        ? AdminHomeScreen(userName: userName)
        : UserHomeScreen(userName: userName);
  }
}

class ChatLaunchTarget {
  final String uid;
  final String displayName;
  final String? photoUrl;

  const ChatLaunchTarget({
    required this.uid,
    required this.displayName,
    this.photoUrl,
  });
}

// ------------------------- Admin Dashboard -------------------------

class AdminHomeScreen extends StatefulWidget {
  final String userName;
  const AdminHomeScreen({super.key, required this.userName});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Qubool Nikah'),
        centerTitle: true,
        actions: [
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
                    icon: const Icon(Icons.notifications_none),
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/notifications'),
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
                          color: kPrimaryGreen,
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
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Platform Overview',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount:
                  MediaQuery.of(context).size.width > AppBreakpoints.mobile
                  ? 4
                  : 2,
              shrinkWrap: true,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.8,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                StatCard(
                  title: 'Total Users',
                  value: '12,430',
                  accent: Colors.green,
                  icon: Icons.people,
                ),
                StatCard(
                  title: 'Active Now',
                  value: '1,203',
                  badge: 'Live',
                  accent: Colors.teal,
                  icon: Icons.circle,
                ),
                StatCard(
                  title: 'Revenue',
                  value: CurrencyFormatter.format(23400),
                  accent: Colors.indigo,
                  icon: Icons.attach_money,
                ),
                StatCard(
                  title: 'Pending Reports',
                  value: '12',
                  badge: 'Urgent',
                  accent: Colors.orange,
                  icon: Icons.flag,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Weekly Growth',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Placeholder for a growth chart (could be replaced with a real chart widget)
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.shadow.withValues(
                                alpha: 0.06,
                              ),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.show_chart,
                            size: 56,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: QuickActionButton(
                              icon: Icons.person_add,
                              label: 'Add User',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: QuickActionButton(
                              icon: Icons.campaign,
                              label: 'Send Alert',
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: QuickActionButton(
                              icon: Icons.download,
                              label: 'Export Data',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const SystemHealthCard(),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: const [
                      Text(
                        'Recent Verification Activity',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 12),
                      UserActivityTile(
                        name: 'Zain',
                        action: 'Verified ID',
                        time: '2m ago',
                      ),
                      UserActivityTile(
                        name: 'Fatima',
                        action: 'Uploaded docs',
                        time: '12m ago',
                      ),
                      UserActivityTile(
                        name: 'Omar',
                        action: 'Reported profile',
                        time: '1h ago',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------- User Dashboard -------------------------

class UserHomeScreen extends StatefulWidget {
  final String userName;
  final int initialIndex;
  final ChatLaunchTarget? initialChatTarget;

  const UserHomeScreen({
    super.key,
    required this.userName,
    this.initialIndex = 0,
    this.initialChatTarget,
  });

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen>
    with WidgetsBindingObserver {
  late int _selectedIndex;
  late final UserDashboardController _controller;
  final GlobalKey<_ChatsTabState> _chatsTabKey = GlobalKey<_ChatsTabState>();
  DateTime? _lastBackPressAt;
  bool _showBottomNav = true;
  bool _isChatThreadOpen = false;
  
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  
  Timer? _presenceHeartbeat;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedIndex = widget.initialIndex;
    _controller = UserDashboardController();
    
    _controller.addListener(_onControllerChanged);
    _controller.seedProfileFromAuth(fallbackName: widget.userName);
    _controller.loadProfile();
    _updatePresence(isOnline: true);
    _startPresenceHeartbeat();
  }

  @override
  void dispose() {
    _presenceHeartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (!kIsWeb) {
      _updatePresence(isOnline: false);
    }
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) {
      return;
    }
    final isOnline = state == AppLifecycleState.resumed;
    if (isOnline) {
      _startPresenceHeartbeat();
    } else {
      _presenceHeartbeat?.cancel();
    }
    _updatePresence(isOnline: isOnline);
  }

  void _onControllerChanged() {
    if (_controller.firestoreUnavailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _scaffoldKey.currentContext;
        if (ctx != null) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text(
                'Offline: cannot reach Firestore. Check browser extensions or network.',
              ),
            ),
          );
        }
      });
    }
    setState(() {});
  }

  Future<void> _logout() async {
    try {
      await RoutePersistence.clear();
      if (!mounted) return;
      await _updatePresence(isOnline: false);
      await AuthService().logout();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil('/onboarding', (route) => false);
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(context, e, fallbackMessage: 'Could not log out.');
    }
  }

  Future<void> _updatePresence({required bool isOnline}) async {
    if (kIsWeb) {
      return;
    }
    final currentUser = AuthService().getCurrentUser();
    if (currentUser == null) {
      return;
    }

    try {
      await UserService().updatePresence(
        currentUser.uid,
        isOnline: isOnline,
        lastSeenAt: Timestamp.now(),
      );
    } catch (e) {
      // ignore: avoid_print
      print('[DEBUG presence] _updatePresence failed: $e');
    }
  }

  void _startPresenceHeartbeat() {
    if (kIsWeb) {
      return;
    }
    _presenceHeartbeat?.cancel();
    _presenceHeartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      _updatePresence(isOnline: true);
    });
  }
  List<Widget> get _userBodies => [
    BrowseProfilesScreen(
      onNavTap: (i) {
        setState(() => _selectedIndex = i);
      },
      showBottomNav: false,
    ),
    const _MatchesTab(),
    _ChatsTab(
      key: _chatsTabKey,
      initialChatTarget: widget.initialChatTarget,
      onThreadVisibilityChanged: _handleChatThreadVisibilityChanged,
    ),
    CurrentUserScreen(
      controller: _controller,
      fallbackName: widget.userName,
      onBack: () => setState(() => _selectedIndex = 0),
    ),
  ];

  PreferredSizeWidget _buildAppBar() {
    // For non-Home tabs show a compact app bar with back navigation and title.
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => setState(() => _selectedIndex = 0),
      ),
      title: Text(_tabTitleForIndex(_selectedIndex)),
      actions: _selectedIndex == 3
          ? [
              TextButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.power_settings_new),
                label: const Text('Logout'),
              ),
            ]
          : null,
    );
  }

  String _tabTitleForIndex(int index) {
    switch (index) {
      case 1:
        return 'Matches';
      case 2:
        return 'Chats';
      case 3:
        return 'Account';
      default:
        return 'Home';
    }
  }

  void _handleBottomNavTap(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
      _showBottomNav = true;
    });
  }

  void _handleChatThreadVisibilityChanged(bool isOpen) {
    _isChatThreadOpen = isOpen;
    if (_selectedIndex != 2) return;
    final shouldShow = !isOpen;
    if (_showBottomNav == shouldShow) return;
    setState(() => _showBottomNav = shouldShow);
  }

  bool _handleRootBackPress() {
    if (_selectedIndex == 2 &&
        (_chatsTabKey.currentState?.handleBackPressed() ?? false)) {
      return false;
    }

    if (_selectedIndex != 0) {
      setState(() {
        _selectedIndex = 0;
        _showBottomNav = true;
      });
      return false;
    }

    final now = DateTime.now();
    final shouldExit = _lastBackPressAt != null &&
        now.difference(_lastBackPressAt!) <= const Duration(seconds: 2);
    if (shouldExit) {
      return true;
    }

    _lastBackPressAt = now;
    AppNotice.showSuccess(
      context,
      'Press back again to exit',
      duration: const Duration(seconds: 2),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final canPop = _selectedIndex == 0;
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleRootBackPress();
      },
      child: Scaffold(
        key: _scaffoldKey,
        extendBody: true,
        resizeToAvoidBottomInset: false,
        appBar: (_selectedIndex == 0 ||
                _selectedIndex == 3 ||
                (_selectedIndex == 2 && _isChatThreadOpen))
            ? null
            : _buildAppBar(),
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: IndexedStack(index: _selectedIndex, children: _userBodies),
        ),
        bottomNavigationBar: (_selectedIndex == 2 && _isChatThreadOpen)
            ? null
            : Container(
                color: Colors.transparent,
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    offset:
                        _showBottomNav ? Offset.zero : const Offset(0, 1.4),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _showBottomNav ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !_showBottomNav,
                        child: _HomeBottomNavBar(
                          currentIndex: _selectedIndex,
                          onTap: _handleBottomNavTap,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _HomeBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _HomeBottomNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _HomeNavItem(
            index: 0,
            icon: Icons.travel_explore,
            label: 'Discover',
            active: currentIndex == 0,
            onTap: onTap,
          ),
          _HomeNavItem(
            index: 1,
            icon: Icons.search,
            label: 'Search',
            active: currentIndex == 1,
            onTap: onTap,
          ),
          _HomeNavItem(
            index: 2,
            icon: Icons.chat_bubble_outline,
            label: 'Chats',
            active: currentIndex == 2,
            onTap: onTap,
            badgeCountStream: currentUserId == null
                ? null
                : ChatService().streamUnreadMessageCount(currentUserId),
          ),
          _HomeNavItem(
            index: 3,
            icon: Icons.person_outline,
            label: 'Profile',
            active: currentIndex == 3,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _HomeNavItem extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final bool active;
  final ValueChanged<int>? onTap;
  final Stream<int>? badgeCountStream;

  const _HomeNavItem({
    required this.index,
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
    this.badgeCountStream,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap == null ? null : () => onTap!(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFE8F4EB) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<int>(
                stream: badgeCountStream,
                builder: (context, snapshot) {
                  final unreadCount = snapshot.data ?? 0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        icon,
                        color: active
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF667085),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: -12,
                          top: -8,
                          child: _UnreadBadge(count: unreadCount),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? const Color(0xFF0F3D2E) : const Color(0xFF667085),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchesTab extends StatefulWidget {
  const _MatchesTab();

  @override
  State<_MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends State<_MatchesTab> {
  _MatchesFilterState _filters = const _MatchesFilterState();

  // ignore: unused_element
  Future<void> _openFilters() async {
    final nextFilters = await showModalBottomSheet<_MatchesFilterState>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MatchesFilterSheet(initialFilters: _filters),
    );
    if (nextFilters != null) {
      setState(() => _filters = nextFilters);
    }
  }

  // ignore: unused_element
  void _removeFilterChip(_MatchesFilterChip chip) {
    setState(() {
      switch (chip.type) {
        case _MatchesFilterChipType.age:
          _filters = _filters.copyWith(clearAgeRange: true);
          break;
        case _MatchesFilterChipType.height:
          _filters = _filters.copyWith(clearHeightRange: true);
          break;
        case _MatchesFilterChipType.occupation:
          _filters = _filters.copyWith(occupationQuery: '');
          break;
        case _MatchesFilterChipType.hobby:
          final hobbies = Set<String>.from(_filters.selectedHobbies)..remove(chip.value);
          _filters = _filters.copyWith(selectedHobbies: hobbies);
          break;
      }
    });
  }

  // ignore: unused_element
  bool _matchesFilter(UserModel user) {
    final age = user.dateOfBirth == null ? null : _calculateAge(user.dateOfBirth!);
    final normalizedOccupation = (user.occupation ?? '').trim().toLowerCase();
    final normalizedQuery = _filters.occupationQuery.trim().toLowerCase();
    final hobbies = (user.hobbies ?? const <String>[])
        .map((hobby) => hobby.trim().toLowerCase())
        .toSet();

    if (_filters.minAge != null && (age == null || age < _filters.minAge!)) {
      return false;
    }
    if (_filters.maxAge != null && (age == null || age > _filters.maxAge!)) {
      return false;
    }
    if (_filters.minHeight != null &&
        (user.height == null || user.height! < _filters.minHeight!)) {
      return false;
    }
    if (_filters.maxHeight != null &&
        (user.height == null || user.height! > _filters.maxHeight!)) {
      return false;
    }
    if (normalizedQuery.isNotEmpty && !normalizedOccupation.contains(normalizedQuery)) {
      return false;
    }
    if (_filters.selectedHobbies.isNotEmpty &&
        !_filters.selectedHobbies.every(
          (hobby) => hobbies.contains(hobby.toLowerCase()),
        )) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService().getCurrentUser();
    if (currentUser == null) {
      return const _MatchesEmptyState(
        icon: Icons.favorite_border_rounded,
        title: 'Sign in to view matches',
        message: 'Your likes, incoming admirers, and mutual matches will appear here.',
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kChatBgTop, _kChatBgBottom],
        ),
      ),
      child: const MatchesScreen(embedOnly: true),
    );
  }
}

// ignore: unused_element
class _MatchesSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emptyMessage;
  final List<String> userIds;
  final _MatchesFilterState filters;
  final bool Function(UserModel user) userMatchesFilter;

  const _MatchesSection({
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.userIds,
    required this.filters,
    required this.userMatchesFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kChatBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(color: _kChatMuted, height: 1.35),
          ),
          const SizedBox(height: 14),
          if (userIds.isEmpty)
            Text(
              emptyMessage,
              style: const TextStyle(color: _kChatMuted, height: 1.4),
            )
          else
            FutureBuilder<List<UserModel>>(
              future: _loadMatchedUsers(userIds),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _MatchesLoadingList();
                }

                final users = (snapshot.data ?? const <UserModel>[])
                    .where(userMatchesFilter)
                    .toList();

                if (users.isEmpty) {
                  return Text(
                    filters.hasActiveFilters
                        ? 'No profiles in this section match your current filters.'
                        : emptyMessage,
                    style: const TextStyle(color: _kChatMuted, height: 1.4),
                  );
                }

                return Column(
                  children: [
                    for (var i = 0; i < users.length; i++) ...[
                      _MatchedUserTile(user: users[i]),
                      if (i != users.length - 1) const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _MatchedUserTile extends StatelessWidget {
  final UserModel user;

  const _MatchedUserTile({required this.user});

  @override
  Widget build(BuildContext context) {
    final age = user.dateOfBirth == null ? null : _calculateAge(user.dateOfBirth!);
    final subtitleParts = <String>[
      if (user.occupation?.trim().isNotEmpty == true) user.occupation!.trim(),
      if (age != null) '$age yrs',
    ];
    final hasImage = user.profilePictureUrl?.trim().isNotEmpty == true;
    final heightLabel = _formatMatchHeight(user.height, user.heightUnit);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFFFF8EE)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFEADFCC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: hasImage
                      ? Image.network(
                          user.profilePictureUrl!.trim(),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _MatchesPhotoFallback(name: user.fullName);
                          },
                        )
                      : _MatchesPhotoFallback(name: user.fullName),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.fullName.trim().isEmpty ? 'Member' : user.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEEF0),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.favorite_rounded,
                                color: Color(0xFFE56363),
                                size: 14,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Match',
                                style: TextStyle(
                                  color: Color(0xFFCC4B5A),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitleParts.isEmpty
                          ? 'Profile details coming soon'
                          : subtitleParts.join(' | '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kChatMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (heightLabel != null)
                          _MatchMetaPill(icon: Icons.height_rounded, label: heightLabel),
                        if ((user.hobbies ?? const <String>[]).isNotEmpty)
                          _MatchMetaPill(
                            icon: Icons.interests_outlined,
                            label: user.hobbies!.first,
                          ),
                        _MatchMetaPill(
                          icon: Icons.verified_user_outlined,
                          label: user.isVerified ? 'Verified member' : 'Active profile',
                          accent: _kChatGreen,
                          background: const Color(0xFFF4F8F4),
                          borderColor: const Color(0xFFD7E8DA),
                        ),
                      ],
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

// ignore: unused_element
class _MatchesFilterHeader extends StatelessWidget {
  final _MatchesFilterState filters;
  final VoidCallback onOpenFilters;
  final ValueChanged<_MatchesFilterChip> onRemoveFilter;

  const _MatchesFilterHeader({
    required this.filters,
    required this.onOpenFilters,
    required this.onRemoveFilter,
  });

  @override
  Widget build(BuildContext context) {
    final chips = filters.toChips();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _kChatBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Refine your matches',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      chips.isEmpty
                          ? 'Filter by age, height, occupation, or hobbies.'
                          : '${chips.length} filter${chips.length == 1 ? '' : 's'} active',
                      style: const TextStyle(color: _kChatMuted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onOpenFilters,
                style: FilledButton.styleFrom(
                  backgroundColor: _kChatGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Filters'),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in chips)
                  InputChip(
                    label: Text(chip.label),
                    onDeleted: () => onRemoveFilter(chip),
                    deleteIconColor: _kChatGreen,
                    backgroundColor: const Color(0xFFF4F8F4),
                    side: const BorderSide(color: Color(0xFFD7E8DA)),
                    labelStyle: const TextStyle(
                      color: _kChatGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MatchesLoadingList extends StatelessWidget {
  const _MatchesLoadingList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _MatchesLoadingCard(),
        SizedBox(height: 12),
        _MatchesLoadingCard(),
      ],
    );
  }
}

class _MatchesLoadingCard extends StatelessWidget {
  const _MatchesLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _kChatBorder),
      ),
      child: const Row(
        children: [
          CircleAvatar(radius: 28, child: Icon(Icons.person_outline)),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 110,
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                ),
                SizedBox(height: 10),
                SizedBox(
                  width: 150,
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final Color background;
  final Color borderColor;

  const _MatchMetaPill({
    required this.icon,
    required this.label,
    this.accent = const Color(0xFF8A6A38),
    this.background = const Color(0xFFFFF4E7),
    this.borderColor = const Color(0xFFF2E3CC),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _MatchesFilterSheet extends StatefulWidget {
  final _MatchesFilterState initialFilters;

  const _MatchesFilterSheet({required this.initialFilters});

  @override
  State<_MatchesFilterSheet> createState() => _MatchesFilterSheetState();
}

class _MatchesFilterSheetState extends State<_MatchesFilterSheet> {
  late final TextEditingController _minAgeController;
  late final TextEditingController _maxAgeController;
  late final TextEditingController _minHeightController;
  late final TextEditingController _maxHeightController;
  late final TextEditingController _occupationController;
  late final TextEditingController _hobbyController;
  late Set<String> _selectedHobbies;

  @override
  void initState() {
    super.initState();
    _minAgeController = TextEditingController(
      text: widget.initialFilters.minAge?.toString() ?? '',
    );
    _maxAgeController = TextEditingController(
      text: widget.initialFilters.maxAge?.toString() ?? '',
    );
    _minHeightController = TextEditingController(
      text: widget.initialFilters.minHeight?.toString() ?? '',
    );
    _maxHeightController = TextEditingController(
      text: widget.initialFilters.maxHeight?.toString() ?? '',
    );
    _occupationController = TextEditingController(
      text: widget.initialFilters.occupationQuery,
    );
    _hobbyController = TextEditingController();
    _selectedHobbies = Set<String>.from(widget.initialFilters.selectedHobbies);
  }

  @override
  void dispose() {
    _minAgeController.dispose();
    _maxAgeController.dispose();
    _minHeightController.dispose();
    _maxHeightController.dispose();
    _occupationController.dispose();
    _hobbyController.dispose();
    super.dispose();
  }

  void _addHobby() {
    final hobby = _hobbyController.text.trim();
    if (hobby.isEmpty) {
      return;
    }
    setState(() {
      _selectedHobbies.add(hobby);
      _hobbyController.clear();
    });
  }

  void _reset() {
    setState(() {
      _minAgeController.clear();
      _maxAgeController.clear();
      _minHeightController.clear();
      _maxHeightController.clear();
      _occupationController.clear();
      _hobbyController.clear();
      _selectedHobbies.clear();
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      _MatchesFilterState(
        minAge: int.tryParse(_minAgeController.text.trim()),
        maxAge: int.tryParse(_maxAgeController.text.trim()),
        minHeight: double.tryParse(_minHeightController.text.trim()),
        maxHeight: double.tryParse(_maxHeightController.text.trim()),
        occupationQuery: _occupationController.text.trim(),
        selectedHobbies: _selectedHobbies,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawKeyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final viewPaddingBottom = MediaQuery.of(context).viewPadding.bottom;
    final bottomInset = rawKeyboardInset < 0 ? 0.0 : rawKeyboardInset;
    final effectiveBottom = bottomInset > viewPaddingBottom ? bottomInset : viewPaddingBottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 24, 12, effectiveBottom + 12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFCF7),
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 30,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Match filters',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Refine your view by age, height, occupation, and hobbies.',
                  style: TextStyle(color: _kChatMuted, height: 1.4),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _MatchesFilterField(
                        controller: _minAgeController,
                        label: 'Min age',
                        icon: Icons.cake_outlined,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MatchesFilterField(
                        controller: _maxAgeController,
                        label: 'Max age',
                        icon: Icons.cake_rounded,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _MatchesFilterField(
                        controller: _minHeightController,
                        label: 'Min height',
                        hintText: 'ft or in',
                        icon: Icons.height_rounded,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MatchesFilterField(
                        controller: _maxHeightController,
                        label: 'Max height',
                        hintText: 'ft or in',
                        icon: Icons.height_rounded,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _MatchesFilterField(
                  controller: _occupationController,
                  label: 'Occupation',
                  hintText: 'Doctor, engineer, designer...',
                  icon: Icons.work_outline_rounded,
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _MatchesFilterField(
                        controller: _hobbyController,
                        label: 'Add hobby',
                        hintText: 'Reading, hiking, cooking...',
                        icon: Icons.interests_outlined,
                        onSubmitted: (_) => _addHobby(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: FilledButton(
                        onPressed: _addHobby,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kChatGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text('Add'),
                      ),
                    ),
                  ],
                ),
                if (_selectedHobbies.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedHobbies
                        .map(
                          (hobby) => InputChip(
                            label: Text(hobby),
                            onDeleted: () {
                              setState(() => _selectedHobbies.remove(hobby));
                            },
                            backgroundColor: const Color(0xFFFFF4E7),
                            side: const BorderSide(color: Color(0xFFF2E3CC)),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 22),
                Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewPadding.bottom + 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _reset,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: _kChatBorder),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _apply,
                          style: FilledButton.styleFrom(
                            backgroundColor: _kChatGreen,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: const Text('Apply filters'),
                        ),
                      ),
                    ],
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

class _MatchesFilterField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final IconData icon;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  const _MatchesFilterField({
    required this.controller,
    required this.label,
    this.hintText,
    required this.icon,
    this.keyboardType,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon, color: _kChatGreen),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _kChatBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _kChatBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _kChatGreen, width: 1.4),
        ),
      ),
    );
  }
}

class _MatchesFilterState {
  final int? minAge;
  final int? maxAge;
  final double? minHeight;
  final double? maxHeight;
  final String occupationQuery;
  final Set<String> selectedHobbies;

  const _MatchesFilterState({
    this.minAge,
    this.maxAge,
    this.minHeight,
    this.maxHeight,
    this.occupationQuery = '',
    this.selectedHobbies = const <String>{},
  });

  bool get hasActiveFilters =>
      minAge != null ||
      maxAge != null ||
      minHeight != null ||
      maxHeight != null ||
      occupationQuery.trim().isNotEmpty ||
      selectedHobbies.isNotEmpty;

  _MatchesFilterState copyWith({
    int? minAge,
    int? maxAge,
    double? minHeight,
    double? maxHeight,
    String? occupationQuery,
    Set<String>? selectedHobbies,
    bool clearAgeRange = false,
    bool clearHeightRange = false,
  }) {
    return _MatchesFilterState(
      minAge: clearAgeRange ? null : (minAge ?? this.minAge),
      maxAge: clearAgeRange ? null : (maxAge ?? this.maxAge),
      minHeight: clearHeightRange ? null : (minHeight ?? this.minHeight),
      maxHeight: clearHeightRange ? null : (maxHeight ?? this.maxHeight),
      occupationQuery: occupationQuery ?? this.occupationQuery,
      selectedHobbies: selectedHobbies ?? this.selectedHobbies,
    );
  }

  List<_MatchesFilterChip> toChips() {
    final chips = <_MatchesFilterChip>[];
    if (minAge != null || maxAge != null) {
      chips.add(
        _MatchesFilterChip(
          type: _MatchesFilterChipType.age,
          label: 'Age ${minAge?.toString() ?? 'Any'}-${maxAge?.toString() ?? 'Any'}',
          value: 'age',
        ),
      );
    }
    if (minHeight != null || maxHeight != null) {
      chips.add(
        _MatchesFilterChip(
          type: _MatchesFilterChipType.height,
          label:
              'Height ${_formatFilterNumber(minHeight) ?? 'Any'}-${_formatFilterNumber(maxHeight) ?? 'Any'}',
          value: 'height',
        ),
      );
    }
    if (occupationQuery.trim().isNotEmpty) {
      chips.add(
        _MatchesFilterChip(
          type: _MatchesFilterChipType.occupation,
          label: 'Occupation: ${occupationQuery.trim()}',
          value: occupationQuery.trim(),
        ),
      );
    }
    for (final hobby in selectedHobbies) {
      chips.add(
        _MatchesFilterChip(
          type: _MatchesFilterChipType.hobby,
          label: 'Hobby: $hobby',
          value: hobby,
        ),
      );
    }
    return chips;
  }
}

enum _MatchesFilterChipType { age, height, occupation, hobby }

class _MatchesFilterChip {
  final _MatchesFilterChipType type;
  final String label;
  final String value;

  const _MatchesFilterChip({
    required this.type,
    required this.label,
    required this.value,
  });
}

class _MatchesPhotoFallback extends StatelessWidget {
  final String name;

  const _MatchesPhotoFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF6E9D8), Color(0xFFE5F1E9)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w800,
          color: Color(0xFF4B5563),
        ),
      ),
    );
  }
}

Future<List<UserModel>> _loadMatchedUsers(List<String> userIds) async {
  final users = await Future.wait(userIds.map((userId) => _homeCachedProfileFuture(userId)));
  return users.whereType<UserModel>().toList();
}

String? _formatMatchHeight(double? height, String? unit) {
  if (height == null) {
    return null;
  }
  final normalizedUnit = (unit ?? '').trim();
  final value = _formatFilterNumber(height) ?? height.toString();
  if (normalizedUnit.isEmpty) {
    return '$value height';
  }
  return '$value $normalizedUnit';
}

String? _formatFilterNumber(double? value) {
  if (value == null) {
    return null;
  }
  return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
}

class _MatchesEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _MatchesEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _kChatBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 38, color: _kChatGreen),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                message,
                style: const TextStyle(color: _kChatMuted, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatsTab extends StatefulWidget {
  final ChatLaunchTarget? initialChatTarget;
  final ValueChanged<bool>? onThreadVisibilityChanged;

  const _ChatsTab({
    super.key,
    this.initialChatTarget,
    this.onThreadVisibilityChanged,
  });

  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> {
  final ChatService _chatService = ChatService();
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _messageController = TextEditingController();
  late Future<bool> _chatAccessFuture;
  _ChatPeer? _selectedPeer;
  _MessageDraftAction? _draftAction;
  String? _currentUserPhotoUrl;
  bool _sendingMessage = false;
  bool _sendingImage = false;

  bool get _supportThreadSelected =>
      _selectedPeer?.uid == ChatService.supportUid;

  @override
  void initState() {
    super.initState();
    _chatAccessFuture = ChatAccessService().canCurrentUserChat();
    final initialTarget = widget.initialChatTarget;
    if (initialTarget != null) {
      _selectedPeer = _ChatPeer(
        uid: initialTarget.uid,
        displayName: initialTarget.displayName,
        photoUrl: initialTarget.photoUrl,
        chatId: _chatService.chatIdFor(
          AuthService().getCurrentUser()?.uid ?? '',
          initialTarget.uid,
        ),
        isPinned: initialTarget.uid == ChatService.supportUid,
        isSupportChat: initialTarget.uid == ChatService.supportUid,
      );
    }
    _loadCurrentUserPhoto();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onThreadVisibilityChanged?.call(_selectedPeer != null);
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserPhoto() async {
    final currentUser = AuthService().getCurrentUser();
    if (currentUser == null) {
      return;
    }

    try {
      final profile = await UserService().getUser(currentUser.uid);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentUserPhotoUrl = profile?.profilePictureUrl ?? currentUser.photoURL;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _currentUserPhotoUrl = currentUser.photoURL;
      });
    }
  }

  void _selectPeer(_ChatPeer? peer) {
    setState(() => _selectedPeer = peer);
    widget.onThreadVisibilityChanged?.call(peer != null);
  }

  bool handleBackPressed() {
    if (_selectedPeer == null) {
      return false;
    }
    _clearDraftAction();
    _selectPeer(null);
    return true;
  }

  Future<void> _reportChat({
    required String currentUserId,
    required _ChatPeer peer,
  }) async {
    try {
      await _chatService.reportChat(
        chatId: peer.chatId,
        reporterId: currentUserId,
        reportedUserId: peer.uid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conversation with ${peer.displayName} reported')),
      );
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(context, e, fallbackMessage: 'Could not report this chat.');
    }
  }

  Future<void> _blockUser({
    required String currentUserId,
    required _ChatPeer peer,
  }) async {
    try {
      await getIt<InteractionsService>().blockUser(currentUserId, peer.uid);
      await _chatService.deleteChatForUser(
        chatId: peer.chatId,
        userId: currentUserId,
      );
      _selectPeer(null);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${peer.displayName} has been blocked')),
      );
    } catch (e) {
      if (!mounted) return;
      AppNotice.showError(context, e, fallbackMessage: 'Could not block this user.');
    }
  }

  Future<void> _sendChatImage() async {
    final currentUser = AuthService().getCurrentUser();
    final peer = _selectedPeer;
    if (currentUser == null || peer == null || _sendingImage) {
      return;
    }

    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (pickedFile == null) {
      return;
    }

    setState(() {
      _sendingImage = true;
    });

    try {
      if (!mounted) return;
      final bytes = await pickedFile.readAsBytes();
      final uploadedUrl = await _storageService.uploadChatImage(
        bytes: bytes,
        uid: currentUser.uid,
        filename: 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final chatId = _chatService.chatIdFor(currentUser.uid, peer.uid);
      await _chatService.sendMessage(
        chatId,
        MessageModel(
          id: '',
          senderId: currentUser.uid,
          receiverId: peer.uid,
          message: '',
          imageUrl: uploadedUrl,
          senderPhotoUrl: _currentUserPhotoUrl ?? currentUser.photoURL,
          replyToMessageId: _draftAction?.message.id,
          replyToText: _draftAction?.message.message,
          replyToImageUrl: _draftAction?.message.imageUrl,
          replyToSenderId: _draftAction?.message.senderId,
        ),
        senderName: _currentUserDisplayName(currentUser),
        receiverName: peer.displayName,
        senderPhotoUrl: _currentUserPhotoUrl ?? currentUser.photoURL,
        receiverPhotoUrl: peer.photoUrl,
      );
      _clearDraftAction();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send image: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _sendingImage = false;
        });
      }
    }
  }

  String _displayNameFromId(String uid) =>
      uid.length > 12 ? uid.substring(0, 12) : uid;

  String _currentUserDisplayName(dynamic currentUser) {
    final displayName = currentUser.displayName;
    if (displayName is String && displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    final email = currentUser.email;
    if (email is String && email.contains('@')) {
      return email.split('@').first;
    }
    return _displayNameFromId(currentUser.uid as String);
  }

  void _setReplyAction(MessageModel message) {
    setState(() {
      _draftAction = _MessageDraftAction.reply(message);
    });
  }

  void _setEditAction(MessageModel message) {
    setState(() {
      _draftAction = _MessageDraftAction.edit(message);
      _messageController.text = message.message;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
    });
  }

  void _clearDraftAction() {
    if (!mounted) {
      _draftAction = null;
      return;
    }
    setState(() {
      _draftAction = null;
    });
  }

  Future<void> _sendMessage() async {
    final currentUser = AuthService().getCurrentUser();
    final text = _messageController.text.trim();
    final draftAction = _draftAction;
    final peer = _selectedPeer;
    if (currentUser == null || peer == null || text.isEmpty || _sendingMessage) {
      return;
    }

    setState(() {
      _sendingMessage = true;
    });

    try {
      final chatId = _chatService.chatIdFor(currentUser.uid, peer.uid);
      if (draftAction?.isEditing == true) {
        await _chatService.updateMessage(
          chatId: chatId,
          messageId: draftAction!.message.id,
          text: text,
        );
      } else {
        await _chatService.sendMessage(
          chatId,
          MessageModel(
            id: '',
            senderId: currentUser.uid,
            receiverId: peer.uid,
            message: text,
            senderPhotoUrl: _currentUserPhotoUrl ?? currentUser.photoURL,
            replyToMessageId: draftAction?.message.id,
            replyToText: draftAction?.message.message,
            replyToImageUrl: draftAction?.message.imageUrl,
            replyToSenderId: draftAction?.message.senderId,
          ),
          senderName: _currentUserDisplayName(currentUser),
          receiverName: peer.displayName,
          senderPhotoUrl: _currentUserPhotoUrl ?? currentUser.photoURL,
          receiverPhotoUrl: peer.photoUrl,
        );
      }
      _messageController.clear();
      _clearDraftAction();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send message: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _sendingMessage = false;
        });
      }
    }
  }

  Future<void> _deleteMessage(MessageModel message) async {
    final currentUser = AuthService().getCurrentUser();
    final peer = _selectedPeer;
    if (currentUser == null || peer == null) {
      return;
    }

    try {
      final chatId = _chatService.chatIdFor(currentUser.uid, peer.uid);
      await _chatService.deleteMessage(chatId: chatId, messageId: message.id);
      if (_draftAction?.message.id == message.id) {
        _messageController.clear();
        _clearDraftAction();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete message: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService().getCurrentUser();
    if (currentUser == null) {
      return const Center(child: Text('Sign in to view your chats.'));
    }

    return FutureBuilder<bool>(
      future: _chatAccessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        final canChat = snapshot.data ?? false;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _chatService.streamChatsForUser(currentUser.uid),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load conversations right now.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final docs = snapshot.data?.docs ?? const [];
            final conversations =
                docs
                    .map((doc) {
                      final data = doc.data();
                      final archivedBy = List<String>.from(
                        data['archivedBy'] as List? ?? const [],
                      );
                      final deletedFor = List<String>.from(
                        data['deletedFor'] as List? ?? const [],
                      );
                      if (archivedBy.contains(currentUser.uid) ||
                          deletedFor.contains(currentUser.uid)) {
                        return null;
                      }
                      final participants = List<String>.from(
                        data['participants'] as List? ?? const [],
                      );
                      final participantNames = Map<String, dynamic>.from(
                        data['participantNames'] as Map? ?? const {},
                      );
                      final participantPhotoUrls = Map<String, dynamic>.from(
                        data['participantPhotoUrls'] as Map? ?? const {},
                      );
                      final mutedBy = List<String>.from(
                        data['mutedBy'] as List? ?? const [],
                      );
                      final pinnedFor = List<String>.from(
                        data['pinnedFor'] as List? ?? const [],
                      );
                      final unreadCounts = Map<String, dynamic>.from(
                        data['unreadCounts'] as Map? ?? const {},
                      );
                      final isSupportChat = data['isSupportChat'] == true;
                      final peerId = participants.firstWhere(
                        (id) => id != currentUser.uid,
                        orElse: () => '',
                      );
                      final unreadCountRaw = unreadCounts[currentUser.uid];
                      final unreadCount = unreadCountRaw is num
                          ? unreadCountRaw.toInt()
                          : 0;
                      return _ChatPeer(
                        uid: peerId,
                        displayName: _resolvePeerDisplayName(
                          peerId,
                          participantNames[peerId] as String?,
                        ),
                        photoUrl: participantPhotoUrls[peerId] as String?,
                        lastMessage: data['lastMessage'] as String?,
                        lastMessageAt: data['lastMessageAt'] as Timestamp?,
                        isMuted: mutedBy.contains(currentUser.uid),
                        chatId: doc.id,
                        unreadCount: unreadCount,
                        isPinned: pinnedFor.contains(currentUser.uid),
                        isSupportChat: isSupportChat || peerId == ChatService.supportUid,
                      );
                    })
                    .whereType<_ChatPeer>()
                    .where((peer) => peer.uid.isNotEmpty)
                    .toList()
                  ..sort((a, b) {
                    if (a.isPinned != b.isPinned) {
                      return a.isPinned ? -1 : 1;
                    }
                    final aMillis = a.lastMessageAt?.millisecondsSinceEpoch ?? 0;
                    final bMillis = b.lastMessageAt?.millisecondsSinceEpoch ?? 0;
                    return bMillis.compareTo(aMillis);
                  });

            final peers = conversations;

            return LayoutBuilder(
              builder: (context, constraints) {
                if (!canChat && !_supportThreadSelected && peers.isEmpty) {
                  return _PremiumChatNotice(
                    onUpgrade: () async {
                      final result = await Navigator.pushNamed(
                        context,
                        '/payment',
                        arguments: const {
                          'initialPlanId': 'premium',
                        },
                      );
                      if (!mounted || result == null) return;
                      setState(() {
                        _chatAccessFuture = Future.value(true);
                      });
                    },
                  );
                }

                final isWide = constraints.maxWidth > 900;
                final listPane = _ChatListPane(
                  peers: peers,
                  selectedPeer: _selectedPeer,
                  onSelect: (peer) {
                    if (!canChat && !peer.isSupportChat) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Upgrade to Premium to open member chats.'),
                        ),
                      );
                      return;
                    }
                    _selectPeer(peer);
                  },
                );
                final threadPane = _selectedPeer == null
                    ? const Center(
                        child: Text('Select a conversation to open the chat.'),
                      )
                    : (!canChat && !_selectedPeer!.isSupportChat)
                    ? _PremiumChatNotice(
                        onUpgrade: () async {
                          final result = await Navigator.pushNamed(
                            context,
                            '/payment',
                            arguments: const {
                              'initialPlanId': 'premium',
                            },
                          );
                          if (!mounted || result == null) return;
                          setState(() {
                            _chatAccessFuture = Future.value(true);
                          });
                        },
                      )
                    : _ChatThreadPane(
                        peer: _selectedPeer!,
                        chatService: _chatService,
                        currentUserId: currentUser.uid,
                        currentUserPhotoUrl: _currentUserPhotoUrl,
                        onBack: isWide ? null : () => _selectPeer(null),
                        onShowActions: _selectedPeer!.isSupportChat
                            ? null
                            : () => showChatOptionsSheet(
                                context: context,
                                onViewProfile: () => Navigator.of(context).pushNamed(
                                  '/view-profile',
                                  arguments: _selectedPeer!.uid,
                                ),
                                onShareProfile: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Profile sharing coming soon.'),
                                    ),
                                  );
                                },
                                onReport: () => _reportChat(
                                  currentUserId: currentUser.uid,
                                  peer: _selectedPeer!,
                                ),
                                onBlockUser: () => _blockUser(
                                  currentUserId: currentUser.uid,
                                  peer: _selectedPeer!,
                                ),
                                onClearChat: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Clear chat coming soon.'),
                                    ),
                                  );
                                },
                              ),
                        messageController: _messageController,
                        draftAction: _draftAction,
                        sendingMessage: _sendingMessage,
                        sendingImage: _sendingImage,
                        onSend: _sendMessage,
                        onPickImage: _sendChatImage,
                        onReply: _setReplyAction,
                        onEdit: _setEditAction,
                        onDelete: _deleteMessage,
                        onClearDraftAction: _clearDraftAction,
                      );

                if (isWide) {
                  return Row(
                    children: [
                      SizedBox(width: 320, child: listPane),
                      const VerticalDivider(width: 1),
                      Expanded(child: threadPane),
                    ],
                  );
                }

                return _selectedPeer == null
                    ? listPane
                    : threadPane;
              },
            );
          },
        );
      },
    );
  }

  String _resolvePeerDisplayName(String uid, String? storedName) {
    if (storedName != null && storedName.trim().isNotEmpty) {
      return storedName.trim();
    }
    return _displayNameFromId(uid);
  }
}

class _PremiumChatNotice extends StatelessWidget {
  final Future<void> Function()? onUpgrade;

  const _PremiumChatNotice({this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kChatBgTop, _kChatBgBottom],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: Opacity(
                  opacity: 0.14,
                  child: Column(
                    children: List.generate(
                      5,
                      (index) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        height: index.isEven ? 72 : 54,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 26,
                      offset: Offset(0, -6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7E2DA),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: 86,
                      height: 86,
                      decoration: const BoxDecoration(
                        color: _kChatGreenSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_outline_rounded,
                        size: 38,
                        color: _kChatGreen,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Chat Locked',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Upgrade to Premium to start chatting.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _kChatMuted, height: 1.45),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onUpgrade != null ? () => onUpgrade!() : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kChatGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Go Premium',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 14, color: _kChatGreen),
                        SizedBox(width: 6),
                        Text('Secure payment', style: TextStyle(fontSize: 12, color: _kChatMuted)),
                        SizedBox(width: 14),
                        Text('|', style: TextStyle(fontSize: 12, color: _kChatMuted)),
                        SizedBox(width: 14),
                        Text('Cancel anytime', style: TextStyle(fontSize: 12, color: _kChatMuted)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPeer {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final String? lastMessage;
  final Timestamp? lastMessageAt;
  final bool isMuted;
  final String chatId;
  final int unreadCount;
  final bool isPinned;
  final bool isSupportChat;

  const _ChatPeer({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.lastMessage,
    this.lastMessageAt,
    this.isMuted = false,
    required this.chatId,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isSupportChat = false,
  });
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: _kChatGreen,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _SupportIntroCard extends StatelessWidget {
  final String message;

  const _SupportIntroCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5EE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCFE4D5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.support_agent_rounded,
            color: _kChatGreen,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF24533A),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageDraftAction {
  final MessageModel message;
  final bool isEditing;

  const _MessageDraftAction.reply(this.message) : isEditing = false;
  const _MessageDraftAction.edit(this.message) : isEditing = true;
}

class _ChatListPane extends StatelessWidget {
  final List<_ChatPeer> peers;
  final _ChatPeer? selectedPeer;
  final ValueChanged<_ChatPeer> onSelect;

  const _ChatListPane({
    required this.peers,
    required this.selectedPeer,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) {
      return Container(
        color: _kChatCream,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _kChatSurface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _kChatBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 38, color: _kChatGreen),
              SizedBox(height: 12),
              Text(
                'No conversations yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 6),
              Text(
                'When you start chatting with a match, your conversations will show up here.',
                style: TextStyle(color: _kChatMuted, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kChatBgTop, _kChatBgBottom],
        ),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        itemCount: peers.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final peer = peers[index];
          final isSelected = selectedPeer?.uid == peer.uid;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFF1F8F3) : Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected ? const Color(0xFFB9D9C4) : _kChatBorder,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => onSelect(peer),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      _ChatUserAvatar(
                        uid: peer.uid,
                        name: peer.displayName,
                        photoUrl: peer.photoUrl,
                        showOnlineIndicator: true,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              peer.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (peer.lastMessage?.trim().isNotEmpty == true)
                                  ? peer.lastMessage!
                                  : 'Open conversation',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _kChatMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (peer.lastMessageAt != null)
                            Text(
                              TimeOfDay.fromDateTime(peer.lastMessageAt!.toDate()).format(context),
                              style: const TextStyle(
                                color: _kChatMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          const SizedBox(height: 8),
                          if (peer.unreadCount > 0)
                            _UnreadBadge(count: peer.unreadCount)
                          else
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: isSelected ? _kChatGreen : Colors.transparent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? _kChatGreen : const Color(0xFFD8D8D8),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChatThreadPane extends StatefulWidget {
  final _ChatPeer peer;
  final ChatService chatService;
  final String currentUserId;
  final String? currentUserPhotoUrl;
  final VoidCallback? onBack;
  final VoidCallback? onShowActions;
  final TextEditingController messageController;
  final _MessageDraftAction? draftAction;
  final bool sendingMessage;
  final bool sendingImage;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final ValueChanged<MessageModel> onReply;
  final ValueChanged<MessageModel> onEdit;
  final ValueChanged<MessageModel> onDelete;
  final VoidCallback onClearDraftAction;

  const _ChatThreadPane({
    required this.peer,
    required this.chatService,
    required this.currentUserId,
    required this.currentUserPhotoUrl,
    this.onBack,
    this.onShowActions,
    required this.messageController,
    required this.draftAction,
    required this.sendingMessage,
    required this.sendingImage,
    required this.onSend,
    required this.onPickImage,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onClearDraftAction,
  });

  @override
  State<_ChatThreadPane> createState() => _ChatThreadPaneState();
}

class _ChatThreadPaneState extends State<_ChatThreadPane> {
  String _supportWelcomeMessage() {
    final currentUser = AuthService().getCurrentUser();
    final name = currentUser?.displayName?.trim().isNotEmpty == true
        ? currentUser!.displayName!.trim()
        : (currentUser?.email?.split('@').first ?? 'there');
    return 'Welcome to Qubool Nikah, how can we be of help you $name';
  }

  void _showComposerInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void initState() {
    super.initState();
    _markVisibleMessagesAsRead();
  }

  @override
  void didUpdateWidget(covariant _ChatThreadPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.peer.uid != widget.peer.uid ||
        oldWidget.currentUserId != widget.currentUserId) {
      _markVisibleMessagesAsRead();
    }
  }

  Future<void> _markVisibleMessagesAsRead() async {
    final chatId = widget.chatService.chatIdFor(
      widget.currentUserId,
      widget.peer.uid,
    );
    try {
      await widget.chatService.markMessagesAsRead(chatId, widget.currentUserId);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final chatId = widget.chatService.chatIdFor(
      widget.currentUserId,
      widget.peer.uid,
    );
    final rawKeyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardInset = kIsWeb
        ? 0.0
        : (rawKeyboardInset.isFinite && rawKeyboardInset > 0
            ? rawKeyboardInset
            : 0.0);
    return FutureBuilder<UserModel?>(
      future: widget.peer.photoUrl?.isNotEmpty == true
          ? Future<UserModel?>.value(null)
          : _homeCachedProfileFuture(widget.peer.uid),
      builder: (context, peerSnapshot) {
        final resolvedPeerPhotoUrl = widget.peer.photoUrl?.isNotEmpty == true
            ? widget.peer.photoUrl
            : peerSnapshot.data?.profilePictureUrl;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: widget.chatService.streamUserPresence(widget.peer.uid),
          builder: (context, presenceSnapshot) {
            final peerIsOnline =
                presenceSnapshot.data?.data()?['isOnline'] as bool? ?? false;

            return Column(
              children: [
                Container(
                  padding: EdgeInsets.fromLTRB(
                    widget.onBack == null ? 16 : 10,
                    widget.onBack == null ? 12 : 10,
                    14,
                    12,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        if (widget.onBack != null)
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: widget.onBack,
                          ),
                        PresenceAvatar(
                          userId: widget.peer.uid,
                          name: widget.peer.displayName,
                          imageUrl: resolvedPeerPhotoUrl,
                          radius: 22,
                          showOnlineIndicator: true,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.peer.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                peerIsOnline ? 'Online' : 'Conversation',
                                style: const TextStyle(
                                  color: _kChatMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.onShowActions != null)
                          IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: widget.onShowActions,
                          ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<MessageModel>>(
                    stream: widget.chatService.streamMessages(chatId),
                    builder: (context, snapshot) {
                      final messages = snapshot.data ?? const [];
                      if (messages.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _markVisibleMessagesAsRead();
                          }
                        });
                      }
                      if (messages.isEmpty) {
                        return Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [_kChatBgTop, _kChatBgBottom],
                            ),
                          ),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.96),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(color: _kChatBorder),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x12000000),
                                      blurRadius: 24,
                                      offset: Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.peer.isSupportChat) ...[
                                      _SupportIntroCard(
                                        message: _supportWelcomeMessage(),
                                      ),
                                      const SizedBox(height: 14),
                                    ],
                                    Text(
                                      widget.peer.isSupportChat
                                          ? 'Send us a message and our team will respond here.'
                                          : 'Say salam to ${widget.peer.displayName} and start the conversation.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: _kChatMuted,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      return Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [_kChatBgTop, _kChatBgBottom],
                          ),
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                          itemCount: messages.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return widget.peer.isSupportChat
                                  ? Padding(
                                      padding: const EdgeInsets.only(bottom: 14),
                                      child: _SupportIntroCard(
                                        message: _supportWelcomeMessage(),
                                      ),
                                    )
                                  : Container(
                                      margin: const EdgeInsets.only(bottom: 14),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: _kChatWarmCard,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: _kChatWarmBorder),
                                      ),
                                      child: const Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.lock_outline_rounded, color: Color(0xFF876134), size: 18),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Keep your conversations respectful and follow our community guidelines.',
                                              style: TextStyle(
                                                color: Color(0xFF6D573D),
                                                fontSize: 13,
                                                height: 1.35,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                            }

                            final message = messages[index - 1];
                            final isMine = message.senderId == widget.currentUserId;
                            final avatarUrl = isMine
                                ? (message.senderPhotoUrl ?? widget.currentUserPhotoUrl)
                                : (message.senderPhotoUrl ?? resolvedPeerPhotoUrl);
                            final avatarName = isMine ? 'You' : widget.peer.displayName;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (!isMine) ...[
                                    PresenceAvatar(
                                      userId: message.senderId,
                                      name: avatarName,
                                      imageUrl: avatarUrl,
                                      radius: 14,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(20),
                                      onLongPress: () => _showMessageActions(context, message),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        constraints: const BoxConstraints(maxWidth: 320),
                                        decoration: BoxDecoration(
                                          color: isMine ? const Color(0xFFE3F0DA) : Colors.white,
                                          borderRadius: BorderRadius.only(
                                            topLeft: const Radius.circular(18),
                                            topRight: const Radius.circular(18),
                                            bottomLeft: Radius.circular(isMine ? 18 : 8),
                                            bottomRight: Radius.circular(isMine ? 8 : 18),
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x0D000000),
                                              blurRadius: 12,
                                              offset: Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (message.replyToMessageId != null)
                                              _ReplyPreviewBubble(
                                                isMine: isMine,
                                                senderLabel: message.replyToSenderId == widget.currentUserId
                                                    ? 'You'
                                                    : widget.peer.displayName,
                                                text: message.replyToText,
                                                imageUrl: message.replyToImageUrl,
                                              ),
                                            if (message.replyToMessageId != null) const SizedBox(height: 8),
                                            if (message.isDeleted)
                                              const Text(
                                                'This message was deleted',
                                                style: TextStyle(
                                                  color: _kChatMuted,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              )
                                            else ...[
                                              if (message.message.trim().isNotEmpty)
                                                Text(
                                                  message.message,
                                                  style: const TextStyle(
                                                    color: Color(0xFF202020),
                                                    height: 1.42,
                                                  ),
                                                ),
                                              if (message.imageUrl != null && message.imageUrl!.trim().isNotEmpty) ...[
                                                if (message.message.trim().isNotEmpty) const SizedBox(height: 8),
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(14),
                                                  child: Image.network(
                                                    message.imageUrl!,
                                                    width: 220,
                                                    height: 220,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (context, error, stackTrace) => Container(
                                                      width: 220,
                                                      height: 220,
                                                      color: const Color(0xFFF2F2F2),
                                                      alignment: Alignment.center,
                                                      child: const Icon(Icons.broken_image_outlined),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  TimeOfDay.fromDateTime(message.timestamp.toDate()).format(context),
                                                  style: const TextStyle(
                                                    color: _kChatMuted,
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                if (message.editedAt != null && !message.isDeleted) ...[
                                                  const SizedBox(width: 6),
                                                  const Text(
                                                    'edited',
                                                    style: TextStyle(
                                                      color: _kChatMuted,
                                                      fontSize: 10.5,
                                                    ),
                                                  ),
                                                ],
                                                if (isMine) ...[
                                                  const SizedBox(width: 6),
                                                  _MessageStatusIcon(
                                                    isRead: message.readAt != null,
                                                    isPeerOnline: peerIsOnline,
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
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
                    },
                  ),
                ),
                AnimatedPadding(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.only(bottom: keyboardInset),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.draftAction != null)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFDDE7DA)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          widget.draftAction!.isEditing
                                              ? 'Editing message'
                                              : 'Replying to ${widget.draftAction!.message.senderId == widget.currentUserId ? 'You' : widget.peer.displayName}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          widget.draftAction!.message.message
                                                  .trim()
                                                  .isNotEmpty
                                              ? widget
                                                    .draftAction!
                                                    .message
                                                    .message
                                              : (widget
                                                            .draftAction!
                                                            .message
                                                            .imageUrl !=
                                                        null
                                                    ? 'Photo'
                                                    : 'Message'),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: widget.onClearDraftAction,
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(26),
                                  border: Border.all(color: _kChatBorder),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x0D000000),
                                      blurRadius: 14,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => _showComposerInfo('Emoji reactions coming soon'),
                                      icon: const Icon(Icons.emoji_emotions_outlined, color: _kChatMuted),
                                    ),
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF7F4EE),
                                          borderRadius: BorderRadius.circular(22),
                                        ),
                                        child: TextField(
                                          controller: widget.messageController,
                                          minLines: 1,
                                          maxLines: 4,
                                          decoration: InputDecoration(
                                            hintText: widget.draftAction?.isEditing == true
                                                ? 'Edit your message'
                                                : 'Type a message...',
                                            hintStyle: const TextStyle(
                                              color: Color(0xFF8A8A8A),
                                              fontWeight: FontWeight.w500,
                                            ),
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                          ),
                                          onSubmitted: (_) => widget.onSend(),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: widget.sendingImage ? null : widget.onPickImage,
                                      icon: widget.sendingImage
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.attach_file_rounded, color: _kChatMuted),
                                    ),
                                    IconButton(
                                      onPressed: () => _showComposerInfo('Voice notes coming soon'),
                                      icon: const Icon(Icons.mic_none_rounded, color: _kChatGreen),
                                    ),
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: const BoxDecoration(
                                        color: _kChatGreen,
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        onPressed: widget.sendingMessage ? null : widget.onSend,
                                        icon: widget.sendingMessage
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2.2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.send_rounded,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showMessageActions(
    BuildContext context,
    MessageModel message,
  ) async {
    final isMine = message.senderId == widget.currentUserId;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () => Navigator.of(context).pop('reply'),
              ),
              if (isMine &&
                  !message.isDeleted &&
                  message.message.trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit'),
                  onTap: () => Navigator.of(context).pop('edit'),
                ),
              if (isMine && !message.isDeleted)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete'),
                  onTap: () => Navigator.of(context).pop('delete'),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null) {
      return;
    }

    switch (selected) {
      case 'reply':
        widget.onReply(message);
        break;
      case 'edit':
        widget.onEdit(message);
        break;
      case 'delete':
        widget.onDelete(message);
        break;
    }
  }
}

class _MessageStatusIcon extends StatelessWidget {
  final bool isRead;
  final bool isPeerOnline;

  const _MessageStatusIcon({required this.isRead, required this.isPeerOnline});

  @override
  Widget build(BuildContext context) {
    final icon = isRead
        ? Icons.done_all_rounded
        : (isPeerOnline ? Icons.done_all_rounded : Icons.done_rounded);
    final color = isRead ? _kChatGreen : const Color(0xFF75907F);

    return Icon(icon, size: 16, color: color);
  }
}

class _ReplyPreviewBubble extends StatelessWidget {
  final bool isMine;
  final String senderLabel;
  final String? text;
  final String? imageUrl;

  const _ReplyPreviewBubble({
    required this.isMine,
    required this.senderLabel,
    required this.text,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final hasText = text?.trim().isNotEmpty == true;
    final hasImage = imageUrl?.trim().isNotEmpty == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isMine
            ? const Color(0xFFF2F7ED)
            : const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            senderLabel,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: _kChatGreen,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasText ? text! : (hasImage ? 'Photo' : 'Message'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _kChatMuted),
          ),
        ],
      ),
    );
  }
}

class _ChatUserAvatar extends StatelessWidget {
  final String uid;
  final String name;
  final String? photoUrl;
  final bool showOnlineIndicator;

  const _ChatUserAvatar({
    required this.uid,
    required this.name,
    required this.photoUrl,
    this.showOnlineIndicator = false,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserModel?>(
      future: photoUrl?.trim().isNotEmpty == true
          ? null
          : _homeCachedProfileFuture(uid),
      builder: (context, snapshot) {
        return PresenceAvatar(
          userId: uid,
          name: name,
          imageUrl: photoUrl?.trim().isNotEmpty == true
              ? photoUrl
              : snapshot.data?.profilePictureUrl,
          showOnlineIndicator: showOnlineIndicator,
        );
      },
    );
  }
}

class _CurrentUserProfileScreen extends StatefulWidget {
  final UserDashboardController controller;
  final String fallbackName;

  const _CurrentUserProfileScreen({
    required this.controller,
    required this.fallbackName,
  });

  @override
  State<_CurrentUserProfileScreen> createState() =>
      _CurrentUserProfileScreenState();
}

class _CurrentUserProfileScreenState extends State<_CurrentUserProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _imagePicker = ImagePicker();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _genderController = TextEditingController();
  final _religionController = TextEditingController();
  final _casteController = TextEditingController();
  final _educationController = TextEditingController();
  final _occupationController = TextEditingController();
  final _heightController = TextEditingController();
  final _hobbyInputController = TextEditingController();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();
  final _aboutMeController = TextEditingController();
  Uint8List? _selectedProfileImageBytes;
  bool _removeProfilePhoto = false;
  bool _processingPhoto = false;
  String? _lastHydratedUid;
  DateTime? _selectedDateOfBirth;
  String _selectedHeightUnit = 'ft';
  List<String> _hobbies = const [];

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _genderController.dispose();
    _religionController.dispose();
    _casteController.dispose();
    _educationController.dispose();
    _occupationController.dispose();
    _heightController.dispose();
    _hobbyInputController.dispose();
    _cityController.dispose();
    _countryController.dispose();
    _aboutMeController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hydrateFromProfile();
  }

  @override
  void didUpdateWidget(covariant _CurrentUserProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _hydrateFromProfile();
  }

  void _hydrateFromProfile() {
    final profile = widget.controller.profile;
    final profileUid = profile?.uid ?? 'fallback';
    if (_lastHydratedUid == profileUid) {
      return;
    }

    _lastHydratedUid = profileUid;
    _fullNameController.text = profile?.fullName ?? widget.fallbackName;
    _emailController.text = profile?.email ?? '';
    _phoneController.text = profile?.phone ?? '';
    _genderController.text = profile?.gender ?? '';
    _religionController.text = profile?.religion ?? '';
    _casteController.text = profile?.caste ?? '';
    _educationController.text = profile?.education ?? '';
    _occupationController.text = profile?.occupation ?? '';
    _heightController.text = profile?.height?.toString() ?? '';
    _selectedHeightUnit = profile?.heightUnit ?? 'ft';
    _hobbies = List<String>.from(profile?.hobbies ?? const []);
    _hobbyInputController.clear();
    _cityController.text = profile?.location?['city'] ?? '';
    _countryController.text = profile?.location?['country'] ?? '';
    _aboutMeController.text = profile?.aboutMe ?? '';
    _selectedDateOfBirth = profile?.dateOfBirth;
    _selectedProfileImageBytes = null;
    _removeProfilePhoto = false;
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initialDate =
        _selectedDateOfBirth ?? DateTime(now.year - 24, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _selectedDateOfBirth = picked;
    });
  }

  Future<void> _pickProfilePhoto() async {
    try {
      final file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (file == null || !mounted) {
        return;
      }

      setState(() => _processingPhoto = true);
      final bytes = await file.readAsBytes();
      if (!mounted) return;

      // Launch cropper screen and get cropped bytes.
      final cropped = await Navigator.of(context).push<Uint8List?>(
        MaterialPageRoute(builder: (_) => ImageCropperScreen(imageBytes: bytes)),
      );
      if (cropped == null) {
        setState(() => _processingPhoto = false);
        return;
      }
      setState(() {
        _selectedProfileImageBytes = cropped;
        _removeProfilePhoto = false;
        _processingPhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processingPhoto = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not pick image: $e')));
    }
  }

  void _removePhoto() {
    setState(() {
      _selectedProfileImageBytes = null;
      _removeProfilePhoto = true;
    });
  }

  void _addHobby([String? rawValue]) {
    final hobby = (rawValue ?? _hobbyInputController.text).trim();
    if (hobby.isEmpty) {
      return;
    }
    if (_hobbies.any(
      (existing) => existing.toLowerCase() == hobby.toLowerCase(),
    )) {
      _hobbyInputController.clear();
      return;
    }
    setState(() {
      _hobbies = [..._hobbies, hobby];
      _hobbyInputController.clear();
    });
  }

  void _removeHobby(String hobby) {
    setState(() {
      _hobbies = _hobbies.where((item) => item != hobby).toList();
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final location = <String, String>{};
    if (_cityController.text.trim().isNotEmpty) {
      location['city'] = _cityController.text.trim();
    }
    if (_countryController.text.trim().isNotEmpty) {
      location['country'] = _countryController.text.trim();
    }

    final data = <String, dynamic>{
      'fullName': _fullNameController.text.trim(),
      'email': _emailController.text.trim().isEmpty
          ? FieldValue.delete()
          : _emailController.text.trim(),
      'phone': _phoneController.text.trim().isEmpty
          ? FieldValue.delete()
          : _phoneController.text.trim(),
      'gender': _genderController.text.trim().isEmpty
          ? FieldValue.delete()
          : _genderController.text.trim(),
      'dateOfBirth': _selectedDateOfBirth == null
          ? FieldValue.delete()
          : Timestamp.fromDate(_selectedDateOfBirth!),
      'religion': _religionController.text.trim().isEmpty
          ? FieldValue.delete()
          : _religionController.text.trim(),
      'caste': _casteController.text.trim().isEmpty
          ? FieldValue.delete()
          : _casteController.text.trim(),
      'education': _educationController.text.trim().isEmpty
          ? FieldValue.delete()
          : _educationController.text.trim(),
      'occupation': _occupationController.text.trim().isEmpty
          ? FieldValue.delete()
          : _occupationController.text.trim(),
      'height': _heightController.text.trim().isEmpty
          ? FieldValue.delete()
          : double.tryParse(_heightController.text.trim()) ??
                FieldValue.delete(),
      'heightUnit': _heightController.text.trim().isEmpty
          ? FieldValue.delete()
          : _selectedHeightUnit,
      'hobbies': _hobbies.isEmpty ? FieldValue.delete() : _hobbies,
      'aboutMe': _aboutMeController.text.trim().isEmpty
          ? FieldValue.delete()
          : _aboutMeController.text.trim(),
      'location': location.isEmpty ? FieldValue.delete() : location,
    };

    final messenger = ScaffoldMessenger.of(context);

    try {
      // Apply optimistic UI update: update controller.profile locally so UI reflects changes immediately.
      final merged = _mergeProfileWithData(data);
      widget.controller.applyLocalProfile(merged);
      final existingPhotoUrl = widget.controller.profile?.profilePictureUrl;
      if (_selectedProfileImageBytes != null) {
        final currentUser = AuthService().getCurrentUser();
        if (currentUser == null) {
          throw StateError('No signed-in user found.');
        }
        final uploadedUrl = await StorageService().uploadProfileImage(
          bytes: _selectedProfileImageBytes!,
          uid: currentUser.uid,
          filename: 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        data['profilePictureUrl'] = uploadedUrl;
        if (existingPhotoUrl != null &&
            existingPhotoUrl.isNotEmpty &&
            existingPhotoUrl != uploadedUrl) {
          try {
            await StorageService().deleteFileByUrl(existingPhotoUrl);
          } catch (_) {}
        }
      } else if (_removeProfilePhoto) {
        data['profilePictureUrl'] = FieldValue.delete();
        if (existingPhotoUrl != null && existingPhotoUrl.isNotEmpty) {
          try {
            await StorageService().deleteFileByUrl(existingPhotoUrl);
          } catch (_) {}
        }
      }

      await widget.controller.updateProfile(data);
      if (!mounted) return;
      setState(() {
        _selectedProfileImageBytes = null;
        _removeProfilePhoto = false;
      });
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated successfully.')));
    } catch (e) {
      if (!mounted) return;
      // Revert by reloading profile from server to ensure consistency.
      try {
        await widget.controller.loadProfile();
      } catch (_) {}
      messenger.showSnackBar(SnackBar(content: Text('Could not update profile: $e')));
    }
  }

  UserModel _mergeProfileWithData(Map<String, dynamic> data) {
    final p = widget.controller.profile;
    return UserModel(
      uid: p?.uid ?? '',
      fullName: data['fullName'] as String? ?? p?.fullName ?? '',
      email: (data['email'] is String) ? data['email'] as String : p?.email,
      phone: (data['phone'] is String) ? data['phone'] as String : p?.phone,
      profileCreatedFor: p?.profileCreatedFor,
      gender: data['gender'] as String? ?? p?.gender,
      dateOfBirth: data['dateOfBirth'] is Timestamp
          ? (data['dateOfBirth'] as Timestamp).toDate()
          : data['dateOfBirth'] is DateTime
              ? data['dateOfBirth'] as DateTime
              : p?.dateOfBirth,
      religion: data['religion'] as String? ?? p?.religion,
      caste: data['caste'] as String? ?? p?.caste,
      familyDetails: data['familyDetails'] as String? ?? p?.familyDetails,
      location: data['location'] != null
          ? Map<String, String>.from(data['location'] as Map)
          : p?.location,
      education: data['education'] as String? ?? p?.education,
      occupation: data['occupation'] as String? ?? p?.occupation,
      income: p?.income,
      height: data['height'] is double ? data['height'] as double : p?.height,
      heightUnit: data['heightUnit'] as String? ?? p?.heightUnit,
      lifestyle: p?.lifestyle,
      hobbies: data['hobbies'] != null ? List<String>.from(data['hobbies'] as List) : p?.hobbies,
      aboutMe: data['aboutMe'] as String? ?? p?.aboutMe,
      profilePictureUrl: data['profilePictureUrl'] as String? ?? p?.profilePictureUrl,
      profileImages: p?.profileImages,
      isVerified: p?.isVerified ?? false,
      isPremium: p?.isPremium ?? false,
      isOnline: p?.isOnline ?? false,
      lastSeenAt: p?.lastSeenAt,
      createdAt: p?.createdAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.controller.profile;
    final isLoading = widget.controller.loadingProfile && profile == null;
    final displayName = profile?.fullName.isNotEmpty == true
        ? profile!.fullName
        : widget.fallbackName;
    final subtitle =
        profile?.email ??
        profile?.phone ??
        'Complete your profile to improve your matches';
    final effectivePhotoUrl = _removeProfilePhoto
        ? null
        : profile?.profilePictureUrl;
    final hasPhoto =
        _selectedProfileImageBytes != null ||
        (effectivePhotoUrl != null && effectivePhotoUrl.isNotEmpty);
    final age = _selectedDateOfBirth == null
        ? null
        : _calculateAge(_selectedDateOfBirth!);
    final dobLabel = _selectedDateOfBirth == null
        ? 'Date of birth not set'
        : MaterialLocalizations.of(
            context,
          ).formatMediumDate(_selectedDateOfBirth!);
    final heightLabel = ValidationService.formatHeight(profile?.height, profile?.heightUnit);
    final hobbies = _hobbies;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileHeader(
              userId: profile?.uid,
              displayName: displayName,
              subtitle: subtitle,
              imageUrl: _selectedProfileImageBytes == null ? effectivePhotoUrl : null,
              imageProvider: _selectedProfileImageBytes != null ? MemoryImage(_selectedProfileImageBytes!) : null,
              hasPhoto: hasPhoto,
              processingPhoto: _processingPhoto,
              savingProfile: widget.controller.savingProfile,
              isVerified: profile?.isVerified == true,
              isPremium: profile?.isPremium == true,
              age: age,
              heightLabel: heightLabel,
              hobbies: hobbies,
              onPickPhoto: _pickProfilePhoto,
              onRemovePhoto: _removePhoto,
            ),
            const SizedBox(height: 20),
            ProfileForm(
              fullNameController: _fullNameController,
              emailController: _emailController,
              phoneController: _phoneController,
              genderController: _genderController,
              religionController: _religionController,
              casteController: _casteController,
              educationController: _educationController,
              occupationController: _occupationController,
              heightController: _heightController,
              hobbyInputController: _hobbyInputController,
              cityController: _cityController,
              countryController: _countryController,
              aboutMeController: _aboutMeController,
              selectedDateOfBirth: _selectedDateOfBirth,
              onPickDateOfBirth: _pickDateOfBirth,
              dobLabel: dobLabel,
              age: age,
              selectedHeightUnit: _selectedHeightUnit,
              onHeightUnitChanged: (v) => setState(() => _selectedHeightUnit = v),
              hobbies: _hobbies,
              onAddHobby: (v) => _addHobby(v),
              onRemoveHobby: (v) => _removeHobby(v),
              onSave: _saveProfile,
              savingProfile: widget.controller.savingProfile,
            ),
          ],
        ),
      ),
    );
  }
}

// Removed unused private helper `_ProfileField` (now handled by `ProfileForm`).

// --- ARCHITECTURE: ResponsiveCardRow ---
 

// Hobby editor removed; ProfileForm handles hobby UX.

// Profile completion result type moved to utils/profile_completion.dart
// This local class is no longer needed.

int _calculateAge(DateTime dateOfBirth) {
  final now = DateTime.now();
  var age = now.year - dateOfBirth.year;
  final hasHadBirthdayThisYear =
      now.month > dateOfBirth.month ||
      (now.month == dateOfBirth.month && now.day >= dateOfBirth.day);
  if (!hasHadBirthdayThisYear) {
    age -= 1;
  }
  return age;
}

 

// ------------------------- Reusable Widgets -------------------------

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color? accent;
  final String? badge;
  final IconData icon;
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.accent,
    this.badge,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseAccent = accent ?? theme.colorScheme.primary;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: baseAccent.withValues(alpha: 0.14),
              child: Icon(icon, color: baseAccent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: baseAccent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            badge!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const QuickActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: null,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class SystemHealthCard extends StatelessWidget {
  const SystemHealthCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'All services operational',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UserActivityTile extends StatelessWidget {
  final String name;
  final String action;
  final String time;
  const UserActivityTile({
    super.key,
    required this.name,
    required this.action,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Text(name[0])),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(action),
      trailing: Text(
        time,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }
}

class MatchCard extends StatelessWidget {
  final String name;
  final int age;
  final String location;
  final int score;
  final VoidCallback? onTap;
  const MatchCard({
    super.key,
    required this.name,
    required this.age,
    required this.location,
    required this.score,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final gradient = LinearGradient(
      colors: [color.withValues(alpha: 0.7), color.withValues(alpha: 0.4)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
        child: SizedBox(
          width: 160,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: gradient,
                      ),
                      child: Center(
                        child: Text(
                          name[0],
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$name, $age',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      location,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: score / 100.0,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$score%',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.favorite_border),
                    color: color,
                    onPressed: null,
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

class ProfileStrength extends StatelessWidget {
  final int percent;
  const ProfileStrength({super.key, required this.percent});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 80,
      width: 80,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 8,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.12),
            ),
          ),
          Center(
            child: CircularProgressIndicator(
              value: percent / 100.0,
              strokeWidth: 8,
              color: color,
            ),
          ),
          Center(
            child: Text(
              '$percent%',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class ActivitySummaryRow extends StatelessWidget {
  final Stream<DashboardActivitySummary> summaryStream;

  const ActivitySummaryRow({super.key, required this.summaryStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DashboardActivitySummary>(
      stream: summaryStream,
      initialData: const DashboardActivitySummary.empty(),
      builder: (context, snapshot) {
        final summary = snapshot.data ?? const DashboardActivitySummary.empty();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _SmallStat(
              label: 'Likes',
              value: _formatCompactCount(summary.likes),
            ),
            _SmallStat(
              label: 'Matches',
              value: _formatCompactCount(summary.matches),
            ),
            _SmallStat(
              label: 'Chats',
              value: _formatCompactCount(summary.chats),
            ),
          ],
        );
      },
    );
  }
}

String _formatCompactCount(int value) {
  if (value >= 1000000) {
    final compact = (value / 1000000).toStringAsFixed(
      value % 1000000 == 0 ? 0 : 1,
    );
    return '${compact}M';
  }
  if (value >= 1000) {
    final compact = (value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1);
    return '${compact}k';
  }
  return value.toString();
}

class _SmallStat extends StatelessWidget {
  final String label;
  final String value;
  const _SmallStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class VisitorList extends StatefulWidget {
  const VisitorList({super.key});

  @override
  State<VisitorList> createState() => _VisitorListState();
}

class _VisitorListState extends State<VisitorList> {
  late final Future<List<UserModel>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _usersFuture = UserService().fetchUsers(limit: 12);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = AuthService().getCurrentUser()?.uid;
    return StreamBuilder<bool>(
      stream: getIt<PremiumService>().isPremiumStream,
      initialData: false,
      builder: (context, premiumSnap) {
        final isPremium = premiumSnap.data ?? false;
        return FutureBuilder<List<UserModel>>(
          future: _usersFuture,
          builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Could not load users right now.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }

        final users = (snapshot.data ?? const <UserModel>[])
          .where((user) => user.uid != currentUserId)
          .toList();

        if (users.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No users found yet.'),
          );
        }

        // Non-premium users see a limited preview with an upgrade CTA
        final previewList = (isPremium ? users.take(5) : users.take(3)).toList();
        final listWidget = Column(
          children: previewList.map((user) {
            final heightLabel = ValidationService.formatHeight(user.height, user.heightUnit);
            final subtitleParts = <String>[
              if (user.location?['city']?.isNotEmpty == true)
                user.location!['city']!,
              if (user.occupation?.isNotEmpty == true) user.occupation!,
              ?heightLabel,
            ];
            return ListTile(
              leading: PresenceAvatar(
                userId: user.uid,
                name: user.fullName,
                imageUrl: user.profilePictureUrl,
              ),
              title: Text(user.fullName),
              subtitle: subtitleParts.isEmpty
                  ? null
                  : Text(subtitleParts.join(' | ')),
              trailing: OutlinedButton(
                onPressed: () => _openUserProfile(context, user),
                child: const Text('View'),
              ),
              onTap: () => _openUserProfile(context, user),
            );
          }).toList(),
        );

        return Column(
          children: [
            listWidget,
            if (!isPremium && users.length > previewList.length) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () async {
                  final ok = await showUpgradeFlow(context);
                  if (!mounted || !ok) return;
                },
                child: const Text('View all â€” Upgrade to Premium'),
              ),
            ]
          ],
        );
      },
    );
      },
    );
  }

  void _openUserProfile(BuildContext context, UserModel user) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _RefinedUserProfileDetailsScreen(user: user)),
    );
  }
}

class _RefinedUserProfileDetailsScreen extends StatelessWidget {
  final UserModel user;

  const _RefinedUserProfileDetailsScreen({required this.user});

  Future<void> _openDirectChat(BuildContext context) async {
    final currentUser = AuthService().getCurrentUser();
    if (currentUser == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign in to start a chat.')));
      return;
    }

    final allowed = await ProfileCompletionGateService.ensureDiscoveryAccess(
      context,
    );
    if (!allowed || !context.mounted) {
      return;
    }

    final canChat = await ChatAccessService().canCurrentUserChat();
    if (!context.mounted) {
      return;
    }
    if (!canChat) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Premium membership is required before you can chat.'),
        ),
      );
      return;
    }

    final userName = currentUser.displayName?.trim().isNotEmpty == true
        ? currentUser.displayName!.trim()
        : (currentUser.email?.split('@').first ?? 'User');

    Navigator.of(
      context,
    ).push(
      MaterialPageRoute(
        builder: (_) => UserHomeScreen(
          userName: userName,
          initialIndex: 2,
          initialChatTarget: ChatLaunchTarget(
            uid: user.uid,
            displayName: user.fullName,
            photoUrl: user.profilePictureUrl,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final age = user.dateOfBirth == null ? null : _calculateAge(user.dateOfBirth!);
    final locationParts = [
      if (user.location?['city']?.trim().isNotEmpty == true) user.location!['city']!.trim(),
      if (user.location?['country']?.trim().isNotEmpty == true) user.location!['country']!.trim(),
    ];
    final location = locationParts.join(', ');
    final heightLabel = ValidationService.formatHeight(user.height, user.heightUnit);
    final hobbies = user.hobbies ?? const <String>[];
    final topInset = MediaQuery.of(context).padding.top;
    final heroHeight = MediaQuery.of(context).size.height * 0.56;
    final identitySummary = [
      if (age != null) '$age yrs',
      if (location.isNotEmpty) location,
    ].join('  •  ');
    final infoChips = <Widget>[
      if (age != null) _RefinedProfilePill(icon: Icons.cake_outlined, label: '$age yrs'),
    ];
    if (location.isNotEmpty) {
      infoChips.add(
        _RefinedProfilePill(icon: Icons.location_on_outlined, label: location),
      );
    }
    if (heightLabel != null) {
      infoChips.add(
        _RefinedProfilePill(icon: Icons.height_rounded, label: heightLabel),
      );
    }
    if (user.religion?.trim().isNotEmpty == true) {
      infoChips.add(
        _RefinedProfilePill(
          icon: Icons.auto_awesome_outlined,
          label: user.religion!.trim(),
        ),
      );
    }
    if (user.education?.trim().isNotEmpty == true) {
      infoChips.add(
        _RefinedProfilePill(
          icon: Icons.school_outlined,
          label: user.education!.trim(),
        ),
      );
    }
    if (user.occupation?.trim().isNotEmpty == true) {
      infoChips.add(
        _RefinedProfilePill(
          icon: Icons.work_outline_rounded,
          label: user.occupation!.trim(),
        ),
      );
    }
    final identityBadges = <Widget>[
      if (age != null) _RefinedProfilePill(icon: Icons.cake_outlined, label: '$age yrs'),
    ];
    if (location.isNotEmpty) {
      identityBadges.add(
        _RefinedProfilePill(icon: Icons.location_on_outlined, label: location),
      );
    }
    final detailsBottomPadding = MediaQuery.of(context).padding.bottom + 112.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F3),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.only(bottom: detailsBottomPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: heroHeight,
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFE7E0D6),
                      image: user.profilePictureUrl?.trim().isNotEmpty == true
                          ? DecorationImage(
                              image: NetworkImage(user.profilePictureUrl!.trim()),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x12000000),
                                Color(0x00000000),
                                Color(0x22000000),
                              ],
                              stops: [0.0, 0.55, 1.0],
                            ),
                          ),
                        ),
                        if (user.profilePictureUrl?.trim().isNotEmpty != true)
                          const Center(
                            child: Icon(
                              Icons.person_rounded,
                              size: 104,
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x12000000),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
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
                                      user.fullName,
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF101010),
                                      ),
                                    ),
                                  ),
                                  if (user.isVerified == true) ...[
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.verified_rounded,
                                      color: Color(0xFF4E9EF7),
                                      size: 24,
                                    ),
                                  ],
                                ],
                              ),
                              if (user.occupation?.trim().isNotEmpty == true) ...[
                                const SizedBox(height: 8),
                                Text(
                                  user.occupation!.trim(),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF3D5C48),
                                  ),
                                ),
                              ],
                              if (identitySummary.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  identitySummary,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF505050),
                                  ),
                                ),
                              ],
                              if (identityBadges.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: identityBadges,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Material(
                          color: const Color(0xFFF4F6F8),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {},
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(
                                Icons.more_horiz_rounded,
                                color: Color(0xFF2B2B2B),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFAF8F5),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (user.aboutMe?.trim().isNotEmpty == true) ...[
                          const _RefinedProfileSectionTitle('About'),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0D000000),
                                  blurRadius: 18,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Text(
                              user.aboutMe!.trim(),
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.55,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (infoChips.isNotEmpty) ...[
                          const _RefinedProfileSectionTitle('Basics'),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: infoChips,
                          ),
                          const SizedBox(height: 24),
                        ],
                        const _RefinedProfileSectionTitle('More Details'),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0D000000),
                                blurRadius: 18,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _RefinedProfileLineItem(label: 'Height', value: heightLabel),
                              _RefinedProfileLineItem(label: 'Religion', value: user.religion),
                              _RefinedProfileLineItem(label: 'Education', value: user.education),
                              _RefinedProfileLineItem(label: 'Occupation', value: user.occupation),
                              _RefinedProfileLineItem(
                                label: 'Family Details',
                                value: user.familyDetails,
                                isLast: hobbies.isEmpty,
                              ),
                              if (hobbies.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                const Text(
                                  'Hobbies',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF6D6D6D),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: hobbies
                                      .map(
                                        (hobby) => _RefinedProfilePill(
                                          icon: Icons.favorite_border_rounded,
                                          label: hobby,
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
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
          Positioned(
            left: 12,
            top: topInset + 12,
            child: _IconCircle(
              icon: Icons.close,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
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
                    icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                    onPressed: () => _openDirectChat(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      ),
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Send Interest'),
                            content: const Text('Send interest action will reuse existing logic.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                            ],
                          ),
                        );
                      },
                      icon: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: const Icon(Icons.favorite, color: Color(0xFF16A34A), size: 18),
                      ),
                      label: const Text('Send Interest', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class _RefinedProfileSectionTitle extends StatelessWidget {
  final String title;

  const _RefinedProfileSectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: Color(0xFF131313),
      ),
    );
  }
}

class _RefinedProfilePill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _RefinedProfilePill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE7E1D6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1D1D1D)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefinedProfileLineItem extends StatelessWidget {
  final String label;
  final String? value;
  final bool isLast;

  const _RefinedProfileLineItem({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedValue = value?.trim();
    if (trimmedValue == null || trimmedValue.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6D6D6D),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            trimmedValue,
            style: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: Color(0xFF242424),
            ),
          ),
          if (!isLast) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF0E9DF)),
          ],
        ],
      ),
    );
  }
}

class _IconCircle extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _IconCircle({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color.fromRGBO(255, 255, 255, 0.95),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, size: 20, color: Colors.black87),
        ),
      ),
    );
  }
}

// ignore: unused_element
class _UserProfileSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _UserProfileSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _UserProfileItem extends StatelessWidget {
  final String label;
  final String? value;

  const _UserProfileItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value!)),
        ],
      ),
    );
  }
}
