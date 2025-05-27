import 'package:livetrackingapp/domain/entities/survey/question.dart';

class Section {
  final String sectionId;
  final String title;
  final String? description;
  final int order;
  final List<Question> questions;

  Section({
    required this.sectionId,
    required this.title,
    this.description,
    required this.order,
    required this.questions,
  });

  // Perbaikan pada method fromMap
  factory Section.fromMap(Map<String, dynamic> map, String id) {
    List<Question> questions = [];
    
    if (map['questions'] != null && map['questions'] is Map<String, dynamic>) {
      questions = (map['questions'] as Map<String, dynamic>).entries.map((entry) {
        return Question.fromMap(entry.value as Map<String, dynamic>, entry.key);
      }).toList();
      
      // Urutkan pertanyaan berdasarkan order
      questions.sort((a, b) => a.order.compareTo(b.order));
    }

    return Section(
      sectionId: id,
      title: map['title'] ?? '',
      description: map['description'],
      order: map['order'] != null ? (map['order'] as num).toInt() : 0,
      questions: questions,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'order': order,
      // Questions akan disimpan sebagai nested map di Firebase
    };
  }
}