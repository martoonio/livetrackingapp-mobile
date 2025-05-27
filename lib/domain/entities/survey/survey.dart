import 'package:livetrackingapp/domain/entities/survey/section.dart';

class Survey {
  final String surveyId;
  final String title;
  final String? description;
  final String createdBy; // User ID of commandCenter
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Section> sections;
  final bool isActive;
  final List<String>?
      targetAudience; // Bisa role 'patrol', 'all', atau list clusterId

  Survey({
    required this.surveyId,
    required this.title,
    this.description,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.sections,
    required this.isActive,
    this.targetAudience,
  });

  factory Survey.fromMap(Map<String, dynamic> map, String id) {
    List<String>? targetAudience;

    // Handle berbagai format targetAudience
    if (map['targetAudience'] is List) {
      targetAudience = List<String>.from(map['targetAudience']);
    } else if (map['targetAudience'] is Map) {
      // Jika targetAudience adalah Map (dari rule baru)
      targetAudience =
          (map['targetAudience'] as Map).keys.map((k) => k.toString()).toList();
    } else {
      targetAudience = null;
    }

    return Survey(
      surveyId: id,
      title: map['title'] ?? '',
      description: map['description'],
      createdBy: map['createdBy'] ?? '',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : DateTime.now(),
      sections:
          (map['sections'] as Map<String, dynamic>?)?.entries.map((entry) {
                return Section.fromMap(
                    entry.value as Map<String, dynamic>, entry.key);
              }).toList() ??
              [],
      isActive: map['isActive'] ?? false,
      targetAudience: targetAudience,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isActive': isActive,
      'targetAudience': targetAudience,
      // Sections akan disimpan sebagai nested map di Firebase,
      // jadi tidak langsung dimasukkan di sini.
      // Penanganannya akan ada di repository/datasource.
    };
  }
}
