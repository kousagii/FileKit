import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:filekit/core/models.dart';
import 'package:filekit/core/storage.dart';
import 'package:filekit/features/conversion/conversion_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('filekit_engine_'),
  );
  tearDown(() async => root.delete(recursive: true));

  Future<SourceFile> fixture(
    img.Image image,
    String name, {
    bool jpg = false,
  }) async {
    final file = File(p.join(root.path, name));
    await file.writeAsBytes(
      jpg ? img.encodeJpg(image, quality: 100) : img.encodePng(image),
    );
    return SourceFile(
      id: name,
      name: name,
      path: file.path,
      bytes: await file.length(),
      width: image.width,
      height: image.height,
      format: jpg ? 'jpg' : 'png',
      hasAlpha: image.hasAlpha,
      thumbnailPath: file.path,
    );
  }

  test('transparent PNG becomes white in JPEG without dark fringes', () async {
    final source = await fixture(
      img.Image(width: 12, height: 12, numChannels: 4),
      'transparent.png',
    );
    final result = await ImageConverter().convert(
      [source],
      const ConversionOptions(quality: 100),
      root.path,
    );
    final decoded = img.decodeJpg(await File(result.path).readAsBytes())!;
    final pixel = decoded.getPixel(6, 6);
    expect(pixel.r, greaterThanOrEqualTo(250));
    expect(pixel.g, greaterThanOrEqualTo(250));
    expect(pixel.b, greaterThanOrEqualTo(250));
    expect(
      (await File(source.path).readAsBytes()).take(4),
      orderedEquals([137, 80, 78, 71]),
    );
  });

  test('PNG output retains alpha values', () async {
    final image = img.Image(width: 8, height: 8, numChannels: 4);
    image.setPixelRgba(3, 3, 255, 0, 0, 128);
    final source = await fixture(image, 'alpha.png');
    final result = await ImageConverter().convert(
      [source],
      const ConversionOptions(format: OutputFormat.png),
      root.path,
    );
    final decoded = img.decodePng(await File(result.path).readAsBytes())!;
    expect(decoded.getPixel(0, 0).a, 0);
    expect(decoded.getPixel(3, 3).a, 128);
  });

  test(
    'EXIF orientation is baked into actual output pixels and dimensions',
    () async {
      final image = img.Image(width: 20, height: 10, numChannels: 3);
      img.fill(image, color: img.ColorRgb8(255, 0, 0));
      image.exif.imageIfd.orientation = 6;
      final source = await fixture(image, 'rotated.jpg', jpg: true);
      final result = await ImageConverter().convert(
        [source],
        const ConversionOptions(format: OutputFormat.png),
        root.path,
      );
      final decoded = img.decodePng(await File(result.path).readAsBytes())!;
      expect(decoded.width, 10);
      expect(decoded.height, 20);
      expect(decoded.getPixel(4, 4).r, greaterThan(240));
    },
  );

  test('resizing fits bounds and never upscales', () {
    final source = img.Image(width: 400, height: 200);
    final smaller = resizeToFit(source, 100, 100);
    expect([smaller.width, smaller.height], [100, 50]);
    final original = resizeToFit(source, 800, 800);
    expect([original.width, original.height], [400, 200]);
  });

  test(
    'actual format detection rejects renamed unsupported and corrupt files',
    () {
      expect(
        () => checkedDecoder(Uint8List.fromList(utf8.encode('%PDF-1.7'))),
        throwsA(isA<FileKitException>()),
      );
      expect(
        () => decodeChecked(Uint8List.fromList([137, 80, 78, 71])),
        throwsA(anything),
      );
      final gif = img.encodeGif(img.Image(width: 4, height: 4));
      expect(() => checkedDecoder(gif), throwsA(isA<FileKitException>()));
    },
  );

  test('dimension limits are checked from image headers', () {
    final bytes = img.encodePng(img.Image(width: 4001, height: 3000));
    expect(() => checkedDecoder(bytes), throwsA(isA<FileKitException>()));
  });

  test('PDF has two pages and embeds the supplied images in order', () async {
    final red = img.Image(width: 16, height: 16, numChannels: 3);
    final blue = img.Image(width: 16, height: 16, numChannels: 3);
    img.fill(red, color: img.ColorRgb8(255, 0, 0));
    img.fill(blue, color: img.ColorRgb8(0, 0, 255));
    final first = await fixture(red, 'red.png');
    final second = await fixture(blue, 'blue.png');
    final result = await ImagesToPdfConverter().convert(
      [second, first],
      const ConversionOptions(format: OutputFormat.pdf),
      root.path,
    );
    final bytes = await File(result.path).readAsBytes();
    final text = latin1.decode(bytes);
    expect(text, startsWith('%PDF-'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 2);
    final embedded = <img.Image>[];
    for (var i = 0; i < bytes.length - 1; i++) {
      if (bytes[i] == 0xff && bytes[i + 1] == 0xd8) {
        for (var j = i + 2; j < bytes.length - 1; j++) {
          if (bytes[j] == 0xff && bytes[j + 1] == 0xd9) {
            final image = img.decodeJpg(Uint8List.sublistView(bytes, i, j + 2));
            if (image != null) embedded.add(image);
            i = j + 1;
            break;
          }
        }
      }
    }
    expect(embedded.length, 2);
    expect(embedded[0].getPixel(8, 8).b, greaterThan(230));
    expect(embedded[1].getPixel(8, 8).r, greaterThan(230));
  });

  test('output names are sanitized and retain a meaningful stem', () {
    expect(safeBaseName('../my:picture.png'), 'my_picture');
    expect(safeBaseName(''), 'converted');
  });

  for (final input in [OutputFormat.png, OutputFormat.jpg, OutputFormat.webp]) {
    for (final output in [
      OutputFormat.png,
      OutputFormat.jpg,
      OutputFormat.webp,
    ]) {
      if (input == output) continue;
      test(
        '${input.label} to ${output.label} produces the requested actual format',
        () async {
          final image = img.Image(width: 12, height: 8, numChannels: 3);
          img.fill(image, color: img.ColorRgb8(100, 150, 200));
          final bytes = switch (input) {
            OutputFormat.jpg => img.encodeJpg(image, quality: 100),
            OutputFormat.webp => img.encodeWebP(image),
            _ => img.encodePng(image),
          };
          final file = await File(p.join(root.path, 'input.${input.name}'))
              .writeAsBytes(bytes);
          final source = SourceFile(
            id: 'cross-format',
            name: 'input.${input.name}',
            path: file.path,
            bytes: bytes.length,
            width: 12,
            height: 8,
            format: input.name,
            hasAlpha: false,
            thumbnailPath: file.path,
          );
          final result = await ImageConverter().convert(
            [source],
            ConversionOptions(format: output, quality: 100),
            root.path,
          );
          final encoded = await File(result.path).readAsBytes();
          expect(checkedDecoder(encoded).format.name, output.name);
          final decoded = img.decodeImage(encoded)!;
          expect([decoded.width, decoded.height], [12, 8]);
          expect(decoded.getPixel(4, 4).r, closeTo(100, 4));
        },
      );
    }
  }

  test(
    'lossless and lossy WebP preserve alpha and use real WebP bitstreams',
    () async {
      final image = img.Image(width: 16, height: 16, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(100, 150, 200, 128));
      final source = await fixture(image, 'webp-alpha.png');
      for (final lossless in [true, false]) {
        final output = await ImageConverter().convert(
          [source],
          ConversionOptions(
            format: OutputFormat.webp,
            webpLossless: lossless,
            quality: 85,
          ),
          root.path,
        );
        final bytes = await File(output.path).readAsBytes();
        expect(latin1.decode(bytes.sublist(8, 12)), 'WEBP');
        final decoded = img.decodeWebP(bytes)!;
        expect(decoded.getPixel(8, 8).a, 128);
        expect(decoded.getPixel(8, 8).r, closeTo(100, lossless ? 0 : 5));
      }
    },
  );
}
