import 'dart:io';

import 'package:video_compress/video_compress.dart';
import 'package:video_snapshot_generator/video_snapshot_generator.dart';

class VideoUtils {
  const VideoUtils._();

  static Future<List<File>> getVideoFrames(
    String videoPath, {
    int numberOfFrames = 5,
  }) async {
    final info = await VideoCompress.getMediaInfo(videoPath);

    final dur = info.duration?.toDouble() ?? 1000;
    final interval = dur / numberOfFrames;

    final positions = List.generate(
      numberOfFrames,
      (index) => (index * interval).toInt(),
    );

    final results = await VideoSnapshotGenerator.generateMultipleThumbnails(
      videoPath: videoPath,
      timePositions: positions,
      options: ThumbnailOptions(videoPath: videoPath, quality: 50),
    );
    return results.map((e) => File(e.path)).toList();
  }
}
