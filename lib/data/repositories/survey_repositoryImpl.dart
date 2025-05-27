import 'package:livetrackingapp/data/source/firebase_survey_datasource.dart';
import 'package:livetrackingapp/domain/entities/survey/survey.dart';
import 'package:livetrackingapp/domain/entities/survey/survey_response.dart';
import 'package:livetrackingapp/domain/repositories/survey_repository.dart';

class SurveyRepositoryImpl implements SurveyRepository {
  final FirebaseSurveyDataSource dataSource;

  SurveyRepositoryImpl({required this.dataSource});

  @override
  Future<List<Survey>> getActiveSurveys(String userId, String userRole, String? clusterId) {
    return dataSource.getActiveSurveys(userId, userRole, clusterId);
  }

  @override
  Future<Survey?> getSurveyDetails(String surveyId) {
    return dataSource.getSurveyDetails(surveyId);
  }

  @override
  Future<void> submitSurveyResponse(SurveyResponse response) {
    return dataSource.submitSurveyResponse(response);
  }

   @override
  Future<SurveyResponse?> getUserSurveyResponse(String surveyId, String userId) {
    return dataSource.getUserSurveyResponse(surveyId, userId);
  }

  @override
  Future<List<Survey>> getAllSurveys(String commandCenterId) {
    return dataSource.getAllSurveys(commandCenterId);
  }

  @override
  Future<String> createSurvey(Survey survey, Map<String, List<Map<String, dynamic>>> sectionsAndQuestionsData) {
    return dataSource.createSurvey(survey, sectionsAndQuestionsData);
  }

  @override
  Future<void> updateSurvey(Survey survey, Map<String, List<Map<String, dynamic>>> sectionsAndQuestionsData) {
    return dataSource.updateSurvey(survey, sectionsAndQuestionsData);
  }

  @override
  Future<void> deleteSurvey(String surveyId) {
    return dataSource.deleteSurvey(surveyId);
  }

  @override
  Future<List<SurveyResponse>> getSurveyResponses(String surveyId) {
    return dataSource.getSurveyResponses(surveyId);
  }

  @override
  Future<Map<String, dynamic>> getSurveyResponsesSummary(String surveyId) {
    return dataSource.getSurveyResponsesSummary(surveyId);
  }

   @override
  Future<void> updateSurveyStatus(String surveyId, bool isActive) {
    return dataSource.updateSurveyStatus(surveyId, isActive);
  }
}