import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../core/widgets.dart';
import 'conversion_controller.dart';

class ResultPanel extends ConsumerWidget {
  const ResultPanel({super.key, required this.job, this.allowRetry = true});
  final HistoryJob job;
  final bool allowRetry;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appControllerProvider.notifier);
    final state = ref.watch(appControllerProvider);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                job.outputs.isEmpty
                    ? Icons.info_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: job.outputs.isEmpty
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  job.outputs.isEmpty
                      ? 'No files saved'
                      : '${job.outputs.length} ${job.outputs.length == 1 ? 'file' : 'files'} saved',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (job.message != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(job.message!),
            ),
          if (job.outputs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Saved to ${job.destination.label}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (final file in job.outputs) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                file.name,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                formatBytes(file.bytes),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => controller.openFile(file),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open file'),
                  ),
                  TextButton.icon(
                    onPressed: () => controller.shareFile(file),
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share'),
                  ),
                ],
              ),
            ],
          ],
          for (final failure in job.failures) ...[
            const SizedBox(height: 12),
            Text(
              failure.name,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              failure.reason,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (allowRetry && job.failures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: OutlinedButton(
                onPressed: state.busy
                    ? null
                    : () => controller.run(failedOnly: true),
                child: Text(
                  job.tool == ToolKind.mergePdf || job.tool == ToolKind.pdf
                      ? 'Retry PDF'
                      : 'Retry failed outputs',
                ),
              ),
            ),
          if (allowRetry)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: state.busy ? null : controller.clearSelection,
                child: const Text('Clear files'),
              ),
            ),
        ],
      ),
    );
  }
}
