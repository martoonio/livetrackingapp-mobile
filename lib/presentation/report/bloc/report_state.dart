abstract class ReportState {}

class ReportInitial extends ReportState {}

class ReportLoading extends ReportState {
  final double? progress; // Opsional, jika ingin menampilkan progress upload

  ReportLoading({this.progress});
}

class ReportSuccess extends ReportState {}

class ReportFailure extends ReportState {
  final String error;

  ReportFailure(this.error);
}
