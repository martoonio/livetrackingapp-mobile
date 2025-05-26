import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/usecases/report_usecase.dart';
import '../../../domain/entities/report.dart';
import 'report_event.dart';
import 'report_state.dart';

class ReportBloc extends Bloc<ReportEvent, ReportState> {
  final CreateReportUseCase createReportUseCase;
  final SyncOfflineReportsUseCase syncOfflineReportsUseCase;
  final GetOfflineReportsUseCase getOfflineReportsUseCase;

  ReportBloc({
    required this.createReportUseCase,
    required this.syncOfflineReportsUseCase,
    required this.getOfflineReportsUseCase,
  }) : super(ReportInitial()) {
    on<CreateReportEvent>(_onCreateReport);
    on<SyncOfflineReportsEvent>(_onSyncOfflineReports);
    on<GetOfflineReportsEvent>(_onGetOfflineReports);
  }

  Future<bool> _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<void> _onCreateReport(
      CreateReportEvent event, Emitter<ReportState> emit) async {
    try {
      // Cek koneksi internet
      final isConnected = await _checkConnectivity();

      // Emit loading state sesuai status koneksi
      emit(ReportLoading(isOfflineMode: !isConnected));

      // Beri sedikit delay untuk UI
      await Future.delayed(const Duration(milliseconds: 100));

      // Panggil use case untuk membuat report
      await createReportUseCase(event.report);

      // Emit success state dengan flag yang menunjukkan mode offline
      emit(ReportSuccess(isSavedOffline: !isConnected));
    } catch (e) {
      print('Error in ReportBloc: $e');
      emit(ReportFailure(e.toString()));
    }
  }

  Future<void> _onSyncOfflineReports(
    SyncOfflineReportsEvent event,
    Emitter<ReportState> emit,
  ) async {
    try {
      // Cek koneksi internet
      final isConnected = await _checkConnectivity();
      if (!isConnected) {
        emit(SyncFailure('Tidak ada koneksi internet'));
        return;
      }

      // Dapatkan laporan offline
      final offlineReports = await getOfflineReportsUseCase();

      if (offlineReports.isEmpty) {
        emit(SyncSuccess());
        return;
      }

      emit(SyncInProgress(total: offlineReports.length, current: 0));

      // Sinkronkan laporan offline
      await syncOfflineReportsUseCase();

      emit(SyncSuccess());
    } catch (e) {
      print('Error syncing offline reports: $e');
      emit(SyncFailure(e.toString()));
    }
  }

  Future<void> _onGetOfflineReports(
    GetOfflineReportsEvent event,
    Emitter<ReportState> emit,
  ) async {
    try {
      emit(ReportLoading());

      // Dapatkan laporan offline
      final offlineReports = await getOfflineReportsUseCase();

      emit(OfflineReportsLoaded(offlineReports));
    } catch (e) {
      print('Error getting offline reports: $e');
      emit(ReportFailure(e.toString()));
    }
  }
}
