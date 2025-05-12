import '../entities/report.dart';
import '../repositories/report_repository.dart';

class CreateReportUseCase {
  final ReportRepository repository;

  CreateReportUseCase(this.repository);

  Future<void> call(Report report) async {
    await repository.createReport(report);
  }
}