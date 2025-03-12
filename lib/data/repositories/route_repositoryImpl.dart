import 'package:firebase_database/firebase_database.dart';
import '../../domain/entities/patrol_task.dart';
import '../../domain/repositories/route_repository.dart';
import '../source/mapbox_service.dart';

class RouteRepositoryImpl implements RouteRepository {
  final MapboxService mapboxService;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  RouteRepositoryImpl({
    required this.mapboxService,
  });

  @override
  Future<PatrolTask?> getCurrentTask(String userId) async {
    final snapshot = await _database
        .child('tasks')
        .orderByChild('userId')
        .equalTo(userId)
        .get();

    if (!snapshot.exists) return null;

    final tasks = Map<String, dynamic>.from(snapshot.value as Map);
    final activeTask = tasks.values.firstWhere(
      (task) => task['status'] == 'active' || task['status'] == 'ongoing',
      orElse: () => null,
    );

    if (activeTask == null) return null;

    return _convertToPatrolTask(activeTask);
  }

  @override
  Future<void> updateTaskStatus(String taskId, String status) async {
    await _database.child('tasks').child(taskId).update({
      'status': status,
    });
  }

  @override
  Future<void> updatePatrolLocation(
    String taskId,
    List<double> coordinates,
    DateTime timestamp,
  ) async {
    final taskRef = _database.child('tasks').child(taskId);

    // Add new coordinates to route_path
    await taskRef.child('route_path').push().set({
      'coordinates': coordinates,
      'timestamp': timestamp.toIso8601String(),
    });

    // Update last known location
    await taskRef.child('lastLocation').set({
      'coordinates': coordinates,
      'timestamp': timestamp.toIso8601String(),
    });
  }

  @override
  Future<List<PatrolTask>> getFinishedTasks(String userId) async {
    try {
      print('Getting finished tasks for user: $userId'); // Debug print

      final snapshot = await _database
          .child('tasks')
          .orderByChild('userId')
          .equalTo(userId)
          .get();

      if (!snapshot.exists) {
        print('No tasks found for user');
        return [];
      }

      final tasks = Map<String, dynamic>.from(snapshot.value as Map);
      final finishedTasks = tasks.entries
          .where((entry) => (entry.value as Map)['status'] == 'finished')
          .map((entry) => _convertToPatrolTask({
                ...entry.value as Map<dynamic, dynamic>,
                'taskId': entry.key,
              }))
          .toList();

      // Sort by end time, most recent first
      finishedTasks.sort((a, b) =>
          (b.endTime ?? DateTime.now()).compareTo(a.endTime ?? DateTime.now()));

      print('Found ${finishedTasks.length} finished tasks'); // Debug print
      return finishedTasks;
    } catch (e) {
      print('Error getting finished tasks: $e'); // Debug print
      throw Exception('Failed to get finished tasks: $e');
    }
  }

// Update watchCurrentTask to handle in_progress status
  @override
  Stream<PatrolTask?> watchCurrentTask(String userId) {
    print('Watching tasks for user: $userId'); // Debug print

    return _database
        .child('tasks')
        .orderByChild('userId')
        .equalTo(userId)
        .onValue
        .map((event) {
      if (!event.snapshot.exists) {
        print('No tasks found');
        return null;
      }

      try {
        final tasksMap = event.snapshot.value as Map<dynamic, dynamic>;
        print('Tasks data: $tasksMap');

        // Find active or in_progress task
        MapEntry<dynamic, dynamic>? activeTaskEntry;
        try {
          activeTaskEntry = tasksMap.entries.firstWhere(
            (entry) {
              final task = entry.value as Map<dynamic, dynamic>;
              final status = task['status']?.toString();
              return status == 'active' || status == 'in_progress';
            },
          );
        } catch (e) {
          activeTaskEntry = null;
        }

        if (activeTaskEntry == null) {
          print('No active/in-progress task found');
          return null;
        }

        print(
            'Found task: ${activeTaskEntry.key} with status: ${(activeTaskEntry.value as Map)['status']}');
        return _convertToPatrolTask({
          ...activeTaskEntry.value as Map<dynamic, dynamic>,
          'taskId': activeTaskEntry.key,
        });
      } catch (e) {
        print('Error processing tasks: $e');
        return null;
      }
    });
  }

  @override
  Stream<List<PatrolTask>> watchFinishedTasks(String userId) {
    return _database
        .child('tasks')
        .orderByChild('userId')
        .equalTo(userId)
        .onValue
        .map((event) {
      if (!event.snapshot.exists) {
        return [];
      }

      try {
        final tasksMap = event.snapshot.value as Map<dynamic, dynamic>;
        final finishedTasks = tasksMap.entries
            .where((entry) => (entry.value as Map)['status'] == 'finished')
            .map((entry) => _convertToPatrolTask({
                  ...entry.value as Map<dynamic, dynamic>,
                  'taskId': entry.key,
                }))
            .toList();

        // Sort by end time, most recent first
        finishedTasks.sort((a, b) => (b.endTime ?? DateTime.now())
            .compareTo(a.endTime ?? DateTime.now()));

        return finishedTasks;
      } catch (e) {
        print('Error processing finished tasks: $e');
        return [];
      }
    });
  }

  PatrolTask _convertToPatrolTask(Map<dynamic, dynamic> data) {
    print('Converting data: $data'); // Debug print
    try {
      return PatrolTask(
        taskId: data['taskId']?.toString() ?? '',
        userId: data['userId']?.toString() ?? '',
        vehicleId: data['vehicleId']?.toString() ?? '',
        assignedRoute: data['assigned_route'] != null
            ? (data['assigned_route'] as List)
                .map((point) => (point as List)
                    .map((coord) => (coord as num).toDouble())
                    .toList())
                .toList()
            : null,
        status: data['status']?.toString() ?? 'active',
        routePath: data['route_path'] != null
            ? Map<String, dynamic>.from(data['route_path'] as Map)
            : null,
        createdAt: data['createdAt'] != null
            ? DateTime.parse(data['createdAt'].toString())
            : DateTime.now(),
        startTime: data['startTime'] != null
            ? DateTime.parse(data['startTime'].toString())
            : null,
        endTime: data['endTime'] != null
            ? DateTime.parse(data['endTime'].toString())
            : null,
      );
    } catch (e) {
      print('Error converting task: $e'); // Debug print
      rethrow;
    }
  }

  @override
  Future<void> updateTask(String taskId, Map<String, dynamic> updates) async {
    try {
      print('Updating task $taskId with: $updates'); // Debug print

      // Get current task data first
      final taskSnapshot = await _database.child('tasks').child(taskId).get();

      if (!taskSnapshot.exists) {
        throw Exception('Task not found');
      }

      // Update task with new data
      await _database.child('tasks').child(taskId).update(updates);

      print('Task updated successfully'); // Debug print
    } catch (e) {
      print('Error updating task: $e'); // Debug print
      throw Exception('Failed to update task: $e');
    }
  }
}
