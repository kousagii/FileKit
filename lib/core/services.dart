import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/conversion/conversion_engine.dart';
import '../features/conversion/pdf_service.dart';
import 'models.dart';
import 'storage.dart';

class AppServices {
  AppServices({
    required this.directory,
    required this.history,
    required this.settings,
    required this.initialSettings,
    required this.initialHistory,
    required this.workingRoot,
    ConverterRegistry? registry,
    PdfService? pdf,
  }) : registry = registry ?? ConverterRegistry(),
       pdf = pdf ?? PdfService();
  final OutputDirectoryGateway directory;
  final HistoryRepository history;
  final SettingsStore settings;
  final AppSettings initialSettings;
  final List<HistoryJob> initialHistory;
  final Directory workingRoot;
  final ConverterRegistry registry;
  final PdfService pdf;

  static Future<AppServices> initialize() async {
    final settings = SettingsRepository(SharedPreferencesAsync());
    final history = await SqliteHistoryRepository.create();
    final root = Directory(
      p.join((await getTemporaryDirectory()).path, 'filekit_jobs'),
    );
    await root.create(recursive: true);
    // Only remove temporary directories owned by FileKit, never selected output folders.
    await for (final child in root.list(followLinks: false)) {
      try {
        await child.delete(recursive: true);
      } on FileSystemException {
        /* Retry on a later launch. */
      }
    }
    return AppServices(
      directory: AndroidDirectoryGateway(),
      history: history,
      settings: settings,
      initialSettings: await settings.load(),
      initialHistory: await history.list(),
      workingRoot: root,
    );
  }
}

final servicesProvider = Provider<AppServices>(
  (ref) => throw StateError('App services were not initialized.'),
);
