import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationPreferencesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  DocumentReference<Map<String, dynamic>> _doc(String userId) => _firestore
      .collection('users')
      .doc(userId)
      .collection('private')
      .doc('notification_settings');

  String? get currentUserId => _auth.currentUser?.uid;

  Stream<Map<String, dynamic>> streamPreferences() {
    final userId = currentUserId;
    if (userId == null) {
      return Stream.value(_defaults());
    }
    return _doc(userId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        return _defaults();
      }
      return {
        ..._defaults(),
        ...data,
      };
    });
  }

  Future<void> savePreferences(Map<String, dynamic> data) async {
    final userId = currentUserId;
    if (userId == null) {
      throw StateError('No signed-in user found.');
    }
    await _doc(userId).set({
      ...data,
      'updatedAt': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  static Map<String, dynamic> _defaults() => {
        'notificationsEnabled': true,
        'pushEnabled': true,
        'emailEnabled': false,
        'soundEnabled': true,
        'vibrationEnabled': true,
        'muteMode': 'off',
        'muteStartMinutes': 1320,
        'muteEndMinutes': 420,
        'interestsEnabled': true,
        'matchesEnabled': true,
        'messagesEnabled': true,
        'profileActivityEnabled': true,
        'savedProfilesEnabled': true,
        'billingEnabled': true,
        'securityEnabled': true,
      };
}
