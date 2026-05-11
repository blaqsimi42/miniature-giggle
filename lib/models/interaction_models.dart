import 'package:cloud_firestore/cloud_firestore.dart';

enum InterestStatus { pending, accepted, rejected }

enum InteractionType { like, interest, shortlist }

/// Model representing a user interest in another profile
class InterestModel {
  final String id;
  final String senderId;
  final String receiverId;
  final InterestStatus status;
  final DateTime sentAt;
  final DateTime? respondedAt;
  final String? message; // Optional message with interest

  InterestModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.status = InterestStatus.pending,
    required this.sentAt,
    this.respondedAt,
    this.message,
  });

  factory InterestModel.fromMap(Map<String, dynamic> map, String id) {
    return InterestModel(
      id: id,
      senderId: map['senderId'] as String,
      receiverId: map['receiverId'] as String,
      status: InterestStatus.values.byName(
        (map['status'] as String?) ?? 'pending',
      ),
      sentAt: (map['sentAt'] as Timestamp).toDate(),
      respondedAt: map['respondedAt'] != null
          ? (map['respondedAt'] as Timestamp).toDate()
          : null,
      message: map['message'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'senderId': senderId,
    'receiverId': receiverId,
    'status': status.name,
    'sentAt': Timestamp.fromDate(sentAt),
    if (respondedAt != null) 'respondedAt': Timestamp.fromDate(respondedAt!),
    if (message != null && message!.isNotEmpty) 'message': message,
  };

  InterestModel copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    InterestStatus? status,
    DateTime? sentAt,
    DateTime? respondedAt,
    String? message,
  }) {
    return InterestModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      status: status ?? this.status,
      sentAt: sentAt ?? this.sentAt,
      respondedAt: respondedAt ?? this.respondedAt,
      message: message ?? this.message,
    );
  }
}

/// Model representing a like/heart interaction
class LikeModel {
  final String id;
  final String userId; // who liked
  final String likedUserId; // profile that was liked
  final DateTime likedAt;

  LikeModel({
    required this.id,
    required this.userId,
    required this.likedUserId,
    required this.likedAt,
  });

  factory LikeModel.fromMap(Map<String, dynamic> map, String id) {
    return LikeModel(
      id: id,
      userId: map['userId'] as String,
      likedUserId: map['likedUserId'] as String,
      likedAt: (map['likedAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'likedUserId': likedUserId,
    'likedAt': Timestamp.fromDate(likedAt),
  };

  LikeModel copyWith({
    String? id,
    String? userId,
    String? likedUserId,
    DateTime? likedAt,
  }) {
    return LikeModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      likedUserId: likedUserId ?? this.likedUserId,
      likedAt: likedAt ?? this.likedAt,
    );
  }
}

/// Model representing a shortlisted profile
class ShortlistModel {
  final String id;
  final String userId; // who shortlisted
  final String shortlistedUserId; // profile that was shortlisted
  final DateTime addedAt;
  final String? notes; // Optional notes about why they were shortlisted

  ShortlistModel({
    required this.id,
    required this.userId,
    required this.shortlistedUserId,
    required this.addedAt,
    this.notes,
  });

  factory ShortlistModel.fromMap(Map<String, dynamic> map, String id) {
    return ShortlistModel(
      id: id,
      userId: map['userId'] as String,
      shortlistedUserId: map['shortlistedUserId'] as String,
      addedAt: (map['addedAt'] as Timestamp).toDate(),
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'userId': userId,
    'shortlistedUserId': shortlistedUserId,
    'addedAt': Timestamp.fromDate(addedAt),
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
  };

  ShortlistModel copyWith({
    String? id,
    String? userId,
    String? shortlistedUserId,
    DateTime? addedAt,
    String? notes,
  }) {
    return ShortlistModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      shortlistedUserId: shortlistedUserId ?? this.shortlistedUserId,
      addedAt: addedAt ?? this.addedAt,
      notes: notes ?? this.notes,
    );
  }
}
