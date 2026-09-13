import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_theme.dart';
import 'package:ruleup/features/rewards/data/reward_image_service.dart';

class RewardImageThumbnail extends ConsumerWidget {
  const RewardImageThumbnail({
    super.key,
    required this.imageKey,
    this.size = 48,
  });

  final String? imageKey;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (imageKey == null) return _Fallback(size: size);
    return FutureBuilder<RewardImageAccess?>(
      future: ref.read(rewardImageServiceProvider).access(imageKey!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return _Fallback(size: size);
        final access = snapshot.data!;
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            key: const Key('reward-image-network'),
            access.uri.toString(),
            width: size,
            height: size,
            fit: BoxFit.cover,
            headers: access.headers,
            errorBuilder: (_, _, _) => _Fallback(size: size),
          ),
        );
      },
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('reward-image-fallback'),
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: HomeDashboardTheme.surfaceRaised,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: HomeDashboardTheme.outline),
    ),
    child: Icon(
      Icons.card_giftcard_rounded,
      color: HomeDashboardTheme.mint,
      size: size * 0.44,
    ),
  );
}
