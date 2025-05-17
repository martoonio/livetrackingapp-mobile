import 'package:livetrackingapp/domain/entities/cluster.dart';

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
    required String? clusterId,
    required DateTime? assignedStartTime,
    required DateTime? assignedEndTime,
  });
  Future<List<ClusterModel>> getClusters();
  Future<void> createCluster({
    required String name,
    required String description,
    required List<List<double>> clusterCoordinates,
    required String status,
  });
  Future<void> updateCluster({
    required String clusterId,
    required Map<String, dynamic> updates,
  });
}
