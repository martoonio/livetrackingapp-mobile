import 'package:livetrackingapp/domain/entities/survey/answer.dart';

class SurveyResponse {
  final String responseId;
  final String surveyId;
  final String userId;
  final DateTime submittedAt;
  final List<Answer> answers; // Diubah menjadi List<Answer>

  SurveyResponse({
    required this.responseId,
    required this.surveyId,
    required this.userId,
    required this.submittedAt,
    required this.answers,
  });

  factory SurveyResponse.fromMap(Map<String, dynamic> map, String id) {
    var answerList = <Answer>[];
    if (map['answers'] != null) {
      final answersMap = map['answers'] as Map<String, dynamic>;
      answerList = answersMap.entries.map((entry) {
        return Answer.fromMap(entry.value as Map<String, dynamic>, entry.key);
      }).toList();
    }
    return SurveyResponse(
      responseId: id,
      surveyId: map['surveyId'] ?? '',
      userId: map['userId'] ?? '',
      submittedAt: map['submittedAt'] != null
          ? DateTime.parse(map['submittedAt'])
          : DateTime.now(),
      answers: answerList,
    );
  }

  Map<String, dynamic> toMap() {
    // Konversi List<Answer> menjadi Map untuk Firebase
    Map<String, dynamic> answersMap = {};
    for (var answer in answers) {
      answersMap[answer.questionId] = answer.toMap();
    }

    return {
      'surveyId': surveyId,
      'userId': userId,
      'submittedAt': submittedAt.toIso8601String(),
      'answers': answersMap,
    };
  }
}