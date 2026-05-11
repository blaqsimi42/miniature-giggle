import 'package:flutter/material.dart';

class GuardianInvitationSentScreen extends StatelessWidget {
  const GuardianInvitationSentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ...<Offset>[
                        const Offset(20, 32),
                        const Offset(145, 34),
                        const Offset(156, 88),
                        const Offset(136, 138),
                        const Offset(46, 148),
                        const Offset(18, 96),
                        const Offset(78, 18),
                        const Offset(112, 18),
                      ].map(
                        (offset) => Positioned(
                          left: offset.dx,
                          top: offset.dy,
                          child: CircleAvatar(
                            radius: 4,
                            backgroundColor:
                                colorScheme.primary.withValues(alpha: 0.22),
                          ),
                        ),
                      ),
                      CircleAvatar(
                        radius: 60,
                        backgroundColor:
                            colorScheme.primary.withValues(alpha: 0.12),
                        child: Icon(
                          Icons.check_circle,
                          size: 64,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Invitation Sent!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'We\'ve sent an invitation to your guardian. Once they accept, you can start chatting.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.popUntil(
                        context,
                        ModalRoute.withName('/chat'),
                      );
                    },
                    child: const Text('Back to Chat'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
