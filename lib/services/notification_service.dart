import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _notificationsRef(String userId) =>
      _firestore.collection('users').doc(userId).collection('notifications');

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> streamNotifications(
    String userId,
  ) {
    return _notificationsRef(userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }

  Stream<int> streamUnreadCount(String userId) {
    return _notificationsRef(userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> sendInterestNotification({
    required String senderId,
    required String receiverId,
    required String senderName,
    String? senderPhotoUrl,
  }) async {
    final doc = _notificationsRef(receiverId).doc();
    await doc.set({
      'id': doc.id,
      'type': 'interest_received',
      'category': 'interests',
      'priority': 'high',
      'actorId': senderId,
      'receiverId': receiverId,
      'title': 'New interest received',
      'body': '$senderName sent you an interest.',
      'actorName': senderName,
      'actorPhotoUrl': senderPhotoUrl,
      'isRead': false,
      'isSeen': false,
      'createdAt': Timestamp.now(),
      'readAt': null,
      'seenAt': null,
      'action': {
        'route': '/view-profile',
        'entityType': 'user',
        'entityId': senderId,
      },
      'data': {
        'senderId': senderId,
      },
    });
  }

  Future<void> markAllAsRead(String userId) async {
    final snapshot = await _notificationsRef(userId)
        .where('isRead', isEqualTo: false)
        .get();

    if (snapshot.docs.isEmpty) {
      return;
    }

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'isRead': true,
        'readAt': Timestamp.now(),
      });
    }
    await batch.commit();
  }
}
