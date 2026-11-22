import 'package:filekit/core/models.dart';
import 'package:filekit/core/storage.dart';
import 'package:filekit/features/conversion/page_ranges.dart';
import 'package:filekit/features/conversion/operations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ranges keep group order and expand empty input to all pages', () {
    expect(parsePageRanges('8-10, 1-3, 5', 10), [
      [8, 9, 10],
      [1, 2, 3],
      [5],
    ]);
    expect(parsePageRanges('', 3), [
      [1, 2, 3],
    ]);
  });
  for (final range in [
    '0',
    '-1',
    '3-1',
    '11',
    '1-11',
    '1,,2',
    'abc',
    '1-3,3-4',
    '1,1',
    '1-',
  ]) {
    test(
      'rejects invalid range $range',
      () => expect(
        () => parsePageRanges(range, 10),
        throwsA(isA<FileKitException>()),
      ),
    );
  }
  test('output matrix includes WebP and restricts PDF raster outputs', () {
    expect(
      Capabilities.outputs(ToolKind.convert, InputFormat.png, []),
      contains(OutputFormat.webp),
    );
    expect(Capabilities.outputs(ToolKind.convert, InputFormat.pdf, []), [
      OutputFormat.png,
      OutputFormat.jpg,
    ]);
  });
  test(
    'mixed input and incompatible manual selections are retained but blocked',
    () {
      const image = SourceFile(
        id: 'img',
        name: 'image.png',
        path: '',
        bytes: 1,
        width: 1,
        height: 1,
        format: 'png',
        hasAlpha: false,
        thumbnailPath: '',
      );
      const pdf = PdfSource(
        id: 'doc',
        name: 'doc.pdf',
        path: '',
        bytes: 1,
        thumbnailPath: '',
        pageCount: 2,
      );
      expect(
        Capabilities.validate(ToolKind.convert, const ConversionOptions(), [
          image,
          pdf,
        ]),
        contains('one job'),
      );
      expect(
        Capabilities.sourceIssue(image, ToolKind.convert, InputFormat.jpg),
        contains('JPG'),
      );
    },
  );
}
