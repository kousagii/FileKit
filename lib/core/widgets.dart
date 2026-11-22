import 'package:material_ui/material_ui.dart';

import 'models.dart';

class FileKitMark extends StatelessWidget {
  const FileKitMark({super.key, this.size = 34});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(size * .28),
    ),
    child: Icon(
      Icons.find_replace_outlined,
      color: Colors.white,
      size: size * .62,
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.size = 48});
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: colors.primary, size: size * .48),
    );
  }
}

class FolderPanel extends StatelessWidget {
  const FolderPanel({
    super.key,
    required this.destination,
    required this.onChoose,
    this.enabled = true,
  });
  final OutputDestination? destination;
  final VoidCallback onChoose;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final label = Row(
          children: [
            const Icon(Icons.folder_outlined, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Save to', style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    destination?.label ?? 'Choose an output folder',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        );
        final action = TextButton(
          onPressed: enabled ? onChoose : null,
          child: Text(destination == null ? 'Choose' : 'Change'),
        );
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(14) > 20) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              Align(alignment: Alignment.centerRight, child: action),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: label),
            const SizedBox(width: 8),
            action,
          ],
        );
      },
    ),
  );
}

class QuietEmptyState extends StatelessWidget {
  const QuietEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title, description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconBadge(icon, size: 64),
        const SizedBox(height: 20),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

IconData toolIcon(ToolKind tool) => switch (tool) {
  ToolKind.convert => Icons.swap_horiz_rounded,
  ToolKind.compress => Icons.compress_rounded,
  ToolKind.resize => Icons.aspect_ratio_rounded,
  ToolKind.pdf => Icons.picture_as_pdf_outlined,
  ToolKind.mergePdf => Icons.merge_type_rounded,
  ToolKind.splitPdf => Icons.call_split_rounded,
};

String toolDescription(ToolKind tool) => switch (tool) {
  ToolKind.convert => 'Convert images or export PDF pages.',
  ToolKind.compress => 'Adjust JPEG quality and file size.',
  ToolKind.resize => 'Set image dimensions in pixels.',
  ToolKind.pdf => 'Combine images into one PDF.',
  ToolKind.mergePdf => 'Combine PDF documents in order.',
  ToolKind.splitPdf => 'Save individual pages or page ranges.',
};
