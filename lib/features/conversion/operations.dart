import '../../core/models.dart';
import '../../core/storage.dart';
import 'conversion_engine.dart';
import 'page_ranges.dart';
import 'pdf_service.dart';

/// The same registry drives picker filtering, dropdowns, validation, and tasks.
class Capabilities {
  static bool isPdfOperation(ToolKind tool) =>
      tool == ToolKind.mergePdf || tool == ToolKind.splitPdf;
  static List<OutputFormat> outputs(
    ToolKind tool,
    InputFormat input,
    List<FileSource> sources,
  ) {
    if (isPdfOperation(tool) || tool == ToolKind.pdf) return [OutputFormat.pdf];
    final pdf =
        input == InputFormat.pdf ||
        (input == InputFormat.autoDetect && sources.any((s) => s.isPdf));
    if (pdf) {
      return tool == ToolKind.convert
          ? [OutputFormat.png, OutputFormat.jpg]
          : [];
    }
    return tool == ToolKind.compress
        ? [OutputFormat.jpg, OutputFormat.webp]
        : tool == ToolKind.resize
        ? [OutputFormat.jpg, OutputFormat.png, OutputFormat.webp]
        : [
            OutputFormat.jpg,
            OutputFormat.png,
            OutputFormat.webp,
            OutputFormat.pdf,
          ];
  }

  static String? sourceIssue(
    FileSource source,
    ToolKind tool,
    InputFormat input,
  ) {
    if (isPdfOperation(tool)) {
      return source.isPdf ? null : 'This tool accepts PDF files.';
    }
    if (source.isPdf && tool != ToolKind.convert) {
      return 'Choose an image for this tool.';
    }
    if (input != InputFormat.autoDetect && source.format != input.name) {
      return 'Choose ${input.label} files, or change Input to Auto-detect.';
    }
    return null;
  }

  static List<String> extensions(ToolKind tool, InputFormat input) =>
      isPdfOperation(tool)
      ? ['pdf']
      : tool != ToolKind.convert && input == InputFormat.autoDetect
      ? ['png', 'jpg', 'jpeg', 'webp', 'bmp']
      : input.extensions;

  static String? validate(
    ToolKind tool,
    ConversionOptions options,
    List<FileSource> sources,
  ) {
    if (sources.isEmpty) return 'Add at least one file.';
    for (final source in sources) {
      final issue = sourceIssue(source, tool, options.input);
      if (issue != null) return issue;
    }
    if (sources.any((s) => s.isPdf) && sources.any((s) => !s.isPdf)) {
      return 'Use images or PDFs in one job. Remove the other file type.';
    }
    if (!outputs(tool, options.input, sources).contains(options.format)) {
      return 'Choose a supported output format.';
    }
    if (tool == ToolKind.mergePdf) {
      if (sources.length < 2) return 'Add at least two PDFs to merge.';
      if (sources.cast<PdfSource>().fold(0, (sum, s) => sum + s.pageCount) >
          AppLimits.maxMergePages) {
        return 'Merge up to 200 pages per job.';
      }
    } else if (sources.first.isPdf) {
      if (sources.length != 1) {
        return 'Choose one PDF. Use Merge PDF to combine documents.';
      }
      final count = (sources.first as PdfSource).pageCount;
      try {
        if (tool == ToolKind.splitPdf && options.splitEachPage) return null;
        if (tool == ToolKind.splitPdf && options.pageRanges.trim().isEmpty) {
          return 'Enter page ranges to split, such as 1-3, 5.';
        }
        if (tool != ToolKind.splitPdf &&
            options.usePageRanges &&
            options.pageRanges.trim().isEmpty) {
          return 'Enter the pages to export, such as 1-3, 5.';
        }
        final groups = parsePageRanges(
          tool == ToolKind.splitPdf || options.usePageRanges
              ? options.pageRanges
              : '',
          count,
        );
        if (tool != ToolKind.splitPdf &&
            groups.expand((p) => p).length > AppLimits.maxExportPages) {
          return 'Export up to 30 pages at a time. Choose a page range.';
        }
      } on FileKitException catch (error) {
        return error.message;
      }
    }
    if (!sources.first.isPdf &&
        ((options.maxWidth != null &&
                (options.maxWidth! < 1 ||
                    options.maxWidth! > AppLimits.maxDimension)) ||
            (options.maxHeight != null &&
                (options.maxHeight! < 1 ||
                    options.maxHeight! > AppLimits.maxDimension)))) {
      return 'Use dimensions from 1 to 12,000 pixels.';
    }
    return null;
  }
}

class OperationTask {
  const OperationTask({
    required this.id,
    required this.label,
    required this.sources,
    this.pages = const [],
  });
  final String id, label;
  final List<FileSource> sources;
  final List<int> pages;
}

List<OperationTask> createTasks(
  ToolKind tool,
  ConversionOptions options,
  List<FileSource> sources,
) {
  final issue = Capabilities.validate(tool, options, sources);
  if (issue != null) throw FileKitException(issue);
  if (tool == ToolKind.mergePdf) {
    return [OperationTask(id: 'merge', label: 'Merged PDF', sources: sources)];
  }
  if (sources.first is PdfSource) {
    final source = sources.first as PdfSource;
    final groups = tool == ToolKind.splitPdf && options.splitEachPage
        ? List.generate(source.pageCount, (i) => [i + 1])
        : parsePageRanges(
            tool == ToolKind.splitPdf || options.usePageRanges
                ? options.pageRanges
                : '',
            source.pageCount,
          );
    final selected = tool == ToolKind.splitPdf
        ? groups
        : groups.expand((p) => p).map((p) => [p]).toList();
    return selected
        .map(
          (pages) => OperationTask(
            id: '${source.id}:${pages.join('-')}',
            label: pages.length == 1
                ? 'Page ${pages.first}'
                : 'Pages ${pages.first}–${pages.last}',
            sources: [source],
            pages: pages,
          ),
        )
        .toList();
  }
  if (options.format == OutputFormat.pdf) {
    return [
      OperationTask(id: 'images-pdf', label: 'Combined PDF', sources: sources),
    ];
  }
  return sources
      .map((s) => OperationTask(id: s.id, label: s.name, sources: [s]))
      .toList();
}

class ProcessedOutput {
  const ProcessedOutput(this.file, [this.notice]);
  final TempOutput file;
  final String? notice;
}

class OperationProcessor {
  OperationProcessor(this.pdf, this.images);
  final PdfService pdf;
  final ConverterRegistry images;
  Future<ProcessedOutput> process(
    ToolKind tool,
    OperationTask task,
    ConversionOptions options,
    String directory,
  ) async {
    if (tool == ToolKind.mergePdf) {
      return ProcessedOutput(
        await pdf.merge(
          task.sources.cast<PdfSource>(),
          options.pdfName,
          directory,
        ),
      );
    }
    if (tool == ToolKind.splitPdf) {
      final source = task.sources.single as PdfSource;
      final suffix = task.pages.length == 1
          ? 'page_${task.pages.first.toString().padLeft(3, '0')}'
          : 'pages_${task.pages.first.toString().padLeft(3, '0')}-${task.pages.last.toString().padLeft(3, '0')}';
      return ProcessedOutput(
        await pdf.split(
          source,
          task.pages,
          '${safeBaseName(source.name)}_$suffix.pdf',
          directory,
        ),
      );
    }
    if (task.sources.first is PdfSource) {
      final result = await pdf.renderPage(
        task.sources.single as PdfSource,
        task.pages.single,
        options,
        directory,
      );
      return ProcessedOutput(result.$1, result.$2);
    }
    return ProcessedOutput(
      await images
          .forFormat(options.format)
          .convert(task.sources.cast<SourceFile>(), options, directory),
    );
  }
}
