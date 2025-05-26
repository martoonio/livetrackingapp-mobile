import 'package:firebase_database/firebase_database.dart';
import '../../domain/entities/survey.dart';
import '../../domain/repositories/survey_repository.dart'; // Pastikan ini diimpor

class SurveyRepositoryImpl implements SurveyRepository {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  @override
  Future<List<Survey>> getActiveSurveys() async {
    try {
      final snapshot = await _database.child('surveys').get();

      if (!snapshot.exists) {
        print('No active surveys found');
        return [];
      }

      final List<Survey> surveys = [];
      final surveysData = snapshot.value as Map<dynamic, dynamic>;

      surveysData.forEach((key, value) {
        try {
          final survey = Survey.fromJson(
            key.toString(),
            Map<String, dynamic>.from(value as Map),
          );
          if (survey.isAvailable) {
            surveys.add(survey);
          }
        } catch (e) {
          print('Error parsing survey: $e');
        }
      });

      // Sort by created date (newest first)
      surveys.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return surveys;
    } catch (e) {
      print('Error fetching active surveys: $e');
      throw Exception('Failed to load surveys: ${e.toString()}');
    }
  }

  @override
  Future<Survey> getSurveyById(String id) async {
    try {
      final snapshot = await _database.child('surveys').child(id).get();

      if (!snapshot.exists) {
        throw Exception('Survey not found');
      }

      return Survey.fromJson(
        id,
        Map<String, dynamic>.from(snapshot.value as Map),
      );
    } catch (e) {
      print('Error fetching survey by ID: $e');
      throw Exception('Failed to get survey: ${e.toString()}');
    }
  }

  @override
  Future<void> createSurvey(Survey survey) async {
    try {
      // Buat referensi baru dengan id auto-generate dari Firebase
      final newSurveyRef = _database.child('surveys').push();
      final String newId = newSurveyRef.key!;

      // Assign ID ke survey utama
      final surveyWithId = Survey(
        id: newId,
        title: survey.title,
        description: survey.description,
        createdAt: survey.createdAt,
        expiresAt: survey.expiresAt,
        createdBy: survey.createdBy,
        isActive: survey.isActive,
        // Panggil helper untuk memberi ID pada section dan question
        sections: _assignIdsToSections(survey.sections),
      );

      // Simpan ke database
      await newSurveyRef.set(surveyWithId.toJson());

      print('Survey created with auto-generated ID: $newId');
    } catch (e) {
      print('Error creating survey: $e');
      throw Exception('Failed to create survey: ${e.toString()}');
    }
  }

  // Helper untuk memberi ID pada section dan question jika ID-nya kosong
  List<SurveySection> _assignIdsToSections(List<SurveySection> sections) {
    return sections.map((section) {
      // Jika section.id kosong, generate ID baru
      final sectionId = section.id.isEmpty
          ? _database
              .child('dummy')
              .push()
              .key! // Gunakan push().key untuk ID unik
          : section.id;

      final questions = section.questions.map((question) {
        // Jika question.id kosong, generate ID baru
        final questionId = question.id.isEmpty
            ? _database
                .child('dummy')
                .push()
                .key! // Gunakan push().key untuk ID unik
            : question.id;

        return SurveyQuestion(
          id: questionId,
          question: question.question,
          description: question.description,
          type: question.type,
          likertLabels: question.likertLabels,
          likertScale: question.likertScale,
          isRequired: question.isRequired,
          choices: question.choices,
          allowCustomAnswer: question.allowCustomAnswer,
          customAnswerLabel: question.customAnswerLabel,
        );
      }).toList();

      return SurveySection(
        id: sectionId,
        title: section.title,
        description: section.description,
        questions: questions,
      );
    }).toList();
  }

  @override
  Future<void> updateSurvey(Survey survey) async {
    try {
      // Pastikan ID section dan question juga di-assign jika ada yang baru ditambahkan
      final updatedSections = _assignIdsToSections(survey.sections);
      final updatedSurvey = Survey(
        id: survey.id,
        title: survey.title,
        description: survey.description,
        createdAt: survey.createdAt,
        expiresAt: survey.expiresAt,
        createdBy: survey.createdBy,
        isActive: survey.isActive,
        sections: updatedSections,
      );
      await _database
          .child('surveys')
          .child(survey.id)
          .update(updatedSurvey.toJson());
    } catch (e) {
      print('Error updating survey: $e');
      throw Exception('Failed to update survey: ${e.toString()}');
    }
  }

  @override
  Future<void> deleteSurvey(String id) async {
    try {
      await _database.child('surveys').child(id).remove();
    } catch (e) {
      print('Error deleting survey: $e');
      throw Exception('Failed to delete survey: ${e.toString()}');
    }
  }

  @override
  Future<void> submitSurveyResponse(SurveyResponse response) async {
    try {
      // Menggunakan path 'surveyResponses' (camelCase) untuk konsistensi
      final newResponseRef = _database.child('surveyResponses').push();
      final String newId = newResponseRef.key!;

      final responseWithId = SurveyResponse(
        id: newId,
        surveyId: response.surveyId,
        userId: response.userId,
        userName: response.userName,
        submittedAt: response.submittedAt,
        answers: response.answers,
      );

      await newResponseRef.set(responseWithId.toJson());

      print('Survey response submitted with auto-generated ID: $newId');
    } catch (e) {
      print('Error submitting survey response: $e');
      throw Exception('Failed to submit survey response: ${e.toString()}');
    }
  }

  @override
  Future<List<SurveyResponse>> getSurveyResponses(String surveyId) async {
    try {
      // Menggunakan path 'surveyResponses' (camelCase) untuk konsistensi
      final snapshot = await _database
          .child('surveyResponses')
          .orderByChild('surveyId')
          .equalTo(surveyId)
          .get();

      if (!snapshot.exists) {
        return [];
      }

      final List<SurveyResponse> responses = [];
      final responsesData = snapshot.value as Map<dynamic, dynamic>;

      responsesData.forEach((key, value) {
        try {
          responses.add(SurveyResponse.fromJson(
            key.toString(),
            Map<String, dynamic>.from(value as Map),
          ));
        } catch (e) {
          print('Error parsing survey response: $e');
        }
      });

      // Sort by submission date (newest first)
      responses.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

      return responses;
    } catch (e) {
      print('Error fetching survey responses: $e');
      throw Exception('Failed to load survey responses: ${e.toString()}');
    }
  }

  @override
  Future<bool> hasUserCompletedSurvey(String surveyId, String userId) async {
    try {
      print('Checking if user $userId has completed survey $surveyId');

      // Tambahkan timeout untuk mencegah hang
      final snapshot = await _database
          .child('surveyResponses')
          .orderByChild('surveyId')
          .equalTo(surveyId)
          .get()
          .timeout(const Duration(seconds: 5), onTimeout: () {
        print('Timeout while checking survey completion');
        throw Exception('Request timeout');
      });

      if (!snapshot.exists) {
        print('No responses found for survey $surveyId');
        return false;
      }

      // Scan semua responses untuk memeriksa apakah userId cocok
      final responsesData = snapshot.value as Map<dynamic, dynamic>;
      bool hasCompleted = false;

      responsesData.forEach((key, value) {
        try {
          final response = Map<String, dynamic>.from(value as Map);

          // Periksa apakah userId pada response cocok dengan userId yang dicari
          if (response['userId'] == userId) {
            print('Found response from user $userId for survey $surveyId');
            hasCompleted = true;
            // Tidak perlu melanjutkan loop jika sudah menemukan kecocokan
            return;
          }
        } catch (e) {
          print('Error parsing response: $e');
        }
      });

      // Log hasil
      if (hasCompleted) {
        print('User $userId has completed survey $surveyId');
      } else {
        print('User $userId has NOT completed survey $surveyId');
      }

      return hasCompleted;
    } catch (e) {
      print('Error checking if user completed survey: $e');
      throw Exception(
          'Failed to check survey completion status: ${e.toString()}');
    }
  }

  // Tambahkan metode baru
  @override
  Future<SurveyResponse> getUserSurveyResponse(
      String surveyId, String userId) async {
    try {
      print('Getting user response for survey $surveyId, user $userId');

      // Query surveyResponses berdasarkan surveyId dan userId
      final snapshot = await _database
          .child('surveyResponses')
          .orderByChild('surveyId')
          .equalTo(surveyId)
          .get();

      if (!snapshot.exists) {
        throw Exception('No responses found for this survey');
      }

      // Iterasi semua responses untuk menemukan yang sesuai dengan userId
      final responsesData = snapshot.value as Map<dynamic, dynamic>;
      SurveyResponse? targetResponse;

      responsesData.forEach((key, value) {
        try {
          final response = Map<String, dynamic>.from(value as Map);
          if (response['userId'] == userId) {
            targetResponse = SurveyResponse.fromJson(
              key.toString(),
              response,
            );
          }
        } catch (e) {
          print('Error parsing response: $e');
        }
      });

      if (targetResponse == null) {
        throw Exception('No response found for this user');
      }

      return targetResponse!;
    } catch (e) {
      print('Error getting user survey response: $e');
      throw Exception('Failed to get user survey response: ${e.toString()}');
    }
  }
}
