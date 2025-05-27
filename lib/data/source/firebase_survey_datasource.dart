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
            print('Error parsing survey $key: $e');
          }
        }
      });

      return surveys;
    } catch (e) {
      print("Error fetching active surveys: $e");
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
      print("Error fetching survey details for $surveyId: $e");
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
      print("Error submitting survey response ${response.responseId}: $e");
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
              print('Error parsing user response $key: $e');
            }
          }
        }
      });

      return userResponse;
    } catch (e) {
      print(
          "Error fetching user survey response for survey $surveyId, user $userId: $e");
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
            print('Error parsing survey $key: $e');
          }
        }
      });

      return surveys;
    } catch (e) {
      print("Error fetching all surveys for $commandCenterId: $e");
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
      print("Error creating survey: $e");
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
      print("Error updating survey ${survey.surveyId}: $e");
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
      print("Error deleting survey $surveyId: $e");
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
            print('Error parsing response $key: $e');
          }
        }
      });

      return responses;
    } catch (e) {
      print("Error fetching survey responses for $surveyId: $e");
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getSurveyResponsesSummary(
      String surveyId) async {
    // Implementasi ini akan cukup kompleks dan bergantung pada bagaimana Anda ingin
    // meringkas data (misalnya, agregasi untuk skala Likert, hitungan untuk pilihan ganda).
    // Untuk contoh sederhana, kita bisa mengembalikan jumlah respons.
    try {
      final responses = await getSurveyResponses(surveyId);
      final summary = <String, dynamic>{};
      summary['totalResponses'] = responses.length;

      // Contoh agregasi untuk pertanyaan spesifik (misal, questionId1 adalah likert)
      // Anda perlu detail struktur pertanyaan untuk melakukan ini dengan benar.
      final surveyDetail = await getSurveyDetails(surveyId);
      if (surveyDetail == null) return summary;

      for (var section in surveyDetail.sections) {
        for (var question in section.questions) {
          final questionId = question.questionId;
          if (question.type == QuestionType.likertScale) {
            List<int> likertValues = [];
            for (var response in responses) {
              final answer = response.answers
                  .firstWhereOrNull((a) => a.questionId == questionId);
              if (answer != null && answer.answerValue is int) {
                likertValues.add(answer.answerValue as int);
              } else if (answer != null && answer.answerValue is String) {
                // Coba parse jika String
                final parsedValue = int.tryParse(answer.answerValue as String);
                if (parsedValue != null) {
                  likertValues.add(parsedValue);
                }
              }
            }
            if (likertValues.isNotEmpty) {
              summary[questionId] = {
                'type': 'likert',
                'average':
                    likertValues.reduce((a, b) => a + b) / likertValues.length,
                'min': question.likertScaleMin,
                'max': question.likertScaleMax,
                'minLabel': question.likertMinLabel,
                'maxLabel': question.likertMaxLabel,
                'responses': likertValues.length,
                // Anda bisa menambahkan distribusi jawaban di sini
              };
            }
          } else if (question.type == QuestionType.multipleChoice ||
              question.type == QuestionType.checkboxes) {
            Map<String, int> optionCounts = {};
            if (question.options != null) {
              for (var option in question.options!) {
                optionCounts[option] = 0;
              }
            }
            for (var response in responses) {
              final answer = response.answers
                  .firstWhereOrNull((a) => a.questionId == questionId);
              if (answer != null) {
                if (question.type == QuestionType.multipleChoice &&
                    answer.answerValue is String) {
                  optionCounts[answer.answerValue as String] =
                      (optionCounts[answer.answerValue as String] ?? 0) + 1;
                } else if (question.type == QuestionType.checkboxes &&
                    answer.answerValue is List) {
                  for (var selectedOption in answer.answerValue as List) {
                    if (selectedOption is String) {
                      optionCounts[selectedOption] =
                          (optionCounts[selectedOption] ?? 0) + 1;
                    }
                  }
                }
              }
            }
            summary[questionId] = {
              'type': questionTypeToString(question.type),
              'options': question.options,
              'counts': optionCounts,
              'responses': responses
                  .length, // Jumlah total responden untuk pertanyaan ini
            };
          } else if (question.type == QuestionType.shortAnswer ||
              question.type == QuestionType.longAnswer) {
            List<String> textAnswers = [];
            for (var response in responses) {
              final answer = response.answers
                  .firstWhereOrNull((a) => a.questionId == questionId);
              if (answer != null && answer.answerValue is String) {
                textAnswers.add(answer.answerValue as String);
              }
            }
            summary[questionId] = {
              'type': questionTypeToString(question.type),
              'answers': textAnswers,
              'responses': textAnswers.length,
            };
          }
        }
      }
      return summary;
    } catch (e) {
      print("Error fetching survey responses summary for $surveyId: $e");
      rethrow;
    }
  }

  Future<void> updateSurveyStatus(String surveyId, bool isActive) async {
    try {
      await _db.child('surveys').child(surveyId).update({'isActive': isActive});
    } catch (e) {
      print("Error updating survey status for $surveyId: $e");
      rethrow;
    }
  }
}
