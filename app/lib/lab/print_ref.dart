import 'dart:typed_data';

/// Where a print's pixels live when they are not a file.
///
/// A desktop print is a path: the thumbnail cache can stat it, read its header
/// and hand the file to the model. A print in Photos or MediaStore is named by
/// an opaque locator, and the platform is the only thing that can read it. This
/// is the small surface the rooms need from either one.
abstract interface class PrintRef {
  /// The platform's name for the print: a path, a `PHAsset` identifier, or a
  /// MediaStore content URI.
  String get locator;

  /// A display name, used before a catalog row exists.
  String get name;

  /// A small image for the wall, at most [maxWidth] pixels wide.
  Future<Uint8List?> thumbnail({required int maxWidth});

  /// The print at a size worth opening, at most [maxWidth] pixels wide.
  ///
  /// Null means the file's own size.
  Future<Uint8List?> image({int? maxWidth});
}
