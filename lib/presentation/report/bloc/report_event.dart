import 'package:livetrackingapp/domain/entities/report.dart';

abstract class ReportEvent {}

class CreateReportEvent extends ReportEvent {
  final Report report;

  CreateReportEvent(this.report);
}