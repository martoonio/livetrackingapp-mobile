import '../entities/patrol_task.dart';
import '../entities/user.dart';

abstract class RouteRepository {
  // ---------------------------------------------
  // PATROL TASK MANAGEMENT
  // ---------------------------------------------

  // Get current active task for a user
  Future<PatrolTask?> getCurrentTask(String userId);

  // Update task status (active, ongoing, finished, etc)
  Future<void> updateTaskStatus(String taskId, String status);

  // Update patrol location in real-time
  Future<void> updatePatrolLocation(
    String taskId,
    List<double> coordinates,
    DateTime timestamp,
  );

  // Watch for changes in current task
  Stream<PatrolTask?> watchCurrentTask(String userId);

  // Update any task field
  Future<void> updateTask(String taskId, Map<String, dynamic> updates);

  // Get all finished tasks for a user
  Future<List<PatrolTask>> getFinishedTasks(String userId);

  // Watch for changes in finished tasks
  Stream<List<PatrolTask>> watchFinishedTasks(String userId);

  // PERBAIKAN: Tambahkan method yang hilang
  Future<List<PatrolTask>> getAllTasks();

  // PERBAIKAN: Tambahkan method untuk pagination
  Future<List<PatrolTask>> getRecentTasks({
    int limit = 50,
    String? lastKey,
  });

  Future<List<PatrolTask>> getAllClusterTasks(String clusterId);

  Future<List<PatrolTask>> getActiveAndCancelledTasks(String clusterId,
      {int limit = 20});

  // PERBAIKAN: Tambahkan method untuk query optimized
  Future<List<PatrolTask>> getActiveTasks({int limit = 50});

  Future<List<PatrolTask>> getOngoingTasks({int limit = 50});

  Future<List<PatrolTask>> getTasksByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    String? status,
    String? clusterId,
    int limit = 50,
    String? lastKey,
  });

  // Create new task
  Future<String> createTask({
    required String clusterId,
    required String vehicleId,
    required List<List<double>> assignedRoute,
    required String? assignedOfficerId,
    required DateTime? assignedStartTime,
    required DateTime? assignedEndTime,
    required String? officerName,
    required String? clusterName,
  });

  // Get tasks for a specific cluster
  Future<List<PatrolTask>> getClusterTasks(
    String clusterId, {
    int limit = 50,
    String? status,
    String? lastKey,
  });

  // ---------------------------------------------
  // USER & OFFICER MANAGEMENT
  // ---------------------------------------------

  // Get all available vehicles
  Future<List<String>> getAllVehicles();

  // ---------------------------------------------
  // CLUSTER MANAGEMENT
  // ---------------------------------------------

  // Get all clusters
  Future<List<User>> getAllClusters();

  // Get a specific cluster by ID
  Future<User> getClusterById(String clusterId);

  // Get current user's cluster
  Future<User?> getCurrentUserCluster();

  // Search clusters by name
  Future<List<User>> searchClustersByName(String searchTerm);

  // Create a new cluster account
  Future<void> createClusterAccount({
    required String name,
    required String email,
    required String password,
    required String role,
    required List<List<double>> clusterCoordinates,
  });

  // Update cluster
  Future<void> updateCluster({
    required String clusterId,
    required Map<String, dynamic> updates,
  });

  // Update cluster coordinates
  Future<void> updateClusterCoordinates({
    required String clusterId,
    required List<List<double>> coordinates,
  });

  // Delete a cluster
  Future<void> deleteCluster(String clusterId);

  // ---------------------------------------------
  // OFFICER MANAGEMENT WITHIN CLUSTERS
  // ---------------------------------------------

  // Get all officers in a cluster
  Future<List<Officer>> getClusterOfficers(String clusterId);

  // Add an officer to a cluster
  Future<void> addOfficerToCluster({
    required String clusterId,
    required Officer officer,
  });

  // Update an officer in a cluster
  Future<void> updateOfficerInCluster({
    required String clusterId,
    required Officer officer,
  });

  // Remove an officer from a cluster
  Future<void> removeOfficerFromCluster({
    required String clusterId,
    required String officerId,
  });

  Future<PatrolTask?> getTaskById({
    required String taskId,
  });

  Future<void> logMockLocationDetection({
    required String taskId,
    required String userId,
    required Map<String, dynamic> mockData,
  });

  Future<List<Map<String, dynamic>>> getMockLocationDetections(String taskId);

  Future<int> getMockLocationCount(String taskId);
}
