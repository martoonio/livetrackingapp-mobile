import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/survey.dart'; // Pastikan path ini benar
import '../../domain/repositories/survey_repository.dart'; // Pastikan ini diimpor

// Events
abstract class SurveyEvent {}

class LoadActiveSurveys extends SurveyEvent {}

class LoadSurveyById extends SurveyEvent {
  final String surveyId;

  LoadSurveyById(this.surveyId);
}

class CreateSurvey extends SurveyEvent {
  final Survey survey;

  CreateSurvey(this.survey);
}

class UpdateSurvey extends SurveyEvent {
  final Survey survey;

  UpdateSurvey(this.survey);
}

class DeleteSurvey extends SurveyEvent {
  final String surveyId;

  DeleteSurvey(this.surveyId);
}

class SubmitSurveyResponse extends SurveyEvent {
  final SurveyResponse response;

  SubmitSurveyResponse(this.response);
}

class LoadSurveyResponses extends SurveyEvent {
  final String surveyId;

  LoadSurveyResponses(this.surveyId);
}

class CheckUserCompletedSurvey extends SurveyEvent {
  final String surveyId;
  final String userId;
  final bool isSilent; // Flag untuk pengecekan silent

  CheckUserCompletedSurvey(
    this.surveyId,
    this.userId, {
    this.isSilent = false,
  });

  @override
  List<Object> get props => [surveyId, userId, isSilent];
}

// Tambahkan event
class LoadUserSurveyResponse extends SurveyEvent {
  final String surveyId;
  final String userId;

  LoadUserSurveyResponse(this.surveyId, this.userId);

  @override
  List<Object> get props => [surveyId, userId];
}

// States
abstract class SurveyState {}

class SurveyInitial extends SurveyState {}

class SurveyLoading extends SurveyState {}

class ActiveSurveysLoaded extends SurveyState {
  final List<Survey> surveys;

  ActiveSurveysLoaded(this.surveys);
}

class SurveyLoaded extends SurveyState {
  final Survey survey;

  SurveyLoaded(this.survey);
}

class SurveyResponseSubmitted extends SurveyState {}

class SurveyResponsesLoaded extends SurveyState {
  final List<SurveyResponse> responses;

  SurveyResponsesLoaded(this.responses);
}

class UserCompletedSurveyChecked extends SurveyState {
  final String surveyId;
  final bool hasCompleted;
  final bool isSilent; // Flag untuk pengecekan silent

  UserCompletedSurveyChecked({
    required this.surveyId,
    required this.hasCompleted,
    this.isSilent = false,
  });

  @override
  List<Object> get props => [surveyId, hasCompleted, isSilent];
}

// Tambahkan state
class UserSurveyResponseLoaded extends SurveyState {
  final SurveyResponse response;

  UserSurveyResponseLoaded(this.response);

  @override
  List<Object> get props => [response];
}

class SurveyError extends SurveyState {
  final String message;

  SurveyError(this.message);
}

class SurveyCreated extends SurveyState {}

class SurveyUpdated extends SurveyState {}

class SurveyDeleted extends SurveyState {}

// BLoC
class SurveyBloc extends Bloc<SurveyEvent, SurveyState> {
  final SurveyRepository repository;

  SurveyBloc({required this.repository}) : super(SurveyInitial()) {
    on<LoadActiveSurveys>(_onLoadActiveSurveys);
    on<LoadSurveyById>(_onLoadSurveyById);
    on<CreateSurvey>(_onCreateSurvey);
    on<UpdateSurvey>(_onUpdateSurvey);
    on<DeleteSurvey>(_onDeleteSurvey);
    on<SubmitSurveyResponse>(_onSubmitSurveyResponse);
    on<LoadSurveyResponses>(_onLoadSurveyResponses);
    on<CheckUserCompletedSurvey>(_onCheckUserCompletedSurvey);
    on<LoadUserSurveyResponse>(_onLoadUserSurveyResponse);
  }

  Future<void> _onLoadActiveSurveys(
    LoadActiveSurveys event,
    Emitter<SurveyState> emit,
  ) async {
    emit(SurveyLoading());
    try {
      final surveys = await repository.getActiveSurveys();
      emit(ActiveSurveysLoaded(surveys));
    } catch (e) {
      print('BLoC error loading surveys: $e');
      emit(SurveyError('Gagal memuat survei: ${e.toString()}'));
    }
  }

  Future<void> _onLoadSurveyById(
    LoadSurveyById event,
    Emitter<SurveyState> emit,
  ) async {
    emit(SurveyLoading());
    try {
      final survey = await repository.getSurveyById(event.surveyId);
      emit(SurveyLoaded(survey));
    } catch (e) {
      print('BLoC error loading survey by ID: $e');
      emit(SurveyError('Gagal memuat detail survei: ${e.toString()}'));
    }
  }

  Future<void> _onCreateSurvey(
    CreateSurvey event,
    Emitter<SurveyState> emit,
  ) async {
    emit(SurveyLoading());
    try {
      print('BLoC: Creating survey: ${event.survey.title}');
      await repository.createSurvey(event.survey);
      print('BLoC: Survey created successfully');
      emit(SurveyCreated());
    } catch (e) {
      print('BLoC error creating survey: $e');
      emit(SurveyError('Gagal membuat survei: ${e.toString()}'));
    }
  }

  Future<void> _onUpdateSurvey(
    UpdateSurvey event,
    Emitter<SurveyState> emit,
  ) async {
    emit(SurveyLoading());
    try {
      await repository.updateSurvey(event.survey);
      emit(SurveyUpdated());

      // Reload the surveys to reflect changes
      add(LoadActiveSurveys());
    } catch (e) {
      print('BLoC error updating survey: $e');
      emit(SurveyError('Gagal memperbarui survei: ${e.toString()}'));
    }
  }

  Future<void> _onDeleteSurvey(
    DeleteSurvey event,
    Emitter<SurveyState> emit,
  ) async {
    emit(SurveyLoading());
    try {
      await repository.deleteSurvey(event.surveyId);
      emit(SurveyDeleted());

      // Reload the surveys to reflect changes
      add(LoadActiveSurveys());
    } catch (e) {
      print('BLoC error deleting survey: $e');
      emit(SurveyError('Gagal menghapus survei: ${e.toString()}'));
    }
  }

  Future<void> _onSubmitSurveyResponse(
    SubmitSurveyResponse event,
    Emitter<SurveyState> emit,
  ) async {
    emit(SurveyLoading());
    try {
      await repository.submitSurveyResponse(event.response);
      emit(SurveyResponseSubmitted());
    } catch (e) {
      print('BLoC error submitting survey response: $e');
      emit(SurveyError('Gagal mengirim tanggapan survei: ${e.toString()}'));
    }
  }

  Future<void> _onLoadSurveyResponses(
    LoadSurveyResponses event,
    Emitter<SurveyState> emit,
  ) async {
    emit(SurveyLoading());
    try {
      final responses = await repository.getSurveyResponses(event.surveyId);
      emit(SurveyResponsesLoaded(responses));
    } catch (e) {
      print('BLoC error loading survey responses: $e');
      emit(SurveyError('Gagal memuat tanggapan survei: ${e.toString()}'));
    }
  }

  Future<void> _onCheckUserCompletedSurvey(
    CheckUserCompletedSurvey event,
    Emitter<SurveyState> emit,
  ) async {
    // Tambahkan log untuk melacak panggilan
    print(
        'Starting check for survey: ${event.surveyId}, user: ${event.userId}, silent: ${event.isSilent}');

    // Hanya emit loading state jika bukan silent check
    if (!event.isSilent) {
      emit(SurveyLoading());
    }

    try {
      final hasCompleted = await repository.hasUserCompletedSurvey(
        event.surveyId,
        event.userId,
      );

      print(
          'Check result for survey ${event.surveyId}: ${hasCompleted ? "completed" : "not completed"}');

      // Selalu emit hasil check, baik silent atau tidak
      emit(UserCompletedSurveyChecked(
        surveyId: event.surveyId,
        hasCompleted: hasCompleted,
        isSilent: event.isSilent,
      ));
    } catch (e) {
      print('Error checking survey completion: $e');

      // Hanya emit error jika bukan silent check
      if (!event.isSilent) {
        emit(SurveyError('Gagal memeriksa status survey: ${e.toString()}'));
      } else {
        // Untuk silent check, masih emit hasil dengan hasCompleted = false
        // agar UI masih bisa update meskipun ada error
        emit(UserCompletedSurveyChecked(
          surveyId: event.surveyId,
          hasCompleted: false,
          isSilent: true,
        ));
      }
    }
  }

  // Tambahkan handler
  Future<void> _onLoadUserSurveyResponse(
    LoadUserSurveyResponse event,
    Emitter<SurveyState> emit,
  ) async {
    emit(SurveyLoading());
    try {
      final response = await repository.getUserSurveyResponse(
        event.surveyId,
        event.userId,
      );
      emit(UserSurveyResponseLoaded(response!));
    } catch (e) {
      emit(SurveyError(e.toString()));
    }
  }
}
