import '../../core/storage.dart';

/// One-based groups, preserving their entered order. Empty means all pages.
List<List<int>> parsePageRanges(String value, int pageCount) {
  if (pageCount < 1) throw const FileKitException('This PDF has no pages.');
  if (value.trim().isEmpty) return [List.generate(pageCount, (i) => i + 1)];
  final used = <int>{};
  final groups = <List<int>>[];
  for (final token in value.split(',')) {
    final match = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+)\s*)?$').firstMatch(token);
    if (match == null) {
      throw const FileKitException(
        'Use page numbers or ranges, such as 1-3, 5, 8-10.',
      );
    }
    final start = int.tryParse(match[1]!) ?? 0;
    final end = int.tryParse(match[2] ?? match[1]!) ?? 0;
    if (start < 1 || end < start || end > pageCount) {
      throw FileKitException(
        'Choose pages from 1 to $pageCount, with each range in ascending order.',
      );
    }
    final pages = <int>[];
    for (var page = start; page <= end; page++) {
      if (!used.add(page)) {
        throw const FileKitException(
          'Page ranges must not overlap or repeat pages.',
        );
      }
      pages.add(page);
    }
    groups.add(pages);
  }
  return groups;
}
