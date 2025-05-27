part of 'survey_bloc.dart';

abstract class SurveyEvent extends Equatable {
  const SurveyEvent();

  @override
  List<Object?> get props => [];
}

// --- Events untuk Semua User ---
class LoadActiveSurveys extends SurveyEvent {
  final String userId;
  final String userRole;
  final String? clusterId; // Opsional, jika user patroli dan ingin filter berdasarkan cluster nya

  const LoadActiveSurveys({required this.userId, required this.userRole, this.clusterId});

  @override
  List<Object?> get props => [userId, userRole, clusterId];
}

class LoadSurveyForFilling extends SurveyEvent {
  final String surveyId;
  final String userId; // Untuk mengecek apakah user sudah pernah mengisi

  const LoadSurveyForFilling({required this.surveyId, required this.userId});

  @override
  List<Object?> get props => [surveyId, userId];
}

class SubmitSurvey extends SurveyEvent {
  final SurveyResponse response;

  const SubmitSurvey({required this.response});

  @override
  List<Object?> get props => [response];
}


// --- Events Khusus CommandCenter ---
class LoadAllCommandCenterSurveys extends SurveyEvent {
  final String commandCenterId;

  const LoadAllCommandCenterSurveys({required this.commandCenterId});

  @override
  List<Object?> get props => [commandCenterId];
}

class LoadSurveyForEditing extends SurveyEvent { // Mirip LoadSurveyForFilling tapi untuk admin
  final String surveyId;
  const LoadSurveyForEditing({required this.surveyId});
  @override
  List<Object?> get props => [surveyId];
}

class SaveSurvey extends SurveyEvent { // Bisa untuk create atau update
  final Survey survey;
  // Data section dan question akan dikelola di UI dan di-pass ke sini
  // Formatnya bisa Map<String sectionId, List<Map<String, dynamic>> questionsData>
  // atau struktur lain yang sesuai.
  final Map<String, List<Map<String, dynamic>>> sectionsAndQuestionsData;
  final bool isUpdate;


  const SaveSurvey({required this.survey, required this.sectionsAndQuestionsData, required this.isUpdate});

  @override
  List<Object?> get props => [survey, sectionsAndQuestionsData, isUpdate];
}

class DeleteSurveyById extends SurveyEvent {
  final String surveyId;

  const DeleteSurveyById({required this.surveyId});

  @override
  List<Object?> get props => [surveyId];
}

class LoadResultsForSurvey extends SurveyEvent {
  final String surveyId;

  const LoadResultsForSurvey({required this.surveyId});

  @override
  List<Object?> get props => [surveyId];
}

class ToggleSurveyStatus extends SurveyEvent {
  final String surveyId;
  final bool isActive;

  const ToggleSurveyStatus({required this.surveyId, required this.isActive});

  @override
  List<Object?> get props => [surveyId, isActive];
}