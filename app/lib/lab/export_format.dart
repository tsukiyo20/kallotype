/// What a finished picture is written as.
///
/// The print pipeline can stay PNG or become JPEG; the framed export can also
/// be TIFF. The label is the format's own name, so it does not translate.
enum ExportFormat {
  jpeg('JPEG', 'jpg'),
  png('PNG', 'png'),
  tiff('TIFF', 'tiff');

  const ExportFormat(this.label, this.extension);

  final String label;
  final String extension;

  /// JPEG throws information away; the other two do not.
  bool get lossless => this != ExportFormat.jpeg;
}

/// One choice in the size row of the export sheet.
///
/// A null [value] means the print's or the frame's own size; a number is a
/// maximum on the long edge (frame) or the print's width. It never upscales.
class ExportSize {
  const ExportSize(this.label, this.value);

  final String label;
  final int? value;
}

/// What the sheet returns.
class ExportOptions {
  const ExportOptions({required this.size, required this.format});

  final int? size;
  final ExportFormat format;
}
