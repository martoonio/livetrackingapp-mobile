import '../entities/report.dart';

abstract class ReportRepository {
  Future<void> createReport(Report report);
  Future<void> saveOfflineReport(Report report);
  Future<List<Report>> getOfflineReports();
  Future<void> syncOfflineReports();
  Future<void> deleteOfflineReport(String id);
}