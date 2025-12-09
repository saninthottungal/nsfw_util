import 'package:image/image.dart';

class InferenceModel {
  final Image image;
  final List<int> inputShape;
  final List<int> outputShape;

  InferenceModel({
    required this.image,
    required this.inputShape,
    required this.outputShape,
  });
}
