import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart';
import 'package:nsfw_util/src/models/inference_model.dart';
import 'package:nsfw_util/src/utils/asset_utils.dart';
import 'package:nsfw_util/src/utils/video_utils.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'src/models/inference_score.dart';

class NSFWUtil {
  late final Interpreter _interpreter;
  late final Tensor _inputTensor;
  late final Tensor _outputTensor;
  late final List<String> _labels;

  Future<void> _loadModel() async {
    final options = InterpreterOptions();

    if (Platform.isAndroid) {
      options.addDelegate(XNNPackDelegate());
    }

    if (Platform.isIOS) {
      options.addDelegate(GpuDelegate());
    }

    _interpreter = await Interpreter.fromAsset(Assets.model, options: options);

    _inputTensor = _interpreter.getInputTensors().first;
    _outputTensor = _interpreter.getOutputTensors().first;
  }

  Future<void> _loadLables() async {
    final labels = await rootBundle.loadString(Assets.labels);
    _labels = labels.split('\n');
  }

  InferenceScore? _inferenceImage(({File file, List<String> labels}) args) {
    final imageBytes = args.file.readAsBytesSync();
    final image = decodeImage(imageBytes);
    if (image == null) return null;

    final model = InferenceModel(
      image: image,
      inputShape: _inputTensor.shape,
      outputShape: _outputTensor.shape,
    );

    final img = model.image;

    // Resize image to model input
    final imageInput = copyResize(
      img,
      width: model.inputShape[1],
      height: model.inputShape[2],
    );

    // Convert image to normalized float matrix
    final normalizedInput = List.generate(
      imageInput.height,
      (y) => List.generate(imageInput.width, (x) {
        final pixel = imageInput.getPixel(x, y);
        // Normalize 0-255 to 0.0-1.0
        return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
      }),
    );

    // Input tensor: [1, 224, 224, 3]
    final input = [normalizedInput];

    // Output tensor: [1, 5]
    final output = [List<double>.filled(model.outputShape[1], 0)];

    _interpreter.run(input, output);

    // Get the array of 5 probabilities
    final result5Class = List<double>.from(output.first);

    double nsfwScore = 0.0;
    // Indices for: hentai (1), porn (3), sexy (4)
    const List<int> nsfwIndices = [1, 3, 4];

    // 1. Sum the probabilities of the defined NSFW classes
    for (final index in nsfwIndices) {
      if (index < result5Class.length) {
        nsfwScore += result5Class[index];
      }
    }

    final Map<String, double> labelScores = {};
    for (int i = 0; i < result5Class.length; i++) {
      labelScores[args.labels[i]] = result5Class[i];
    }

    // 2. The SAFE score is the sum of the remaining classes (drawings and neutral)
    // Calculated as 1.0 minus the summed NSFW score.
    final double safeScore = 1.0 - nsfwScore;

    return InferenceScore(
      nsfwScore: nsfwScore,
      safeScore: safeScore,
      labelScores: labelScores,
      frame: args.file,
    );
  }

  Future<void> initialize() async {
    await _loadModel();
    await _loadLables();
  }

  Future<InferenceScore?> inferenceImage(File imageFile) async {
    final args = (file: imageFile, labels: _labels);

    final score = await compute(_inferenceImage, args);

    return score;
  }

  Future<List<InferenceScore?>> inferenceVideo(
    String videoPath, {
    int numberOfFrames = 5,
  }) async {
    final videoFrames = await VideoUtils.getVideoFrames(
      videoPath,
      numberOfFrames: numberOfFrames,
    );

    final List<InferenceScore?> scores = [];

    for (final frame in videoFrames) {
      final score = await inferenceImage(frame);
      scores.add(score);
    }

    return scores;
  }

  void dispose() {
    _interpreter.close();
  }
}
