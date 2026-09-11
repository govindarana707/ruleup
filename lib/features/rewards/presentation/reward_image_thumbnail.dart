import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_theme.dart';
import 'package:ruleup/features/rewards/data/reward_image_service.dart';

class RewardImageThumbnail extends ConsumerWidget {
  const RewardImageThumbnail({super.key, required this.imageKey});
  final String? imageKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (imageKey == null) return const _Fallback();
    return FutureBuilder<RewardImageAccess?>(
      future: ref.read(rewardImageServiceProvider).access(imageKey!),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _Fallback();
        final access = snapshot.data!;
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            access.uri.toString(),
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            headers: access.headers,
            errorBuilder: (_, _, _) => const _Fallback(),
          ),
        );
      },
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();
  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: HomeDashboardTheme.surfaceRaised,
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Icon(
      Icons.card_giftcard_rounded,
      color: HomeDashboardTheme.mint,
    ),
  );
}
