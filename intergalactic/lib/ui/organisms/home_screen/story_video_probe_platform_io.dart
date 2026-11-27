import 'package:media_kit/media_kit.dart';

Future<void> enableStoryVideoProbeTrack(Player player) async {
  final platform = player.platform;
  if (platform is NativePlayer) {
    await platform.setProperty('vid', 'auto');
  }
}
