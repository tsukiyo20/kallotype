import 'dart:io';
import 'dart:ui' as ui;

/// Decode an image file at no more than a width.
///
/// The width is asked for at decode time rather than scaled afterwards,
/// because the bench holds a 26 megapixel photograph to show 1200 points and
/// the difference is a hundred megabytes thrown away.
Future<ui.Image> decode(File file, {int width = 1200}) async {
  final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
    await file.readAsBytes(),
  );
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec(
      targetWidth: descriptor.width > width ? width : null,
    );
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    // The frame owns its pixels. The decoder's buffer and codec are scratch:
    // release them now so a slider drag does not leave a trail of decoders
    // waiting for the next GC.
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
