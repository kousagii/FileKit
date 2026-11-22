import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/storage.dart';
import '../../core/widgets.dart';
import '../tools/tools_screen.dart';
import 'conversion_controller.dart';
import 'operations.dart';
import 'result_panel.dart';

class WorkbenchScreen extends ConsumerStatefulWidget {
  const WorkbenchScreen({super.key});
  @override
  ConsumerState<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends ConsumerState<WorkbenchScreen> {
  late final TextEditingController width;
  late final TextEditingController height;
  late final TextEditingController filename;
  late final TextEditingController ranges;
  bool resize = false;
  @override
  void initState() {
    super.initState();
    final options = ref.read(appControllerProvider).options;
    width = TextEditingController(text: '${options.maxWidth ?? 1920}');
    height = TextEditingController(text: '${options.maxHeight ?? 1920}');
    filename = TextEditingController(
      text: p.basenameWithoutExtension(options.pdfName),
    );
    ranges = TextEditingController(text: options.pageRanges);
    resize = options.maxWidth != null;
  }

  @override
  void dispose() {
    width.dispose();
    height.dispose();
    filename.dispose();
    ranges.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final options = state.options;
    final pdfTool = Capabilities.isPdfOperation(state.tool);
    final pdfSource =
        state.sources.length == 1 && state.sources.first is PdfSource
        ? state.sources.first as PdfSource
        : null;
    final pdfInput =
        options.input == InputFormat.pdf || state.sources.any((s) => s.isPdf);
    final enabled = !state.busy && !state.picking;
    final availableOutputs = Capabilities.outputs(
      state.tool,
      options.input,
      state.sources,
    );
    final issue = Capabilities.validate(state.tool, options, state.sources);
    final requirement =
        issue ??
        (state.settings.destination == null
            ? 'Choose an output folder.'
            : null);
    final orderable =
        state.tool == ToolKind.mergePdf ||
        (!pdfInput && options.format == OutputFormat.pdf);
    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const PageStorageKey('workbench'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              const ToolSelector(),
              const SizedBox(height: 16),
              if (!pdfTool) ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final input = DropdownButtonFormField<InputFormat>(
                      key: ValueKey(options.input),
                      initialValue: options.input,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Input'),
                      items: InputFormat.values
                          .map(
                            (format) => DropdownMenuItem(
                              value: format,
                              child: Text(format.label),
                            ),
                          )
                          .toList(),
                      onChanged: enabled
                          ? (input) => controller.updateOptions(
                              options.copyWith(input: input),
                            )
                          : null,
                    );
                    final output = DropdownButtonFormField<OutputFormat>(
                      key: ValueKey(
                        '${options.format}:${availableOutputs.join()}',
                      ),
                      initialValue: availableOutputs.contains(options.format)
                          ? options.format
                          : null,
                      isExpanded: true,
                      hint: const Text('Choose'),
                      decoration: const InputDecoration(labelText: 'Output'),
                      items: availableOutputs
                          .map(
                            (format) => DropdownMenuItem(
                              value: format,
                              child: Text(format.label),
                            ),
                          )
                          .toList(),
                      onChanged: enabled
                          ? (format) => controller.updateOptions(
                              options.copyWith(format: format),
                            )
                          : null,
                    );
                    if (constraints.maxWidth < 300 ||
                        MediaQuery.textScalerOf(context).scale(14) > 20) {
                      return Column(
                        children: [input, const SizedBox(height: 12), output],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: input),
                        const SizedBox(width: 12),
                        Expanded(child: output),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
              ] else ...[
                Text(
                  toolDescription(state.tool),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: enabled && state.sources.length < AppLimits.maxFiles
                    ? controller.addFiles
                    : null,
                icon: const Icon(Icons.add_rounded),
                label: Text(state.picking ? 'Reading files…' : 'Add files'),
              ),
              const SizedBox(height: 12),
              if (state.picking)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(),
                ),
              if (state.sources.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 8,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        pdfTool || options.input == InputFormat.pdf
                            ? Icons.picture_as_pdf_outlined
                            : Icons.insert_drive_file_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        size: 32,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No files selected',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        pdfTool || options.input == InputFormat.pdf
                            ? 'PDF · Up to 50 MB and 100 pages per file'
                            : 'JPG, PNG, WebP, BMP, PDF',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              else ...[
                SectionHeading(
                  'Files (${state.sources.length})',
                  trailing: TextButton(
                    onPressed: enabled ? controller.clearSelection : null,
                    child: const Text('Clear'),
                  ),
                ),
                Panel(
                  padding: const EdgeInsets.all(4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      onReorderItem: enabled && orderable
                          ? controller.reorderFiles
                          : (_, _) {},
                      itemCount: state.sources.length,
                      itemBuilder: (context, index) => _SourceRow(
                        key: ValueKey(state.sources[index].id),
                        file: state.sources[index],
                        index: index,
                        orderable: orderable,
                        enabled: enabled,
                        count: state.sources.length,
                      ),
                    ),
                  ),
                ),
                if (issue != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      issue,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
              if (pdfSource != null && !state.busy && !state.picking) ...[
                const SizedBox(height: 16),
                PdfPageStrip(source: pdfSource),
              ],
              if (state.tool == ToolKind.mergePdf) ...[
                const SizedBox(height: 16),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const PageStorageKey('merge-pdf-name'),
                        controller: filename,
                        enabled: enabled,
                        maxLength: 100,
                        decoration: const InputDecoration(
                          labelText: 'File name',
                          suffixText: '.pdf',
                          counterText: '',
                        ),
                        onChanged: (name) => controller.updateOptions(
                          options.copyWith(
                            pdfName:
                                '${name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}.pdf',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${state.sources.whereType<PdfSource>().fold(0, (n, s) => n + s.pageCount)} pages · 1 PDF output',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              if (state.tool == ToolKind.splitPdf ||
                  (!pdfTool && pdfInput)) ...[
                const SizedBox(height: 16),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<bool>(
                        key: ValueKey('split:${options.splitEachPage}'),
                        initialValue: state.tool == ToolKind.splitPdf
                            ? options.splitEachPage
                            : !options.usePageRanges,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: state.tool == ToolKind.splitPdf
                              ? 'Split by'
                              : 'Pages',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: true,
                            child: Text(
                              state.tool == ToolKind.splitPdf
                                  ? 'Each page'
                                  : 'All pages',
                            ),
                          ),
                          const DropdownMenuItem(
                            value: false,
                            child: Text('Page ranges'),
                          ),
                        ],
                        onChanged: enabled
                            ? (all) {
                                if (state.tool == ToolKind.splitPdf) {
                                  controller.updateOptions(
                                    options.copyWith(splitEachPage: all),
                                  );
                                } else {
                                  if (!all! && ranges.text.isEmpty) {
                                    ranges.text = '1';
                                  }
                                  controller.updateOptions(
                                    options.copyWith(
                                      usePageRanges: !all,
                                      pageRanges: ranges.text,
                                    ),
                                  );
                                }
                              }
                            : null,
                      ),
                      if ((state.tool == ToolKind.splitPdf &&
                              !options.splitEachPage) ||
                          (state.tool != ToolKind.splitPdf &&
                              options.usePageRanges)) ...[
                        const SizedBox(height: 16),
                        TextField(
                          key: const PageStorageKey('pdf-page-ranges'),
                          controller: ranges,
                          enabled: enabled,
                          decoration: const InputDecoration(
                            labelText: 'Page ranges',
                            hintText: '1-3, 5, 8-10',
                            helperText: 'Page numbers start at 1.',
                          ),
                          onChanged: (value) => controller.updateOptions(
                            options.copyWith(pageRanges: value),
                          ),
                        ),
                      ],
                      if (state.tool != ToolKind.splitPdf) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          initialValue: options.dpi,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Resolution',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 150,
                              child: Text('150 DPI'),
                            ),
                            DropdownMenuItem(
                              value: 300,
                              child: Text('300 DPI'),
                            ),
                          ],
                          onChanged: enabled
                              ? (dpi) => controller.updateOptions(
                                  options.copyWith(dpi: dpi),
                                )
                              : null,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'One image per page, with a white background. Large pages are limited to 12 MP.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (pdfSource != null && issue == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _outputSummary(state),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (!pdfTool) ...[
                const SizedBox(height: 16),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    initiallyExpanded:
                        state.tool != ToolKind.convert ||
                        options.format == OutputFormat.pdf,
                    key: PageStorageKey(
                      'options:${state.tool}:${options.format}',
                    ),
                    title: const Text('Options'),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      if (options.format == OutputFormat.webp) ...[
                        DropdownButtonFormField<bool>(
                          key: ValueKey(options.webpLossless),
                          initialValue: options.webpLossless,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'WebP mode',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: true,
                              child: Text('Lossless'),
                            ),
                            DropdownMenuItem(
                              value: false,
                              child: Text('Smaller file'),
                            ),
                          ],
                          onChanged: enabled
                              ? (value) => controller.updateOptions(
                                  options.copyWith(webpLossless: value),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (options.format == OutputFormat.jpg ||
                          options.format == OutputFormat.pdf ||
                          (options.format == OutputFormat.webp &&
                              !options.webpLossless))
                        _QualityControl(options: options, enabled: enabled),
                      if (options.format == OutputFormat.png)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'PNG is lossless. Output files may be larger.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      if (!pdfInput &&
                          (options.format == OutputFormat.jpg ||
                              options.format == OutputFormat.pdf) &&
                          state.sources.whereType<SourceFile>().any(
                            (file) => file.hasAlpha,
                          )) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Transparency background',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final color in const {
                                0xffffffff: 'White',
                                0xff000000: 'Black',
                              }.entries)
                                ChoiceChip(
                                  label: Text(color.value),
                                  selected: color.key == options.fillColor,
                                  onSelected: enabled
                                      ? (_) => controller.updateOptions(
                                          options.copyWith(
                                            fillColor: color.key,
                                          ),
                                        )
                                      : null,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (!pdfInput && options.format == OutputFormat.pdf) ...[
                        TextField(
                          key: const PageStorageKey('images-pdf-name'),
                          controller: filename,
                          enabled: enabled,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            labelText: 'File name',
                            suffixText: '.pdf',
                            counterText: '',
                          ),
                          onChanged: (name) => controller.updateOptions(
                            options.copyWith(
                              pdfName:
                                  '${name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')}.pdf',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<bool>(
                          initialValue: options.pdfA4,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Page size',
                          ),
                          items: const [
                            DropdownMenuItem(value: true, child: Text('A4')),
                            DropdownMenuItem(
                              value: false,
                              child: Text('Fit image'),
                            ),
                          ],
                          onChanged: enabled
                              ? (value) => controller.updateOptions(
                                  options.copyWith(pdfA4: value),
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'One image per page, in file order.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (!pdfInput) ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Resize'),
                          subtitle: Text(
                            resize
                                ? 'Keep aspect ratio. Do not enlarge.'
                                : 'Keep original dimensions.',
                          ),
                          value: resize,
                          onChanged: enabled
                              ? (value) {
                                  setState(() => resize = value);
                                  controller.updateOptions(
                                    value
                                        ? options.copyWith(
                                            maxWidth:
                                                int.tryParse(width.text) ?? 0,
                                            maxHeight:
                                                int.tryParse(height.text) ?? 0,
                                          )
                                        : options.copyWith(clearSize: true),
                                  );
                                }
                              : null,
                        ),
                        if (resize)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              Widget field(
                                TextEditingController text,
                                bool isWidth,
                              ) => TextField(
                                // EditableText restores its own horizontal scroll offset.
                                // It must not read the ExpansionTile's saved bool.
                                key: PageStorageKey(
                                  isWidth ? 'resize-width' : 'resize-height',
                                ),
                                controller: text,
                                enabled: enabled,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(5),
                                ],
                                decoration: InputDecoration(
                                  labelText: isWidth
                                      ? 'Max width'
                                      : 'Max height',
                                  suffixText: 'px',
                                ),
                                onChanged: (value) => controller.updateOptions(
                                  isWidth
                                      ? options.copyWith(
                                          maxWidth: int.tryParse(value) ?? 0,
                                        )
                                      : options.copyWith(
                                          maxHeight: int.tryParse(value) ?? 0,
                                        ),
                                ),
                              );
                              if (constraints.maxWidth < 280 ||
                                  MediaQuery.textScalerOf(context).scale(14) >
                                      20) {
                                return Column(
                                  children: [
                                    field(width, true),
                                    const SizedBox(height: 12),
                                    field(height, false),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  Expanded(child: field(width, true)),
                                  const SizedBox(width: 12),
                                  Expanded(child: field(height, false)),
                                ],
                              );
                            },
                          ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FolderPanel(
                destination: state.settings.destination,
                onChoose: controller.chooseFolder,
                enabled: enabled,
              ),
              if (pdfTool)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Page content is kept. Forms, bookmarks, and signatures may not carry over.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (state.busy) ...[
                const SizedBox(height: 16),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.stage,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 10),
                      Text(
                        '${state.completed} of ${state.total} outputs processed',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Keep the app open until saving finishes.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              if (state.result != null) ...[
                const SizedBox(height: 16),
                ResultPanel(job: state.result!),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant
                    .withValues(alpha: .5),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!state.busy && requirement != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    requirement,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              FilledButton.icon(
                onPressed: state.busy
                    ? state.cancelRequested
                          ? null
                          : controller.cancel
                    : enabled && requirement == null
                    ? () {
                        FocusScope.of(context).unfocus();
                        controller.run();
                      }
                    : null,
                icon: Icon(
                  state.busy ? Icons.close_rounded : toolIcon(state.tool),
                ),
                label: Text(
                  state.busy
                      ? state.cancelRequested
                            ? 'Stopping…'
                            : 'Cancel'
                      : state.tool.verb,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _outputSummary(FileKitState state) {
    try {
      final count = createTasks(
        state.tool,
        state.options,
        state.sources,
      ).length;
      final noun = state.tool == ToolKind.splitPdf
          ? (count == 1 ? 'PDF' : 'PDFs')
          : (count == 1 ? 'image' : 'images');
      return '$count $noun will be created.';
    } on FileKitException {
      return '';
    }
  }
}

class _QualityControl extends ConsumerWidget {
  const _QualityControl({required this.options, required this.enabled});
  final ConversionOptions options;
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Quality',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text('${options.quality}%'),
        ],
      ),
      Slider(
        value: options.quality.toDouble(),
        min: 50,
        max: 100,
        divisions: 50,
        semanticFormatterCallback: (value) => '${value.round()} percent',
        onChanged: enabled
            ? (value) => ref
                  .read(appControllerProvider.notifier)
                  .updateOptions(options.copyWith(quality: value.round()))
            : null,
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Smaller file',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Higher quality',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _SourceRow extends ConsumerWidget {
  const _SourceRow({
    super.key,
    required this.file,
    required this.index,
    required this.count,
    required this.orderable,
    required this.enabled,
  });
  final FileSource file;
  final int index, count;
  final bool orderable, enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final issue = Capabilities.sourceIssue(
      file,
      state.tool,
      state.options.input,
    );
    final details = file is PdfSource
        ? '${(file as PdfSource).pageCount} pages'
        : '${(file as SourceFile).width} × ${(file as SourceFile).height}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 2, 4),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(file.thumbnailPath),
                  width: 40,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stack) => SizedBox(
                    width: 40,
                    height: 44,
                    child: Icon(
                      file.isPdf
                          ? Icons.picture_as_pdf_outlined
                          : Icons.image_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      '$details · ${formatBytes(file.bytes)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: enabled
                    ? () => controller.removeFile(file.id)
                    : null,
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: 'Remove ${file.name}',
              ),
            ],
          ),
          if (issue != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  issue,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          if (orderable)
            Row(
              children: [
                ReorderableDelayedDragStartListener(
                  index: index,
                  enabled: enabled,
                  child: const Tooltip(
                    message: 'Hold to reorder',
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.drag_handle_rounded),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${file.isPdf ? 'Document' : 'Page'} ${index + 1}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                IconButton(
                  onPressed: enabled && index > 0
                      ? () => controller.moveFile(index, -1)
                      : null,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  tooltip: 'Move up',
                ),
                IconButton(
                  onPressed: enabled && index < count - 1
                      ? () => controller.moveFile(index, 1)
                      : null,
                  icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                  tooltip: 'Move down',
                ),
              ],
            ),
          const Divider(),
        ],
      ),
    );
  }
}

class PdfPageStrip extends ConsumerWidget {
  const PdfPageStrip({super.key, required this.source});
  final PdfSource source;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Pages (${source.pageCount})',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: MediaQuery.textScalerOf(context).scale(14) > 20 ? 140 : 112,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: source.pageCount,
          itemBuilder: (context, index) => _PageThumbnail(
            key: ValueKey('${source.id}:$index'),
            source: source,
            page: index + 1,
          ),
        ),
      ),
    ],
  );
}

class _PageThumbnail extends ConsumerStatefulWidget {
  const _PageThumbnail({super.key, required this.source, required this.page});
  final PdfSource source;
  final int page;
  @override
  ConsumerState<_PageThumbnail> createState() => _PageThumbnailState();
}

class _PageThumbnailState extends ConsumerState<_PageThumbnail> {
  late final Future<String> image;
  @override
  void initState() {
    super.initState();
    image = ref
        .read(servicesProvider)
        .pdf
        .thumbnail(widget.source, widget.page, p.dirname(widget.source.path));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 10),
    child: SizedBox(
      width: 76,
      child: Column(
        children: [
          Expanded(
            child: Card(
              child: Center(
                child: FutureBuilder<String>(
                  future: image,
                  builder: (context, snapshot) => snapshot.hasData
                      ? Image.file(
                          File(snapshot.data!),
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, stack) =>
                              const Icon(Icons.picture_as_pdf_outlined),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined, size: 24),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('${widget.page}', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}
