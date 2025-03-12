import '../entities/patrol_task.dart';

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
}