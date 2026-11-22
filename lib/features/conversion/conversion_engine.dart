import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/models.dart';
import '../../core/storage.dart';

class ImageInspection {
  const ImageInspection(this.width, this.height, this.format, this.hasAlpha);
  final int width, height;
  final String format;
  final bool hasAlpha;
}

/// Reads a format header before allocating a decoded pixel buffer.
img.Decoder checkedDecoder(Uint8List bytes) {
  if (bytes.length > AppLimits.maxBytes) {
    throw const FileKitException('This file is larger than 20 MB.');
  }
  img.Decoder.defaultMaxPixels = AppLimits.maxPixels;
  final decoder = img.findDecoderForData(bytes);
  const supported = {
    img.ImageFormat.jpg,
    img.ImageFormat.png,
    img.ImageFormat.webp,
    img.ImageFormat.bmp,
  };
  if (decoder == null || !supported.contains(decoder.format)) {
    throw const FileKitException(
      'Unsupported file. Choose a JPG, PNG, WebP, or BMP image.',
    );
  }
  img.DecodeInfo? info;
  try {
    info = decoder.startDecode(bytes);
  } on img.ImageException catch (error) {
    if (error.toString().contains('maximum')) {
      throw const FileKitException(
        'This image exceeds the 12-megapixel limit.',
      );
    }
    throw const FileKitException('This image is damaged or cannot be read.');
  }
  if (info == null || info.width <= 0 || info.height <= 0) {
    throw const FileKitException('This image is damaged or cannot be read.');
  }
  if (info.width * info.height > AppLimits.maxPixels ||
      info.width > AppLimits.maxDimension ||
      info.height > AppLimits.maxDimension) {
    throw const FileKitException('This image exceeds the 12-megapixel limit.');
  }
  if (info.numFrames > 1) {
    throw const FileKitException('Animated images are not supported.');
  }
  return decoder;
}

img.Image decodeChecked(Uint8List bytes) {
  final decoder = checkedDecoder(bytes);
  final decoded = decoder.decodeFrame(0);
  if (decoded == null) {
    throw const FileKitException('This image is damaged or cannot be read.');
  }
  return img.bakeOrientation(decoded);
}

img.Image resizeToFit(img.Image source, int? maxWidth, int? maxHeight) {
  if (maxWidth == null && maxHeight == null) return source;
  if ((maxWidth != null && maxWidth <= 0) ||
      (maxHeight != null && maxHeight <= 0)) {
    throw const FileKitException('Image dimensions must be greater than zero.');
  }
  final scale = math.min(
    1.0,
    math.min(
      maxWidth == null ? 1.0 : maxWidth / source.width,
      maxHeight == null ? 1.0 : maxHeight / source.height,
    ),
  );
  if (scale >= 1) return source;
  return img.copyResize(
    source,
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
    interpolation: img.Interpolation.average,
  );
}

img.Image flattenImage(img.Image source, int argb) {
  final background = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 3,
  );
  img.fill(
    background,
    color: img.ColorRgb8((argb >> 16) & 255, (argb >> 8) & 255, argb & 255),
  );
  img.compositeImage(background, source);
  return background;
}

String safeBaseName(String name) {
  final base = p
      .basenameWithoutExtension(name)
      .replaceAll(RegExp(r'[\x00-\x1F<>:"/\\|?*]'), '_')
      .replaceAll(RegExp(r'[.\s]+$'), '')
      .trim();
  final result = base.isEmpty ? 'converted' : base;
  return result.length > 100 ? result.substring(0, 100) : result;
}

class TempOutput {
  const TempOutput(this.path, this.name, this.mime);
  final String path, name, mime;
}

abstract class Converter {
  bool supports(OutputFormat format);
  Future<TempOutput> convert(
    List<SourceFile> sources,
    ConversionOptions options,
    String workingDirectory,
  );
}

class ImageConverter implements Converter {
  @override
  bool supports(OutputFormat format) => format != OutputFormat.pdf;
  @override
  Future<TempOutput> convert(
    List<SourceFile> sources,
    ConversionOptions options,
    String workingDirectory,
  ) {
    if (sources.length != 1 || !supports(options.format)) {
      throw const FileKitException('Select a supported image output format.');
    }
    return Isolate.run(() async {
      final source = sources.single;
      final bytes = await File(source.path).readAsBytes();
      var image = resizeToFit(
        decodeChecked(bytes),
        options.maxWidth,
        options.maxHeight,
      );
      final Uint8List output;
      if (options.format == OutputFormat.jpg) {
        image = flattenImage(image, options.fillColor);
        output = img.encodeJpg(image, quality: options.quality.clamp(50, 100));
      } else if (options.format == OutputFormat.webp) {
        output = img.encodeWebP(
          image,
          lossless: options.webpLossless,
          quality: options.quality.clamp(50, 100),
          method: 1,
          singleFrame: true,
        );
      } else {
        output = img.encodePng(image, level: 6);
      }
      final name =
          '${safeBaseName(source.name)}_converted.${options.format.name}';
      final path = p.join(
        workingDirectory,
        '${source.id}.${options.format.name}',
      );
      await File(path).writeAsBytes(output, flush: true);
      return TempOutput(path, name, options.format.mime);
    });
  }
}

class ImagesToPdfConverter implements Converter {
  @override
  bool supports(OutputFormat format) => format == OutputFormat.pdf;
  @override
  Future<TempOutput> convert(
    List<SourceFile> sources,
    ConversionOptions options,
    String workingDirectory,
  ) {
    return Isolate.run(() async {
      if (sources.isEmpty) {
        throw const FileKitException('Add at least one image.');
      }
      final document = pw.Document(
        compress: true,
        title: safeBaseName(options.pdfName),
        creator: 'FileKit',
      );
      for (final source in sources) {
        final bytes = await File(source.path).readAsBytes();
        // One decoded image at a time; PDF retains encoded, not raw, images.
        var image = resizeToFit(
          decodeChecked(bytes),
          options.maxWidth,
          options.maxHeight,
        );
        image = flattenImage(image, options.fillColor);
        final embedded = pw.MemoryImage(
          img.encodeJpg(image, quality: options.quality.clamp(50, 100)),
        );
        final width = image.width.toDouble() * 72 / 96;
        final height = image.height.toDouble() * 72 / 96;
        final format = options.pdfA4
            ? PdfPageFormat.a4
            : PdfPageFormat(width, height);
        document.addPage(
          pw.Page(
            pageFormat: format,
            margin: options.pdfA4
                ? const pw.EdgeInsets.all(24)
                : pw.EdgeInsets.zero,
            build: (_) =>
                pw.Center(child: pw.Image(embedded, fit: pw.BoxFit.contain)),
          ),
        );
      }
      final name = '${safeBaseName(options.pdfName)}.pdf';
      final path = p.join(workingDirectory, 'combined.pdf');
      await File(path).writeAsBytes(await document.save(), flush: true);
      return TempOutput(path, name, 'application/pdf');
    });
  }
}

class ConverterRegistry {
  final List<Converter> _converters = [
    ImageConverter(),
    ImagesToPdfConverter(),
  ];
  Converter forFormat(OutputFormat format) =>
      _converters.firstWhere((converter) => converter.supports(format));
}

Future<ImageInspection> inspectSource(String path, String thumbnailPath) =>
    Isolate.run(() async {
      final bytes = await File(path).readAsBytes();
      final decoder = checkedDecoder(bytes);
      final image = decodeChecked(bytes);
      final thumbnail = resizeToFit(image, 144, 144);
      await File(thumbnailPath).writeAsBytes(img.encodePng(thumbnail));
      return ImageInspection(
        image.width,
        image.height,
        decoder.format.name,
        image.hasAlpha,
      );
    });
