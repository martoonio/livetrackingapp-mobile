import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../domain/usecases/report_usecase.dart';
import 'report_event.dart';
import 'report_state.dart';

class ReportBloc extends Bloc<ReportEvent, ReportState> {
  final CreateReportUseCase createReportUseCase;

  ReportBloc(this.createReportUseCase) : super(ReportInitial()) {
    on<CreateReportEvent>((event, emit) async {
      emit(ReportLoading());
      try {
        // Tambahkan delay kecil untuk memastikan UI merender status loading
        await Future.delayed(const Duration(milliseconds: 100));

        // Panggil use case untuk membuat report
        await createReportUseCase(event.report);

        // Tentukan jeda sebelum emitting success state
        // untuk memastikan UI loading ditampilkan cukup lama
        await Future.delayed(const Duration(milliseconds: 300));

        // Emit success state
        emit(ReportSuccess());
      } catch (e) {
        print('Error in ReportBloc: $e');
        emit(ReportFailure(e.toString()));
      }
    });
  }
}
