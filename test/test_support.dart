import 'dart:io';

import 'package:filekit/core/models.dart';
import 'package:filekit/core/services.dart';
import 'package:filekit/core/storage.dart';
import 'package:filekit/features/conversion/pdf_service.dart';
import 'package:path/path.dart' as p;

class MemorySettings implements SettingsStore {
  AppSettings value = const AppSettings();
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async => value = settings;
}

class MemoryHistory implements HistoryRepository {
  final Map<String, HistoryJob> jobs = {};
  bool failWrites = false;
  @override
  Future<void> save(HistoryJob job) async {
    if (failWrites) {
      throw const FileSystemException('Simulated database failure');
    }
    jobs[job.id] = job;
  }

  @override
  Future<List<HistoryJob>> list() async =>
      jobs.values.toList().reversed.toList();
  @override
  Future<void> clear() async => jobs.clear();
}

class LocalTestGateway implements OutputDirectoryGateway {
  LocalTestGateway(this.folder);
  final Directory folder;
  bool valid = true;
  int calls = 0;
  int? failCall;
  void Function()? afterSave;
  @override
  Future<OutputDestination?> choose(OutputDestination? previous) async =>
      OutputDestination(uri: folder.uri.toString(), label: 'FileKit output');
  @override
  Future<bool> validate(OutputDestination destination) async => valid;
  @override
  Future<ConvertedFile> export({
    required OutputDestination destination,
    required String tempPath,
    required String name,
    required String mime,
  }) async {
    calls++;
    if (calls == failCall) {
      throw const FileKitException('Test provider cannot save this file.');
    }
    final extension = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    var file = File(p.join(folder.path, name));
    var suffix = 1;
    while (await file.exists()) {
      file = File(p.join(folder.path, '$stem (${suffix++})$extension'));
    }
    await File(tempPath).copy(file.path);
    afterSave?.call();
    return ConvertedFile(
      name: p.basename(file.path),
      uri: file.uri.toString(),
      mime: mime,
      bytes: await file.length(),
    );
  }

  @override
  Future<void> open(ConvertedFile file) async {
    if (!await File.fromUri(Uri.parse(file.uri)).exists()) {
      throw const FileKitException('This file is no longer available.');
    }
  }

  @override
  Future<String> prepareShare(ConvertedFile file) async =>
      File.fromUri(Uri.parse(file.uri)).path;
}

Future<AppServices> testServices(
  Directory root, {
  AppSettings? initialSettings,
  PdfService? pdf,
}) async {
  final output = await Directory(p.join(root.path, 'output')).create();
  final work = await Directory(p.join(root.path, 'work')).create();
  return AppServices(
    directory: LocalTestGateway(output),
    history: MemoryHistory(),
    settings: MemorySettings(),
    initialSettings: initialSettings ?? outputDestinationSettings(output),
    initialHistory: [],
    workingRoot: work,
    pdf: pdf,
  );
}

AppSettings outputDestinationSettings(Directory output) => AppSettings(
  destination: OutputDestination(
    uri: output.uri.toString(),
    label: 'FileKit output',
  ),
);
