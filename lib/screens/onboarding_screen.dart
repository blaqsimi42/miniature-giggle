import 'dart:async';
import 'package:flutter/material.dart';
import '../services/route_persistence.dart';
// removed test loader import

const Color _kGreen = Color(0xFF16A34A);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _outerController = PageController();
  Timer? _autoAdvanceTimer;
  

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _outerController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Auto-advance from the welcome image to the detail page after 3 seconds
    _autoAdvanceTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _outerController.animateToPage(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: PageView(
        controller: _outerController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildWelcomePage(context),
          _buildDetailOnboardingPage(context),
        ],
      ),
    );
  }

  Widget _buildWelcomePage(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/nikkah.png',
            fit: BoxFit.cover,
          ),
        ),
        // Welcome image remains for 3 seconds then auto-advances to next page.
      ],
    );
  }

  

  Widget _buildDetailOnboardingPage(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/halal.png',
            fit: BoxFit.cover,
          ),
        ),

        // Back button intentionally removed — onboarding proceeds forward only.

        // bottom panel with buttons (transparent over image)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(24, 20, 24, mq.padding.bottom + 20),
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    unawaited(RoutePersistence.save('/personal'));
                    Navigator.pushNamed(context, '/personal');
                  },
                  child: const Text('Get Started', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 12),
                GestureDetector(onTap: () => Navigator.pushNamed(context, '/login'), child: Text('Already have an account?', style: TextStyle(color: _kGreen, fontWeight: FontWeight.w600))),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// `_Indicator` removed — carousel uses centered dots in the carousel page.
