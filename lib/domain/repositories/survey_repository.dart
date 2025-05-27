import 'package:livetrackingapp/domain/entities/survey/survey.dart';
import 'package:livetrackingapp/domain/entities/survey/survey_response.dart';

abstract class SurveyRepository {
  // Untuk semua user
  Future<List<Survey>> getActiveSurveys(String userId, String userRole, String? clusterId);
  Future<Survey?> getSurveyDetails(String surveyId);
  Future<void> submitSurveyResponse(SurveyResponse response);
  Future<SurveyResponse?> getUserSurveyResponse(String surveyId, String userId);


  // Khusus CommandCenter
  Future<List<Survey>> getAllSurveys(String commandCenterId);
  Future<String> createSurvey(Survey survey, Map<String, List<Map<String, dynamic>>> sectionsAndQuestionsData);
  Future<void> updateSurvey(Survey survey, Map<String, List<Map<String, dynamic>>> sectionsAndQuestionsData);
  Future<void> deleteSurvey(String surveyId);
  Future<List<SurveyResponse>> getSurveyResponses(String surveyId);
  Future<Map<String, dynamic>> getSurveyResponsesSummary(String surveyId);
  Future<void> updateSurveyStatus(String surveyId, bool isActive);
}