import 'dart:async';

import 'package:flutter/material.dart';

import '../services/profile_completion_gate_service.dart';
import '../utils/profile_completion.dart';
import '../widgets/profile_completion_widgets.dart';

class ProfileCompletionGateScreen extends StatefulWidget {
  const ProfileCompletionGateScreen({super.key});

  @override
  State<ProfileCompletionGateScreen> createState() => _ProfileCompletionGateScreenState();
}

class _ProfileCompletionGateScreenState extends State<ProfileCompletionGateScreen> {
  int? _completionPercent;
  String _nextStep = 'We are checking your profile progress.';

  @override
  void initState() {
    super.initState();
    unawaited(_loadCompletion());
  }

  Future<void> _loadCompletion() async {
    final profile = await ProfileCompletionGateService.loadCurrentProfile();
    if (!mounted) return;
    final completion = calculateProfileCompletion(profile);
    setState(() {
      _completionPercent = completion.percent;
      _nextStep = completion.nextStep;
    });
  }

  void _continueSetup() {
    Navigator.of(context).pushNamed(
      '/profile-setup',
      arguments: const {
        'initialStep': 0,
      },
    );
  }

  void _maybeLater() {
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    final percent = _completionPercent;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F2),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: percent == null
                  ? const Center(child: CircularProgressIndicator())
                  : ProfileCompletionGateCard(
                      percent: percent,
                      nextStep: _nextStep,
                      onContinue: _continueSetup,
                      onLater: _maybeLater,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
