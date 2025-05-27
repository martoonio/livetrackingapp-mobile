part of 'survey_bloc.dart';

abstract class SurveyState extends Equatable {
  const SurveyState();

  @override
  List<Object?> get props => [];
}

class SurveyInitial extends SurveyState {}

class SurveyLoading extends SurveyState {
    final String? message;
    const SurveyLoading({this.message});
    @override
    List<Object?> get props => [message];
}

// State untuk daftar survei yang bisa diisi user
class ActiveSurveysLoaded extends SurveyState {
  final List<Survey> surveys;
  const ActiveSurveysLoaded(this.surveys);
  @override
  List<Object?> get props => [surveys];
}

// State untuk menampilkan detail/form survei untuk diisi
class SurveyFormLoaded extends SurveyState {
  final Survey survey;
  final SurveyResponse? existingResponse; // Jika user melanjutkan mengisi
  const SurveyFormLoaded({required this.survey, this.existingResponse});
  @override
  List<Object?> get props => [survey, existingResponse];
}

// State untuk menampilkan survei yang akan diedit oleh CommandCenter
class SurveyEditLoaded extends SurveyState {
  final Survey survey;
  const SurveyEditLoaded(this.survey);
  @override
  List<Object?> get props => [survey];
}


// State untuk daftar semua survei yang dikelola CommandCenter
class CommandCenterSurveysLoaded extends SurveyState {
  final List<Survey> surveys;
  const CommandCenterSurveysLoaded(this.surveys);
  @override
  List<Object?> get props => [surveys];
}

// State untuk hasil/respons dari sebuah survei (untuk CommandCenter)
class SurveyResultsLoaded extends SurveyState {
  final Survey survey; // Detail survei untuk konteks
  final List<SurveyResponse> responses;
  final Map<String, dynamic> summary; // Ringkasan hasil
  const SurveyResultsLoaded({required this.survey, required this.responses, required this.summary});
  @override
  List<Object?> get props => [survey, responses, summary];
}

class SurveyOperationSuccess extends SurveyState {
  final String message;
  const SurveyOperationSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

class SurveyError extends SurveyState {
  final String message;
  const SurveyError(this.message);
  @override
  List<Object?> get props => [message];
}