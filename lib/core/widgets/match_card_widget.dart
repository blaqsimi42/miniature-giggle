import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class MatchCardWidget extends StatelessWidget {
  final String id;
  final String name;
  final int age;
  final String location;
  final int score;
  final String? imageUrl;
  final VoidCallback? onTap;

  const MatchCardWidget({super.key, required this.id, required this.name, required this.age, required this.location, required this.score, this.imageUrl, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'match-$id',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          child: Container(
            width: 260,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppColors.cardRadius),
              image: (imageUrl != null && imageUrl!.isNotEmpty)
                  ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
                  : null,
              color: (imageUrl == null || imageUrl!.isEmpty) ? AppColors.primary.withAlpha((0.06 * 255).round()) : null,
              boxShadow: [BoxShadow(color: Colors.black.withAlpha((0.08 * 255).round()), blurRadius: 16, offset: const Offset(0, 8))],
            ),
            child: Stack(
              children: [
                if (imageUrl == null || imageUrl!.isEmpty)
                  Center(
                    child: CircleAvatar(
                      radius: 46,
                      backgroundColor: AppColors.primary.withAlpha((0.12 * 255).round()),
                      child: Text(name.isNotEmpty ? name[0] : 'U', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.transparent, Colors.black.withAlpha((0.56 * 255).round())], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$name, $age', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(location, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                children: [
                                  const Icon(Icons.star, color: Colors.white70, size: 14),
                                  const SizedBox(width: 6),
                                  Text('$score%', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Icon(Icons.favorite_border, color: Colors.white70),
                          ],
                        ),
                      ],
                    ),
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
