class Answer {
  final String questionId;
  final dynamic answerValue; // Bisa String, List<String>, int, dll.

  Answer({
    required this.questionId,
    required this.answerValue,
  });

  factory Answer.fromMap(Map<String, dynamic> map, String qId) {
    return Answer(
      questionId: qId, // questionId didapat dari key map di SurveyResponse
      answerValue: map['answerValue'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      // 'questionId': questionId, // Tidak perlu disimpan lagi karena sudah jadi key
      'answerValue': answerValue,
    };
  }
}