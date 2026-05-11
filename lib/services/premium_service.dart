import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PremiumService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream that emits current user's `isPremium` value (defaults to false).
  Stream<bool> get isPremiumStream {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream<bool>.value(false);
    return _firestore.collection('users').doc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return false;
      final val = data['isPremium'];
      return val == true;
    });
  }

  /// One-off check for current user's premium status.
  Future<bool> isPremium() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null) return false;
    return data['isPremium'] == true;
  }
}
