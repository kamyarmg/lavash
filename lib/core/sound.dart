import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// UI sound helper for very short effects (currently only tile click).
/// Requires an asset `assets/sounds/click.wav` declared in `pubspec.yaml`.
class Sound {
  Sound._();
  static final AudioPlayer _player = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop)
    ..setVolume(0.5);

  /// Plays the click sound; falls back to a system click if asset fails.
  static Future<void> playClick() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/click.wav'));
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }
}
