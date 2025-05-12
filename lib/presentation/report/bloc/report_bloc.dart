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
        await createReportUseCase(event.report);
        emit(ReportSuccess());
      } catch (e) {
        emit(ReportFailure(e.toString()));
      }
    });
  }
}