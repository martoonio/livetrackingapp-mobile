import '../entities/survey.dart';

abstract class SurveyRepository {
  Future<List<Survey>> getActiveSurveys();
  Future<Survey> getSurveyById(String id);
  Future<void> createSurvey(Survey survey);
  Future<void> updateSurvey(Survey survey);
  Future<void> deleteSurvey(String id);
  Future<void> submitSurveyResponse(SurveyResponse response);
  Future<List<SurveyResponse>> getSurveyResponses(String surveyId);
  Future<bool> hasUserCompletedSurvey(String surveyId, String userId);
  Future<SurveyResponse?> getUserSurveyResponse(
      String surveyId, String userId);
}