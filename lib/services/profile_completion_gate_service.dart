import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../utils/profile_completion.dart';
import 'user_service.dart';

class ProfileCompletionGateService {
  const ProfileCompletionGateService._();
  static bool _routingInProgress = false;

  static Future<UserModel?> _syncStoredCompletion(UserModel? profile) async {
    if (profile == null) return null;

    final weighted = calculateWeightedProfileCompletion(profile);
    final storedPercent = profile.profileCompletion?.round();
    final storedCompleted = profile.profileSetupCompleted;
    final needsSync = storedPercent == null ||
        storedPercent != weighted.percent ||
        storedCompleted == null ||
        storedCompleted != weighted.meetsDiscoveryThreshold;

    if (!needsSync) return profile;

    final snapshot = buildProfileCompletionSnapshot(
      profile,
      updatedAt: Timestamp.now(),
    );
    await UserService().updateUser(profile.uid, snapshot);
    return await UserService().getUser(profile.uid) ?? UserModel.fromMaps({
      ...profile.toPublicMap(),
      ...snapshot,
      'email': profile.email,
      'phone': profile.phone,
    });
  }

  static Future<UserModel?> loadCurrentProfile() async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return null;
    final existing = await UserService().getUser(authUser.uid);
    if (existing != null) return _syncStoredCompletion(existing);

    final fallbackName = (authUser.displayName ?? '').trim().isNotEmpty
        ? authUser.displayName!.trim()
        : authUser.email?.split('@').first ?? 'Member';
    final fallback = UserModel(
      uid: authUser.uid,
      fullName: fallbackName,
      email: authUser.email,
      phone: authUser.phoneNumber,
      profilePictureUrl: authUser.photoURL,
      profilePhotoUrl: authUser.photoURL,
      createdAt: Timestamp.now(),
    );
    return _syncStoredCompletion(fallback);
  }

  static Future<void> routeAfterAuth(
    BuildContext context, {
    Map<String, dynamic>? homeArgs,
  }) async {
    if (_routingInProgress) return;
    _routingInProgress = true;
    try {
      // Wait briefly for FirebaseAuth.currentUser to be available after sign-in.
      var attempts = 0;
      while (FirebaseAuth.instance.currentUser == null && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 150));
        attempts += 1;
      }

      final profile = await loadCurrentProfile();
      if (!context.mounted) return;
      final completion = calculateProfileCompletion(profile);
      if (completion.meetsDiscoveryThreshold) {
        Navigator.of(context).pushReplacementNamed('/home', arguments: {
          ...?homeArgs,
          'completionPercent': completion.percent,
        });
        return;
      }

      Navigator.of(context).pushReplacementNamed(
        '/profile-setup',
        arguments: {
          ...?homeArgs,
          'initialStep': inferJourneyStep(profile),
          'completionPercent': completion.percent,
        },
      );
    } finally {
      _routingInProgress = false;
    }
  }

  static Future<bool> ensureDiscoveryAccess(
    BuildContext context, {
    UserModel? profile,
  }) async {
    final resolved = profile ?? await loadCurrentProfile();
    final completion = calculateProfileCompletion(resolved);
    if (completion.meetsDiscoveryThreshold) {
      return true;
    }

    if (!context.mounted) return false;
    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Complete your profile to continue',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF171717),
            ),
          ),
          content: Text(
            'Your profile is currently ${completion.percent}% complete. Reach 70% to start connecting with compatible matches.',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not Now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5C2E),
                foregroundColor: Colors.white,
              ),
              child: const Text('Continue Setup'),
            ),
          ],
        );
      },
    );

    if (shouldContinue == true && context.mounted) {
      Navigator.of(context).pushNamed(
        '/profile-setup',
        arguments: const {
          'initialStep': 0,
        },
      );
    }
    return false;
  }
}
