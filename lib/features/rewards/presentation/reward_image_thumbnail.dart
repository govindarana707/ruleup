import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ruleup/features/auth/presentation/auth_controller.dart';
import 'package:ruleup/features/home/presentation/home_dashboard_theme.dart';

class RewardImageThumbnail extends ConsumerWidget {
  const RewardImageThumbnail({super.key, required this.imageKey});
  final String? imageKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final token = ref.read(tokenStorageProvider).read();
    if (imageKey == null) return const _Fallback();
    return FutureBuilder<String?>(
      future: token,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _Fallback();
        final uri = ref
            .read(apiClientProvider)
            .resolve('/reward-images/${Uri.encodeComponent(imageKey!)}');
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            uri.toString(),
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            headers: {'authorization': 'Bearer ${snapshot.data}'},
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
