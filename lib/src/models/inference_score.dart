class InferenceScore {
  final double nsfwScore;
  final double safeScore;
  final Map<String, double> labelScores;

  InferenceScore({
    required this.nsfwScore,
    required this.safeScore,
    required this.labelScores,
  });
}
