// import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../domain/entities/patrol_task.dart';
import '../../domain/repositories/route_repository.dart';
import '../../domain/entities/user.dart' as UserModel;

class RouteRepositoryImpl implements RouteRepository {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  RouteRepositoryImpl();

  Future<void> _checkAuth() async {
    if (_auth.currentUser == null) {
      throw Exception('Not authenticated');
    }
  }

  @override
  Future<PatrolTask?> getCurrentTask(String userId) async {
    // await _checkAuth();
    final snapshot = await _database
        .child('tasks')
        .orderByChild('userId')
        .equalTo(userId)
        .get();

    if (!snapshot.exists) return null;

    final tasks = Map<String, dynamic>.from(snapshot.value as Map);
    final activeTask = tasks.values.firstWhere(
      (task) =>
          task['status'] == 'active' ||
          task['status'] == 'ongoing' ||
          task['status'] == 'in_progress',
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
    try {
      print('=== UPDATE PATROL LOCATION ===');
      print('TaskID: $taskId');
      print('Coordinates: $coordinates');
      print('Timestamp: $timestamp');

      await _checkAuth();
      final user = _auth.currentUser;
      print('Authenticated as: ${user?.uid}');

      final taskRef = _database.child('tasks').child(taskId);

      // Verify task exists
      final taskSnapshot = await taskRef.get();
      if (!taskSnapshot.exists) {
        throw Exception('Task not found: $taskId');
      }
      print('Task found in database');

      // Create timestamp key
      final timestampKey = timestamp.millisecondsSinceEpoch.toString();

      // Update route_path
      await taskRef
          .child('route_path')
          .child(timestampKey)
          .set({
            'coordinates': coordinates,
            'timestamp': timestamp.toIso8601String(),
          })
          .then((_) => print('route_path updated successfully'))
          .catchError((error) => print('Error updating route_path: $error'));

      // Update lastLocation
      await taskRef
          .child('lastLocation')
          .set({
            'coordinates': coordinates,
            'timestamp': timestamp.toIso8601String(),
          })
          .then((_) => print('lastLocation updated successfully'))
          .catchError((error) => print('Error updating lastLocation: $error'));

      print('=== UPDATE COMPLETE ===');
    } catch (e, stackTrace) {
      print('=== UPDATE FAILED ===');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      throw Exception('Failed to update location: $e');
    }
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

        // Find active or ongoing task
        MapEntry<dynamic, dynamic>? activeTaskEntry;
        try {
          activeTaskEntry = tasksMap.entries.firstWhere(
            (entry) {
              final task = entry.value as Map<dynamic, dynamic>;
              final status = task['status']?.toString();
              return status == 'active' ||
                  status == 'ongoing' ||
                  status == 'in_progress';
            },
          );
        } catch (e) {
          activeTaskEntry = null;
        }

        if (activeTaskEntry == null) {
          print('No active/ongoing task found');
          return null;
        }

        // Log assigned start/end times for debugging
        final taskData = activeTaskEntry.value as Map<dynamic, dynamic>;
        print('Task assigned start time: ${taskData['assignedStartTime']}');
        print('Task assigned end time: ${taskData['assignedEndTime']}');


        // Create PatrolTask with the task data
        return _convertToPatrolTask({
          ...taskData,
          'taskId': activeTaskEntry.key,
        });
      } catch (e, stackTrace) {
        print('Error processing tasks: $e');
        print('Stack trace: $stackTrace');
        return null;
      }
    }).handleError((error) {
      print('Error in task stream: $error');
      return null;
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

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    try {
      if (value is String) {
        // Handle string with microseconds
        if (value.contains('.')) {
          final parts = value.split('.');
          final mainPart = parts[0];
          final microPart = parts[1];

          // Limit microseconds to 6 digits
          final cleanMicroPart =
              microPart.length > 6 ? microPart.substring(0, 6) : microPart;

          return DateTime.parse('$mainPart.$cleanMicroPart');
        }
        return DateTime.parse(value);
      } else if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
    } catch (e) {
      print('Error parsing datetime: $value, error: $e');
    }
    return null;
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
        distance: data['distance'] != null
            ? (data['distance'] as num).toDouble()
            : null,
        routePath: data['route_path'] != null
            ? Map<String, dynamic>.from(data['route_path'] as Map)
            : null,
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
        startTime: _parseDateTime(data['startTime']),
        endTime: _parseDateTime(data['endTime']),
        assignedStartTime: _parseDateTime(data['assignedStartTime']),
        assignedEndTime: _parseDateTime(data['assignedEndTime']),
      );
    } catch (e, stackTrace) {
      print('Error converting task: $e'); // Debug print
      print('Stack trace: $stackTrace');

      // Return a default task instead of rethrowing
      return PatrolTask(
        taskId: data['taskId']?.toString() ?? '',
        userId: data['userId']?.toString() ?? '',
        vehicleId: data['vehicleId']?.toString() ?? '',
        assignedStartTime: data['assignedStartTime'] != null
            ? _parseDateTime(data['assignedStartTime'])
            : null,
        assignedEndTime: data['assignedEndTime'] != null
            ? _parseDateTime(data['assignedEndTime'])
            : null,
        status: 'error',
        createdAt: DateTime.now(),
      );
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

      // Format any DateTime objects in updates to ISO format
      final formattedUpdates = Map<String, dynamic>.from(updates);
      for (final key in formattedUpdates.keys) {
        final value = formattedUpdates[key];
        if (value is DateTime) {
          formattedUpdates[key] = value.toIso8601String();
        }
      }

      // Update task with new data
      await _database.child('tasks').child(taskId).update(formattedUpdates);

      print('Task updated successfully'); // Debug print
    } catch (e, stackTrace) {
      print('Error updating task: $e'); // Debug print
      print('Stack trace: $stackTrace');
      throw Exception('Failed to update task: $e');
    }
  }

  // Add these methods after the existing ones
  @override
  Future<void> createTask({
    required String vehicleId,
    required List<List<double>> assignedRoute,
    required String? assignedOfficerId,
    required DateTime? assignedStartTime,
    required DateTime? assignedEndTime,
  }) async {
    try {
      await _checkAuth();
      final taskRef = _database.child('tasks').push();

      final newTask = {
        'taskId': taskRef.key,
        'vehicleId': vehicleId,
        'userId': assignedOfficerId,
        'assigned_route': assignedRoute,
        'assignedStartTime': assignedStartTime != null
            ? DateTime(
                DateTime.now().year,
                DateTime.now().month,
                DateTime.now().day,
                assignedStartTime.hour,
                assignedStartTime.minute,
              ).toIso8601String()
            : null,
        'assignedEndTime': assignedEndTime != null
            ? DateTime(
                DateTime.now().year,
                DateTime.now().month,
                DateTime.now().day,
                assignedEndTime.hour,
                assignedEndTime.minute,
              ).toIso8601String()
            : null,
        'status': 'active',
        'createdAt': DateTime.now().toIso8601String(),
        'route_path': null,
        'lastLocation': null,
      };

      await taskRef.set(newTask);
      print('New task created with ID: ${taskRef.key}');
    } catch (e) {
      print('Error creating task: $e');
      throw Exception('Failed to create task: $e');
    }
  }

  @override
  Future<List<PatrolTask>> getAllTasks() async {
    try {
      await _checkAuth();
      final snapshot = await _database.child('tasks').get();

      if (!snapshot.exists) {
        return [];
      }

      final tasksMap = Map<String, dynamic>.from(snapshot.value as Map);
      final tasks = tasksMap.entries.map((entry) {
        return _convertToPatrolTask({
          ...entry.value as Map<dynamic, dynamic>,
          'taskId': entry.key,
        });
      }).toList();

      // Sort by creation date, most recent first
      tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      print('Retrieved ${tasks.length} tasks');
      return tasks;
    } catch (e) {
      print('Error getting all tasks: $e');
      throw Exception('Failed to get tasks: $e');
    }
  }

  @override
  Future<List<UserModel.User>> getAllOfficers() async {
    try {
      await _checkAuth();
      final snapshot = await _database
          .child('users')
          .orderByChild('role')
          .equalTo('Officer')
          .get();

      if (!snapshot.exists) {
        return [];
      }

      final usersMap = Map<String, dynamic>.from(snapshot.value as Map);
      final officers = usersMap.entries.map((entry) {
        final userData = entry.value as Map<dynamic, dynamic>;
        return UserModel.User(
          id: entry.key,
          name: userData['name']?.toString() ?? '',
          email: userData['email']?.toString() ?? '',
          role: userData['role']?.toString() ?? 'officer',
        );
      }).toList();

      print('Retrieved ${officers.length} officers');
      return officers;
    } catch (e) {
      print('Error getting officers: $e');
      throw Exception('Failed to get officers: $e');
    }
  }

  @override
  Future<List<String>> getAllVehicles() async {
    try {
      await _checkAuth();
      final snapshot = await _database.child('vehicle').get();

      if (!snapshot.exists) {
        print('No vehicles found in database');
        return [];
      }

      final value = snapshot.value;
      print('Raw vehicle data type: ${value.runtimeType}');
      print('Raw vehicle data: $value');

      if (value is List) {
        // Handle list format
        return value
            .whereType<String>()
            .where((item) => item.isNotEmpty)
            .toList();
      } else if (value is Map) {
        // Handle map format
        return value.values
            .where((item) => item != null)
            .map((item) => item.toString())
            .toList();
      }

      print('Unexpected data format for vehicles');
      return [];
    } catch (e) {
      print('Error getting vehicles: $e');
      throw Exception('Failed to get vehicles: $e');
    }
  }
}
