import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decodes raw image bytes into a [ui.Image].
///
/// Uses a codec to read the first frame and returns it as a GPU-usable image.
/// Throws an Exception if decoding fails (e.g., unsupported/corrupt data).
Future<ui.Image> decodeUiImage(Uint8List data) async {
  try {
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (e) {
    throw Exception('Failed to decode image: $e');
  }
}
