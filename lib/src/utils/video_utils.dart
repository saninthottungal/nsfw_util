import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_snapshot_generator/video_snapshot_generator.dart';

class VideoUtils {
  const VideoUtils._();

  static Future<List<File>> getVideoFrames(
    String videoPath, {
    required numberOfFrames,
  }) async {
    MediaInfo? info;

    try {
      info = await VideoCompress.getMediaInfo(videoPath);
    } on TypeError catch (e) {
      debugPrint("NSFWUtil: error in getting media info: $e ");
    }

    final dur = info?.duration?.toDouble() ?? 1000;
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
