import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

abstract class OutputDirectoryGateway {
  Future<OutputDestination?> choose(OutputDestination? previous);
  Future<bool> validate(OutputDestination destination);
  Future<ConvertedFile> export({
    required OutputDestination destination,
    required String tempPath,
    required String name,
    required String mime,
  });
  Future<void> open(ConvertedFile file);
  Future<String> prepareShare(ConvertedFile file);
}

class AndroidDirectoryGateway implements OutputDirectoryGateway {
  static const channel = MethodChannel('dev.kousagii.filekit/documents');
  @override
  Future<OutputDestination?> choose(OutputDestination? previous) async {
    final result = await channel.invokeMapMethod<String, dynamic>(
      'chooseDirectory',
      {'initialUri': previous?.uri},
    );
    return result == null ? null : OutputDestination.fromMap(result);
  }

  @override
  Future<bool> validate(OutputDestination destination) async =>
      await channel.invokeMethod<bool>('validateDirectory', {
        'uri': destination.uri,
      }) ??
      false;
  @override
  Future<ConvertedFile> export({
    required OutputDestination destination,
    required String tempPath,
    required String name,
    required String mime,
  }) async {
    final result = await channel.invokeMapMethod<String, dynamic>(
      'exportFile',
      {'uri': destination.uri, 'path': tempPath, 'name': name, 'mime': mime},
    );
    if (result == null) {
      throw const FileKitException('The file could not be saved.');
    }
    return ConvertedFile.fromMap(result);
  }

  @override
  Future<void> open(ConvertedFile file) => channel.invokeMethod<void>(
    'openDocument',
    {'uri': file.uri, 'mime': file.mime},
  );
  @override
  Future<String> prepareShare(ConvertedFile file) async {
    final path = await channel.invokeMethod<String>('prepareShare', {
      'uri': file.uri,
      'name': file.name,
    });
    if (path == null) {
      throw const FileKitException('This file is no longer available.');
    }
    return path;
  }
}

abstract class HistoryRepository {
  Future<void> save(HistoryJob job);
  Future<List<HistoryJob>> list();
  Future<void> clear();
}

class SqliteHistoryRepository implements HistoryRepository {
  SqliteHistoryRepository(this.database);
  final Database database;
  static Future<SqliteHistoryRepository> create({String? path}) async {
    final database = await openDatabase(
      path ?? p.join(await getDatabasesPath(), 'filekit.db'),
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute(
          '''CREATE TABLE jobs (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, tool TEXT NOT NULL,
          format TEXT NOT NULL, createdAt INTEGER NOT NULL,
          destination TEXT NOT NULL, sourceCount INTEGER NOT NULL,
          inputBytes INTEGER NOT NULL, status TEXT NOT NULL,
          failures TEXT NOT NULL, message TEXT, requestJson TEXT NOT NULL DEFAULT '{}')''',
        );
        await db.execute('''CREATE TABLE outputs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          jobId TEXT NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
          name TEXT NOT NULL, uri TEXT NOT NULL, mime TEXT NOT NULL,
          bytes INTEGER NOT NULL, itemId TEXT)''');
      },
      onUpgrade: migrateHistoryDatabase,
    );
    await database.update(
      'jobs',
      {
        'status': JobStatus.interrupted.name,
        'message':
            'The app closed before this job finished. Saved files are kept.',
      },
      where: 'status = ?',
      whereArgs: [JobStatus.processing.name],
    );
    return SqliteHistoryRepository(database);
  }

  @override
  Future<void> save(HistoryJob job) => database.transaction((txn) async {
    final updated = await txn.update(
      'jobs',
      job.toRow(),
      where: 'id = ?',
      whereArgs: [job.id],
    );
    if (updated == 0) await txn.insert('jobs', job.toRow());
    await txn.delete('outputs', where: 'jobId = ?', whereArgs: [job.id]);
    for (final file in job.outputs) {
      await txn.insert('outputs', {...file.toMap(), 'jobId': job.id});
    }
  });
  @override
  Future<List<HistoryJob>> list() async {
    final rows = await database.query('jobs', orderBy: 'createdAt DESC');
    final files = await database.query('outputs', orderBy: 'id ASC');
    return rows
        .map(
          (row) => HistoryJob.fromRows(
            row,
            files
                .where((file) => file['jobId'] == row['id'])
                .map(
                  (file) =>
                      ConvertedFile.fromMap(Map<String, dynamic>.from(file)),
                )
                .toList(),
          ),
        )
        .toList();
  }

  @override
  Future<void> clear() => database.transaction((txn) async {
    await txn.delete('outputs');
    await txn.delete('jobs');
  });
}

abstract class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

Future<void> migrateHistoryDatabase(
  Database db,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion < 2) {
    await db.execute(
      "ALTER TABLE jobs ADD COLUMN requestJson TEXT NOT NULL DEFAULT '{}'",
    );
    await db.execute('ALTER TABLE outputs ADD COLUMN itemId TEXT');
  }
}

class SettingsRepository implements SettingsStore {
  SettingsRepository(this.preferences);
  final SharedPreferencesAsync preferences;
  @override
  Future<AppSettings> load() async {
    final folder = await preferences.getString('destination');
    OutputDestination? destination;
    if (folder != null) {
      try {
        final candidate = OutputDestination.fromMap(
          jsonDecode(folder) as Map<String, dynamic>,
        );
        if (candidate.persistent) destination = candidate;
      } catch (_) {
        /* Ignore a malformed preference. */
      }
    }
    final storedTheme = await preferences.getString('theme') ?? 'system';
    return AppSettings(
      theme: const ['system', 'light', 'dark'].contains(storedTheme)
          ? storedTheme
          : 'system',
      quality: (await preferences.getInt('quality') ?? 85).clamp(50, 100),
      destination: destination,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    await preferences.setString('theme', settings.theme);
    await preferences.setInt('quality', settings.quality);
    if (settings.destination != null) {
      await preferences.setString(
        'destination',
        jsonEncode(settings.destination!.toMap()),
      );
    }
  }
}

class FileKitException implements Exception {
  const FileKitException(this.message);
  final String message;
  @override
  String toString() => message;
}

String friendlyError(Object error) {
  if (error is FileKitException) return error.message;
  if (error is PlatformException) {
    return error.message ?? 'The file operation could not be completed.';
  }
  if (error is FileSystemException) {
    return 'The file could not be read or saved. Check available storage and try again.';
  }
  return 'This file could not be processed. Try another file.';
}
