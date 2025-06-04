import 'package:firebase_database/firebase_database.dart';
import 'package:livetrackingapp/domain/entities/survey/question.dart';
import 'package:livetrackingapp/domain/entities/survey/survey.dart';
import 'package:livetrackingapp/domain/entities/survey/survey_response.dart';
import 'package:collection/collection.dart'; // Import for firstWhereOrNull

class FirebaseSurveyDataSource {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<List<Survey>> getActiveSurveys(
      String userId, String userRole, String? clusterId) async {
    try {
      final snapshot = await _db.child('surveys').get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final surveys = <Survey>[];
      final surveysMap = snapshot.value as Map<dynamic, dynamic>;

      surveysMap.forEach((key, value) {
        // PERBAIKAN: Konversi ke Map<String, dynamic> dengan cara yang sama
        if (value is Map) {
          final Map<String, dynamic> surveyData = {};

          value.forEach((k, v) {
            surveyData[k.toString()] = v;

            // Khusus untuk sections, perlu penanganan nested map
            if (k.toString() == 'sections' && v is Map) {
              Map<String, dynamic> cleanSections = {};

              v.forEach((sectionKey, sectionValue) {
                if (sectionValue is Map) {
                  Map<String, dynamic> cleanSection = {};

                  sectionValue.forEach((sk, sv) {
                    cleanSection[sk.toString()] = sv;

                    // Penanganan untuk nested questions
                    if (sk.toString() == 'questions' && sv is Map) {
                      Map<String, dynamic> cleanQuestions = {};

                      sv.forEach((questionKey, questionValue) {
                        if (questionValue is Map) {
                          Map<String, dynamic> cleanQuestion = {};

                          questionValue.forEach((qk, qv) {
                            cleanQuestion[qk.toString()] = qv;
                          });

                          cleanQuestions[questionKey.toString()] =
                              cleanQuestion;
                        }
                      });

                      cleanSection['questions'] = cleanQuestions;
                    }
                  });

                  cleanSections[sectionKey.toString()] = cleanSection;
                }
              });

              surveyData['sections'] = cleanSections;
            }
          });

          try {
            final survey = Survey.fromMap(surveyData, key.toString());
            bool canAccess = false;
            if (survey.isActive) {
              if (survey.targetAudience == null ||
                  survey.targetAudience!.contains('all')) {
                canAccess = true;
              } else if (survey.targetAudience!.contains(userRole)) {
                canAccess = true;
              } else if (clusterId != null &&
                  survey.targetAudience!.contains(clusterId)) {
                canAccess = true;
              }
            }
            if (canAccess) {
              surveys.add(survey);
            }
          } catch (e) {
          }
        }
      });

      return surveys;
    } catch (e) {
      rethrow;
    }
  }

  Future<Survey?> getSurveyDetails(String surveyId) async {
    try {
      final snapshot = await _db.child('surveys').child(surveyId).get();
      if (!snapshot.exists || snapshot.value == null) return null;

      // PERBAIKAN: Konversi ke Map<String, dynamic>
      final value = snapshot.value as Map<dynamic, dynamic>;
      final Map<String, dynamic> surveyData = {};

      value.forEach((k, v) {
        surveyData[k.toString()] = v;

        // Khusus untuk sections, perlu penanganan nested map
        if (k.toString() == 'sections' && v is Map) {
          Map<String, dynamic> cleanSections = {};

          v.forEach((sectionKey, sectionValue) {
            if (sectionValue is Map) {
              Map<String, dynamic> cleanSection = {};

              sectionValue.forEach((sk, sv) {
                cleanSection[sk.toString()] = sv;

                // Penanganan untuk nested questions
                if (sk.toString() == 'questions' && sv is Map) {
                  Map<String, dynamic> cleanQuestions = {};

                  sv.forEach((questionKey, questionValue) {
                    if (questionValue is Map) {
                      Map<String, dynamic> cleanQuestion = {};

                      questionValue.forEach((qk, qv) {
                        cleanQuestion[qk.toString()] = qv;
                      });

                      cleanQuestions[questionKey.toString()] = cleanQuestion;
                    }
                  });

                  cleanSection['questions'] = cleanQuestions;
                }
              });

              cleanSections[sectionKey.toString()] = cleanSection;
            }
          });

          surveyData['sections'] = cleanSections;
        }
      });

      return Survey.fromMap(surveyData, surveyId);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> submitSurveyResponse(SurveyResponse response) async {
    try {
      await _db
          .child('survey_responses')
          .child(response.responseId)
          .set(response.toMap());
    } catch (e) {
      rethrow;
    }
  }

  Future<SurveyResponse?> getUserSurveyResponse(
      String surveyId, String userId) async {
    try {
      final snapshot = await _db
          .child('survey_responses')
          .orderByChild('surveyId')
          .equalTo(surveyId)
          .get();

      if (!snapshot.exists || snapshot.value == null) return null;

      final responsesMap = snapshot.value as Map<dynamic, dynamic>;
      SurveyResponse? userResponse;

      responsesMap.forEach((key, value) {
        if (value is Map) {
          final userIdFromResponse = value['userId'];

          if (userIdFromResponse == userId) {
            // PERBAIKAN: Konversi ke Map<String, dynamic>
            final Map<String, dynamic> responseData = {};

            value.forEach((k, v) {
              responseData[k.toString()] = v;

              // Khusus untuk answers, perlu penanganan nested map
              if (k.toString() == 'answers' && v is Map) {
                Map<String, dynamic> cleanAnswers = {};

                v.forEach((answerId, answerValue) {
                  if (answerValue is Map) {
                    Map<String, dynamic> cleanAnswer = {};

                    answerValue.forEach((ak, av) {
                      cleanAnswer[ak.toString()] = av;
                    });

                    cleanAnswers[answerId.toString()] = cleanAnswer;
                  }
                });

                responseData['answers'] = cleanAnswers;
              }
            });

            try {
              userResponse =
                  SurveyResponse.fromMap(responseData, key.toString());
              return; // Keluar dari forEach setelah menemukan
            } catch (e) {
            }
          }
        }
      });

      return userResponse;
    } catch (e) {
      rethrow;
    }
  }

  // Helper method untuk mengkonversi Map dari Firebase ke Map<String, dynamic>
  Map<String, dynamic> _convertFirebaseMap(Map<dynamic, dynamic> firebaseMap) {
    Map<String, dynamic> result = {};

    firebaseMap.forEach((key, value) {
      if (value is Map) {
        result[key.toString()] =
            _convertFirebaseMap(value as Map<dynamic, dynamic>);
      } else if (value is List) {
        result[key.toString()] = _convertFirebaseList(value as List<dynamic>);
      } else {
        result[key.toString()] = value;
      }
    });

    return result;
  }

  List<dynamic> _convertFirebaseList(List<dynamic> firebaseList) {
    List<dynamic> result = [];

    for (var item in firebaseList) {
      if (item is Map) {
        result.add(_convertFirebaseMap(item as Map<dynamic, dynamic>));
      } else if (item is List) {
        result.add(_convertFirebaseList(item));
      } else {
        result.add(item);
      }
    }

    return result;
  }

  // --- CommandCenter Specific Methods ---

  Future<List<Survey>> getAllSurveys(String commandCenterId) async {
    try {
      final snapshot = await _db
          .child('surveys')
          .orderByChild('createdBy')
          .equalTo(commandCenterId)
          .get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final surveys = <Survey>[];
      final surveysMap = snapshot.value as Map<dynamic, dynamic>;

      surveysMap.forEach((key, value) {
        if (value is Map) {
          try {
            // Gunakan helper method untuk konversi
            final surveyData =
                _convertFirebaseMap(value as Map<dynamic, dynamic>);
            final survey = Survey.fromMap(surveyData, key.toString());
            surveys.add(survey);
          } catch (e) {
          }
        }
      });

      return surveys;
    } catch (e) {
      rethrow;
    }
  }

  Future<String> createSurvey(Survey survey,
      Map<String, List<Map<String, dynamic>>> sectionsAndQuestionsData) async {
    try {
      final surveyRef = _db.child('surveys').push();
      final surveyId = surveyRef.key!;

      await surveyRef.set(survey.toMap());

      for (var sectionEntry in sectionsAndQuestionsData.entries) {
        final sectionId = sectionEntry.key;
        final questionsData = sectionEntry.value;
        final sectionData = survey.sections.firstWhere((s) =>
            s.sectionId == sectionId); // Ambil data section dari objek Survey

        final sectionRef =
            _db.child('surveys/$surveyId/sections').child(sectionId);
        await sectionRef.set(sectionData.toMap()); // Simpan data section utama

        for (var questionMap in questionsData) {
          final questionId = questionMap['questionId']
              as String; // Asumsi Anda punya questionId di map
          await sectionRef
              .child('questions')
              .child(questionId)
              .set(questionMap);
        }
      }
      return surveyId;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateSurvey(Survey survey,
      Map<String, List<Map<String, dynamic>>> sectionsAndQuestionsData) async {
    try {
      final surveyRef = _db.child('surveys').child(survey.surveyId);
      await surveyRef.update(survey.toMap()); // Update data survey utama

      // Hapus sections lama dulu untuk memastikan konsistensi (atau lakukan update yang lebih granular)
      await surveyRef.child('sections').remove();

      // Tambahkan sections yang baru/diupdate
      for (var sectionEntry in sectionsAndQuestionsData.entries) {
        final sectionId = sectionEntry.key;
        final questionsData = sectionEntry.value;
        final sectionData =
            survey.sections.firstWhere((s) => s.sectionId == sectionId);

        final sectionRef = surveyRef.child('sections').child(sectionId);
        await sectionRef.set(sectionData.toMap());

        for (var questionMap in questionsData) {
          final questionId = questionMap['questionId'] as String;
          await sectionRef
              .child('questions')
              .child(questionId)
              .set(questionMap);
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteSurvey(String surveyId) async {
    try {
      await _db.child('surveys').child(surveyId).remove();
      // Pertimbangkan untuk menghapus respons terkait juga, atau arsipkan.
      // final responsesSnapshot = await _db.child('survey_responses').orderByChild('surveyId').equalTo(surveyId).get();
      // if (responsesSnapshot.exists) {
      //   final responsesMap = responsesSnapshot.value as Map<dynamic, dynamic>;
      //   for (var key in responsesMap.keys) {
      //     await _db.child('survey_responses').child(key as String).remove();
      //   }
      // }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<SurveyResponse>> getSurveyResponses(String surveyId) async {
    try {
      final snapshot = await _db
          .child('survey_responses')
          .orderByChild('surveyId')
          .equalTo(surveyId)
          .get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final responses = <SurveyResponse>[];
      final responsesMap = snapshot.value as Map<dynamic, dynamic>;

      responsesMap.forEach((key, value) {
        if (value is Map) {
          // PERBAIKAN: Konversi ke Map<String, dynamic>
          final Map<String, dynamic> responseData = {};

          value.forEach((k, v) {
            responseData[k.toString()] = v;

            // Khusus untuk answers, perlu penanganan nested map
            if (k.toString() == 'answers' && v is Map) {
              Map<String, dynamic> cleanAnswers = {};

              v.forEach((answerId, answerValue) {
                if (answerValue is Map) {
                  Map<String, dynamic> cleanAnswer = {};

                  answerValue.forEach((ak, av) {
                    cleanAnswer[ak.toString()] = av;
                  });

                  cleanAnswers[answerId.toString()] = cleanAnswer;
                }
              });

              responseData['answers'] = cleanAnswers;
            }
          });

          try {
            responses.add(SurveyResponse.fromMap(responseData, key.toString()));
          } catch (e) {
          }
        }
      });

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
            'type': questionTypeToString(question.type), // MODIFIED LINE
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
      await _db.child('surveys').child(surveyId).update({'isActive': isActive});
    } catch (e) {
      rethrow;
    }
  }
}
