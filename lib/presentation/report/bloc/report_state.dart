abstract class ReportState {}

class ReportInitial extends ReportState {}

class ReportLoading extends ReportState {}

class ReportSuccess extends ReportState {}

class ReportFailure extends ReportState {
  final String error;

  ReportFailure(this.error);
}