
class Survey {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String createdBy; // userId dari pembuat survey
  final bool isActive;
  final List<SurveySection> sections; // Daftar bagian dalam survey

  Survey({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.expiresAt,
    required this.createdBy,
    required this.isActive,
    required this.sections,
  });

  // Factory constructor untuk membuat survey baru dengan ID otomatis
  factory Survey.create({
    required String title,
    required String description,
    required DateTime expiresAt,
    required String createdBy,
    required List<SurveySection> sections,
    bool isActive = true,
  }) {
    // ID akan di-generate oleh Firebase push().key di repository
    return Survey(
      id: '', // Akan diisi oleh repository
      title: title,
      description: description,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
      createdBy: createdBy,
      isActive: isActive,
      sections: sections,
    );
  }

  // Konversi dari JSON (Map)
  factory Survey.fromJson(String id, Map<String, dynamic> json) {
    return Survey(
      id: id,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      createdAt: DateTime.parse(json['createdAt']),
      expiresAt: DateTime.parse(json['expiresAt']),
      createdBy: json['createdBy'] ?? '',
      isActive: json['isActive'] ?? true,
      sections: (json['sections'] as List<dynamic>?)
              ?.map((s) => SurveySection.fromJson(Map<String, dynamic>.from(s)))
              .toList() ??
          [],
    );
  }

  // Konversi ke JSON (Map)
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'createdBy': createdBy,
      'isActive': isActive,
      'sections': sections.map((s) => s.toJson()).toList(),
    };
  }

  // Helper untuk mengecek apakah survey masih tersedia
  bool get isAvailable => isActive && expiresAt.isAfter(DateTime.now());

  // Helper untuk mengecek apakah survey sudah kadaluarsa
  bool get isExpired => expiresAt.isBefore(DateTime.now());
}

class SurveySection {
  final String id;
  final String title;
  final String description;
  final List<SurveyQuestion> questions;

  SurveySection({
    required this.id,
    required this.title,
    required this.description,
    required this.questions,
  });

  SurveySection copyWith({
    String? id,
    String? title,
    String? description,
    List<SurveyQuestion>? questions,
  }) {
    return SurveySection(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      questions: questions ?? List.from(this.questions.map((q) => q.copyWith())), // Deep copy questions juga
    );
  }

  // Factory constructor untuk membuat section baru dengan ID otomatis
  factory SurveySection.create({
    required String title,
    required String description,
    required List<SurveyQuestion> questions,
  }) {
    // ID akan di-generate oleh repository atau saat pertama kali ditambahkan
    return SurveySection(
      id: '', // Akan diisi oleh repository
      title: title,
      description: description,
      questions: questions,
    );
  }

  factory SurveySection.fromJson(Map<String, dynamic> json) {
    return SurveySection(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      questions: (json['questions'] as List<dynamic>?)
              ?.map(
                  (q) => SurveyQuestion.fromJson(Map<String, dynamic>.from(q)))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'questions': questions.map((q) => q.toJson()).toList(),
    };
  }
}

// Asumsi: lib/domain/entities/question.dart
// import 'package:uuid/uuid.dart'; // Asumsi Uuid digunakan untuk ID

enum QuestionType {
  likert,
  shortAnswer,
  longAnswer,
  singleChoice,
  multipleChoice,
}

class SurveyQuestion {
  final String id;
  final String question;
  final String description;
  final QuestionType type;
  final Map<String, String>? likertLabels; // Untuk Likert
  final int? likertScale; // Untuk Likert
  final bool isRequired; // Apakah pertanyaan wajib diisi
  final List<String>? choices; // Untuk Single/Multiple Choice
  final bool allowCustomAnswer; // Untuk Single/Multiple Choice, opsi "Lainnya"
  final String? customAnswerLabel; // Label untuk opsi "Lainnya"

  SurveyQuestion({
    required this.id,
    required this.question,
    required this.description,
    required this.type,
    this.likertLabels,
    this.likertScale,
    this.isRequired = true, // Default wajib
    this.choices,
    this.allowCustomAnswer = false,
    this.customAnswerLabel,
  });

  SurveyQuestion copyWith({
    String? id,
    String? question,
    String? description,
    QuestionType? type,
    Map<String, String>? likertLabels, // Untuk Likert
    int? likertScale, // Untuk Likert
    bool? isRequired, // Apakah pertanyaan wajib diisi
    List<String>? choices, // Untuk Single/Multiple Choice
    bool? allowCustomAnswer, // Untuk Single/Multiple Choice, opsi "Lainnya"
    String? customAnswerLabel,
  }) {
    return SurveyQuestion(
      id: id ?? this.id,
      question: question ?? this.question,
      description: description ?? this.description,
      type: type ?? this.type,
      likertLabels: likertLabels ?? this.likertLabels,
      likertScale: likertScale ?? this.likertScale,
      isRequired: isRequired ?? this.isRequired,
      choices: choices ?? this.choices,
      allowCustomAnswer: allowCustomAnswer ?? this.allowCustomAnswer,
      customAnswerLabel: customAnswerLabel ?? this.customAnswerLabel,
    );
  }

  // Factory constructor untuk membuat pertanyaan baru dengan ID otomatis
  factory SurveyQuestion.create({
    required String question,
    required String description,
    required QuestionType type,
    Map<String, String>? likertLabels,
    int? likertScale,
    bool isRequired = true,
    List<String>? choices,
    bool allowCustomAnswer = false,
    String? customAnswerLabel,
  }) {
    // ID akan di-generate oleh repository
    return SurveyQuestion(
      id: '', // Akan diisi oleh repository
      question: question,
      description: description,
      type: type,
      likertLabels: likertLabels,
      likertScale: likertScale,
      isRequired: isRequired,
      choices: choices,
      allowCustomAnswer: allowCustomAnswer,
      customAnswerLabel: customAnswerLabel,
    );
  }

  factory SurveyQuestion.fromJson(Map<String, dynamic> json) {
    return SurveyQuestion(
      id: json['id'] ?? '',
      question: json['question'] ?? '',
      description: json['description'] ?? '',
      type: QuestionType.values.firstWhere(
          (e) => e.toString() == 'QuestionType.${json['type']}',
          orElse: () => QuestionType.shortAnswer),
      likertLabels: json['likertLabels'] != null
          ? Map<String, String>.from(json['likertLabels'])
          : null,
      likertScale: json['likertScale'],
      isRequired: json['isRequired'] ?? true,
      choices: (json['choices'] as List<dynamic>?)
          ?.map((c) => c.toString())
          .toList(),
      allowCustomAnswer: json['allowCustomAnswer'] ?? false,
      customAnswerLabel: json['customAnswerLabel'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'description': description,
      'type': type.toString().split('.').last,
      'likertLabels': likertLabels,
      'likertScale': likertScale,
      'isRequired': isRequired,
      'choices': choices,
      'allowCustomAnswer': allowCustomAnswer,
      'customAnswerLabel': customAnswerLabel,
    };
  }
}

class SurveyResponse {
  final String id;
  final String surveyId;
  final String userId;
  final String userName;
  final DateTime submittedAt;
  final Map<String, dynamic> answers; // Map<questionId, answerData>

  SurveyResponse({
    required this.id,
    required this.surveyId,
    required this.userId,
    required this.userName,
    required this.submittedAt,
    required this.answers,
  });

  factory SurveyResponse.fromJson(String id, Map<String, dynamic> json) {
    return SurveyResponse(
      id: id,
      surveyId: json['surveyId'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      submittedAt: DateTime.parse(json['submittedAt']),
      answers: Map<String, dynamic>.from(json['answers']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'surveyId': surveyId,
      'userId': userId,
      'userName': userName,
      'submittedAt': submittedAt.toIso8601String(),
      'answers': answers,
    };
  }
}
