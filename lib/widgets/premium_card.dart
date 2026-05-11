import 'package:flutter/material.dart';

const Color _gold = Color(0xFFFFF4D6);

class PremiumCard extends StatelessWidget {
  final VoidCallback? onTap;

  const PremiumCard({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: _gold,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 1,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Color(0xFFFAF3DF),
                child: Icon(Icons.workspace_premium_outlined, color: Color(0xFFB07A00)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Go Premium', style: TextStyle(fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text('Unlock all features', style: TextStyle(color: Color(0xFF6B6B6B))),
                  ],
                ),
              ),
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Upgrade'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
