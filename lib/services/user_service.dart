import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import '../widgets/beautiful_loader.dart';
import '../models/user_model.dart';
import '../utils/profile_completion.dart';

class FirestoreUnavailableException implements Exception {
  final String message;
  FirestoreUnavailableException(this.message);
  @override
  String toString() => 'FirestoreUnavailableException: $message';
}

class UserService {
  final CollectionReference _usersRef = FirebaseFirestore.instance.collection(
    'users',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Simple in-memory cache to avoid repeated identical reads during short-lived UI rebuilds.
  // Keyed by normalized uid -> Future that resolves to UserModel?;
  final Map<String, Future<UserModel?>> _userCache = {};
  // Configurable TTL for cached futures. Default to 30 seconds.
  Duration _cacheTTL = const Duration(seconds: 30);
  final Map<String, DateTime> _userCacheTimestamps = {};

  DocumentReference<Map<String, dynamic>> _privateProfileRef(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('account');
  }

  Future<void> createUserProfile(
    UserModel user, {
    BuildContext? context,
  }) async {
    Future<void> operation() async {
      try {
        // Defensive check: ensure the client is signed-in as the same UID
        final currentUid = _auth.currentUser?.uid;
        if (currentUid == null || currentUid != user.uid) {
          // ignore: avoid_print
          print('[DEBUG UserService] createUserProfile auth mismatch: authUid=$currentUid targetUid=${user.uid}');
          throw FirestoreUnavailableException('Authenticated UID does not match profile UID.');
        }
        // Diagnostic logging: show which Firestore app is used and payload
        try {
          final app = FirebaseFirestore.instance.app;
          // ignore: avoid_print
          print(
            '[DEBUG UserService] Firestore app: ${app.name}, projectId=${app.options.projectId}, appId=${app.options.appId}',
          );
        } catch (e) {
          // ignore: avoid_print
          print('[DEBUG UserService] Could not read Firestore.app: $e');
        }
        final completionSnapshot = buildProfileCompletionSnapshot(
          user,
          updatedAt: user.profileCompletionUpdatedAt ?? Timestamp.now(),
        );
        final enrichedUser = UserModel.fromMaps({
          ...user.toPublicMap(),
          ...completionSnapshot,
        }, user.toPrivateMap());
        final payload = enrichedUser.toMap();
        // ignore: avoid_print
        print(
          '[DEBUG UserService] createUserProfile payload for uid=${user.uid}: $payload',
        );
        final batch = FirebaseFirestore.instance.batch();
        batch.set(_usersRef.doc(user.uid), enrichedUser.toPublicMap());
        final privateData = enrichedUser.toPrivateMap();
        if (privateData.isNotEmpty) {
          batch.set(_privateProfileRef(user.uid), privateData);
        }
        await batch.commit();
      } catch (e, st) {
        // ignore: avoid_print
        print('[DEBUG UserService] createUserProfile error: $e');
        // ignore: avoid_print
        print(st);
        throw FirestoreUnavailableException(e.toString());
      }
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(
        context,
        operation,
        message: 'We are getting you ready',
      );
    }
    return await operation();
  }

  Future<UserModel?> getUser(String uid, {BuildContext? context}) async {
    final normalizedUid = uid.trim();

    // If a context is provided we don't use the in-memory cache so callers
    // that require a loading UI still show the LoadingScreen correctly.
    if (context == null) {
      final cached = _userCache[normalizedUid];
      final ts = _userCacheTimestamps[normalizedUid];
      if (cached != null && ts != null && DateTime.now().difference(ts) < _cacheTTL) {
        return await cached;
      }
      // stale entry cleanup
      if (cached != null) {
        _userCache.remove(normalizedUid);
        _userCacheTimestamps.remove(normalizedUid);
      }
    }

    Future<UserModel?> operation() async {
      try {
        if (normalizedUid.isEmpty) {
          throw FirestoreUnavailableException(
            'Cannot load a profile without a user id.',
          );
        }
        // Diagnostic: log which document path we're attempting to read
        final currentUid = _auth.currentUser?.uid;
        // ignore: avoid_print
        print('[DEBUG UserService] getUser attempting read for uid=$normalizedUid using authUid=$currentUid path=users/$normalizedUid');
        final doc = await _usersRef.doc(normalizedUid).get();
        if (!doc.exists) {
          return null;
        }
        final data = doc.data();
        if (data == null) {
          return null;
        }
        Map<String, dynamic>? privateData;
        if (currentUid == normalizedUid) {
          try {
            final privateDoc = await _privateProfileRef(normalizedUid).get();
            privateData = privateDoc.data();
          } catch (e) {
            // If we can't read the private doc (rules/permissions), log and continue with public data.
            // ignore: avoid_print
            print('[DEBUG UserService] getUser: could not read private profile for uid=$normalizedUid: $e');
            privateData = null;
          }
        }
        return UserModel.fromMaps(
          data as Map<String, dynamic>,
          privateData,
        );
      } catch (e, st) {
        // ignore: avoid_print
        print('[DEBUG UserService] getUser error: $e');
        // ignore: avoid_print
        print(st);
        // On web, the Firestore JS SDK sometimes throws INTERNAL ASSERTION errors
        // We attempt a single retry after a short delay before failing to reduce
        // transient client-side SDK issues (e.g., IndexedDB state problems).
        if (kIsWeb && e.toString().contains('INTERNAL ASSERTION FAILED')) {
          try {
            await Future.delayed(const Duration(milliseconds: 500));
            final docRetry = await _usersRef.doc(normalizedUid).get();
            if (!docRetry.exists) return null;
            final dataRetry = docRetry.data();
            if (dataRetry == null) return null;
            Map<String, dynamic>? privateData;
            final currentUid = _auth.currentUser?.uid;
            if (currentUid == normalizedUid) {
              try {
                final privateDoc = await _privateProfileRef(normalizedUid).get();
                privateData = privateDoc.data();
              } catch (_) {
                privateData = null;
              }
            }
            return UserModel.fromMaps(dataRetry as Map<String, dynamic>, privateData);
          } catch (e2, st2) {
            // ignore: avoid_print
            print('[DEBUG UserService] getUser retry failed: $e2');
            // ignore: avoid_print
            print(st2);
            throw FirestoreUnavailableException(e2.toString());
          }
        }
        throw FirestoreUnavailableException(e.toString());
      }
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }

    // Store the future in the cache so concurrent callers for the same uid
    // share the same underlying request and we avoid repeated reads.
    final future = operation();
    _userCache[normalizedUid] = future;
    _userCacheTimestamps[normalizedUid] = DateTime.now();
    try {
      return await future;
    } finally {
      // keep cache entry for short TTL; invalidation occurs on updates
      // or when entries age out on next access.
    }
  }

  /// Returns true if the current authenticated user is marked as premium.
  Future<bool> isCurrentUserPremium() async {
    try {
      final currentUid = _auth.currentUser?.uid;
      if (currentUid == null) return false;
      final doc = await _usersRef.doc(currentUid).get();
      if (!doc.exists) return false;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return false;
      return data['isPremium'] == true;
    } catch (e, st) {
      // ignore: avoid_print
      print('[DEBUG UserService] isCurrentUserPremium error: $e');
      // ignore: avoid_print
      print(st);
      return false;
    }
  }

  Future<void> updateUser(
    String uid,
    Map<String, dynamic> data, {
    BuildContext? context,
  }) async {
    Future<void> operation() async {
      try {
        final currentUid = _auth.currentUser?.uid;
        if (currentUid == null || currentUid != uid) {
          // ignore: avoid_print
          print('[DEBUG UserService] updateUser auth mismatch: authUid=$currentUid targetUid=$uid');
          throw FirestoreUnavailableException('Authenticated UID does not match update target UID.');
        }
        final publicData = <String, dynamic>{};
        final privateData = <String, dynamic>{};

        for (final entry in data.entries) {
          if (UserModel.privateFieldKeys.contains(entry.key)) {
            privateData[entry.key] = entry.value;
          } else {
            publicData[entry.key] = entry.value;
          }
        }

        final batch = FirebaseFirestore.instance.batch();
        if (publicData.isNotEmpty) {
          batch.set(_usersRef.doc(uid), publicData, SetOptions(merge: true));
        }
        if (privateData.isNotEmpty) {
          batch.set(
            _privateProfileRef(uid),
            privateData,
            SetOptions(merge: true),
          );
        }
        if (publicData.isEmpty && privateData.isEmpty) {
          return;
        }
        await batch.commit();
      } catch (e, st) {
        // ignore: avoid_print
        print('[DEBUG UserService] updateUser error: $e');
        // ignore: avoid_print
        print(st);
        throw FirestoreUnavailableException(e.toString());
      }
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }
    final result = await operation();
    // Invalidate cached user so subsequent reads fetch fresh data.
    final key = uid.trim();
    _userCache.remove(key);
    _userCacheTimestamps.remove(key);
    return result;
  }

  /// Invalidate cached entry for a specific user UID.
  void invalidateUserCache(String uid) {
    final key = uid.trim();
    _userCache.remove(key);
    _userCacheTimestamps.remove(key);
  }

  /// Invalidate cached entries for multiple UIDs.
  void invalidateUserCaches(List<String> uids) {
    for (final uid in uids) {
      invalidateUserCache(uid);
    }
  }

  /// Set the in-memory cache TTL used to consider entries fresh.
  /// Useful for tests or adjusting behavior in low-network scenarios.
  void setCacheTTL(Duration ttl) {
    _cacheTTL = ttl;
  }

  /// Force a sweep to remove stale cache entries older than the current TTL.
  void sweepStaleCacheEntries() {
    final now = DateTime.now();
    final expired = <String>[];
    for (final entry in _userCacheTimestamps.entries) {
      if (now.difference(entry.value) >= _cacheTTL) {
        expired.add(entry.key);
      }
    }
    for (final k in expired) {
      _userCache.remove(k);
      _userCacheTimestamps.remove(k);
    }
  }

  /// Clear the entire in-memory user cache.
  void clearUserCache() {
    _userCache.clear();
    _userCacheTimestamps.clear();
  }

  Future<void> updatePresence(
    String uid, {
    required bool isOnline,
    Timestamp? lastSeenAt,
  }) async {
    try {
      final currentUid = _auth.currentUser?.uid;
      if (currentUid == null || currentUid != uid) {
        // ignore: avoid_print
        print('[DEBUG UserService] updatePresence auth mismatch: authUid=$currentUid targetUid=$uid');
        throw FirestoreUnavailableException('Authenticated UID does not match presence target UID.');
      }
      await _usersRef.doc(uid).set({
        'uid': uid,
        'isOnline': isOnline,
        'lastSeenAt': lastSeenAt ?? Timestamp.now(),
      }, SetOptions(merge: true));
      // ignore: avoid_print
      print(
        '[DEBUG UserService] updatePresence uid=$uid isOnline=$isOnline lastSeenAt=${(lastSeenAt ?? Timestamp.now()).toDate().toIso8601String()}',
      );
    } catch (e, st) {
      // For certain internal Firestore assertion errors on web SDK, swallow and log
      final msg = e.toString();
      // ignore: avoid_print
      print('[DEBUG UserService] updatePresence error: $e');
      // ignore: avoid_print
      print(st);
      if (kIsWeb && msg.contains('INTERNAL ASSERTION FAILED')) {
        // Do not throw to avoid crashing UI from a client-side SDK bug.
        // ignore: avoid_print
        print('[DEBUG UserService] suppressed web INTERNAL ASSERTION error while updating presence.');
        return;
      }
      throw FirestoreUnavailableException(e.toString());
    }
  }

  Future<List<UserModel>> fetchUsers({
    int? minAge,
    int? maxAge,
    String? city,
    String? religion,
    String? gender,
    String? education,
    String? occupation,
    String? income,
    String? excludeUserId, // exclude current user and blocked users
    List<String>? excludeUserIds, // exclude specific users (blocked, etc)
    int limit = 50,
    BuildContext? context,
  }) async {
    Future<List<UserModel>> operation() async {
      Query query = _usersRef;

      if (gender != null) {
        query = query.where('gender', isEqualTo: gender);
      }
      if (religion != null) {
        query = query.where('religion', isEqualTo: religion);
      }
      if (education != null) {
        query = query.where('education', isEqualTo: education);
      }
      if (occupation != null) {
        query = query.where('occupation', isEqualTo: occupation);
      }
      if (income != null) {
        query = query.where('income', isEqualTo: income);
      }
      if (city != null) {
        query = query.where('location.city', isEqualTo: city);
      }

      // Age filtering: convert to dateOfBirth range
      if (minAge != null || maxAge != null) {
        final now = DateTime.now();
        if (minAge != null) {
          final maxDob = DateTime(now.year - minAge, now.month, now.day);
          query = query.where(
            'dateOfBirth',
            isLessThanOrEqualTo: Timestamp.fromDate(maxDob),
          );
        }
        if (maxAge != null) {
          final minDob = DateTime(
            now.year - maxAge - 1,
            now.month,
            now.day,
          ).add(const Duration(days: 1));
          query = query.where(
            'dateOfBirth',
            isGreaterThanOrEqualTo: Timestamp.fromDate(minDob),
          );
        }
      }

      try {
        final snapshot = await query.limit(limit * 2).get(); // Fetch extra for filtering
        final docs = snapshot.docs.toList();
        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aBoost = aData['boostExpiresAt'];
          final bBoost = bData['boostExpiresAt'];
          final aBoostMs = aBoost is Timestamp ? aBoost.toDate().millisecondsSinceEpoch : 0;
          final bBoostMs = bBoost is Timestamp ? bBoost.toDate().millisecondsSinceEpoch : 0;
          final aActive = aBoostMs > DateTime.now().millisecondsSinceEpoch;
          final bActive = bBoostMs > DateTime.now().millisecondsSinceEpoch;
          if (aActive != bActive) return aActive ? -1 : 1;
          if (aBoostMs != bBoostMs) return bBoostMs.compareTo(aBoostMs);
          return 0;
        });

        var users = docs
            .map((d) => UserModel.fromMap(d.data() as Map<String, dynamic>))
            .toList();

        // Filter out excluded users (current user, blocked users, etc)
        if (excludeUserId != null || (excludeUserIds?.isNotEmpty ?? false)) {
          final idsToExclude = <String>{};
          if (excludeUserId != null) idsToExclude.add(excludeUserId);
          if (excludeUserIds != null) idsToExclude.addAll(excludeUserIds);
          users = users.where((u) => !idsToExclude.contains(u.uid)).toList();
        }

        return users.take(limit).toList();
      } catch (e, st) {
        // ignore: avoid_print
        print('[DEBUG UserService] fetchUsers error: $e');
        // ignore: avoid_print
        print(st);
        throw FirestoreUnavailableException(e.toString());
      }
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    }
    return await operation();
  }

  /// Get profiles based on filters with pagination
  Future<List<UserModel>> getDiscoverProfiles({
    String? currentUserId,
    int? minAge,
    int? maxAge,
    String? city,
    String? religion,
    String? gender,
    String? education,
    int limit = 20,
    List<String>? excludeUserIds,
    BuildContext? context,
  }) async {
    return fetchUsers(
      minAge: minAge,
      maxAge: maxAge,
      city: city,
      religion: religion,
      gender: gender,
      education: education,
      excludeUserId: currentUserId,
      excludeUserIds: excludeUserIds,
      limit: limit,
      context: context,
    );
  }
}

