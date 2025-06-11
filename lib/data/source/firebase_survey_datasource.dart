import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:livetrackingapp/domain/entities/survey/question.dart';
import 'package:livetrackingapp/domain/entities/survey/survey.dart';
import 'package:livetrackingapp/domain/entities/survey/survey_response.dart';
import 'package:collection/collection.dart'; // Import for firstWhereOrNull

class FirebaseSurveyDataSource {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Survey>> getActiveSurveys(
      String userId, String userRole, String? clusterId) async {
    try {
      final snapshot = await _firestore
          .collection('surveys')
          .where('isActive', isEqualTo: true)
          .get();

      if (snapshot.docs.isEmpty) return [];

      final surveys = <Survey>[];

      for (var doc in snapshot.docs) {
        try {
          final surveyData = doc.data();
          final survey = Survey.fromMap(surveyData, doc.id);

          bool canAccess = false;
          if (survey.targetAudience == null ||
              survey.targetAudience!.contains('all')) {
            canAccess = true;
          } else if (survey.targetAudience!.contains(userRole)) {
            canAccess = true;
          } else if (clusterId != null &&
              survey.targetAudience!.contains(clusterId)) {
            canAccess = true;
          }

          if (canAccess) {
            surveys.add(survey);
          }
        } catch (e) {
          // Continue processing other surveys
        }
      }

      return surveys;
    } catch (e) {
      rethrow;
    }
  }

  Future<Survey?> getSurveyDetails(String surveyId) async {
    try {
      final doc = await _firestore.collection('surveys').doc(surveyId).get();

      if (!doc.exists) return null;

      final surveyData = doc.data()!;
      return Survey.fromMap(surveyData, surveyId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> submitSurveyResponse(SurveyResponse response) async {
    try {
      await _firestore
          .collection('survey_responses')
          .doc(response.responseId)
          .set({
        ...response.toMap(),
        'submittedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<SurveyResponse?> getUserSurveyResponse(
      String surveyId, String userId) async {
    try {
      final snapshot = await _firestore
          .collection('survey_responses')
          .where('surveyId', isEqualTo: surveyId)
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final doc = snapshot.docs.first;
      final responseData = doc.data();
      return SurveyResponse.fromMap(responseData, doc.id);
    } catch (e) {
      rethrow;
    }
  }

  // --- CommandCenter Specific Methods ---

  Future<List<Survey>> getAllSurveys(String commandCenterId) async {
    try {
      final snapshot = await _firestore
          .collection('surveys')
          .where('createdBy', isEqualTo: commandCenterId)
          .orderBy('createdAt', descending: true)
          .get();

      if (snapshot.docs.isEmpty) return [];

      final surveys = <Survey>[];

      for (var doc in snapshot.docs) {
        try {
          final surveyData = doc.data();
          final survey = Survey.fromMap(surveyData, doc.id);
          surveys.add(survey);
        } catch (e) {
          // Continue processing other surveys
        }
      }

      return surveys;
    } catch (e) {
      rethrow;
    }
  }

  Future<String> createSurvey(Survey survey,
      Map<String, List<Map<String, dynamic>>> sectionsAndQuestionsData) async {
    try {
      // Create survey document with auto-generated ID
      final docRef = _firestore.collection('surveys').doc();
      final surveyId = docRef.id;

      // Prepare survey data with sections and questions
      final surveyData = survey.toMap();

      // Add sections with questions to survey data
      final sectionsMap = <String, dynamic>{};
      for (var sectionEntry in sectionsAndQuestionsData.entries) {
        final sectionId = sectionEntry.key;
        final questionsData = sectionEntry.value;
        final sectionData =
            survey.sections.firstWhere((s) => s.sectionId == sectionId);

        // Convert questions list to map for Firestore
        final questionsMap = <String, dynamic>{};
        for (var questionMap in questionsData) {
          final questionId = questionMap['questionId'] as String;
          questionsMap[questionId] = questionMap;
        }

        final sectionMap = sectionData.toMap();
        sectionMap['questions'] = questionsMap;
        sectionsMap[sectionId] = sectionMap;
      }

      surveyData['sections'] = sectionsMap;
      surveyData['createdAt'] = FieldValue.serverTimestamp();
      surveyData['updatedAt'] = FieldValue.serverTimestamp();

      await docRef.set(surveyData);
      return surveyId;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateSurvey(Survey survey,
      Map<String, List<Map<String, dynamic>>> sectionsAndQuestionsData) async {
    try {
      // Prepare survey data with sections and questions
      final surveyData = survey.toMap();

      // Add sections with questions to survey data
      final sectionsMap = <String, dynamic>{};
      for (var sectionEntry in sectionsAndQuestionsData.entries) {
        final sectionId = sectionEntry.key;
        final questionsData = sectionEntry.value;
        final sectionData =
            survey.sections.firstWhere((s) => s.sectionId == sectionId);

        // Convert questions list to map for Firestore
        final questionsMap = <String, dynamic>{};
        for (var questionMap in questionsData) {
          final questionId = questionMap['questionId'] as String;
          questionsMap[questionId] = questionMap;
        }

        final sectionMap = sectionData.toMap();
        sectionMap['questions'] = questionsMap;
        sectionsMap[sectionId] = sectionMap;
      }

      surveyData['sections'] = sectionsMap;
      surveyData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore
          .collection('surveys')
          .doc(survey.surveyId)
          .update(surveyData);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteSurvey(String surveyId) async {
    try {
      // Use batch to ensure atomicity
      final batch = _firestore.batch();

      // Delete survey document
      batch.delete(_firestore.collection('surveys').doc(surveyId));

      // Optional: Delete related responses (or archive them)
      final responsesSnapshot = await _firestore
          .collection('survey_responses')
          .where('surveyId', isEqualTo: surveyId)
          .get();

      for (var doc in responsesSnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    } catch (e) {
      rethrow;
    }
  }

  Future<List<SurveyResponse>> getSurveyResponses(String surveyId) async {
    try {
      final snapshot = await _firestore
          .collection('survey_responses')
          .where('surveyId', isEqualTo: surveyId)
          .orderBy('submittedAt', descending: true)
          .get();

      if (snapshot.docs.isEmpty) return [];

      final responses = <SurveyResponse>[];

      for (var doc in snapshot.docs) {
        try {
          final responseData = doc.data();
          responses.add(SurveyResponse.fromMap(responseData, doc.id));
        } catch (e) {
          // Continue processing other responses
        }
      }

      return responses;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getSurveyResponsesSummary(
      String surveyId) async {
    try {
      final responses = await getSurveyResponses(surveyId);
      final summary = <String, dynamic>{};
      summary['totalResponses'] = responses.length;

      final surveyDetail = await getSurveyDetails(surveyId);
      if (surveyDetail == null) return summary;

      for (var section in surveyDetail.sections) {
        for (var question in section.questions) {
          final questionId = question.questionId;
          // Ensure questionData is initialized for every question in the survey
          final questionSummary = <String, dynamic>{
            'type': questionTypeToString(question.type),
            'text': question.text,
            'responses': 0, // Initialize responses count
          };

          if (question.type == QuestionType.likertScale) {
            questionSummary['min'] = question.likertScaleMin ?? 1;
            questionSummary['max'] = question.likertScaleMax ?? 5;
            questionSummary['minLabel'] = question.likertMinLabel ?? '';
            questionSummary['maxLabel'] = question.likertMaxLabel ?? '';
            questionSummary['distribution'] = <String, int>{};
            for (int i = (question.likertScaleMin ?? 1);
                i <= (question.likertScaleMax ?? 5);
                i++) {
              questionSummary['distribution'][i.toString()] = 0;
            }
            questionSummary['total'] = 0; // For calculating average later
          } else if (question.type == QuestionType.multipleChoice ||
              question.type == QuestionType.checkboxes) {
            questionSummary['options'] = question.options ?? [];
            questionSummary['counts'] = <String, int>{};
            if (question.options != null) {
              for (final option in question.options!) {
                questionSummary['counts'][option] = 0;
              }
            }
          } else if (question.type == QuestionType.shortAnswer ||
              question.type == QuestionType.longAnswer) {
            questionSummary['answers'] = <String>[];
          }
          summary[questionId] = questionSummary;
        }
      }

      // Populate summary data from responses
      for (var response in responses) {
        for (var answer in response.answers) {
          final questionId = answer.questionId;
          final questionData = summary[questionId];

          if (questionData == null || answer.answerValue == null) continue;

          questionData['responses'] = (questionData['responses'] ?? 0) + 1;
          final QuestionType currentQuestionType =
              stringToQuestionType(questionData['type']);

          if (currentQuestionType == QuestionType.likertScale) {
            final int value = answer.answerValue is int
                ? answer.answerValue
                : int.tryParse(answer.answerValue.toString()) ?? 0;

            if (value >= (questionData['min'] ?? 1) &&
                value <= (questionData['max'] ?? 5)) {
              questionData['total'] = (questionData['total'] ?? 0) + value;
              final String valueKey = value.toString();
              questionData['distribution'][valueKey] =
                  (questionData['distribution'][valueKey] ?? 0) + 1;
            }
          } else if (currentQuestionType == QuestionType.multipleChoice) {
            final String option = answer.answerValue.toString();
            if (questionData['counts'].containsKey(option)) {
              questionData['counts'][option] =
                  (questionData['counts'][option] ?? 0) + 1;
            }
          } else if (currentQuestionType == QuestionType.checkboxes) {
            if (answer.answerValue is List) {
              for (final option in answer.answerValue) {
                if (questionData['counts'].containsKey(option.toString())) {
                  questionData['counts'][option.toString()] =
                      (questionData['counts'][option.toString()] ?? 0) + 1;
                }
              }
            } else if (answer.answerValue is String) {
              if (questionData['counts']
                  .containsKey(answer.answerValue.toString())) {
                questionData['counts'][answer.answerValue.toString()] =
                    (questionData['counts'][answer.answerValue.toString()] ??
                            0) +
                        1;
              }
            }
          } else if (currentQuestionType == QuestionType.shortAnswer ||
              currentQuestionType == QuestionType.longAnswer) {
            questionData['answers'].add(answer.answerValue.toString());
          }
        }
      }

      // Calculate average for likert scale after processing all responses
      summary.forEach((key, value) {
        if (value is Map &&
            stringToQuestionType(value['type']) == QuestionType.likertScale) {
          final questionData = value;
          if (questionData['responses'] > 0) {
            questionData['average'] =
                (questionData['total'] ?? 0) / questionData['responses'];
          } else {
            questionData['average'] = 0.0;
          }
        }
      });

      return summary;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateSurveyStatus(String surveyId, bool isActive) async {
    try {
      await _firestore.collection('surveys').doc(surveyId).update({
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      rethrow;
    }
  }

  // Additional helper methods for Firestore

  /// Get surveys by date range
  Future<List<Survey>> getSurveysByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    String? createdBy,
  }) async {
    try {
      Query query = _firestore.collection('surveys');

      if (createdBy != null) {
        query = query.where('createdBy', isEqualTo: createdBy);
      }

      query = query
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('createdAt', descending: true);

      final snapshot = await query.get();

      final surveys = <Survey>[];
      for (var doc in snapshot.docs) {
        try {
          final surveyData = doc.data() as Map<String, dynamic>;
          surveys.add(Survey.fromMap(surveyData, doc.id));
        } catch (e) {
          // Continue processing other surveys
        }
      }

      return surveys;
    } catch (e) {
      rethrow;
    }
  }

  /// Get response statistics
  Future<Map<String, dynamic>> getResponseStatistics(String surveyId) async {
    try {
      final responsesSnapshot = await _firestore
          .collection('survey_responses')
          .where('surveyId', isEqualTo: surveyId)
          .get();

      final stats = <String, dynamic>{
        'totalResponses': responsesSnapshot.docs.length,
        'responsesByDate': <String, int>{},
        'responsesByUser': <String, int>{},
      };

      for (var doc in responsesSnapshot.docs) {
        final data = doc.data();

        // Count by date
        if (data['submittedAt'] != null) {
          final timestamp = data['submittedAt'] as Timestamp;
          final dateKey = timestamp.toDate().toIso8601String().split('T')[0];
          stats['responsesByDate'][dateKey] =
              (stats['responsesByDate'][dateKey] ?? 0) + 1;
        }

        // Count by user
        final userId = data['userId'] as String?;
        if (userId != null) {
          stats['responsesByUser'][userId] =
              (stats['responsesByUser'][userId] ?? 0) + 1;
        }
      }

      return stats;
    } catch (e) {
      rethrow;
    }
  }

  /// Stream surveys for real-time updates
  Stream<List<Survey>> streamSurveys(String commandCenterId) {
    return _firestore
        .collection('surveys')
        .where('createdBy', isEqualTo: commandCenterId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final surveys = <Survey>[];
      for (var doc in snapshot.docs) {
        try {
          final surveyData = doc.data();
          surveys.add(Survey.fromMap(surveyData, doc.id));
        } catch (e) {
          // Continue processing other surveys
        }
      }
      return surveys;
    });
  }

  /// Stream survey responses for real-time updates
  Stream<List<SurveyResponse>> streamSurveyResponses(String surveyId) {
    return _firestore
        .collection('survey_responses')
        .where('surveyId', isEqualTo: surveyId)
        .orderBy('submittedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final responses = <SurveyResponse>[];
      for (var doc in snapshot.docs) {
        try {
          final responseData = doc.data();
          responses.add(SurveyResponse.fromMap(responseData, doc.id));
        } catch (e) {
          // Continue processing other responses
        }
      }
      return responses;
    });
  }
}
