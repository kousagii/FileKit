import 'dart:io';

import 'package:filekit/core/models.dart';
import 'package:filekit/core/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

void main() {
  late Directory root;
  late String path;
  setUpAll(() {
    ffi.sqfliteFfiInit();
    platform.databaseFactory = ffi.databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('filekit_history_');
    path = p.join(root.path, 'history.db');
  });
  tearDown(() async => root.delete(recursive: true));

  HistoryJob sample({
    ToolKind tool = ToolKind.pdf,
    OutputFormat format = OutputFormat.pdf,
    JobStatus status = JobStatus.succeeded,
    String request = '{}',
    List<ConvertedFile> outputs = const [],
  }) => HistoryJob(
    id: 'old-job',
    title: 'Old images',
    tool: tool,
    format: format,
    createdAt: DateTime(2026, 11, 15),
    destination: const OutputDestination(
      uri: 'content://provider/tree/folder',
      label: 'Assignments',
    ),
    sourceCount: 2,
    inputBytes: 100,
    status: status,
    outputs: outputs,
    requestJson: request,
  );

  test(
    'real SQLite upgrade preserves version-1 PDF history and output URIs',
    () async {
      final database = await platform.openDatabase(
        path,
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            '''CREATE TABLE jobs (id TEXT PRIMARY KEY, title TEXT NOT NULL,
        tool TEXT NOT NULL, format TEXT NOT NULL, createdAt INTEGER NOT NULL, destination TEXT NOT NULL,
        sourceCount INTEGER NOT NULL, inputBytes INTEGER NOT NULL, status TEXT NOT NULL, failures TEXT NOT NULL, message TEXT)''',
          );
          await db.execute(
            '''CREATE TABLE outputs (id INTEGER PRIMARY KEY AUTOINCREMENT,
        jobId TEXT NOT NULL REFERENCES jobs(id), name TEXT NOT NULL, uri TEXT NOT NULL, mime TEXT NOT NULL, bytes INTEGER NOT NULL)''',
          );
        },
      );
      final row = sample().toRow()..remove('requestJson');
      await database.insert('jobs', row);
      await database.insert('outputs', {
        'jobId': 'old-job',
        'name': 'old.pdf',
        'uri': 'content://provider/document/old',
        'mime': 'application/pdf',
        'bytes': 123,
      });
      await database.close();
      final repository = await SqliteHistoryRepository.create(path: path);
      try {
        final restored = (await repository.list()).single;
        expect(restored.tool, ToolKind.pdf);
        expect(restored.format, OutputFormat.pdf);
        expect(restored.outputs.single.uri, 'content://provider/document/old');
        expect(restored.outputs.single.itemId, isNull);
        expect(restored.requestJson, '{}');
        expect(await repository.database.getVersion(), 2);
      } finally {
        await repository.database.close();
      }
    },
  );

  test(
    'new format, task IDs, options, and interrupted status survive a reopen',
    () async {
      var repository = await SqliteHistoryRepository.create(path: path);
      await repository.save(
        sample(
          tool: ToolKind.splitPdf,
          format: OutputFormat.webp,
          status: JobStatus.processing,
          request: '{"pages":[2,3]}',
          outputs: const [
            ConvertedFile(
              name: 'page.webp',
              uri: 'content://provider/document/page',
              mime: 'image/webp',
              bytes: 20,
              itemId: 'source:2',
            ),
          ],
        ),
      );
      await repository.database.close();
      repository = await SqliteHistoryRepository.create(path: path);
      try {
        final restored = (await repository.list()).single;
        expect(restored.status, JobStatus.interrupted);
        expect(restored.tool, ToolKind.splitPdf);
        expect(restored.format, OutputFormat.webp);
        expect(restored.outputs.single.itemId, 'source:2');
        expect(restored.requestJson, '{"pages":[2,3]}');
      } finally {
        await repository.database.close();
      }
    },
  );

  test('clearing actual SQL history leaves the saved file untouched', () async {
    final file = await File(p.join(root.path, 'saved.pdf'))
        .writeAsString('already saved');
    final repository = await SqliteHistoryRepository.create(path: path);
    try {
      await repository.save(
        sample(
          outputs: [
            ConvertedFile(
              name: 'saved.pdf',
              uri: file.uri.toString(),
              mime: 'application/pdf',
              bytes: 13,
            ),
          ],
        ),
      );
      await repository.clear();
      expect(await repository.list(), isEmpty);
      expect(await file.readAsString(), 'already saved');
    } finally {
      await repository.database.close();
    }
  });
}
