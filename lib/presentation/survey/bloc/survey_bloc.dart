import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:livetrackingapp/domain/entities/survey/survey.dart';
import 'package:livetrackingapp/domain/entities/survey/survey_response.dart';
import 'package:livetrackingapp/domain/usecases/survey_usecase.dart';

part 'survey_event.dart';
part 'survey_state.dart';

class SurveyBloc extends Bloc<SurveyEvent, SurveyState> {
  final GetActiveSurveysUseCase _getActiveSurveysUseCase;
  final GetSurveyDetailsUseCase _getSurveyDetailsUseCase;
  final SubmitSurveyResponseUseCase _submitSurveyResponseUseCase;
  final GetAllSurveysUseCase _getAllSurveysUseCase;
  final CreateSurveyUseCase _createSurveyUseCase;
  final UpdateSurveyUseCase _updateSurveyUseCase;
  final DeleteSurveyUseCase _deleteSurveyUseCase;
  final GetSurveyResponsesUseCase _getSurveyResponsesUseCase;
  final GetSurveyResponsesSummaryUseCase _getSurveyResponsesSummaryUseCase;
  final UpdateSurveyStatusUseCase _updateSurveyStatusUseCase;
  final GetUserSurveyResponseUseCase _getUserSurveyResponseUseCase;


  SurveyBloc({
    required GetActiveSurveysUseCase getActiveSurveysUseCase,
    required GetSurveyDetailsUseCase getSurveyDetailsUseCase,
    required SubmitSurveyResponseUseCase submitSurveyResponseUseCase,
    required GetAllSurveysUseCase getAllSurveysUseCase,
    required CreateSurveyUseCase createSurveyUseCase,
    required UpdateSurveyUseCase updateSurveyUseCase,
    required DeleteSurveyUseCase deleteSurveyUseCase,
    required GetSurveyResponsesUseCase getSurveyResponsesUseCase,
    required GetSurveyResponsesSummaryUseCase getSurveyResponsesSummaryUseCase,
    required UpdateSurveyStatusUseCase updateSurveyStatusUseCase,
    required GetUserSurveyResponseUseCase getUserSurveyResponseUseCase,
  })  : _getActiveSurveysUseCase = getActiveSurveysUseCase,
        _getSurveyDetailsUseCase = getSurveyDetailsUseCase,
        _submitSurveyResponseUseCase = submitSurveyResponseUseCase,
        _getAllSurveysUseCase = getAllSurveysUseCase,
        _createSurveyUseCase = createSurveyUseCase,
        _updateSurveyUseCase = updateSurveyUseCase,
        _deleteSurveyUseCase = deleteSurveyUseCase,
        _getSurveyResponsesUseCase = getSurveyResponsesUseCase,
        _getSurveyResponsesSummaryUseCase = getSurveyResponsesSummaryUseCase,
        _updateSurveyStatusUseCase = updateSurveyStatusUseCase,
        _getUserSurveyResponseUseCase = getUserSurveyResponseUseCase,
        super(SurveyInitial()) {
    on<LoadActiveSurveys>(_onLoadActiveSurveys);
    on<LoadSurveyForFilling>(_onLoadSurveyForFilling);
    on<SubmitSurvey>(_onSubmitSurvey);
    on<LoadAllCommandCenterSurveys>(_onLoadAllCommandCenterSurveys);
    on<LoadSurveyForEditing>(_onLoadSurveyForEditing);
    on<SaveSurvey>(_onSaveSurvey);
    on<DeleteSurveyById>(_onDeleteSurveyById);
    on<LoadResultsForSurvey>(_onLoadResultsForSurvey);
    on<ToggleSurveyStatus>(_onToggleSurveyStatus);
  }

  Future<void> _onLoadActiveSurveys(
    LoadActiveSurveys event,
    Emitter<SurveyState> emit,
  ) async {
    emit(const SurveyLoading(message: "Memuat survei aktif..."));
    try {
      final surveys = await _getActiveSurveysUseCase(event.userId, event.userRole, event.clusterId);
      emit(ActiveSurveysLoaded(surveys));
    } catch (e) {
      emit(SurveyError("Gagal memuat survei: ${e.toString()}"));
    }
  }

  Future<void> _onLoadSurveyForFilling(
    LoadSurveyForFilling event,
    Emitter<SurveyState> emit,
  ) async {
    emit(const SurveyLoading(message: "Memuat detail survei..."));
    try {
      final survey = await _getSurveyDetailsUseCase(event.surveyId);
      if (survey == null) {
        emit(const SurveyError("Survei tidak ditemukan."));
        return;
      }
      final existingResponse = await _getUserSurveyResponseUseCase(event.surveyId, event.userId);
      emit(SurveyFormLoaded(survey: survey, existingResponse: existingResponse));
    } catch (e) {
      emit(SurveyError("Gagal memuat detail survei: ${e.toString()}"));
    }
  }

   Future<void> _onLoadSurveyForEditing(
    LoadSurveyForEditing event,
    Emitter<SurveyState> emit,
  ) async {
    emit(const SurveyLoading(message: "Memuat survei untuk diedit..."));
    try {
      final survey = await _getSurveyDetailsUseCase(event.surveyId);
      if (survey == null) {
        emit(const SurveyError("Survei tidak ditemukan."));
        return;
      }
      emit(SurveyEditLoaded(survey));
    } catch (e) {
      emit(SurveyError("Gagal memuat survei untuk diedit: ${e.toString()}"));
    }
  }


  Future<void> _onSubmitSurvey(
    SubmitSurvey event,
    Emitter<SurveyState> emit,
  ) async {
    emit(const SurveyLoading(message: "Mengirim jawaban survei..."));
    try {
      await _submitSurveyResponseUseCase(event.response);
      emit(const SurveyOperationSuccess("Jawaban survei berhasil dikirim."));
    } catch (e) {
      emit(SurveyError("Gagal mengirim jawaban survei: ${e.toString()}"));
    }
  }

  Future<void> _onLoadAllCommandCenterSurveys(
    LoadAllCommandCenterSurveys event,
    Emitter<SurveyState> emit,
  ) async {
    emit(const SurveyLoading(message: "Memuat semua survei..."));
    try {
      final surveys = await _getAllSurveysUseCase(event.commandCenterId);
      emit(CommandCenterSurveysLoaded(surveys));
    } catch (e) {
      emit(SurveyError("Gagal memuat survei: ${e.toString()}"));
    }
  }

  Future<void> _onSaveSurvey(
    SaveSurvey event,
    Emitter<SurveyState> emit,
  ) async {
    emit(SurveyLoading(message: event.isUpdate ? "Memperbarui survei..." : "Menyimpan survei..."));
    try {
      if (event.isUpdate) {
        await _updateSurveyUseCase(event.survey, event.sectionsAndQuestionsData);
        emit(const SurveyOperationSuccess("Survei berhasil diperbarui."));
      } else {
        await _createSurveyUseCase(event.survey, event.sectionsAndQuestionsData);
        emit(const SurveyOperationSuccess("Survei berhasil dibuat."));
      }
      // Mungkin perlu reload daftar survei setelahnya
      // add(LoadAllCommandCenterSurveys(commandCenterId: event.survey.createdBy));
    } catch (e) {
      emit(SurveyError("Gagal menyimpan survei: ${e.toString()}"));
    }
  }

  Future<void> _onDeleteSurveyById(
    DeleteSurveyById event,
    Emitter<SurveyState> emit,
  ) async {
    emit(const SurveyLoading(message: "Menghapus survei..."));
    try {
      await _deleteSurveyUseCase(event.surveyId);
      emit(const SurveyOperationSuccess("Survei berhasil dihapus."));
       // Mungkin perlu reload daftar survei setelahnya
    } catch (e) {
      emit(SurveyError("Gagal menghapus survei: ${e.toString()}"));
    }
  }

  Future<void> _onLoadResultsForSurvey(
    LoadResultsForSurvey event,
    Emitter<SurveyState> emit,
  ) async {
    emit(const SurveyLoading(message: "Memuat hasil survei..."));
    try {
      final survey = await _getSurveyDetailsUseCase(event.surveyId);
      if (survey == null) {
          emit(const SurveyError("Detail survei tidak ditemukan untuk melihat hasil."));
          return;
      }
      final responses = await _getSurveyResponsesUseCase(event.surveyId);
      final summary = await _getSurveyResponsesSummaryUseCase(event.surveyId);
      emit(SurveyResultsLoaded(survey: survey, responses: responses, summary: summary));
    } catch (e) {
      emit(SurveyError("Gagal memuat hasil survei: ${e.toString()}"));
    }
  }

  Future<void> _onToggleSurveyStatus(
    ToggleSurveyStatus event,
    Emitter<SurveyState> emit,
  ) async {
    emit(SurveyLoading(message: event.isActive ? "Mengaktifkan survei..." : "Menonaktifkan survei..."));
    try {
        await _updateSurveyStatusUseCase(event.surveyId, event.isActive);
        emit(SurveyOperationSuccess(event.isActive ? "Survei berhasil diaktifkan." : "Survei berhasil dinonaktifkan."));
        // Reload survey list or details might be needed here
    } catch (e) {
        emit(SurveyError("Gagal mengubah status survei: ${e.toString()}"));
    }
  }
}