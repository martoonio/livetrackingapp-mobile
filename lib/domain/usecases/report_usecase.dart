import '../entities/report.dart';
import '../repositories/report_repository.dart';

class CreateReportUseCase {
  final ReportRepository repository;

  CreateReportUseCase(this.repository);

  Future<void> call(Report report) async {
    await repository.createReport(report);
  }
}

// Tambahkan UseCase baru untuk sinkronisasi
class SyncOfflineReportsUseCase {
  final ReportRepository repository;

  SyncOfflineReportsUseCase(this.repository);

  Future<void> call() async {
    await repository.syncOfflineReports();
  }
}

// UseCase untuk mendapatkan laporan offline
class GetOfflineReportsUseCase {
  final ReportRepository repository;

  GetOfflineReportsUseCase(this.repository);

  Future<List<Report>> call() async {
    return await repository.getOfflineReports();
  }
}