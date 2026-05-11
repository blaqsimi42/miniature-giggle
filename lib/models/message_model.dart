import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String message;
  final String? imageUrl;
  final String? senderPhotoUrl;
  final String? replyToMessageId;
  final String? replyToText;
  final String? replyToImageUrl;
  final String? replyToSenderId;
  final bool isDeleted;
  final Timestamp? deliveredAt;
  final Timestamp? readAt;
  final Timestamp? editedAt;
  final Timestamp timestamp;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.message,
    this.imageUrl,
    this.senderPhotoUrl,
    this.replyToMessageId,
    this.replyToText,
    this.replyToImageUrl,
    this.replyToSenderId,
    this.isDeleted = false,
    this.deliveredAt,
    this.readAt,
    this.editedAt,
    Timestamp? timestamp,
  }) : timestamp = timestamp ?? Timestamp.now();

  factory MessageModel.fromMap(Map<String, dynamic> map, String id) {
    return MessageModel(
      id: id,
      senderId: map['senderId'] as String,
      receiverId: map['receiverId'] as String,
      message: map['message'] as String,
      imageUrl: map['imageUrl'] as String?,
      senderPhotoUrl: map['senderPhotoUrl'] as String?,
      replyToMessageId: map['replyToMessageId'] as String?,
      replyToText: map['replyToText'] as String?,
      replyToImageUrl: map['replyToImageUrl'] as String?,
      replyToSenderId: map['replyToSenderId'] as String?,
      isDeleted: map['isDeleted'] as bool? ?? false,
      deliveredAt: map['deliveredAt'] as Timestamp?,
      readAt: map['readAt'] as Timestamp?,
      editedAt: map['editedAt'] as Timestamp?,
      timestamp: map['timestamp'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'message': message,
      'imageUrl': imageUrl,
      'senderPhotoUrl': senderPhotoUrl,
      'replyToMessageId': replyToMessageId,
      'replyToText': replyToText,
      'replyToImageUrl': replyToImageUrl,
      'replyToSenderId': replyToSenderId,
      'isDeleted': isDeleted,
      'deliveredAt': deliveredAt,
      'readAt': readAt,
      'editedAt': editedAt,
      'timestamp': timestamp,
    }..removeWhere((key, value) => value == null);
  }
}
