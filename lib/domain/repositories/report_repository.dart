import '../entities/report.dart';

abstract class ReportRepository {
  Future<void> createReport(Report report);
}