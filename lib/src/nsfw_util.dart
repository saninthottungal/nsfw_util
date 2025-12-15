import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart';
import 'package:nsfw_util/nsfw_util.dart';
import 'package:nsfw_util/src/models/inference_model.dart';
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
    debugPrint('NSFWUtil: Starting _loadModel...');
    final options = InterpreterOptions();

    if (Platform.isAndroid) {
      options.addDelegate(XNNPackDelegate());
      debugPrint('NSFWUtil: Added XNNPackDelegate for Android.');
    }

    if (Platform.isIOS) {
      options.addDelegate(GpuDelegate());
      debugPrint('NSFWUtil: Added GpuDelegate for iOS.');
    }

    _interpreter = await Interpreter.fromAsset(Assets.model, options: options);
    debugPrint('NSFWUtil: Model loaded from asset: ${Assets.model}');

    _inputTensor = _interpreter.getInputTensors().first;
    _outputTensor = _interpreter.getOutputTensors().first;
    debugPrint(
      'NSFWUtil: Input tensor shape: ${_inputTensor.shape}, Output tensor shape: ${_outputTensor.shape}',
    );
    debugPrint('NSFWUtil: _loadModel completed.');
  }

  Future<void> _loadLables() async {
    debugPrint('NSFWUtil: Starting _loadLables...');
    final labels = await rootBundle.loadString(Assets.labels);
    _labels = labels.split('\n');
    debugPrint('NSFWUtil: Labels loaded. Count: ${_labels.length}');
    debugPrint('NSFWUtil: _loadLables completed.');
  }

  InferenceScore? _inferenceImage(
    ({File file, List<String> labels, InferType type}) args,
  ) {
    debugPrint(
      'NSFWUtil: Starting _inferenceImage for file: ${args.file.path}',
    );
    final imageBytes = args.file.readAsBytesSync();
    debugPrint('NSFWUtil: Read image bytes.');
    final image = decodeImage(imageBytes);
    if (image == null) {
      debugPrint('NSFWUtil: Failed to decode image.');
      return null;
    }
    debugPrint(
      'NSFWUtil: Image decoded. Original size: ${image.width}x${image.height}',
    );

    final model = InferenceModel(
      image: image,
      inputShape: _inputTensor.shape,
      outputShape: _outputTensor.shape,
    );
    debugPrint('NSFWUtil: InferenceModel created.');

    final img = model.image;

    // Resize image to model input
    final imageInput = copyResize(
      img,
      width: model.inputShape[1],
      height: model.inputShape[2],
    );
    debugPrint(
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
    debugPrint('NSFWUtil: Image converted to normalized float matrix.');

    // Input tensor: [1, 224, 224, 3]
    final input = [normalizedInput];

    // Output tensor: [1, 5]
    final output = [List<double>.filled(model.outputShape[1], 0)];

    debugPrint('NSFWUtil: Running interpreter...');
    _interpreter.run(input, output);
    debugPrint('NSFWUtil: Interpreter run completed.');

    // Get the array of 5 probabilities
    final result5Class = List<double>.from(output.first);
    debugPrint('NSFWUtil: Raw output probabilities: $result5Class');

    double nsfwScore = 0.0;
    // Indices for: hentai (1), porn (3), sexy (4)
    const List<int> nsfwIndices = [1, 3, 4];

    // 1. Sum the probabilities of the defined NSFW classes
    for (final index in nsfwIndices) {
      if (index < result5Class.length) {
        nsfwScore += result5Class[index];
      }
    }
    debugPrint(
      'NSFWUtil: NSFW score (sum of indices $nsfwIndices) calculated: $nsfwScore',
    );

    final Map<String, double> labelScores = {};
    for (int i = 0; i < result5Class.length; i++) {
      labelScores[args.labels[i]] = result5Class[i];
    }
    debugPrint('NSFWUtil: Label scores mapped: $labelScores');

    // 2. The SAFE score is the sum of the remaining classes (drawings and neutral)
    // Calculated as 1.0 minus the summed NSFW score.
    final double safeScore = 1.0 - nsfwScore;
    debugPrint('NSFWUtil: Safe score calculated: $safeScore');

    debugPrint('NSFWUtil: _inferenceImage finished.');

    if (args.type == .porn) {
      return InferenceScore(
        nsfwScore: result5Class[3],
        safeScore: 1 - result5Class[3],
        labelScores: labelScores,
        frame: args.file,
      );
    } else {
      return InferenceScore(
        nsfwScore: nsfwScore,
        safeScore: safeScore,

        labelScores: labelScores,
        frame: args.file,
      );
    }
  }

  /// Initializes the model and loads the classification labels.
  Future<void> initialize() async {
    debugPrint('NSFWUtil: Starting initialize...');
    await _loadModel();
    await _loadLables();
    debugPrint('NSFWUtil: initialize completed.');
  }

  /// Runs content inference on a single image file.
  ///
  /// The inference is run in a separate isolate using `compute` to avoid
  /// blocking the UI thread.
  Future<InferenceScore?> inferenceImage(
    File imageFile, {
    required InferType type,
  }) async {
    debugPrint('NSFWUtil: Starting inferenceImage for file: ${imageFile.path}');
    final args = (file: imageFile, labels: _labels, type: type);

    debugPrint('NSFWUtil: Starting compute for _inferenceImage...');
    final score = await compute(_inferenceImage, args);
    debugPrint('NSFWUtil: compute finished. Score: ${score?.nsfwScore}');

    return score;
  }

  /// Runs content inference on a video by sampling a specified number of frames.
  ///
  /// Returns a list of scores, one for each frame sampled.
  Future<List<InferenceScore?>> inferenceVideo(
    File file, {
    required InferType type,
    int numberOfFrames = 5,
  }) async {
    debugPrint(
      'NSFWUtil: Starting inferenceVideo for path: ${file.path} with $numberOfFrames frames.',
    );
    final videoFrames = await VideoUtils.getVideoFrames(
      file.path,
      numberOfFrames: numberOfFrames,
    );
    debugPrint('NSFWUtil: Extracted ${videoFrames.length} frames.');

    final List<InferenceScore?> scores = [];

    for (final frame in videoFrames) {
      debugPrint('NSFWUtil: Inferencing frame: ${frame.path}');
      final score = await inferenceImage(frame, type: type);
      scores.add(score);
      debugPrint(
        'NSFWUtil: Frame inference score added. NSFW: ${score?.nsfwScore}',
      );
    }

    debugPrint('NSFWUtil: inferenceVideo completed.');
    return scores;
  }

  /// Closes the TFLite interpreter and releases resources.
  void dispose() {
    debugPrint('NSFWUtil: Disposing interpreter...');
    _interpreter.close();
    debugPrint('NSFWUtil: Interpreter disposed.');
  }
}
