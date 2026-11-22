import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../core/widgets.dart';
import '../conversion/conversion_controller.dart';
import '../conversion/result_panel.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(appControllerProvider.select((s) => s.history));
    if (history.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          SizedBox(height: 48),
          QuietEmptyState(
            icon: Icons.history_rounded,
            title: 'No conversions yet',
            description: 'Completed jobs and saved files will appear here.',
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      itemCount: history.length,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final job = history[index];
        final date = MaterialLocalizations.of(context)
            .formatShortDate(job.createdAt);
        final time = MaterialLocalizations.of(context)
            .formatTimeOfDay(TimeOfDay.fromDateTime(job.createdAt));
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => showJobDetails(context, job),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(
                    job.format == OutputFormat.pdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${job.format.label} · ${job.outputs.length} saved · ${job.status.label}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$date, $time',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

void showJobDetails(BuildContext context, HistoryJob job) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => FractionallySizedBox(
      heightFactor: .85,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(job.tool.label, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(job.status.label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 20),
          ResultPanel(job: job, allowRetry: false),
        ],
      ),
    ),
  );
}

Future<void> confirmClearHistory(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Clear history?'),
      content: const Text(
        'This removes history records. Saved files remain in your folders.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Clear history'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(appControllerProvider.notifier).clearHistory();
  }
}
