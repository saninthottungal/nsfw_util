import 'dart:io';

import 'package:video_compress/video_compress.dart';

class VideoUtils {
  const VideoUtils._();

  static Future<List<File>> getVideoFrames(
    String videoPath, {
    int numberOfFrames = 5,
  }) async {
    final List<File> frames = [];

    final info = await VideoCompress.getMediaInfo(videoPath);

    final dur = info.duration?.toDouble() ?? 1000;
    final interval = dur / numberOfFrames;

    for (int i = 0; i < numberOfFrames; i++) {
      final frame = await VideoCompress.getFileThumbnail(
        videoPath,
        quality: 50,
        position: (i * interval).toInt(),
      );
      frames.add(frame);
    }

    return frames;
  }
}
