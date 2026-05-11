import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'core/config/service_locator.dart';
import 'models/user_model.dart';
import 'services/fcm_service.dart';
import 'services/network_status_service.dart';
import 'firebase_options.dart';
import 'screens/app_initializer.dart';
import 'screens/browse_profiles_screen.dart';
import 'screens/debug_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/profile_view_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/home_dashboard.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/password_setup_screen.dart';
import 'screens/personal_details_screen.dart';
import 'screens/phone_login_screen.dart';
import 'screens/verify_phone_link_screen.dart';
import 'services/auth_service.dart';
import 'services/route_persistence.dart';
import 'screens/payment_screen.dart';
import 'screens/manage_subscription_screen.dart';
import 'screens/privacy_safety_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/notification_settings_screen.dart';
import 'screens/app_settings_screen.dart';
import 'screens/profile_completion_gate_screen.dart';
import 'screens/profile_setup_journey_screen.dart';
import 'screens/reset_password_via_otp_screen.dart';
import 'screens/matches_screen.dart';
import 'screens/add_guardian_screen.dart';
import 'screens/guardian_invitation_sent_screen.dart';
import 'widgets/app_notice.dart';



Future<void> main() async {
  // Ensure the bindings, Firebase initialization and runApp all execute in the
  // same Zone to avoid the "Zone mismatch" runtime assertion on web.
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      if (kDebugMode) debugPrint('[DEBUG] Firebase.initializeApp succeeded. Apps: ${Firebase.apps.map((a) => a.name).toList()}');
      try {
        final u = FirebaseAuth.instance.currentUser;
        if (kDebugMode) debugPrint('[DEBUG] FirebaseAuth.currentUser: $u');
      } catch (e) {
        if (kDebugMode) debugPrint('[DEBUG] FirebaseAuth access error: $e');
      }

      // Keep startup diagnostics read-only unless a user is already authenticated.
      try {
        final firestore = FirebaseFirestore.instance;
        if (kDebugMode) debugPrint('[DEBUG] FirebaseFirestore instance available. App name: ${firestore.app.name}');
        if (kDebugMode) debugPrint('[DEBUG] Firestore projectId: ${firestore.app.options.projectId}');
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          try {
            final snap = await firestore.collection('users').doc(currentUser.uid).get();
            if (kDebugMode) debugPrint('[DEBUG] Firestore current-user check succeeded. exists=${snap.exists}');
          } catch (e, st) {
            if (kDebugMode) debugPrint('[WARN] Firestore current-user check failed: $e\n$st');
          }
        } else {
          if (kDebugMode) debugPrint('[DEBUG] Skipping Firestore user read because no user is signed in yet.');
        }
      } catch (e, st) {
        if (kDebugMode) debugPrint('[WARN] Firestore initialization/access error: $e\n$st');
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[ERROR] Firebase.initializeApp failed: $e\n$st');
    }

    // Setup service locator for dependency injection AFTER Firebase is initialized
    await setupServiceLocator();
    // Register background message handler (must be a top-level function)
    try {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] onBackgroundMessage registration failed: $e');
    }
    // Initialize FCM and subscribe to development topic for premium events
    try {
      await getIt<FcmService>().initialize(onMessage: (msg) {
        if (kDebugMode) debugPrint('[FCM] message received: ${msg.notification?.title} - ${msg.notification?.body}');
        // Show an in-app banner/snackbar when messages arrive while app is foreground
        final title = msg.notification?.title ?? 'Notification';
        final body = msg.notification?.body ?? '';
        MyApp.scaffoldKey.currentState?.showSnackBar(
          SnackBar(content: Text('$title: $body')),
        );
      });
      await getIt<FcmService>().subscribeToTopic('premium-updates');
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] initialization error: $e');
    }

    try {
      await getIt<NetworkStatusService>().start();
    } catch (e) {
      if (kDebugMode) debugPrint('[NetworkStatus] initialization error: $e');
    }

    // Global error handling: prevent certain engine/web assertions from crashing the app
    FlutterError.onError = (FlutterErrorDetails details) {
      final msg = details.exceptionAsString();
      if (msg.contains('ViewInsets cannot be negative')) {
        if (kDebugMode) debugPrint('[WARN] suppressed engine assertion: $msg');
        return;
      }
      // Suppress known sporadic web Firestore internal assertion failures
      if (kIsWeb && msg.contains('INTERNAL ASSERTION FAILED')) {
        if (kDebugMode) debugPrint('[WARN] suppressed web Firestore internal assertion: $msg');
        return;
      }
      FlutterError.presentError(details);
    };

    runApp(const MyApp());
  }, (error, stack) {
    final msg = error.toString();
    if (msg.contains('ViewInsets cannot be negative')) {
      if (kDebugMode) debugPrint('[WARN] suppressed zoned engine assertion: $msg');
      return;
    }
    // Suppress web Firestore internal assertion failures thrown from JS SDK
    if (kIsWeb && msg.contains('INTERNAL ASSERTION FAILED')) {
      if (kDebugMode) debugPrint('[WARN] suppressed zoned web Firestore internal assertion: $msg');
      return;
    }
    // ignore: avoid_print
    print('[ERROR uncaught] $error');
  });
}

// Background message handler must be a top-level function.
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  if (kDebugMode) {
    debugPrint('[FCM background] Message received: ${message.messageId} ${message.notification?.title} - ${message.notification?.body}');
  }
}

// Theme constants
  const Color kPrimaryGreen = Color(0xFF16A34A);
  const Color kBackgroundWhite = Color(0xFFFFFFFF);
  const Color kSecondaryBg = Color(0xFFF5F5F5);
  const Color kTextPrimary = Color(0xFF111827);
  const Color kTextSecondary = Color(0xFF6B7280);

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  static final GlobalKey<ScaffoldMessengerState> scaffoldKey = GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
  static final RoutePersistenceObserver routeObserver = RoutePersistenceObserver();

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: kPrimaryGreen,
        surface: kBackgroundWhite,
      ),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Qubool Nikah',
      navigatorKey: MyApp.navKey,
      scaffoldMessengerKey: MyApp.scaffoldKey,
      navigatorObservers: [MyApp.routeObserver],
      theme: base.copyWith(
        textTheme: GoogleFonts.poppinsTextTheme(
          base.textTheme,
        ).apply(bodyColor: kTextPrimary, displayColor: kTextPrimary),
        scaffoldBackgroundColor: kBackgroundWhite,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kSecondaryBg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
      builder: (context, child) {
        return _NetworkStatusToastHost(
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AppInitializer(),
      routes: {
        '/onboarding': (_) => const OnboardingScreen(),
        '/personal': (_) => const PersonalDetailsScreen(),
        '/password': (_) => const PasswordSetupScreen(),
        '/verify-phone-link': (_) => const VerifyPhoneLinkScreen(),
        '/login': (_) => const LoginScreen(),
        '/forgot-password': (_) => const ForgotPasswordScreen(),
        '/phone-login': (_) => const PhoneLoginScreen(),
        '/reset-password-otp': (_) => const ResetPasswordViaOtpScreen(),
        '/debug': (_) => const DebugScreen(),
        '/browse': (_) => const BrowseProfilesScreen(),
        '/matches': (_) => const MatchesScreen(),
        '/guardian/add': (_) => const AddGuardianScreen(),
        '/guardian/sent': (_) => const GuardianInvitationSentScreen(),
        '/payment': (ctx) {
          final route = ModalRoute.of(ctx);
          final args = route?.settings.arguments;
          if (args is Map<String, dynamic>) {
            return PaymentScreen(
              amount: args['amount'] is int ? args['amount'] as int : 239900,
              initialPlanId: args['initialPlanId'] as String? ?? 'premium',
              includeBoostPlan: args['includeBoostPlan'] == true,
            );
          }
          return const PaymentScreen();
        },
        '/manage-subscription': (_) => const ManageSubscriptionScreen(),
        '/app-settings': (_) => const AppSettingsScreen(),
        '/profile-completion-gate': (_) => const ProfileCompletionGateScreen(),
        '/profile-setup': (_) => const ProfileSetupJourneyScreen(),
        '/edit-profile': (ctx) {
          final route = ModalRoute.of(ctx);
          final args = route?.settings.arguments;
          String userId;
          if (args is String) {
            userId = args;
          } else {
            final u = AuthService().getCurrentUser();
            userId = u?.uid ?? '';
          }
          return EditProfileScreen(userId: userId);
        },
        '/view-profile': (ctx) {
          final route = ModalRoute.of(ctx);
          final args = route?.settings.arguments;
          if (args is UserModel) {
            return ProfileViewScreen(userId: args.uid, initialProfile: args);
          }
          if (args is String && args.isNotEmpty) {
            return ProfileViewScreen(userId: args);
          }
          final u = AuthService().getCurrentUser();
          return ProfileViewScreen(userId: u?.uid ?? '');
        },
        '/privacy-safety': (_) => const PrivacySafetyScreen(),
        '/notifications': (_) => const NotificationsScreen(),
        '/notification-settings': (_) => const NotificationSettingsScreen(),
        '/profile': (ctx) {
          final u = AuthService().getCurrentUser();
          final userName = u?.displayName ?? u?.email?.split('@').first ?? 'User';
          return UserHomeScreen(userName: userName, initialIndex: 3);
        },
        '/home': (ctx) {
          final route = ModalRoute.of(ctx);
          final args = route?.settings.arguments;
          String userName;
          int initialIndex = 0;
          if (args is String) {
            userName = args;
          } else if (args is Map<String, dynamic> && args['userName'] is String) {
            userName = args['userName'] as String;
            if (args['initialIndex'] is int) {
              initialIndex = args['initialIndex'] as int;
            }
          } else if (args is Map && args['name'] is String) {
            userName = args['name'] as String;
            if (args['initialIndex'] is int) {
              initialIndex = args['initialIndex'] as int;
            }
          } else {
            final u = AuthService().getCurrentUser();
            userName = u?.displayName ?? u?.email?.split('@').first ?? 'User';
          }
          return UserHomeScreen(userName: userName, initialIndex: initialIndex);
        },
      },
    );
  }
}

class _NetworkStatusToastHost extends StatefulWidget {
  final Widget child;

  const _NetworkStatusToastHost({required this.child});

  @override
  State<_NetworkStatusToastHost> createState() => _NetworkStatusToastHostState();
}

class _NetworkStatusToastHostState extends State<_NetworkStatusToastHost> {
  StreamSubscription<NetworkStatus>? _networkSub;
  NetworkStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _lastStatus = getIt<NetworkStatusService>().currentStatus;
      _showNoticeFor(_lastStatus!, initial: true);
    });
    _networkSub = getIt<NetworkStatusService>().stream.listen((status) {
      if (!mounted) return;
      final previousStatus = _lastStatus;
      _lastStatus = status;
      _showNoticeFor(status, previousStatus: previousStatus);
    });
  }

  void _showNoticeFor(
    NetworkStatus status, {
    NetworkStatus? previousStatus,
    bool initial = false,
  }) {
    switch (status) {
      case NetworkStatus.offline:
        MyApp.scaffoldKey.currentState?.hideCurrentSnackBar();
        AppNotice.showError(
          context,
          'No internet connection.',
          fallbackMessage: 'No internet connection.',
        );
        break;
      case NetworkStatus.slow:
        MyApp.scaffoldKey.currentState?.hideCurrentSnackBar();
        AppNotice.showError(
          context,
          'Bad network connection.',
          fallbackMessage: 'Bad network connection.',
        );
        break;
      case NetworkStatus.online:
        if (!initial &&
            previousStatus != null &&
            previousStatus != NetworkStatus.online) {
          MyApp.scaffoldKey.currentState?.hideCurrentSnackBar();
          AppNotice.showSuccess(context, 'Back online');
        }
        break;
    }
  }

  @override
  void dispose() {
    _networkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
