import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decode raw image bytes into a [ui.Image].
/// High quality filter; keeps it simple and reusable across sources.
Future<ui.Image> decodeUiImage(Uint8List data) async {
  final codec = await ui.instantiateImageCodec(data);
  final frame = await codec.getNextFrame();
  return frame.image;
}
