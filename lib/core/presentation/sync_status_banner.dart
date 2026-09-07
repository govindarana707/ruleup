import 'package:flutter/material.dart';
import 'package:ruleup/core/sync/sync_provider.dart';

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({
    super.key,
    required this.offline,
    required this.sync,
    required this.offlineMessage,
    required this.syncingMessage,
    required this.failedMessage,
    this.onRetry,
    this.margin = EdgeInsets.zero,
  });

  final bool offline;
  final SyncState sync;
  final String offlineMessage;
  final String syncingMessage;
  final String failedMessage;
  final VoidCallback? onRetry;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final failed = !offline && sync.status == SyncStatus.failed;
    final message = offline
        ? offlineMessage
        : sync.status == SyncStatus.syncing
        ? syncingMessage
        : failedMessage;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: margin,
      child: Semantics(
        container: true,
        liveRegion: true,
        excludeSemantics: true,
        label: message,
        child: Material(
          color: failed ? scheme.errorContainer : scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Icon(
                  offline
                      ? Icons.cloud_off_outlined
                      : failed
                      ? Icons.sync_problem_outlined
                      : Icons.sync,
                  size: 20,
                  color: failed
                      ? scheme.onErrorContainer
                      : scheme.onSecondaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(message)),
                if (failed && onRetry != null)
                  TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
