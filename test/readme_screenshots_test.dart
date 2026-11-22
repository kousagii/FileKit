import 'dart:io';

import 'package:filekit/app/app.dart';
import 'package:filekit/core/models.dart';
import 'package:filekit/core/services.dart';
import 'package:filekit/features/conversion/conversion_controller.dart';
import 'package:filekit/features/conversion/pdf_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'test_support.dart';

// Pre-render real fixture PDFs outside widget fake time. Screenshots exercise
// production widgets; only app state and platform boundaries use sample data.
class _CachedPreviews extends PdfService {
  @override
  Future<String> thumbnail(
    PdfSource source,
    int page,
    String directory,
  ) async => p.join(directory, '${source.id}_page_$page.png');
}

class _PreviewController extends AppController {
  _PreviewController(this.tool, this.options, this.sources, this.jobs);
  final ToolKind tool;
  final ConversionOptions options;
  final List<FileSource> sources;
  final List<HistoryJob> jobs;

  @override
  FileKitState build() => super.build().copyWith(
    tool: tool,
    options: options,
    sources: sources,
    history: jobs,
  );
}

void main() {
  late Directory root;
  late AppServices services;
  late SourceFile image;
  late PdfSource lecture, notes;
  final previews = <String>[];
  late List<HistoryJob> jobs;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('filekit_readme_');
    services = await testServices(
      root,
      initialSettings: const AppSettings(
        theme: 'light',
        destination: OutputDestination(
          uri: 'content://sample/assignments',
          label: 'Assignments',
        ),
      ),
      pdf: _CachedPreviews(),
    );
    final picture = img.Image(width: 600, height: 400);
    img.fill(picture, color: img.ColorRgb8(238, 239, 250));
    img.fillRect(
      picture,
      x1: 50,
      y1: 50,
      x2: 550,
      y2: 350,
      color: img.ColorRgb8(255, 255, 255),
    );
    img.drawString(
      picture,
      'BIOLOGY 101',
      font: img.arial24,
      x: 85,
      y: 85,
      color: img.ColorRgb8(70, 76, 120),
    );
    for (var line = 0; line < 5; line++) {
      img.fillRect(
        picture,
        x1: 85,
        y1: 150 + line * 30,
        x2: line.isEven ? 490 : 420,
        y2: 156 + line * 30,
        color: img.ColorRgb8(190, 196, 216),
      );
    }
    final imagePath = p.join(root.path, 'study-notes.png');
    await File(imagePath).writeAsBytes(img.encodePng(picture));
    previews.add(imagePath);
    image = SourceFile(
      id: 'image',
      name: 'study-notes.png',
      path: imagePath,
      bytes: await File(imagePath).length(),
      width: 600,
      height: 400,
      format: 'png',
      hasAlpha: false,
      thumbnailPath: imagePath,
    );

    final engine = PdfService(
      initialize: () => pdfrxInitialize(tmpPath: root.path),
    );
    Future<PdfSource> document(String id, String title, int pages) async {
      final doc = pw.Document();
      for (var page = 1; page <= pages; page++) {
        doc.addPage(
          pw.Page(
            build: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 26,
                    color: pdf.PdfColors.indigo,
                  ),
                ),
                pw.SizedBox(height: 18),
                pw.Text(
                  'Week 3 - Page $page',
                  style: const pw.TextStyle(fontSize: 16),
                ),
                pw.SizedBox(height: 30),
                for (var line = 0; line < 12; line++)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 16),
                    child: pw.Container(
                      height: 3,
                      width: line.isEven ? 420 : 340,
                      color: pdf.PdfColors.grey300,
                    ),
                  ),
              ],
            ),
          ),
        );
      }
      final path = p.join(root.path, '$id.pdf');
      await File(path).writeAsBytes(await doc.save());
      final source = PdfSource(
        id: id,
        name: '$id.pdf',
        path: path,
        bytes: await File(path).length(),
        thumbnailPath: p.join(root.path, '$id.thumb.png'),
        pageCount: pages,
      );
      await engine.inspect(path, source.thumbnailPath);
      previews.add(source.thumbnailPath);
      for (var page = 1; page <= pages; page++) {
        previews.add(await engine.thumbnail(source, page, root.path));
      }
      return source;
    }

    lecture = await document('lecture-notes', 'Biology 101', 3);
    notes = await document('lab-report', 'Lab report', 2);
    jobs = [
      for (final entry in [
        (
          'lecture-notes.pdf',
          ToolKind.splitPdf,
          OutputFormat.pdf,
          'lecture-notes_pages_001-002.pdf',
        ),
        (
          'study-notes.png',
          ToolKind.convert,
          OutputFormat.webp,
          'study-notes.webp',
        ),
        ('2 files', ToolKind.mergePdf, OutputFormat.pdf, 'assignment.pdf'),
      ])
        HistoryJob(
          id: entry.$4,
          title: entry.$1,
          tool: entry.$2,
          format: entry.$3,
          createdAt: DateTime(2026, 11, 16, 10, 30),
          destination: services.initialSettings.destination!,
          sourceCount: 1,
          inputBytes: 245760,
          status: JobStatus.succeeded,
          outputs: [
            ConvertedFile(
              name: entry.$4,
              uri: 'content://sample/${entry.$4}',
              mime: entry.$3.mime,
              bytes: 102400,
            ),
          ],
        ),
    ];
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  tearDownAll(() async => root.delete(recursive: true));

  final cases = [
    (
      'image-conversion',
      ToolKind.convert,
      const ConversionOptions(
        input: InputFormat.png,
        format: OutputFormat.webp,
        webpLossless: false,
        quality: 80,
      ),
    ),
    ('compress', ToolKind.compress, const ConversionOptions(quality: 70)),
    (
      'convert-resize',
      ToolKind.convert,
      const ConversionOptions(
        input: InputFormat.png,
        format: OutputFormat.webp,
        maxWidth: 400,
        maxHeight: 300,
      ),
    ),
    (
      'resize',
      ToolKind.resize,
      const ConversionOptions(maxWidth: 400, maxHeight: 300),
    ),
    (
      'images-pdf',
      ToolKind.convert,
      const ConversionOptions(
        format: OutputFormat.pdf,
        pdfName: 'assignment.pdf',
      ),
    ),
    (
      'pdf-pages',
      ToolKind.convert,
      const ConversionOptions(
        input: InputFormat.pdf,
        format: OutputFormat.png,
        usePageRanges: true,
        pageRanges: '1-2',
      ),
    ),
    (
      'merge-pdf',
      ToolKind.mergePdf,
      const ConversionOptions(
        input: InputFormat.pdf,
        format: OutputFormat.pdf,
        pdfName: 'assignment.pdf',
      ),
    ),
    (
      'split-pdf',
      ToolKind.splitPdf,
      const ConversionOptions(
        input: InputFormat.pdf,
        format: OutputFormat.pdf,
        splitEachPage: false,
        pageRanges: '1-2, 3',
      ),
    ),
    ('history', ToolKind.convert, const ConversionOptions()),
  ];
  for (final scenario in cases) {
    testWidgets('README ${scenario.$1} preview', (tester) async {
      tester.view.physicalSize = const Size(420, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sources = switch (scenario.$1) {
        'merge-pdf' => <FileSource>[lecture, notes],
        'split-pdf' || 'pdf-pages' => <FileSource>[lecture],
        'history' => <FileSource>[],
        _ => <FileSource>[image],
      };
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox(key: Key('precache-root'))),
      );
      await tester.runAsync(() async {
        final context = tester.element(find.byKey(const Key('precache-root')));
        for (final path in previews) {
          await precacheImage(FileImage(File(path)), context);
        }
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            servicesProvider.overrideWithValue(services),
            appControllerProvider.overrideWith(
              () => _PreviewController(scenario.$2, scenario.$3, sources, jobs),
            ),
          ],
          child: const FileKitApp(),
        ),
      );
      await tester.pumpAndSettle();
      if (scenario.$1 == 'convert-resize') {
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        await container
            .read(appControllerProvider.notifier)
            .updateSettings(theme: 'dark');
        await tester.pumpAndSettle();
      }
      if (scenario.$1 == 'image-conversion' ||
          scenario.$1 == 'convert-resize') {
        await tester.tap(find.text('Options'));
        await tester.pumpAndSettle();
      } else if (scenario.$1 == 'history') {
        await tester.tap(find.text('History'));
        await tester.pumpAndSettle();
      }
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile(
          '../docs/screenshots/${scenario.$1}-${scenario.$1 == 'convert-resize' ? 'dark' : 'light'}.png',
        ),
      );
    });
  }
}
