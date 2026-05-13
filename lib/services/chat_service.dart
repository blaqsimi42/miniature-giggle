import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../widgets/beautiful_loader.dart';
import '../models/message_model.dart';

class ChatService {
  static const String supportUid = 'support_account';
  static const String supportDisplayName = 'Qubool Support';
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String chatIdFor(String a, String b) {
    final sorted = [a, b]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  Future<void> sendMessage(
    String chatId,
    MessageModel message, {
    String? senderName,
    String? receiverName,
    String? senderPhotoUrl,
    String? receiverPhotoUrl,
    BuildContext? context,
  }) async {
    Future<void> operation() async {
      try {
        final participantNames = <String, String>{};
        final participantPhotoUrls = <String, String>{};
        if (senderName != null && senderName.trim().isNotEmpty) {
          participantNames[message.senderId] = senderName.trim();
        }
        if (receiverName != null && receiverName.trim().isNotEmpty) {
          participantNames[message.receiverId] = receiverName.trim();
        }
        if (senderPhotoUrl != null && senderPhotoUrl.trim().isNotEmpty) {
          participantPhotoUrls[message.senderId] = senderPhotoUrl.trim();
        }
        if (receiverPhotoUrl != null && receiverPhotoUrl.trim().isNotEmpty) {
          participantPhotoUrls[message.receiverId] = receiverPhotoUrl.trim();
        }

        final lastMessageText = message.message.trim().isNotEmpty
            ? message.message
            : (message.imageUrl != null && message.imageUrl!.trim().isNotEmpty
                  ? 'Photo'
                  : '');

        await _firestore.collection('chats').doc(chatId).set({
          'participants': [message.senderId, message.receiverId]..sort(),
          if (participantNames.isNotEmpty) 'participantNames': participantNames,
          if (participantPhotoUrls.isNotEmpty)
            'participantPhotoUrls': participantPhotoUrls,
          'lastMessage': lastMessageText,
          'lastMessageAt': message.timestamp,
          'unreadCounts.${message.receiverId}': FieldValue.increment(1),
          'unreadCounts.${message.senderId}': 0,
        }, SetOptions(merge: true));
        final ref = _firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages');
        await ref.add({
          ...message.toMap(),
          'deliveredAt': message.deliveredAt ?? Timestamp.now(),
        });
      } catch (e) {
        final message = e.toString();
        if (kIsWeb && message.contains('INTERNAL ASSERTION FAILED')) {
          throw Exception(
            'Could not send message right now. Please try again in a moment.',
          );
        }
        rethrow;
      }
    }

    if (context != null) {
      return await LoadingScreen.whileLoading(context, operation);
    } else {
      return await operation();
    }
  }

  Stream<List<MessageModel>> streamMessages(String chatId, {int limit = 100}) {
    final ref = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .limit(limit);
    return ref.snapshots().map(
      (snap) =>
          snap.docs.map((d) => MessageModel.fromMap(d.data(), d.id)).toList(),
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> streamChatsForUser(
    String userId,
  ) {
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: userId)
        .snapshots();
  }

  Future<void> ensureSupportConversationForUser({
    required String userId,
    required String userDisplayName,
    String? userPhotoUrl,
  }) async {
    final chatId = chatIdFor(userId, supportUid);
    final chatRef = _firestore.collection('chats').doc(chatId);
    final trimmedName = userDisplayName.trim().isNotEmpty
        ? userDisplayName.trim()
        : 'there';
    final welcomeMessage =
        'Welcome to Qubool Nikah, how can we be of help you $trimmedName';

    await chatRef.set({
      'participants': [userId, supportUid]..sort(),
      'participantNames': {
        userId: trimmedName == 'there' ? 'User' : trimmedName,
        supportUid: supportDisplayName,
      },
      'participantPhotoUrls': {
        if (userPhotoUrl != null && userPhotoUrl.trim().isNotEmpty)
          userId: userPhotoUrl.trim(),
      },
      'pinnedFor': FieldValue.arrayUnion([userId]),
      'isSupportChat': true,
      'lastMessage': welcomeMessage,
      'lastMessageAt': Timestamp.now(),
      'supportIntro': welcomeMessage,
      'unreadCounts.$userId': 0,
    }, SetOptions(merge: true));
  }

  Future<void> muteChatForUser({
    required String chatId,
    required String userId,
    required bool muted,
  }) async {
    await _firestore.collection('chats').doc(chatId).set({
      'mutedBy': muted
          ? FieldValue.arrayUnion([userId])
          : FieldValue.arrayRemove([userId]),
    }, SetOptions(merge: true));
  }

  Future<void> archiveChatForUser({
    required String chatId,
    required String userId,
  }) async {
    await _firestore.collection('chats').doc(chatId).set({
      'archivedBy': FieldValue.arrayUnion([userId]),
    }, SetOptions(merge: true));
  }

  Future<void> deleteChatForUser({
    required String chatId,
    required String userId,
  }) async {
    await _firestore.collection('chats').doc(chatId).set({
      'deletedFor': FieldValue.arrayUnion([userId]),
    }, SetOptions(merge: true));
  }

  Future<void> requestGuardianAccess({
    required String chatId,
    required String userId,
    required String peerUserId,
  }) async {
    await _firestore.collection('chats').doc(chatId).set({
      'guardianAccessRequests': {
        userId: {
          'requestedAt': Timestamp.now(),
          'peerUserId': peerUserId,
          'status': 'requested',
        },
      },
    }, SetOptions(merge: true));
  }

  Future<void> reportChat({
    required String chatId,
    required String reporterId,
    required String reportedUserId,
    String reason = 'General safety concern',
  }) async {
    await _firestore.collection('chat_reports').add({
      'chatId': chatId,
      'reporterId': reporterId,
      'reportedUserId': reportedUserId,
      'reason': reason,
      'createdAt': Timestamp.now(),
    });
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> streamUserPresence(
    String userId,
  ) {
    return _firestore.collection('users').doc(userId).snapshots();
  }

  Stream<int> streamUnreadMessageCount(String userId) {
    return _firestore
        .collectionGroup('messages')
        .where('receiverId', isEqualTo: userId)
        .where('readAt', isNull: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> updateMessage({
    required String chatId,
    required String messageId,
    required String text,
  }) async {
    final docRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);
    await docRef.update({'message': text, 'editedAt': Timestamp.now()});
    await _refreshChatLastMessage(chatId);
  }

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    final docRef = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId);
    await docRef.update({
      'message': '',
      'imageUrl': FieldValue.delete(),
      'replyToMessageId': FieldValue.delete(),
      'replyToText': FieldValue.delete(),
      'replyToImageUrl': FieldValue.delete(),
      'replyToSenderId': FieldValue.delete(),
      'isDeleted': true,
      'editedAt': Timestamp.now(),
    });
    await _refreshChatLastMessage(chatId);
  }

  Future<void> markMessagesAsRead(String chatId, String userId) async {
    final ref = _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages');
    final snapshot = await ref.where('receiverId', isEqualTo: userId).get();
    final unreadDocs = snapshot.docs
        .where((doc) => doc.data()['readAt'] == null)
        .toList();

    if (unreadDocs.isEmpty) {
      return;
    }

    final batch = _firestore.batch();
    for (final doc in unreadDocs) {
      batch.update(doc.reference, {
        'readAt': Timestamp.now(),
        'deliveredAt': doc.data()['deliveredAt'] ?? Timestamp.now(),
      });
    }
    batch.set(_firestore.collection('chats').doc(chatId), {
      'unreadCounts.$userId': 0,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> _refreshChatLastMessage(String chatId) async {
    final latestSnapshot = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (latestSnapshot.docs.isEmpty) {
      await _firestore.collection('chats').doc(chatId).set({
        'lastMessage': '',
        'lastMessageAt': null,
      }, SetOptions(merge: true));
      return;
    }

    final latest = MessageModel.fromMap(
      latestSnapshot.docs.first.data(),
      latestSnapshot.docs.first.id,
    );
    await _firestore.collection('chats').doc(chatId).set({
      'lastMessage': _messagePreviewText(latest),
      'lastMessageAt': latest.timestamp,
    }, SetOptions(merge: true));
  }

  String _messagePreviewText(MessageModel message) {
    if (message.isDeleted) {
      return 'Message deleted';
    }
    if (message.message.trim().isNotEmpty) {
      return message.message;
    }
    if (message.imageUrl != null && message.imageUrl!.trim().isNotEmpty) {
      return 'Photo';
    }
    return '';
  }
}
