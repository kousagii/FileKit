import 'dart:io';

import 'package:filekit/core/models.dart';
import 'package:filekit/core/storage.dart';
import 'package:filekit/features/conversion/operations.dart';
import 'package:filekit/features/conversion/pdf_service.dart';
import 'package:filekit/features/conversion/conversion_controller.dart';
import 'package:filekit/core/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' as creation;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'test_support.dart';

class PdfControllerFixture extends AppController {
  PdfControllerFixture(this.source);
  final PdfSource source;
  @override
  FileKitState build() => super.build().copyWith(
    sources: [source],
    tool: ToolKind.convert,
    options: const ConversionOptions(
      input: InputFormat.pdf,
      format: OutputFormat.png,
    ),
  );
}

void main() {
  late Directory root;
  late PdfService service;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('filekit_pdf_');
    service = PdfService(initialize: () => pdfrxInitialize(tmpPath: root.path));
  });
  tearDownAll(() async => root.delete(recursive: true));

  Future<PdfSource> fixture(
    String id,
    List<String> labels, {
    double width = 144,
    double height = 72,
  }) async {
    final document = pw.Document();
    for (final label in labels) {
      document.addPage(
        pw.Page(
          pageFormat: creation.PdfPageFormat(width, height),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Container(
            color: label.contains('BLUE')
                ? creation.PdfColors.blue
                : creation.PdfColors.red,
            child: pw.Center(
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 8,
                  color: creation.PdfColors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final file = File(p.join(root.path, '$id.pdf'));
    await file.writeAsBytes(await document.save());
    return PdfSource(
      id: id,
      name: '$id.pdf',
      path: file.path,
      bytes: await file.length(),
      thumbnailPath: p.join(root.path, '$id.png'),
      pageCount: labels.length,
    );
  }

  Future<List<String>> textOf(String path) async {
    final doc = await PdfDocument.openFile(path);
    try {
      return [
        for (final page in doc.pages) (await page.loadText())!.fullText.trim(),
      ];
    } finally {
      await doc.dispose();
    }
  }

  test('native engine inspects a PDF and creates a real thumbnail', () async {
    final source = await fixture('inspect', ['RED ONE', 'BLUE TWO']);
    final inspection = await service.inspect(source.path, source.thumbnailPath);
    expect(inspection.pageCount, 2);
    final thumbnail = img.decodePng(
      await File(source.thumbnailPath).readAsBytes(),
    )!;
    expect(thumbnail.width, 160);
    expect(thumbnail.height, 80);
    expect(await textOf(source.path), ['RED ONE', 'BLUE TWO']);
  });

  test('native merge keeps text, file order, and page dimensions', () async {
    final first = await fixture('merge_first', ['RED ONE', 'RED TWO']);
    final second = await fixture(
      'merge_second',
      ['BLUE THREE'],
      width: 72,
      height: 144,
    );
    final output = await service.merge(
      [second, first],
      'merged.pdf',
      root.path,
    );
    expect(await textOf(output.path), ['BLUE THREE', 'RED ONE', 'RED TWO']);
    final document = await PdfDocument.openFile(output.path);
    try {
      expect(document.pages.first.width, closeTo(72, .1));
      expect(document.pages.first.height, closeTo(144, .1));
      expect(document.pages.last.width, closeTo(144, .1));
    } finally {
      await document.dispose();
    }
  });

  test(
    'split exports exactly the requested pages with selectable text',
    () async {
      final source = await fixture('split', [
        'RED ONE',
        'BLUE TWO',
        'RED THREE',
      ]);
      final output = await service.split(
        source,
        [3, 1],
        'selected.pdf',
        root.path,
      );
      expect(await textOf(output.path), ['RED THREE', 'RED ONE']);
      expect(await textOf(source.path), ['RED ONE', 'BLUE TWO', 'RED THREE']);
    },
  );

  test(
    'page export creates valid PNG/JPEG with correct DPI and page content',
    () async {
      final source = await fixture('render', ['RED ONE', 'BLUE TWO']);
      for (final format in [OutputFormat.png, OutputFormat.jpg]) {
        final output = await service.renderPage(
          source,
          2,
          ConversionOptions(format: format, dpi: 150),
          root.path,
        );
        final decoded = img.decodeImage(
          await File(output.$1.path).readAsBytes(),
        )!;
        expect([decoded.width, decoded.height], [300, 150]);
        final pixel = decoded.getPixel(5, 5);
        expect(pixel.b, greaterThan(230));
        expect(pixel.r, closeTo(creation.PdfColors.blue.red * 255, 3));
        expect(output.$1.name, 'render_page_002.${format.name}');
        expect(output.$2, isNull);
      }
    },
  );

  test('PDF rotation survives native merge and page rendering', () async {
    final original = await fixture('rotation_source', ['RED ROTATED']);
    final document = await PdfDocument.openFile(original.path);
    final rotatedFile = File(p.join(root.path, 'rotated.pdf'));
    try {
      document.pages = [document.pages.single.rotatedCW90()];
      await rotatedFile.writeAsBytes(await document.encodePdf());
    } finally {
      await document.dispose();
    }
    final rotated = PdfSource(
      id: 'rotated',
      name: 'rotated.pdf',
      path: rotatedFile.path,
      bytes: await rotatedFile.length(),
      thumbnailPath: p.join(root.path, 'rotated.png'),
      pageCount: 1,
    );
    final output = await service.merge(
      [rotated, original],
      'rotation.pdf',
      root.path,
    );
    final merged = await PdfDocument.openFile(output.path);
    try {
      expect(merged.pages.first.rotation, PdfPageRotation.clockwise90);
      expect(await textOf(output.path), ['RED ROTATED', 'RED ROTATED']);
    } finally {
      await merged.dispose();
    }
    final rendered = await service.renderPage(
      rotated,
      1,
      const ConversionOptions(format: OutputFormat.png, dpi: 150),
      root.path,
    );
    final image = img.decodePng(await File(rendered.$1.path).readAsBytes())!;
    expect([image.width, image.height], [150, 300]);
    expect(image.getPixel(5, 5).r, greaterThan(230));
  });

  test('large page dimensions are capped before rendering', () {
    final size = pdfRenderSize(2000, 3000, 300);
    expect(size.width * size.height, lessThanOrEqualTo(AppLimits.maxPixels));
    expect(size.effectiveDpi, lessThan(300));
  });

  test(
    'damaged PDF has an actionable error and does not poison later jobs',
    () async {
      final file = File(p.join(root.path, 'broken.pdf'));
      await file.writeAsString('%PDF-1.7\nnot a valid document');
      await expectLater(
        service.inspect(file.path, p.join(root.path, 'broken.png')),
        throwsA(isA<FileKitException>()),
      );
      final valid = await fixture('after_error', ['RED OK']);
      expect(
        (await service.inspect(valid.path, valid.thumbnailPath)).pageCount,
        1,
      );
    },
  );

  test('password-protected PDFs are rejected clearly', () async {
    await expectLater(
      service.inspect(
        'test/fixtures/encrypted.pdf',
        p.join(root.path, 'protected.png'),
      ),
      throwsA(
        isA<FileKitException>().having(
          (error) => error.message,
          'message',
          contains('password-protected'),
        ),
      ),
    );
  });

  test('100-page split range uses a bounded temporary filename', () async {
    final source = await fixture(
      'long_range',
      List.generate(100, (index) => 'RED PAGE ${index + 1}'),
    );
    final output = await service.split(
      source,
      List.generate(100, (index) => index + 1),
      'all-pages.pdf',
      root.path,
    );
    expect(p.basename(output.path).length, lessThan(50));
    final text = await textOf(output.path);
    expect(text.length, 100);
    expect(text.first, 'RED PAGE 1');
    expect(text.last, 'RED PAGE 100');
  });

  test('split and page export tasks have stable distinct IDs', () async {
    final source = await fixture('tasks', ['RED ONE', 'BLUE TWO', 'RED THREE']);
    final tasks = createTasks(
      ToolKind.splitPdf,
      const ConversionOptions(
        format: OutputFormat.pdf,
        splitEachPage: false,
        pageRanges: '1-2, 3',
      ),
      [source],
    );
    expect(tasks.map((t) => t.id), ['tasks:1-2', 'tasks:3']);
    final pages = createTasks(
      ToolKind.convert,
      const ConversionOptions(
        format: OutputFormat.png,
        usePageRanges: true,
        pageRanges: '3, 1',
      ),
      [source],
    );
    expect(pages.map((t) => t.id), ['tasks:3', 'tasks:1']);
  });

  test('real PDF page failures retry only the failed page without duplicate exports', () async {
    final source = await fixture('retry', ['RED ONE', 'BLUE TWO', 'RED THREE']);
    final appRoot = await Directory(p.join(root.path, 'retry-app')).create();
    final services = await testServices(appRoot, pdf: service);
    final gateway = services.directory as LocalTestGateway;
    gateway.failCall = 2;
    final container = ProviderContainer(
      overrides: [
        servicesProvider.overrideWithValue(services),
        appControllerProvider.overrideWith(() => PdfControllerFixture(source)),
      ],
    );
    try {
      final controller = container.read(appControllerProvider.notifier);
      await controller.run();
      var result = container.read(appControllerProvider).result!;
      expect(result.status, JobStatus.partiallySucceeded);
      expect(result.outputs.map((f) => f.itemId), ['retry:1', 'retry:3']);
      expect(result.failures.single.sourceId, 'retry:2');
      gateway.failCall = null;
      await controller.run(failedOnly: true);
      result = container.read(appControllerProvider).result!;
      expect(result.outputs.single.itemId, 'retry:2');
      expect(gateway.calls, 4);
      expect((await gateway.folder.list().toList()).length, 3);
    } finally {
      container.dispose();
    }
  });
}
