import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize({Function(RemoteMessage)? onMessage, Function(RemoteMessage)? onBackground}) async {
    await _messaging.requestPermission();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (onMessage != null) {
        onMessage(message);
      }
    });

    // Background handler must be a top-level function registered in app entrypoint if handling background messages.
  }

  Future<String?> getToken() async {
    return await _messaging.getToken();
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      if (kIsWeb) {
        // Topic subscriptions are not supported on web; skip with debug log
        // ignore: avoid_print
        print('[DEBUG FcmService] skipping subscribeToTopic on web: $topic');
        return;
      }
      await _messaging.subscribeToTopic(topic);
    } catch (e) {
      // ignore: avoid_print
      print('[DEBUG FcmService] subscribeToTopic failed: $e');
    }
  }
}
