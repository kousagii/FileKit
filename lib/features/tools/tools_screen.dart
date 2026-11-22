import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../../core/widgets.dart';
import '../conversion/conversion_controller.dart';

class ToolSelector extends ConsumerWidget {
  const ToolSelector({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: state.busy || state.picking
            ? null
            : () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (context) => SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            'Choose a tool',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        for (final group in const {
                          'General': [ToolKind.convert],
                          'Images': [ToolKind.compress, ToolKind.resize],
                          'PDF': [ToolKind.mergePdf, ToolKind.splitPdf],
                        }.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              group.key,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          for (final tool in group.value)
                            ListTile(
                              leading: Icon(toolIcon(tool)),
                              title: Text(tool.label),
                              selected: tool == state.tool,
                              trailing: tool == state.tool
                                  ? const Icon(Icons.check_rounded)
                                  : null,
                              onTap: () {
                                ref
                                    .read(appControllerProvider.notifier)
                                    .selectTool(tool);
                                Navigator.pop(context);
                              },
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(toolIcon(state.tool), size: 22),
              const SizedBox(width: 12),
              Text('Tool', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  state.tool.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.expand_more_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
