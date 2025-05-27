enum QuestionType {
  shortAnswer,
  longAnswer,
  multipleChoice,
  checkboxes,
  likertScale,
  // Tambahkan tipe lain jika perlu (misal: dropdown, date, time)
}

String questionTypeToString(QuestionType type) {
  return type.toString().split('.').last;
}

QuestionType stringToQuestionType(String typeString) {
  return QuestionType.values.firstWhere(
      (e) => e.toString().split('.').last == typeString,
      orElse: () => QuestionType.shortAnswer);
}

class Question {
  final String questionId;
  final String text;
  final QuestionType type;
  final bool isRequired;
  final List<String>? options; // Untuk multipleChoice, checkboxes
  final int? likertScaleMin;   // Untuk likertScale
  final int? likertScaleMax;   // Untuk likertScale
  final String? likertMinLabel;
  final String? likertMaxLabel;
  final int order;

  Question({
    required this.questionId,
    required this.text,
    required this.type,
    required this.isRequired,
    this.options,
    this.likertScaleMin,
    this.likertScaleMax,
    this.likertMinLabel,
    this.likertMaxLabel,
    required this.order,
  });

  factory Question.fromMap(Map<String, dynamic> map, String id) {
    return Question(
      questionId: id,
      text: map['text'] ?? '',
      type: stringToQuestionType(map['type'] ?? 'shortAnswer'),
      isRequired: map['isRequired'] ?? false,
      options: map['options'] != null ? List<String>.from(map['options']) : null,
      likertScaleMin: map['likertScaleMin'],
      likertScaleMax: map['likertScaleMax'],
      likertMinLabel: map['likertMinLabel'],
      likertMaxLabel: map['likertMaxLabel'],
      order: map['order'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'type': questionTypeToString(type),
      'isRequired': isRequired,
      'options': options,
      'likertScaleMin': likertScaleMin,
      'likertScaleMax': likertScaleMax,
      'likertMinLabel': likertMinLabel,
      'likertMaxLabel': likertMaxLabel,
      'order': order,
    };
  }
}