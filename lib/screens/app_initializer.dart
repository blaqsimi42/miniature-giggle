import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/beautiful_loader.dart';
import '../services/profile_completion_gate_service.dart';
import '../services/route_persistence.dart';
import '../utils/profile_completion.dart';

class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _started = false;
  static const Set<String> _guestRestorableRoutes = {
    '/login',
    '/personal',
    '/password',
    '/forgot-password',
    '/phone-login',
    '/onboarding',
  };
  static const Set<String> _authenticatedRestorableRoutes = {
    '/home',
    '/profile',
    '/edit-profile',
    '/profile-completion-gate',
    '/profile-setup',
    '/privacy-safety',
    '/notifications',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startInitialization());
  }

  Future<void> _startInitialization() async {
    if (_started) return;
    _started = true;

    // Show the overlay loader while we preload images and do early setup.
    LoadingScreen.show(context);

    // List of images we want to ensure are ready for display.
    // Only include assets that actually exist in the repository to avoid
    // 404s during web development.
    final images = <String>[
      'assets/images/nikkah.png',
      'assets/images/halal.png',
    ];

    // Attempt to precache each image with a per-image timeout so we don't hang forever
    final futures = images.map((asset) async {
      try {
        await precacheImage(
          AssetImage(asset),
          context,
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        // ignore individual failures — we'll still continue to the app
      }
    }).toList();

    // Wait for all precache attempts (they either complete or timeout)
    await Future.wait(futures);

    // Small delay so the loader feels smooth
    await Future.delayed(const Duration(milliseconds: 400));

    // Check for a saved last route (from previous session) and navigate there.
    final saved = await RoutePersistence.getSaved();
    final currentUser = FirebaseAuth.instance.currentUser;
    LoadingScreen.hide();
    if (!mounted) return;

    final route = saved?['route'] as String?;
    final args = saved?['args'];

    if (currentUser == null) {
      if (route != null && _guestRestorableRoutes.contains(route)) {
        Navigator.of(context).pushReplacementNamed(route, arguments: args);
        return;
      }
      Navigator.of(context).pushReplacementNamed('/onboarding');
      return;
    }

    if (route != null && _authenticatedRestorableRoutes.contains(route)) {
      final profile = await ProfileCompletionGateService.loadCurrentProfile();
      if (!mounted) return;
      final completion = calculateProfileCompletion(profile);
      if (!completion.meetsDiscoveryThreshold &&
          route != '/profile-setup') {
        Navigator.of(context).pushReplacementNamed(
          '/profile-setup',
          arguments: {
            'initialStep': inferJourneyStep(profile),
            'completionPercent': completion.percent,
          },
        );
        return;
      }
      Navigator.of(context).pushReplacementNamed(route, arguments: args);
      return;
    }

    final profile = await ProfileCompletionGateService.loadCurrentProfile();
    if (!mounted) return;
    final completion = calculateProfileCompletion(profile);
    if (completion.meetsDiscoveryThreshold) {
      Navigator.of(context).pushReplacementNamed('/home');
      return;
    }
    Navigator.of(context).pushReplacementNamed(
      '/profile-setup',
      arguments: {
        'initialStep': inferJourneyStep(profile),
        'completionPercent': completion.percent,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // While initialization is happening, show an empty scaffold — the loader overlay will be visible.
    return const Scaffold(body: SizedBox.expand());
  }
}
