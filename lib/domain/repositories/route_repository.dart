import '../entities/patrol_task.dart';
import '../entities/user.dart';

abstract class RouteRepository {
  Future<PatrolTask?> getCurrentTask(String userId);
  Future<void> updateTaskStatus(String taskId, String status);
  Future<void> updatePatrolLocation(
    String taskId,
    List<double> coordinates,
    DateTime timestamp,
  );
  Stream<PatrolTask?> watchCurrentTask(String userId);
  Future<void> updateTask(String taskId, Map<String, dynamic> updates);
  Future<List<PatrolTask>> getFinishedTasks(String userId);
  Stream<List<PatrolTask>> watchFinishedTasks(String userId);
  Future<List<PatrolTask>> getAllTasks();
  Future<List<User>> getAllOfficers();
  Future<List<String>> getAllVehicles();
  Future<void> createTask({
    required String vehicleId,
    required List<List<double>> assignedRoute,
    required String? assignedOfficerId,
  });
}