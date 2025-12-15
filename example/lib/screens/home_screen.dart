import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nsfw_util/nsfw_util.dart';
import 'package:video_player/video_player.dart';

class HomeWidget extends StatefulWidget {
  const HomeWidget({super.key});

  @override
  State<HomeWidget> createState() => _HomeWidgetState();
}

class _HomeWidgetState extends State<HomeWidget> {
  NSFWUtil? helper;
  final imagePicker = ImagePicker();
  String? mediaPath;
  bool isImage = true;
  InferType inferType = .porn;

  InferenceScore? score;
  List<InferenceScore?>? videoScores;

  @override
  void initState() {
    helper = NSFWUtil();
    helper?.initialize();
    super.initState();
  }

  @override
  void dispose() {
    helper?.dispose();
    super.dispose();
  }

  // Clean old results when press some take picture button
  void cleanResult() {
    mediaPath = null;
    score = null;
    setState(() {});
  }

  // Process picked image
  Future<void> processImage() async {
    if (mediaPath != null) {
      if (isImage) {
        score = await helper?.inferenceImage(File(mediaPath!));
      } else {
        videoScores = await helper?.inferenceVideo(File(mediaPath!));
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            RadioGroup<InferType>(
              groupValue: inferType,
              onChanged: (value) {
                setState(() {
                  inferType = value ?? .porn;
                });
              },
              child: Row(
                children: [
                  Expanded(
                    child: RadioListTile(
                      value: InferType.porn,
                      title: Text('PORN'),
                      toggleable: true,
                    ),
                  ),

                  Expanded(
                    child: RadioListTile(
                      value: InferType.nsfw,
                      title: Text('NSFW'),
                      toggleable: true,
                    ),
                  ),
                ],
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                //* Pick Image
                TextButton.icon(
                  onPressed: () async {
                    cleanResult();
                    final result = await imagePicker.pickImage(
                      source: ImageSource.gallery,
                    );

                    mediaPath = result?.path;
                    isImage = true;
                    setState(() {});
                    processImage();
                  },
                  icon: const Icon(Icons.photo, size: 48),
                  label: const Text("Pick Image"),
                ),

                //* Pick Video
                TextButton.icon(
                  onPressed: () async {
                    cleanResult();
                    final result = await imagePicker.pickVideo(
                      source: ImageSource.gallery,
                    );

                    mediaPath = result?.path;
                    isImage = false;
                    setState(() {});
                    processImage();
                  },
                  icon: const Icon(Icons.photo, size: 48),
                  label: const Text("Pick Video"),
                ),
              ],
            ),

            if (isImage) ...[
              _ContentView(score),
            ] else if (videoScores case final scores?) ...[
              if (mediaPath != null) _VideoPreview(mediaPath: mediaPath!),
              SizedBox(
                height: MediaQuery.of(context).size.height,
                child: PageView.builder(
                  itemCount: scores.length,
                  itemBuilder: (context, index) {
                    final score = scores[index];

                    return _ContentView(score);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContentView extends StatelessWidget {
  const _ContentView(this.score);

  final InferenceScore? score;

  @override
  Widget build(BuildContext context) {
    final mediaPath = score?.frame.path;

    return Column(
      children: [
        const Divider(color: Colors.black),
        if (mediaPath != null)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.heightOf(context) * 0.5,
            ),
            child: Image.file(File(mediaPath)),
          ),

        if (mediaPath == null)
          const Text(
            "Take a photo or choose one from the gallery to "
            "inference.",
          ),

        //* Score
        if (score != null) ...[
          Container(
            padding: const EdgeInsets.all(8),
            color: score?.isNsfw == true ? Colors.red : Colors.white,
            child: Text("NSFW: ${score?.nsfwScore.toStringAsFixed(2)}"),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: score?.isNsfw == false ? Colors.green : Colors.white,
            child: Text("Safe: ${score?.safeScore.toStringAsFixed(2)}"),
          ),
          const SizedBox(height: 8),
          for (final label
              in (score?.labelScores.entries ?? <MapEntry<String, double>>[]))
            Text("${label.key}: ${label.value.toStringAsFixed(2)}"),
        ],
      ],
    );
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.mediaPath});

  final String mediaPath;

  @override
  State<_VideoPreview> createState() => __VideoPreviewState();
}

class __VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? controller;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.file(File(widget.mediaPath));
    controller?.initialize().then((_) {
      setState(() {});
      controller?.play();
      controller?.setLooping(true);
      controller?.setVolume(0);
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return controller == null
        ? const SizedBox.shrink()
        : ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: AspectRatio(
              aspectRatio: controller!.value.aspectRatio,
              child: VideoPlayer(controller!),
            ),
          );
  }
}

extension on InferenceScore {
  bool get isNsfw => nsfwScore > 0.7;
}

enum InferType { nsfw, porn }
