import 'package:livetrackingapp/domain/entities/report.dart';

abstract class ReportState {}

class ReportInitial extends ReportState {}

class ReportLoading extends ReportState {
  final double? progress; // Opsional, jika ingin menampilkan progress upload
  final bool isOfflineMode;

  ReportLoading({this.progress, this.isOfflineMode = false});
}

class ReportSuccess extends ReportState {
  final bool isSavedOffline;
  
  ReportSuccess({this.isSavedOffline = false});
}

class ReportFailure extends ReportState {
  final String error;
  final bool isSavedOffline;

  ReportFailure(this.error, {this.isSavedOffline = false});
}

class OfflineReportsLoaded extends ReportState {
  final List<Report> reports;
  
  OfflineReportsLoaded(this.reports);
}

class SyncInProgress extends ReportState {
  final int total;
  final int current;
  
  SyncInProgress({required this.total, required this.current});
}

class SyncSuccess extends ReportState {}

class SyncFailure extends ReportState {
  final String error;
  
  SyncFailure(this.error);
}
