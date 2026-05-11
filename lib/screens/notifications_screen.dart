import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationService _notificationService = NotificationService();
  String? _uid;
  bool _markingRead = false;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    unawaited(_markAllUnreadAsRead());
  }

  Future<void> _markAllUnreadAsRead() async {
    final uid = _uid;
    if (uid == null || _markingRead) return;
    _markingRead = true;
    try {
      await _notificationService.markAllAsRead(uid);
    } catch (_) {
      // Keep the inbox usable even if mark-as-read fails.
    } finally {
      _markingRead = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F2),
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            onPressed: () =>
                Navigator.of(context).pushNamed('/notification-settings'),
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Notification settings',
          ),
          IconButton(
            onPressed: uid == null ? null : _markAllUnreadAsRead,
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Mark all as read',
          ),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('Sign in to view notifications.'))
          : StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              stream: _notificationService.streamNotifications(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final notifications = snapshot.data ?? const [];
                if (notifications.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.notifications_none_rounded,
                            size: 64,
                            color: Colors.black26,
                          ),
                          SizedBox(height: 14),
                          Text(
                            'No notifications yet.',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'When someone sends you an interest or other updates arrive, they will show up here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = notifications[index].data();
                    final title = (data['title'] ?? 'Notification').toString();
                    final body = (data['body'] ?? '').toString();
                    final senderName = (data['actorName'] ?? data['senderName'] ?? '').toString();
                    final senderPhoto = (data['actorPhotoUrl'] ?? data['senderPhotoUrl'] ?? '').toString();
                    final isRead = data['isRead'] == true;
                    final createdAt = data['createdAt'];
                    final when = createdAt is Timestamp
                        ? _timeAgo(createdAt.toDate())
                        : '';

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x11000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ],
                        border: Border.all(
                          color: isRead
                              ? const Color(0xFFF0ECE4)
                              : const Color(0xFFBFE7CB),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: const Color(0xFFE8F4EB),
                            backgroundImage: senderPhoto.isNotEmpty
                                ? NetworkImage(senderPhoto)
                                : null,
                            child: senderPhoto.isEmpty
                                ? const Icon(
                                    Icons.favorite_rounded,
                                    color: Color(0xFF16A34A),
                                  )
                                : null,
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
                                        title,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F3D2E),
                                        ),
                                      ),
                                    ),
                                    if (!isRead)
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF16A34A),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ),
                                if (senderName.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    senderName,
                                    style: const TextStyle(
                                      color: Color(0xFF16A34A),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                                if (body.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    body,
                                    style: const TextStyle(
                                      color: Color(0xFF475569),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                                if (when.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    when,
                                    style: const TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.day}/${time.month}/${time.year}';
  }
}
