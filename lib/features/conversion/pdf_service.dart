import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../core/models.dart';
import '../../core/storage.dart';
import 'conversion_engine.dart';

class PdfInspection {
  const PdfInspection(this.pageCount);
  final int pageCount;
}

class RenderSize {
  const RenderSize(this.width, this.height, this.effectiveDpi);
  final int width, height;
  final double effectiveDpi;
}

RenderSize pdfRenderSize(double width, double height, int dpi) {
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
    throw const FileKitException('This PDF contains an invalid page size.');
  }
  var scale = dpi / 72;
  scale = math.min(scale, math.sqrt(AppLimits.maxPixels / (width * height)));
  scale = math.min(scale, AppLimits.maxDimension / math.max(width, height));
  return RenderSize(
    math.max(1, (width * scale).floor()),
    math.max(1, (height * scale).floor()),
    scale * 72,
  );
}

/// Owns native document lifetimes and serializes complete PDF operations.
/// PDFium itself runs native work on pdfrx's documented background worker.
class PdfService {
  PdfService({Future<void> Function()? initialize})
    : _initialize = initialize ?? pdfrxFlutterInitialize;
  final Future<void> Function() _initialize;
  Future<void>? _initialization;
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      await (_initialization ??= _initialize());
      return await Pdfrx.runAsBackgroundWork(action);
    } on PdfPasswordException {
      throw const FileKitException(
        'This PDF is password-protected. Choose an unprotected copy.',
      );
    } on PdfException {
      throw const FileKitException(
        'This PDF could not be read. It may be damaged or unsupported.',
      );
    } finally {
      done.complete();
    }
  }

  Future<PdfDocument> _open(String path) async {
    final document = await PdfDocument.openFile(
      path,
      passwordProvider: () async => null,
    );
    try {
      if (document.isEncrypted) {
        throw const FileKitException(
          'This PDF is password-protected. Choose an unprotected copy.',
        );
      }
      if (document.pages.isEmpty) {
        throw const FileKitException('This PDF has no pages.');
      }
      if (document.pages.length > AppLimits.maxPdfPages) {
        throw const FileKitException(
          'Choose a PDF with no more than 100 pages.',
        );
      }
      return document;
    } catch (_) {
      await document.dispose();
      rethrow;
    }
  }

  Future<PdfInspection> inspect(String path, String thumbnailPath) =>
      _serial(() async {
        if (await File(path).length() > AppLimits.maxPdfBytes) {
          throw const FileKitException('This PDF is larger than 50 MB.');
        }
        final document = await _open(path);
        try {
          await _thumbnail(document.pages.first, thumbnailPath);
          return PdfInspection(document.pages.length);
        } finally {
          await document.dispose();
        }
      });

  Future<String> thumbnail(
    PdfSource source,
    int pageNumber,
    String directory,
  ) => _serial(() async {
    final target = p.join(directory, '${source.id}_page_$pageNumber.png');
    if (await File(target).exists()) return target;
    final document = await _open(source.path);
    try {
      if (pageNumber < 1 || pageNumber > document.pages.length) {
        throw const FileKitException('Page unavailable.');
      }
      await _thumbnail(document.pages[pageNumber - 1], target);
      return target;
    } finally {
      await document.dispose();
    }
  });

  Future<void> _thumbnail(PdfPage page, String path) async {
    final scale = 160 / math.max(page.width, page.height);
    final width = math.max(1, (page.width * scale).round());
    final height = math.max(1, (page.height * scale).round());
    final rendered = await page.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
      priority: PdfPageRenderPriority.low,
    );
    if (rendered == null) return;
    try {
      await File(path).writeAsBytes(img.encodePng(rendered.createImageNF()));
    } finally {
      rendered.dispose();
    }
  }

  Future<TempOutput> merge(
    List<PdfSource> sources,
    String name,
    String directory,
  ) => _serial(() async {
    final documents = <PdfDocument>[];
    PdfDocument? result;
    try {
      for (final source in sources) {
        documents.add(await _open(source.path));
      }
      if (documents.fold(0, (sum, doc) => sum + doc.pages.length) >
          AppLimits.maxMergePages) {
        throw const FileKitException('Merge up to 200 pages per job.');
      }
      result = await PdfDocument.createNew(sourceName: 'filekit_merged');
      result.pages = documents.expand((doc) => doc.pages).toList();
      final target = p.join(directory, 'merged.pdf');
      await File(target).writeAsBytes(await result.encodePdf(), flush: true);
      return TempOutput(target, '${safeBaseName(name)}.pdf', 'application/pdf');
    } finally {
      await result?.dispose();
      for (final doc in documents) {
        await doc.dispose();
      }
    }
  });

  Future<TempOutput> split(
    PdfSource source,
    List<int> pages,
    String name,
    String directory,
  ) => _serial(() async {
    final document = await _open(source.path);
    PdfDocument? result;
    try {
      if (pages.isEmpty ||
          pages.any((page) => page < 1 || page > document.pages.length)) {
        throw const FileKitException(
          'The selected pages are not available in this PDF.',
        );
      }
      result = await PdfDocument.createNew(
        sourceName:
            'filekit_split_${pages.first}_${pages.last}_${pages.length}',
      );
      result.pages = pages.map((page) => document.pages[page - 1]).toList();
      final target = p.join(
        directory,
        'pages_${pages.first}_${pages.last}_${pages.length}.pdf',
      );
      await File(target).writeAsBytes(await result.encodePdf(), flush: true);
      return TempOutput(target, name, 'application/pdf');
    } finally {
      await result?.dispose();
      await document.dispose();
    }
  });

  Future<(TempOutput, String?)> renderPage(
    PdfSource source,
    int number,
    ConversionOptions options,
    String directory,
  ) => _serial(() async {
    final document = await _open(source.path);
    try {
      final page = document.pages[number - 1];
      final size = pdfRenderSize(page.width, page.height, options.dpi);
      final rendered = await page.render(
        width: size.width,
        height: size.height,
        fullWidth: size.width.toDouble(),
        fullHeight: size.height.toDouble(),
        backgroundColor: 0xffffffff,
      );
      if (rendered == null) {
        throw const FileKitException('This page could not be rendered.');
      }
      final name =
          '${safeBaseName(source.name)}_page_${number.toString().padLeft(3, '0')}.${options.format.name}';
      final target = p.join(directory, name);
      try {
        await compute(_encodeRendered, (
          rendered.createImageNF(),
          options.format,
          options.quality,
          target,
        ));
      } finally {
        rendered.dispose();
      }
      final notice = size.effectiveDpi < options.dpi - 1
          ? 'Page $number was exported at ${size.effectiveDpi.floor()} DPI to stay within the image-size limit.'
          : null;
      return (TempOutput(target, name, options.format.mime), notice);
    } finally {
      await document.dispose();
    }
  });
}

Future<void> _encodeRendered(
  (img.Image, OutputFormat, int, String) request,
) async {
  final (image, format, quality, path) = request;
  final bytes = format == OutputFormat.jpg
      ? img.encodeJpg(flattenImage(image, 0xffffffff), quality: quality)
      : img.encodePng(image);
  await File(path).writeAsBytes(bytes, flush: true);
}
