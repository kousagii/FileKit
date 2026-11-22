import 'dart:convert';

// Keep `pdf` readable for version-1 history; new PDF creation uses Convert.
enum ToolKind { convert, compress, resize, pdf, mergePdf, splitPdf }

extension ToolKindLabel on ToolKind {
  String get label => switch (this) {
    ToolKind.convert => 'Convert',
    ToolKind.compress => 'Compress images',
    ToolKind.resize => 'Resize images',
    ToolKind.pdf => 'Create PDF',
    ToolKind.mergePdf => 'Merge PDF',
    ToolKind.splitPdf => 'Split PDF',
  };
  String get verb => switch (this) {
    ToolKind.convert => 'Convert',
    ToolKind.compress => 'Compress',
    ToolKind.resize => 'Resize',
    ToolKind.pdf => 'Create PDF',
    ToolKind.mergePdf => 'Merge PDF',
    ToolKind.splitPdf => 'Split PDF',
  };
}

enum InputFormat { autoDetect, png, jpg, webp, pdf }

extension InputFormatInfo on InputFormat {
  String get label => switch (this) {
    InputFormat.autoDetect => 'Auto-detect',
    InputFormat.webp => 'WebP',
    _ => name.toUpperCase(),
  };
  List<String> get extensions => switch (this) {
    InputFormat.autoDetect => ['png', 'jpg', 'jpeg', 'webp', 'bmp', 'pdf'],
    InputFormat.jpg => ['jpg', 'jpeg'],
    _ => [name],
  };
}

enum OutputFormat { jpg, png, pdf, webp }

extension OutputFormatInfo on OutputFormat {
  String get label => this == OutputFormat.webp ? 'WebP' : name.toUpperCase();
  String get mime => switch (this) {
    OutputFormat.jpg => 'image/jpeg',
    OutputFormat.png => 'image/png',
    OutputFormat.pdf => 'application/pdf',
    OutputFormat.webp => 'image/webp',
  };
}

enum JobStatus {
  processing,
  succeeded,
  partiallySucceeded,
  failed,
  cancelled,
  interrupted,
}

extension JobStatusLabel on JobStatus {
  String get label => switch (this) {
    JobStatus.processing => 'In progress',
    JobStatus.succeeded => 'Saved',
    JobStatus.partiallySucceeded => 'Partly saved',
    JobStatus.failed => 'Failed',
    JobStatus.cancelled => 'Cancelled',
    JobStatus.interrupted => 'Interrupted',
  };
}

class AppLimits {
  static const maxFiles = 10;
  static const maxBytes = 20 * 1024 * 1024;
  static const maxPixels = 12000000;
  static const maxDimension = 12000;
  static const maxPdfBytes = 50 * 1024 * 1024;
  static const maxPdfPages = 100;
  static const maxMergePages = 200;
  static const maxExportPages = 30;
}

sealed class FileSource {
  const FileSource({
    required this.id,
    required this.name,
    required this.path,
    required this.bytes,
    required this.thumbnailPath,
  });
  final String id, name, path, thumbnailPath;
  final int bytes;
  bool get isPdf => this is PdfSource;
  String get format;
}

class SourceFile extends FileSource {
  const SourceFile({
    required super.id,
    required super.name,
    required super.path,
    required super.bytes,
    required this.width,
    required this.height,
    required this.format,
    required this.hasAlpha,
    required super.thumbnailPath,
  });
  @override
  final String format;
  final int width, height;
  final bool hasAlpha;
}

class PdfSource extends FileSource {
  const PdfSource({
    required super.id,
    required super.name,
    required super.path,
    required super.bytes,
    required super.thumbnailPath,
    required this.pageCount,
  });
  final int pageCount;
  @override
  String get format => 'pdf';
}

class OutputDestination {
  const OutputDestination({
    required this.uri,
    required this.label,
    this.persistent = true,
  });
  final String uri, label;
  final bool persistent;
  Map<String, Object?> toMap() => {
    'uri': uri,
    'label': label,
    'persistent': persistent,
  };
  factory OutputDestination.fromMap(Map<String, dynamic> map) =>
      OutputDestination(
        uri: map['uri'] as String,
        label: map['label'] as String,
        persistent: map['persistent'] as bool? ?? false,
      );
}

class ConversionOptions {
  const ConversionOptions({
    this.input = InputFormat.autoDetect,
    this.format = OutputFormat.jpg,
    this.quality = 85,
    this.maxWidth,
    this.maxHeight,
    this.fillColor = 0xffffffff,
    this.pdfA4 = true,
    this.pdfName = 'converted_images.pdf',
    this.webpLossless = true,
    this.pageRanges = '',
    this.splitEachPage = true,
    this.usePageRanges = false,
    this.dpi = 150,
  });
  final OutputFormat format;
  final InputFormat input;
  final int quality, fillColor;
  final int? maxWidth, maxHeight;
  final bool pdfA4;
  final String pdfName;
  final bool webpLossless, splitEachPage, usePageRanges;
  final String pageRanges;
  final int dpi;
  ConversionOptions copyWith({
    OutputFormat? format,
    InputFormat? input,
    int? quality,
    int? maxWidth,
    int? maxHeight,
    bool clearSize = false,
    int? fillColor,
    bool? pdfA4,
    String? pdfName,
    bool? webpLossless,
    String? pageRanges,
    bool? splitEachPage,
    bool? usePageRanges,
    int? dpi,
  }) => ConversionOptions(
    format: format ?? this.format,
    input: input ?? this.input,
    quality: quality ?? this.quality,
    maxWidth: clearSize ? null : maxWidth ?? this.maxWidth,
    maxHeight: clearSize ? null : maxHeight ?? this.maxHeight,
    fillColor: fillColor ?? this.fillColor,
    pdfA4: pdfA4 ?? this.pdfA4,
    pdfName: pdfName ?? this.pdfName,
    webpLossless: webpLossless ?? this.webpLossless,
    pageRanges: pageRanges ?? this.pageRanges,
    splitEachPage: splitEachPage ?? this.splitEachPage,
    usePageRanges: usePageRanges ?? this.usePageRanges,
    dpi: dpi ?? this.dpi,
  );
  Map<String, Object?> toMap() => {
    'format': format.name,
    'input': input.name,
    'quality': quality,
    'maxWidth': maxWidth,
    'maxHeight': maxHeight,
    'fillColor': fillColor,
    'pdfA4': pdfA4,
    'pdfName': pdfName,
    'webpLossless': webpLossless,
    'pageRanges': pageRanges,
    'splitEachPage': splitEachPage,
    'usePageRanges': usePageRanges,
    'dpi': dpi,
  };
}

class ConvertedFile {
  const ConvertedFile({
    required this.name,
    required this.uri,
    required this.mime,
    required this.bytes,
    this.itemId,
  });
  final String name, uri, mime;
  final int bytes;
  final String? itemId;
  ConvertedFile forItem(String id) =>
      ConvertedFile(name: name, uri: uri, mime: mime, bytes: bytes, itemId: id);
  Map<String, Object?> toMap() => {
    'name': name,
    'uri': uri,
    'mime': mime,
    'bytes': bytes,
    'itemId': itemId,
  };
  factory ConvertedFile.fromMap(Map<String, dynamic> map) => ConvertedFile(
    name: map['name'] as String,
    uri: map['uri'] as String,
    mime: map['mime'] as String,
    bytes: (map['bytes'] as num).toInt(),
    itemId: map['itemId'] as String?,
  );
}

class ItemFailure {
  const ItemFailure(this.sourceId, this.name, this.reason);
  final String sourceId, name, reason;
  Map<String, Object?> toMap() => {
    'sourceId': sourceId,
    'name': name,
    'reason': reason,
  };
}

class HistoryJob {
  const HistoryJob({
    required this.id,
    required this.title,
    required this.tool,
    required this.format,
    required this.createdAt,
    required this.destination,
    required this.sourceCount,
    required this.inputBytes,
    required this.status,
    this.outputs = const [],
    this.failures = const [],
    this.message,
    this.requestJson = '{}',
  });
  final String id, title;
  final ToolKind tool;
  final OutputFormat format;
  final DateTime createdAt;
  final OutputDestination destination;
  final int sourceCount, inputBytes;
  final JobStatus status;
  final List<ConvertedFile> outputs;
  final List<ItemFailure> failures;
  final String? message;
  final String requestJson;
  HistoryJob copyWith({
    JobStatus? status,
    List<ConvertedFile>? outputs,
    List<ItemFailure>? failures,
    String? message,
  }) => HistoryJob(
    id: id,
    title: title,
    tool: tool,
    format: format,
    createdAt: createdAt,
    destination: destination,
    sourceCount: sourceCount,
    inputBytes: inputBytes,
    status: status ?? this.status,
    outputs: outputs ?? this.outputs,
    failures: failures ?? this.failures,
    message: message ?? this.message,
    requestJson: requestJson,
  );
  Map<String, Object?> toRow() => {
    'id': id,
    'title': title,
    'tool': tool.name,
    'format': format.name,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'destination': jsonEncode(destination.toMap()),
    'sourceCount': sourceCount,
    'inputBytes': inputBytes,
    'status': status.name,
    'failures': jsonEncode(failures.map((e) => e.toMap()).toList()),
    'message': message,
    'requestJson': requestJson,
  };
  factory HistoryJob.fromRows(
    Map<String, Object?> row,
    List<ConvertedFile> outputs,
  ) => HistoryJob(
    id: row['id'] as String,
    title: row['title'] as String,
    tool: ToolKind.values.byName(row['tool'] as String),
    format: OutputFormat.values.byName(row['format'] as String),
    createdAt: DateTime.fromMillisecondsSinceEpoch(row['createdAt'] as int),
    destination: OutputDestination.fromMap(
      jsonDecode(row['destination'] as String) as Map<String, dynamic>,
    ),
    sourceCount: row['sourceCount'] as int,
    inputBytes: row['inputBytes'] as int,
    status: JobStatus.values.byName(row['status'] as String),
    outputs: outputs,
    failures: (jsonDecode(row['failures'] as String) as List).map((e) {
      final map = e as Map<String, dynamic>;
      return ItemFailure(
        map['sourceId'] as String,
        map['name'] as String,
        map['reason'] as String,
      );
    }).toList(),
    message: row['message'] as String?,
    requestJson: row['requestJson'] as String? ?? '{}',
  );
}

class AppSettings {
  const AppSettings({
    this.theme = 'system',
    this.quality = 85,
    this.destination,
  });
  final String theme;
  final int quality;
  final OutputDestination? destination;
  AppSettings copyWith({
    String? theme,
    int? quality,
    OutputDestination? destination,
  }) => AppSettings(
    theme: theme ?? this.theme,
    quality: quality ?? this.quality,
    destination: destination ?? this.destination,
  );
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
