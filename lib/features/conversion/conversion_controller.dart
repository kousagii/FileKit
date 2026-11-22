import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/models.dart';
import '../../core/services.dart';
import '../../core/storage.dart';
import 'conversion_engine.dart';
import 'operations.dart';

class FileKitState {
  const FileKitState({
    required this.settings,
    this.history = const [],
    this.sources = const [],
    this.tool = ToolKind.convert,
    this.options = const ConversionOptions(),
    this.busy = false,
    this.picking = false,
    this.stage = '',
    this.completed = 0,
    this.total = 0,
    this.cancelRequested = false,
    this.result,
    this.notice,
  });
  final AppSettings settings;
  final List<HistoryJob> history;
  final List<FileSource> sources;
  final ToolKind tool;
  final ConversionOptions options;
  final bool busy, picking, cancelRequested;
  final String stage;
  final int completed, total;
  final HistoryJob? result;
  final String? notice;
  FileKitState copyWith({
    AppSettings? settings,
    List<HistoryJob>? history,
    List<FileSource>? sources,
    ToolKind? tool,
    ConversionOptions? options,
    bool? busy,
    bool? picking,
    String? stage,
    int? completed,
    int? total,
    bool? cancelRequested,
    HistoryJob? result,
    bool clearResult = false,
    String? notice,
    bool clearNotice = false,
  }) => FileKitState(
    settings: settings ?? this.settings,
    history: history ?? this.history,
    sources: sources ?? this.sources,
    tool: tool ?? this.tool,
    options: options ?? this.options,
    busy: busy ?? this.busy,
    picking: picking ?? this.picking,
    stage: stage ?? this.stage,
    completed: completed ?? this.completed,
    total: total ?? this.total,
    cancelRequested: cancelRequested ?? this.cancelRequested,
    result: clearResult ? null : result ?? this.result,
    notice: clearNotice ? null : notice ?? this.notice,
  );
}

final appControllerProvider = NotifierProvider<AppController, FileKitState>(
  AppController.new,
);

class AppController extends Notifier<FileKitState> {
  late AppServices _services;
  bool _cancelled = false;
  Directory? _selectionDirectory;
  int _sequence = 0;

  @override
  FileKitState build() {
    _services = ref.read(servicesProvider);
    return FileKitState(
      settings: _services.initialSettings,
      history: _services.initialHistory,
      options: ConversionOptions(quality: _services.initialSettings.quality),
    );
  }

  void selectTool(ToolKind selected) {
    if (state.busy || state.picking) return;
    final tool = selected == ToolKind.pdf ? ToolKind.convert : selected;
    final pdfOperation = Capabilities.isPdfOperation(tool);
    final hasPdf =
        state.sources.isNotEmpty && state.sources.every((s) => s.isPdf);
    final options = ConversionOptions(
      format: pdfOperation || selected == ToolKind.pdf
          ? OutputFormat.pdf
          : hasPdf && tool == ToolKind.convert
          ? OutputFormat.png
          : OutputFormat.jpg,
      input: pdfOperation ? InputFormat.pdf : InputFormat.autoDetect,
      quality: tool == ToolKind.compress ? 75 : state.settings.quality,
      maxWidth: tool == ToolKind.resize ? 1920 : null,
      maxHeight: tool == ToolKind.resize ? 1920 : null,
      pdfName: tool == ToolKind.mergePdf
          ? 'merged.pdf'
          : 'converted_images.pdf',
    );
    state = state.copyWith(
      tool: tool,
      options: options,
      clearResult: true,
      clearNotice: true,
    );
  }

  void updateOptions(ConversionOptions options) {
    if (!state.busy && !state.picking) {
      state = state.copyWith(options: options, clearResult: true);
    }
  }

  void dismissNotice() => state = state.copyWith(clearNotice: true);
  void showNotice(String message) => state = state.copyWith(notice: message);

  Future<void> addFiles() async {
    if (state.busy || state.picking) return;
    if (state.sources.length >= AppLimits.maxFiles) {
      showNotice('Select up to 10 files per job.');
      return;
    }
    state = state.copyWith(picking: true, clearNotice: true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: Capabilities.extensions(
          state.tool,
          state.options.input,
        ),
      );
      if (files.isEmpty) return;
      _selectionDirectory ??= await _services.workingRoot.createTemp(
        'selection_',
      );
      final selected = [...state.sources];
      final errors = <String>[];
      final available = AppLimits.maxFiles - selected.length;
      if (files.length > available) {
        errors.add(
          'Only the first $available files were added. The limit is 10.',
        );
      }
      for (final file in files.take(available)) {
        File? staged;
        File? thumbnail;
        try {
          final length = await file.length();
          if (length != null && length > AppLimits.maxPdfBytes) {
            throw const FileKitException('This file is larger than 50 MB.');
          }
          final id = '${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';
          staged = File(p.join(_selectionDirectory!.path, '$id.source'));
          final sink = staged.openWrite();
          var count = 0;
          try {
            await for (final chunk in file.readAsByteStream()) {
              count += chunk.length;
              if (count > AppLimits.maxPdfBytes) {
                throw const FileKitException('This file is larger than 50 MB.');
              }
              sink.add(chunk);
            }
            await sink.flush();
          } finally {
            await sink.close();
          }
          final reader = await staged.open();
          late final bool isPdf;
          try {
            isPdf = latin1.decode(await reader.read(1024)).contains('%PDF-');
          } finally {
            await reader.close();
          }
          thumbnail = File(p.join(_selectionDirectory!.path, '$id.thumb.png'));
          if (isPdf) {
            final inspection = await _services.pdf.inspect(
              staged.path,
              thumbnail.path,
            );
            selected.add(
              PdfSource(
                id: id,
                name: file.name,
                path: staged.path,
                bytes: count,
                thumbnailPath: thumbnail.path,
                pageCount: inspection.pageCount,
              ),
            );
          } else {
            final inspection = await inspectSource(staged.path, thumbnail.path);
            selected.add(
              SourceFile(
                id: id,
                name: file.name,
                path: staged.path,
                bytes: count,
                thumbnailPath: thumbnail.path,
                width: inspection.width,
                height: inspection.height,
                format: inspection.format,
                hasAlpha: inspection.hasAlpha,
              ),
            );
          }
        } catch (error) {
          for (final temp in [staged, thumbnail]) {
            try {
              if (temp != null && await temp.exists()) await temp.delete();
            } on FileSystemException {
              /* Startup cleanup retries. */
            }
          }
          errors.add('${file.name}: ${friendlyError(error)}');
        }
      }
      state = state.copyWith(
        sources: selected,
        clearResult: true,
        notice: errors.isEmpty ? null : errors.take(3).join('\n'),
        clearNotice: errors.isEmpty,
      );
    } catch (error) {
      showNotice(friendlyError(error));
    } finally {
      state = state.copyWith(picking: false);
    }
  }

  Future<void> removeFile(String id) async {
    if (state.busy || state.picking) return;
    final file = state.sources.firstWhere((file) => file.id == id);
    state = state.copyWith(
      sources: state.sources.where((file) => file.id != id).toList(),
      clearResult: true,
    );
    for (final path in [file.path, file.thumbnailPath]) {
      try {
        await File(path).delete();
      } on FileSystemException {
        /* Startup cleanup retries. */
      }
    }
  }

  void reorderFiles(int oldIndex, int newIndex) {
    if (state.busy || state.picking) return;
    final list = [...state.sources];
    list.insert(newIndex, list.removeAt(oldIndex));
    state = state.copyWith(sources: list, clearResult: true);
  }

  void moveFile(int index, int delta) {
    if (state.busy || state.picking) return;
    final target = index + delta;
    if (target < 0 || target >= state.sources.length) return;
    final list = [...state.sources];
    list.insert(target, list.removeAt(index));
    state = state.copyWith(sources: list, clearResult: true);
  }

  Future<void> chooseFolder() async {
    if (state.busy || state.picking) return;
    state = state.copyWith(picking: true, clearNotice: true);
    try {
      final destination = await _services.directory.choose(
        state.settings.destination,
      );
      if (destination == null) return;
      final settings = state.settings.copyWith(destination: destination);
      state = state.copyWith(settings: settings);
      await _services.settings.save(settings);
      if (!destination.persistent) {
        showNotice('Choose this folder again after restarting the app.');
      }
    } catch (error) {
      showNotice(friendlyError(error));
    } finally {
      state = state.copyWith(picking: false);
    }
  }

  Future<void> updateSettings({String? theme, int? quality}) async {
    final settings = state.settings.copyWith(theme: theme, quality: quality);
    state = state.copyWith(settings: settings);
    try {
      await _services.settings.save(settings);
    } catch (_) {
      showNotice('Your setting could not be saved. Try again.');
    }
  }

  void cancel() {
    if (!state.busy) return;
    _cancelled = true;
    state = state.copyWith(
      cancelRequested: true,
      stage: 'Stopping after the current step…',
    );
  }

  Future<void> run({bool failedOnly = false}) async {
    if (state.busy || state.picking) return;
    final destination = state.settings.destination;
    if (destination == null) {
      showNotice('Choose an output folder.');
      return;
    }
    final options = state.options;
    final tool = state.tool;
    final sources = List<FileSource>.unmodifiable(state.sources);
    final failedIds =
        state.result?.failures.map((f) => f.sourceId).toSet() ?? <String>{};
    late final List<OperationTask> tasks;
    try {
      tasks = createTasks(
        tool,
        options,
        sources,
      ).where((task) => !failedOnly || failedIds.contains(task.id)).toList();
    } catch (error) {
      showNotice(friendlyError(error));
      return;
    }
    if (tasks.isEmpty) {
      showNotice('There are no failed outputs to retry.');
      return;
    }
    _cancelled = false;
    state = state.copyWith(
      busy: true,
      completed: 0,
      total: tasks.length,
      cancelRequested: false,
      stage: 'Checking output folder…',
      clearResult: true,
      clearNotice: true,
    );
    HistoryJob? job;
    Directory? work;
    var historyWarning = false;
    final notices = <String>[];
    try {
      if (!await _services.directory.validate(destination)) {
        throw const FileKitException(
          'This folder is no longer available. Choose another folder.',
        );
      }
      if (_cancelled) return;
      final participating = tasks
          .expand((task) => task.sources)
          .map((s) => s.id)
          .toSet();
      final inputs = sources
          .where((s) => participating.contains(s.id))
          .toList();
      job = HistoryJob(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: inputs.length == 1
            ? inputs.first.name
            : '${inputs.length} files',
        tool: tool,
        format: options.format,
        createdAt: DateTime.now(),
        destination: destination,
        sourceCount: inputs.length,
        inputBytes: inputs.fold(0, (sum, s) => sum + s.bytes),
        status: JobStatus.processing,
        requestJson: jsonEncode({
          'options': options.toMap(),
          'tasks': tasks.map((t) => {'id': t.id, 'pages': t.pages}).toList(),
        }),
      );
      await _services.history.save(job);
      work = await _services.workingRoot.createTemp('output_');
      final processor = OperationProcessor(_services.pdf, _services.registry);
      for (final task in tasks) {
        if (_cancelled) break;
        TempOutput? temp;
        try {
          state = state.copyWith(stage: 'Processing ${task.label}…');
          final processed = await processor.process(
            tool,
            task,
            options,
            work.path,
          );
          temp = processed.file;
          if (processed.notice != null) notices.add(processed.notice!);
          if (_cancelled) break;
          state = state.copyWith(stage: 'Saving ${temp.name}…');
          final output = await _services.directory.export(
            destination: destination,
            tempPath: temp.path,
            name: temp.name,
            mime: temp.mime,
          );
          job = job!.copyWith(
            outputs: [...job.outputs, output.forItem(task.id)],
          );
        } catch (error) {
          job = job!.copyWith(
            failures: [
              ...job.failures,
              ItemFailure(task.id, task.label, friendlyError(error)),
            ],
          );
        } finally {
          if (temp != null) {
            try {
              await File(temp.path).delete();
            } on FileSystemException {
              /* Later cleanup. */
            }
          }
        }
        try {
          await _services.history.save(job);
        } catch (_) {
          historyWarning = true;
        }
        state = state.copyWith(completed: state.completed + 1);
      }
      final status = _cancelled
          ? JobStatus.cancelled
          : job!.failures.isEmpty
          ? JobStatus.succeeded
          : job.outputs.isEmpty
          ? JobStatus.failed
          : JobStatus.partiallySucceeded;
      final messages = [
        if (_cancelled) 'Stopped. Files already saved are kept.',
        ...notices.take(3),
        if (notices.length > 3)
          '${notices.length - 3} more pages used reduced resolution.',
      ];
      job = job!.copyWith(
        status: status,
        message: messages.isEmpty ? null : messages.join('\n'),
      );
    } catch (error) {
      if (job == null) {
        showNotice(friendlyError(error));
      } else {
        job = job.copyWith(
          status: JobStatus.failed,
          message: friendlyError(error),
        );
      }
    } finally {
      if (job != null) {
        try {
          await _services.history.save(job);
        } catch (_) {
          historyWarning = true;
        }
        try {
          state = state.copyWith(history: await _services.history.list());
        } catch (_) {
          historyWarning = true;
        }
        state = state.copyWith(result: job);
      }
      if (work != null) {
        try {
          await work.delete(recursive: true);
        } on FileSystemException {
          /* Later cleanup. */
        }
      }
      state = state.copyWith(
        busy: false,
        stage: '',
        notice: historyWarning
            ? 'Files already saved are kept, but history could not be updated.'
            : state.notice,
      );
    }
  }

  Future<void> clearSelection() async {
    if (state.busy || state.picking) return;
    state = state.copyWith(
      sources: [],
      clearResult: true,
      clearNotice: true,
      completed: 0,
      total: 0,
    );
    final directory = _selectionDirectory;
    _selectionDirectory = null;
    if (directory != null) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        /* Later cleanup. */
      }
    }
  }

  Future<void> openFile(ConvertedFile file) async {
    try {
      await _services.directory.open(file);
    } catch (error) {
      showNotice(friendlyError(error));
    }
  }

  Future<void> shareFile(ConvertedFile file) async {
    try {
      final path = await _services.directory.prepareShare(file);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: file.mime)],
          title: file.name,
        ),
      );
    } catch (error) {
      showNotice(friendlyError(error));
    }
  }

  Future<void> clearHistory() async {
    if (state.busy) return;
    try {
      await _services.history.clear();
      state = state.copyWith(history: []);
    } catch (_) {
      showNotice('History could not be cleared. Try again.');
    }
  }
}
