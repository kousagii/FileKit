import 'dart:io';

import 'package:filekit/core/models.dart';
import 'package:filekit/core/services.dart';
import 'package:filekit/features/conversion/conversion_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'test_support.dart';

class SeededController extends AppController {
  SeededController(this.sources);
  final List<SourceFile> sources;
  @override
  FileKitState build() =>
      super.build().copyWith(sources: sources, tool: ToolKind.convert);
}

void main() {
  late Directory root;
  late AppServices services;
  late ProviderContainer container;
  late AppController controller;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('filekit_controller_');
    services = await testServices(root);
    final sources = <SourceFile>[];
    for (var i = 0; i < 2; i++) {
      final file = File(p.join(root.path, '$i.png'));
      await file.writeAsBytes(img.encodePng(img.Image(width: 10, height: 10)));
      sources.add(
        SourceFile(
          id: '$i',
          name: 'same.png',
          path: file.path,
          bytes: await file.length(),
          width: 10,
          height: 10,
          format: 'png',
          hasAlpha: false,
          thumbnailPath: file.path,
        ),
      );
    }
    container = ProviderContainer(
      overrides: [
        servicesProvider.overrideWithValue(services),
        appControllerProvider.overrideWith(() => SeededController(sources)),
      ],
    );
    controller = container.read(appControllerProvider.notifier);
  });
  tearDown(() async {
    container.dispose();
    await root.delete(recursive: true);
  });

  test('batch saves actual files and preserves duplicate names', () async {
    await controller.run();
    final result = container.read(appControllerProvider).result!;
    expect(result.status, JobStatus.succeeded);
    expect(result.outputs.map((file) => file.name), [
      'same_converted.jpg',
      'same_converted (1).jpg',
    ]);
    for (final file in result.outputs) {
      expect(
        img.decodeJpg(await File.fromUri(Uri.parse(file.uri)).readAsBytes()),
        isNotNull,
      );
    }
  });

  test('a failed output produces partial success and only failed files are retried', () async {
    final gateway = services.directory as LocalTestGateway;
    gateway.failCall = 2;
    await controller.run();
    var result = container.read(appControllerProvider).result!;
    expect(result.status, JobStatus.partiallySucceeded);
    expect(result.outputs.length, 1);
    expect(result.failures.single.sourceId, '1');
    gateway.failCall = null;
    await controller.run(failedOnly: true);
    result = container.read(appControllerProvider).result!;
    expect(result.status, JobStatus.succeeded);
    expect(result.sourceCount, 1);
    expect(gateway.calls, 3);
  });

  test(
    'cancel preserves the output already saved and skips remaining files',
    () async {
      final gateway = services.directory as LocalTestGateway;
      gateway.afterSave = controller.cancel;
      await controller.run();
      final result = container.read(appControllerProvider).result!;
      expect(result.status, JobStatus.cancelled);
      expect(result.outputs.length, 1);
      expect(gateway.calls, 1);
    },
  );

  test('revoked directory permission never reports success', () async {
    (services.directory as LocalTestGateway).valid = false;
    await controller.run();
    final state = container.read(appControllerProvider);
    expect(state.result, isNull);
    expect(state.notice, contains('folder is no longer available'));
    expect(state.busy, false);
    expect((services.directory as LocalTestGateway).calls, 0);
  });

  test('history failure after export preserves the output and warns without duplicate saves', () async {
    (services.directory as LocalTestGateway).afterSave = () =>
        (services.history as MemoryHistory).failWrites = true;
    await controller.run();
    final state = container.read(appControllerProvider);
    expect(state.result!.outputs.length, 2);
    expect(state.notice, contains('history could not be updated'));
    expect((services.directory as LocalTestGateway).calls, 2);
  });

  test('clearing history does not remove saved output files', () async {
    await controller.run();
    final outputs = container.read(appControllerProvider).result!.outputs;
    await controller.clearHistory();
    expect(container.read(appControllerProvider).history, isEmpty);
    for (final file in outputs) {
      expect(await File.fromUri(Uri.parse(file.uri)).exists(), true);
    }
  });
}
