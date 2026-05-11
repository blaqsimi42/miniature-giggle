import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/user_service.dart';
import '../models/user_model.dart';
import '../core/config/service_locator.dart';
import '../services/auth_service.dart';
import '../widgets/upgrade_flow.dart';

class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key});

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> {
  List<Map<String, dynamic>> _users = [];
  String _log = '';

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  void _appendLog(String line) {
    setState(() {
      _log = '$_log\n$line';
    });
  }

  Future<void> _refreshStatus() async {
    try {
      final app = FirebaseFirestore.instance.app;
      _appendLog('[INFO] Firestore app: ${app.name}, projectId=${app.options.projectId}');
    } catch (e) {
      _appendLog('[WARN] Could not read Firestore.app: $e');
    }
    await _fetchUsers();
  }

  Future<void> _useEmulator() async {
    try {
      FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
      _appendLog('[INFO] Configured Firestore to use emulator at localhost:8080');
      await _fetchUsers();
    } catch (e, st) {
      _appendLog('[ERROR] useEmulator failed: $e\n$st');
    }
  }

  Future<void> _fetchUsers() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      final docs = snap.docs.map((d) => {'id': d.id, 'data': d.data()}).toList();
      setState(() => _users = docs);
      _appendLog('[INFO] Fetched ${docs.length} users');
    } catch (e, st) {
      _appendLog('[ERROR] fetchUsers failed: $e\n$st');
    }
  }

  Future<void> _createSampleUser() async {
    final uid = 'debug-${DateTime.now().millisecondsSinceEpoch}';
    final user = UserModel(uid: uid, fullName: 'Debug User', email: 'debug@example.com');
    try {
      await UserService().createUserProfile(user);
      _appendLog('[INFO] Created sample user $uid');
      await _fetchUsers();
    } catch (e, st) {
      _appendLog('[ERROR] createSampleUser failed: $e\n$st');
    }
  }

  Future<void> _triggerMockPayment() async {
    try {
      final authSvc = getIt<AuthService>();
      final uid = authSvc.getCurrentUser()?.uid;

      final ok = await showUpgradeFlow(context);
      if (!mounted) return;
      _appendLog('[INFO] Mock payment flow completed: success=$ok');
      if (ok && uid != null) {
        _appendLog('[INFO] Marked user $uid as premium (isPremium=true)');
      }
      await _fetchUsers();
    } catch (e, st) {
      _appendLog('[ERROR] mockPayment failed: $e\n$st');
    }
  }

  Future<void> _checkPremiumStatus() async {
    try {
      final userSvc = getIt<UserService>();
      final isPremium = await userSvc.isCurrentUserPremium();
      _appendLog('[INFO] Current user premium: $isPremium');
    } catch (e, st) {
      _appendLog('[ERROR] checkPremiumStatus failed: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firestore Debug'),
        actions: [if (kDebugMode) IconButton(onPressed: _refreshStatus, icon: const Icon(Icons.refresh))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton(onPressed: _fetchUsers, child: const Text('Fetch users')),
              ElevatedButton(onPressed: _useEmulator, child: const Text('Use Emulator')),
              ElevatedButton(onPressed: _createSampleUser, child: const Text('Create sample user')),
              ElevatedButton(onPressed: _triggerMockPayment, child: const Text('Mock payment success')),
              ElevatedButton(onPressed: _checkPremiumStatus, child: const Text('Check premium status')),
            ]),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Users (${_users.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Expanded(
                              child: _users.isEmpty
                                  ? const Center(child: Text('No users found'))
                                  : ListView.separated(
                                      itemCount: _users.length,
                                      separatorBuilder: (_, _) => const Divider(height: 1),
                                      itemBuilder: (ctx, i) {
                                        final u = _users[i];
                                        return ListTile(
                                          dense: true,
                                          title: Text(u['id'] ?? ''),
                                          subtitle: Text(u['data']?.toString() ?? ''),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: SingleChildScrollView(
                          child: Text(_log.isEmpty ? 'Logs will appear here' : _log),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
