import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/interaction_models.dart';

class InteractionsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _docId(List<String> parts) => parts.join('_');

  // ============== INTERESTS ==============
  
  /// Send interest to another user
  Future<void> sendInterest(
    String currentUserId,
    String targetUserId, {
    String? message,
  }) async {
    final interestId = const Uuid().v4();
    final sentAt = Timestamp.now();
    await _firestore.collection('interactions').doc(interestId).set({
      'id': interestId,
      'senderId': currentUserId,
      'receiverId': targetUserId,
      'type': 'interest',
      'status': 'pending',
      'sentAt': sentAt,
      if (message != null && message.isNotEmpty) 'message': message,
    });

    // Best-effort notification fanout into the receiver's inbox.
    try {
      final senderSnap = await _firestore
          .collection('users')
          .doc(currentUserId)
          .get();
      final senderData = senderSnap.data() ?? const <String, dynamic>{};
      final senderName =
          (senderData['fullName'] as String?)?.trim().isNotEmpty == true
              ? (senderData['fullName'] as String).trim()
              : 'Someone';
      final senderPhotoUrl =
          (senderData['profilePictureUrl'] as String?)?.trim();

      final notificationRef = _firestore
          .collection('users')
          .doc(targetUserId)
          .collection('notifications')
          .doc();

      await notificationRef.set({
        'id': notificationRef.id,
        'type': 'interest_received',
        'category': 'interests',
        'priority': 'high',
        'receiverId': targetUserId,
        'actorId': currentUserId,
        'actorName': senderName,
        'actorPhotoUrl': senderPhotoUrl,
        'title': 'New interest received',
        'body': '$senderName sent you an interest.',
        'isRead': false,
        'isSeen': false,
        'createdAt': sentAt,
        'readAt': null,
        'seenAt': null,
        'action': {
          'route': '/view-profile',
          'entityType': 'user',
          'entityId': currentUserId,
        },
        'data': {
          'interestId': interestId,
          'senderId': currentUserId,
        },
      });
    } on FirebaseException {
      // Keep interest sending usable even if notification fanout fails.
    }
  }

  /// Respond to an interest (accept or reject)
  Future<void> respondToInterest(
    String interestId,
    InterestStatus status,
  ) async {
    await _firestore.collection('interactions').doc(interestId).update({
      'status': status.name,
      'respondedAt': Timestamp.now(),
    });
  }

  /// Get incoming interests for current user
  Stream<List<InterestModel>> getIncomingInterests(String userId) {
    return _firestore
        .collection('interactions')
        .where('receiverId', isEqualTo: userId)
        .where('type', isEqualTo: 'interest')
        .snapshots()
        .map((snap) {
          final items = snap.docs
              .map((doc) => InterestModel.fromMap(doc.data(), doc.id))
              .toList();
          items.sort((a, b) => b.sentAt.compareTo(a.sentAt));
          return items;
        });
  }

  /// Get sent interests for current user
  Stream<List<InterestModel>> getSentInterests(String userId) {
    return _firestore
        .collection('interactions')
        .where('senderId', isEqualTo: userId)
        .where('type', isEqualTo: 'interest')
        .snapshots()
        .map((snap) {
          final items = snap.docs
              .map((doc) => InterestModel.fromMap(doc.data(), doc.id))
              .toList();
          items.sort((a, b) => b.sentAt.compareTo(a.sentAt));
          return items;
        });
  }

  /// Check if user has already sent interest to another user
  Future<bool> hasInterestPending(String senderId, String receiverId) async {
    final query = await _firestore
        .collection('interactions')
        .where('senderId', isEqualTo: senderId)
        .where('receiverId', isEqualTo: receiverId)
        .where('type', isEqualTo: 'interest')
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    return query.docs.isNotEmpty;
  }

  // ============== LIKES ==============

  /// Like a profile
  Future<void> likeProfile(String currentUserId, String profileUserId) async {
    final batch = _firestore.batch();
    final likedAt = Timestamp.now();

    // Add to user's likes
    final userLikeRef = _firestore
      .collection('interactions')
      .doc(_docId([currentUserId, 'likes', profileUserId]));
    batch.set(userLikeRef, {
      'userId': currentUserId,
      'likedUserId': profileUserId,
      'type': 'like',
      'likedAt': likedAt,
    });

    // Add to profile owner's likedBy
    final profileLikedByRef = _firestore
      .collection('interactions')
      .doc(_docId([profileUserId, 'likedBy', currentUserId]));
    batch.set(profileLikedByRef, {
      'userId': currentUserId,
      'likedUserId': profileUserId,
      'type': 'likedBy',
      'likedAt': likedAt,
    });

    await batch.commit();

    // Best-effort notification fanout into the liked user's inbox.
    try {
      final senderSnap = await _firestore
          .collection('users')
          .doc(currentUserId)
          .get();
      final senderData = senderSnap.data() ?? const <String, dynamic>{};
      final senderName =
          (senderData['fullName'] as String?)?.trim().isNotEmpty == true
              ? (senderData['fullName'] as String).trim()
              : 'Someone';
      final senderPhotoUrl =
          (senderData['profilePictureUrl'] as String?)?.trim();

      final notificationRef = _firestore
          .collection('users')
          .doc(profileUserId)
          .collection('notifications')
          .doc();

      await notificationRef.set({
        'id': notificationRef.id,
        'type': 'profile_liked',
        'category': 'profile',
        'priority': 'medium',
        'receiverId': profileUserId,
        'actorId': currentUserId,
        'actorName': senderName,
        'actorPhotoUrl': senderPhotoUrl,
        'title': 'Your profile was liked',
        'body': '$senderName liked your profile.',
        'isRead': false,
        'isSeen': false,
        'createdAt': likedAt,
        'readAt': null,
        'seenAt': null,
        'action': {
          'route': '/view-profile',
          'entityType': 'user',
          'entityId': currentUserId,
        },
        'data': {
          'likedUserId': profileUserId,
          'senderId': currentUserId,
        },
      });
    } on FirebaseException {
      // Keep like interactions usable even if notification fanout fails.
    }
  }

  /// Unlike a profile
  Future<void> unlikeProfile(String currentUserId, String profileUserId) async {
    final userLikeRef = _firestore
      .collection('interactions')
      .doc(_docId([currentUserId, 'likes', profileUserId]));
    final profileLikedByRef = _firestore
      .collection('interactions')
      .doc(_docId([profileUserId, 'likedBy', currentUserId]));

    // Remove the current user's like first. This is the source of truth for
    // the local liked state and should not depend on cleanup of any mirror doc.
    await userLikeRef.delete();

    // Best-effort cleanup for legacy/mirrored likedBy documents. If rules do
    // not allow deleting this companion doc, do not fail the unlike action.
    try {
      await profileLikedByRef.delete();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' && e.code != 'not-found') {
        rethrow;
      }
    }
  }

  /// Get profiles liked by current user
  Stream<List<String>> getLikedProfiles(String userId) {
    return _firestore
        .collection('interactions')
        .where('userId', isEqualTo: userId)
        .where('type', isEqualTo: 'like')
        .snapshots()
        .map((snap) {
          final docs = [...snap.docs]
            ..sort((a, b) {
              final aTs = a.data()['likedAt'] as Timestamp?;
              final bTs = b.data()['likedAt'] as Timestamp?;
              final aMs = aTs?.millisecondsSinceEpoch ?? 0;
              final bMs = bTs?.millisecondsSinceEpoch ?? 0;
              return bMs.compareTo(aMs);
            });
          return docs
              .map((doc) => doc.data()['likedUserId'] as String)
              .toList();
        });
  }

  /// Get profiles that liked current user
  Stream<List<String>> getLikedByProfiles(String userId) {
    return _firestore
        .collection('interactions')
        .where('likedUserId', isEqualTo: userId)
        .where('type', isEqualTo: 'likedBy')
        .snapshots()
        .map((snap) {
          final docs = [...snap.docs]
            ..sort((a, b) {
              final aTs = a.data()['likedAt'] as Timestamp?;
              final bTs = b.data()['likedAt'] as Timestamp?;
              final aMs = aTs?.millisecondsSinceEpoch ?? 0;
              final bMs = bTs?.millisecondsSinceEpoch ?? 0;
              return bMs.compareTo(aMs);
            });
          return docs.map((doc) => doc.data()['userId'] as String).toList();
        });
  }

  /// Check if user has liked a profile
  Future<bool> hasLikedProfile(String userId, String profileUserId) async {
    final doc = await _firestore
      .collection('interactions')
      .doc(_docId([userId, 'likes', profileUserId]))
      .get();
    return doc.exists;
  }

  // ============== SHORTLIST ==============

  /// Add profile to shortlist
  Future<void> addToShortlist(
    String currentUserId,
    String profileUserId, {
    String? notes,
  }) async {
    final docId = _docId([currentUserId, 'shortlist', profileUserId]);
    await _firestore.collection('interactions').doc(docId).set({
      'userId': currentUserId,
      'shortlistedUserId': profileUserId,
      'type': 'shortlist',
      'addedAt': Timestamp.now(),
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
  }

  /// Remove profile from shortlist
  Future<void> removeFromShortlist(
    String currentUserId,
    String profileUserId,
  ) async {
    final docId = _docId([currentUserId, 'shortlist', profileUserId]);
    await _firestore.collection('interactions').doc(docId).delete();
  }

  /// Get shortlisted profiles for current user
  Stream<List<ShortlistModel>> getShortlistedProfiles(String userId) {
    return _firestore
        .collection('interactions')
        .where('userId', isEqualTo: userId)
        .where('type', isEqualTo: 'shortlist')
        .snapshots()
        .map((snap) {
          final items = snap.docs
              .map((doc) => ShortlistModel.fromMap(doc.data(), doc.id))
              .toList();
          items.sort((a, b) => b.addedAt.compareTo(a.addedAt));
          return items;
        });
  }

  /// Check if profile is in shortlist
  Future<bool> isInShortlist(String userId, String profileUserId) async {
    final docId = _docId([userId, 'shortlist', profileUserId]);
    final doc = await _firestore.collection('interactions').doc(docId).get();
    return doc.exists;
  }

  // ============== PROFILE VIEWS ==============

  /// Record that a user viewed another profile
  Future<void> recordProfileView(String viewerId, String viewedUserId) async {
    final docId = _docId([viewerId, 'view', viewedUserId]);
    await _firestore.collection('interactions').doc(docId).set({
      'userId': viewerId,
      'viewedUserId': viewedUserId,
      'type': 'view',
      'viewedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  /// Get recently viewed profiles
  Stream<List<String>> getRecentlyViewedProfiles(String userId) {
    return _firestore
        .collection('interactions')
        .where('userId', isEqualTo: userId)
        .where('type', isEqualTo: 'view')
        .orderBy('viewedAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => doc.data()['viewedUserId'] as String).toList());
  }

  /// Get profiles that viewed current user (premium feature)
  Stream<List<String>> getWhoViewedProfile(String userId) {
    return _firestore
        .collection('interactions')
        .where('viewedUserId', isEqualTo: userId)
        .where('type', isEqualTo: 'view')
        .orderBy('viewedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => doc.data()['userId'] as String).toList());
  }

  // ============== BLOCK ==============

  /// Block a user
  Future<void> blockUser(String currentUserId, String blockUserId) async {
    final docId = _docId([currentUserId, 'block', blockUserId]);
    await _firestore.collection('interactions').doc(docId).set({
      'userId': currentUserId,
      'blockedUserId': blockUserId,
      'type': 'block',
      'blockedAt': Timestamp.now(),
    });
  }

  /// Unblock a user
  Future<void> unblockUser(String currentUserId, String blockUserId) async {
    final docId = _docId([currentUserId, 'block', blockUserId]);
    await _firestore.collection('interactions').doc(docId).delete();
  }

  /// Get blocked users
  Stream<List<String>> getBlockedUsers(String userId) {
    return _firestore
        .collection('interactions')
        .where('userId', isEqualTo: userId)
        .where('type', isEqualTo: 'block')
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => doc.data()['blockedUserId'] as String).toList());
  }

  /// Check if user is blocked
  Future<bool> isUserBlocked(String userId, String checkUserId) async {
    final blockedUsers = await _firestore
        .collection('interactions')
        .where('userId', isEqualTo: userId)
        .where('type', isEqualTo: 'block')
        .where('blockedUserId', isEqualTo: checkUserId)
        .limit(1)
        .get();
    return blockedUsers.docs.isNotEmpty;
  }
}
