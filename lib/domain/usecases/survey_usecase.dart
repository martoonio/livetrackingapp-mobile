import 'package:livetrackingapp/domain/entities/survey/survey.dart';
import 'package:livetrackingapp/domain/entities/survey/survey_response.dart';
import 'package:livetrackingapp/domain/repositories/survey_repository.dart';

// --- Use Cases untuk Semua User ---
class GetActiveSurveysUseCase {
  final SurveyRepository repository;
  GetActiveSurveysUseCase(this.repository);
  Future<List<Survey>> call(String userId, String userRole, String? clusterId) => repository.getActiveSurveys(userId, userRole, clusterId);
}

class GetSurveyDetailsUseCase {
  final SurveyRepository repository;
  GetSurveyDetailsUseCase(this.repository);
  Future<Survey?> call(String surveyId) => repository.getSurveyDetails(surveyId);
}

class SubmitSurveyResponseUseCase {
  final SurveyRepository repository;
  SubmitSurveyResponseUseCase(this.repository);
  Future<void> call(SurveyResponse response) => repository.submitSurveyResponse(response);
}

class GetUserSurveyResponseUseCase {
    final SurveyRepository repository;
    GetUserSurveyResponseUseCase(this.repository);
    Future<SurveyResponse?> call(String surveyId, String userId) => repository.getUserSurveyResponse(surveyId, userId);
}


// --- Use Cases Khusus CommandCenter ---
class GetAllSurveysUseCase {
  final SurveyRepository repository;
  GetAllSurveysUseCase(this.repository);
  Future<List<Survey>> call(String commandCenterId) => repository.getAllSurveys(commandCenterId);
}

class CreateSurveyUseCase {
  final SurveyRepository repository;
  CreateSurveyUseCase(this.repository);
  Future<String> call(Survey survey, Map<String, List<Map<String, dynamic>>> sectionsAndQuestionsData) => repository.createSurvey(survey, sectionsAndQuestionsData);
}

class UpdateSurveyUseCase {
  final SurveyRepository repository;
  UpdateSurveyUseCase(this.repository);
  Future<void> call(Survey survey, Map<String, List<Map<String, dynamic>>> sectionsAndQuestionsData) => repository.updateSurvey(survey, sectionsAndQuestionsData);
}

class DeleteSurveyUseCase {
  final SurveyRepository repository;
  DeleteSurveyUseCase(this.repository);
  Future<void> call(String surveyId) => repository.deleteSurvey(surveyId);
}

class GetSurveyResponsesUseCase {
  final SurveyRepository repository;
  GetSurveyResponsesUseCase(this.repository);
  Future<List<SurveyResponse>> call(String surveyId) => repository.getSurveyResponses(surveyId);
}

class GetSurveyResponsesSummaryUseCase {
    final SurveyRepository repository;
    GetSurveyResponsesSummaryUseCase(this.repository);
    Future<Map<String, dynamic>> call(String surveyId) => repository.getSurveyResponsesSummary(surveyId);
}

class UpdateSurveyStatusUseCase {
    final SurveyRepository repository;
    UpdateSurveyStatusUseCase(this.repository);
    Future<void> call(String surveyId, bool isActive) => repository.updateSurveyStatus(surveyId, isActive);
}