import 'dart:io';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart';
import 'package:nsfw_util/src/models/inference_model.dart';
import 'package:nsfw_util/src/models/inference_score.dart';
import 'package:nsfw_util/src/utils/asset_utils.dart';
import 'package:nsfw_util/src/utils/video_utils.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// A utility class for performing NSFW (Not Safe For Work) content detection
/// using a TensorFlow Lite model.
///
/// It handles model loading, image/video frame pre-processing, and running
/// inference to classify content into predefined categories (e.g., safe, nsfw,
/// hentai, porn, sexy, neutral, drawings).
class NSFWUtil {
  late final Interpreter _interpreter;
  late final Tensor _inputTensor;
  late final Tensor _outputTensor;
  late final List<String> _labels;

  Future<void> _loadModel() async {
    log('NSFWUtil: Starting _loadModel...');
    final options = InterpreterOptions();

    if (Platform.isAndroid) {
      options.addDelegate(XNNPackDelegate());
      log('NSFWUtil: Added XNNPackDelegate for Android.');
    }

    if (Platform.isIOS) {
      options.addDelegate(GpuDelegate());
      log('NSFWUtil: Added GpuDelegate for iOS.');
    }

    _interpreter = await Interpreter.fromAsset(Assets.model, options: options);
    log('NSFWUtil: Model loaded from asset: ${Assets.model}');

    _inputTensor = _interpreter.getInputTensors().first;
    _outputTensor = _interpreter.getOutputTensors().first;
    log(
      'NSFWUtil: Input tensor shape: ${_inputTensor.shape}, Output tensor shape: ${_outputTensor.shape}',
    );
    log('NSFWUtil: _loadModel completed.');
  }

  Future<void> _loadLables() async {
    log('NSFWUtil: Starting _loadLables...');
    final labels = await rootBundle.loadString(Assets.labels);
    _labels = labels.split('\n');
    log('NSFWUtil: Labels loaded. Count: ${_labels.length}');
    log('NSFWUtil: _loadLables completed.');
  }

  InferenceScore? _inferenceImage(({File file, List<String> labels}) args) {
    log('NSFWUtil: Starting _inferenceImage for file: ${args.file.path}');
    final imageBytes = args.file.readAsBytesSync();
    log('NSFWUtil: Read image bytes.');
    final image = decodeImage(imageBytes);
    if (image == null) {
      log('NSFWUtil: Failed to decode image.');
      return null;
    }
    log(
      'NSFWUtil: Image decoded. Original size: ${image.width}x${image.height}',
    );

    final model = InferenceModel(
      image: image,
      inputShape: _inputTensor.shape,
      outputShape: _outputTensor.shape,
    );
    log('NSFWUtil: InferenceModel created.');

    final img = model.image;

    // Resize image to model input
    final imageInput = copyResize(
      img,
      width: model.inputShape[1],
      height: model.inputShape[2],
    );
    log(
      'NSFWUtil: Image resized to input dimensions: ${imageInput.width}x${imageInput.height}',
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
    log('NSFWUtil: Image converted to normalized float matrix.');

    // Input tensor: [1, 224, 224, 3]
    final input = [normalizedInput];

    // Output tensor: [1, 5]
    final output = [List<double>.filled(model.outputShape[1], 0)];

    log('NSFWUtil: Running interpreter...');
    _interpreter.run(input, output);
    log('NSFWUtil: Interpreter run completed.');

    // Get the array of 5 probabilities
    final result5Class = List<double>.from(output.first);
    log('NSFWUtil: Raw output probabilities: $result5Class');

    double nsfwScore = 0.0;
    // Indices for: hentai (1), porn (3), sexy (4)
    const List<int> nsfwIndices = [1, 3, 4];

    // 1. Sum the probabilities of the defined NSFW classes
    for (final index in nsfwIndices) {
      if (index < result5Class.length) {
        nsfwScore += result5Class[index];
      }
    }
    log(
      'NSFWUtil: NSFW score (sum of indices $nsfwIndices) calculated: $nsfwScore',
    );

    final Map<String, double> labelScores = {};
    for (int i = 0; i < result5Class.length; i++) {
      labelScores[args.labels[i]] = result5Class[i];
    }
    log('NSFWUtil: Label scores mapped: $labelScores');

    // 2. The SAFE score is the sum of the remaining classes (drawings and neutral)
    // Calculated as 1.0 minus the summed NSFW score.
    final double safeScore = 1.0 - nsfwScore;
    log('NSFWUtil: Safe score calculated: $safeScore');

    log('NSFWUtil: _inferenceImage finished.');
    return InferenceScore(
      nsfwScore: nsfwScore,
      safeScore: safeScore,
      labelScores: labelScores,
      frame: args.file,
    );
  }

  /// Initializes the model and loads the classification labels.
  Future<void> initialize() async {
    log('NSFWUtil: Starting initialize...');
    await _loadModel();
    await _loadLables();
    log('NSFWUtil: initialize completed.');
  }

  /// Runs content inference on a single image file.
  ///
  /// The inference is run in a separate isolate using `compute` to avoid
  /// blocking the UI thread.
  Future<InferenceScore?> inferenceImage(File imageFile) async {
    log('NSFWUtil: Starting inferenceImage for file: ${imageFile.path}');
    final args = (file: imageFile, labels: _labels);

    log('NSFWUtil: Starting compute for _inferenceImage...');
    final score = await compute(_inferenceImage, args);
    log('NSFWUtil: compute finished. Score: ${score?.nsfwScore}');

    return score;
  }

  /// Runs content inference on a video by sampling a specified number of frames.
  ///
  /// Returns a list of scores, one for each frame sampled.
  Future<List<InferenceScore?>> inferenceVideo(
    File file, {
    int numberOfFrames = 5,
  }) async {
    log(
      'NSFWUtil: Starting inferenceVideo for path: ${file.path} with $numberOfFrames frames.',
    );
    final videoFrames = await VideoUtils.getVideoFrames(
      file.path,
      numberOfFrames: numberOfFrames,
    );
    log('NSFWUtil: Extracted ${videoFrames.length} frames.');

    final List<InferenceScore?> scores = [];

    for (final frame in videoFrames) {
      log('NSFWUtil: Inferencing frame: ${frame.path}');
      final score = await inferenceImage(frame);
      scores.add(score);
      log('NSFWUtil: Frame inference score added. NSFW: ${score?.nsfwScore}');
    }

    log('NSFWUtil: inferenceVideo completed.');
    return scores;
  }

  /// Closes the TFLite interpreter and releases resources.
  void dispose() {
    log('NSFWUtil: Disposing interpreter...');
    _interpreter.close();
    log('NSFWUtil: Interpreter disposed.');
  }
}
