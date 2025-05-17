// import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
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
    try {
      print('Getting current task for user: $userId'); // Debug print

      final snapshot = await _database
          .child('tasks')
          .orderByChild('userId')
          .equalTo(userId)
          .get();

      if (!snapshot.exists) {
        print('No tasks found for user $userId');
        return null;
      }

      final tasks = Map<dynamic, dynamic>.from(snapshot.value as Map);
      print('Found tasks: ${tasks.length}');

      // Debugging
      tasks.forEach((key, value) {
        print(
            'Task ID: $key, Status: ${value['status']}, UserId: ${value['userId']}');
      });

      // Try to find active task
      MapEntry<dynamic, dynamic>? activeTaskEntry;
      try {
        activeTaskEntry = tasks.entries.firstWhere(
          (entry) {
            final task = entry.value as Map<dynamic, dynamic>;
            final status = task['status']?.toString();
            return status == 'active' ||
                status == 'ongoing' ||
                status == 'in_progress';
          },
        );

        if (activeTaskEntry != null) {
          print('Found active task with ID: ${activeTaskEntry.key}');
        }
      } catch (e) {
        print('No active task found: $e');
        activeTaskEntry = null;
      }

      if (activeTaskEntry == null) {
        print('No active/ongoing task found for user $userId');
        return null;
      }

      // Create PatrolTask with the task data
      final taskData = activeTaskEntry.value as Map<dynamic, dynamic>;

      // Add officer name to task if possible
      String? officerName;
      try {
        if (taskData['userId'] != null) {
          final officerId = taskData['userId'].toString();
          final clusterId = taskData['clusterId']?.toString();

          if (clusterId != null && clusterId.isNotEmpty) {
            // Try to find officer in cluster's officers list
            final officerSnapshot = await _database
                .child('users/$clusterId/officers')
                .orderByKey() // Use orderByKey for new structure
                .equalTo(officerId)
                .get();

            if (officerSnapshot.exists) {
              final officerData = officerSnapshot.value as Map;
              officerName = officerData[officerId]['name'];
              print('Found officer name: $officerName');
            }
          }
        }
      } catch (e) {
        print('Error getting officer name: $e');
      }

      final task = _convertToPatrolTask({
        ...taskData,
        'taskId': activeTaskEntry.key,
        'officerName': officerName,
      });

      return task;
    } catch (e, stackTrace) {
      print('Error in getCurrentTask: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
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

      // Skip auth check to avoid permission issues
      final user = _auth.currentUser;
      if (user == null) {
        print('Warning: No authenticated user, but continuing');
      } else {
        print('Authenticated as: ${user.uid}');
      }

      final taskRef = _database.child('tasks').child(taskId);

      // Create timestamp key
      final timestampKey = timestamp.millisecondsSinceEpoch.toString();

      // Format data consistently
      final locationData = {
        'coordinates': coordinates,
        'timestamp': timestamp.toIso8601String(),
      };

      // Try direct path first for better performance
      try {
        await taskRef.child('route_path').child(timestampKey).set(locationData);
        print('route_path updated successfully');
      } catch (e) {
        print('Error with direct route_path update: $e');

        // Try alternative approach with update()
        final updates = {
          'route_path/$timestampKey': locationData,
        };
        await taskRef.update(updates);
        print('route_path updated with alternative method');
      }

      // Also update lastLocation
      await taskRef.child('lastLocation').set(locationData);
      print('lastLocation updated successfully');

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
        officerName:
            data['officerName']?.toString(), // Support for officer name
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
        clusterId: data['clusterId'].toString(), // Add clusterId support
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
    required String clusterId,
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
        'clusterId': clusterId,
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

  //Cluster Logic
  // Tambahkan implementasi method-method baru ini ke AdminRepositoryImpl

  @override
  Future<UserModel.User> getClusterById(String clusterId) async {
    try {
      final snapshot = await _database.child('users/$clusterId').get();

      if (!snapshot.exists) {
        throw Exception('Cluster not found');
      }

      final data = snapshot.value as Map<dynamic, dynamic>;
      final userData = Map<String, dynamic>.from(data);
      userData['id'] = clusterId;

      return UserModel.User.fromMap(userData);
    } catch (e) {
      print('Error getting cluster details: $e');
      throw Exception('Failed to get cluster details: $e');
    }
  }

  @override
  Future<void> createClusterAccount({
    required String name,
    required String email,
    required String password,
    required String role,
    required List<List<double>> clusterCoordinates,
  }) async {
    try {
      // Create Firebase Auth account
      final firebaseAuth = FirebaseAuth.instance;
      final userCredential = await firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final userId = userCredential.user!.uid;

      // Create user data in Realtime Database
      final now = DateTime.now().toIso8601String();
      await _database.child('users/$userId').set({
        'name': name,
        'email': email,
        'role': role,
        'cluster_coordinates': clusterCoordinates,
        'officers': [], // Empty officers list initially
        'created_at': now,
        'updated_at': now,
      });

      return;
    } catch (e) {
      print('Error creating cluster account: $e');
      throw Exception('Failed to create cluster account: $e');
    }
  }

  Future<void> updateClusterAccount(UserModel.User cluster) async {
    try {
      final updates = {
        'name': cluster.name,
        'role': cluster.role,
        'cluster_coordinates': cluster.clusterCoordinates,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _database.child('users/${cluster.id}').update(updates);
      return;
    } catch (e) {
      print('Error updating cluster account: $e');
      throw Exception('Failed to update cluster account: $e');
    }
  }

  // Memperbaiki metode addOfficerToCluster untuk menggunakan push().key sebagai ID

  @override
  Future<void> addOfficerToCluster({
    required String clusterId,
    required Officer officer,
  }) async {
    try {
      await _checkAuth();

      // Buat referensi baru untuk officer dengan push()
      final officerRef = _database.child('users/$clusterId/officers').push();

      // Dapatkan key yang dibuat Firebase
      final String officerId = officerRef.key!;

      // Buat officer dengan ID Firebase
      final updatedOfficer = Officer(
        id: officerId,
        name: officer.name,
        shift: officer.shift,
        clusterId: clusterId,
        photoUrl: officer.photoUrl,
      );

      // Simpan officer dengan ID Firebase
      await officerRef.set(updatedOfficer.toMap());

      // Update timestamp cluster
      await _database.child('users/$clusterId').update({
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': _auth.currentUser?.uid,
      });

      print('Officer added to cluster with Firebase ID: $officerId');
      return;
    } catch (e) {
      print('Error adding officer to cluster: $e');
      throw Exception('Failed to add officer to cluster: $e');
    }
  }

// Tambahkan method helper untuk generate string random

  @override
  Future<void> updateOfficerInCluster({
    required String clusterId,
    required Officer officer,
  }) async {
    try {
      // Get current officers list
      final snapshot = await _database.child('users/$clusterId/officers').get();

      if (!snapshot.exists || snapshot.value == null) {
        throw Exception('No officers found in cluster');
      }

      List<Map<String, dynamic>> officersList = [];
      final data = snapshot.value;

      if (data is List) {
        officersList = List<Map<String, dynamic>>.from(
          data.map((item) => item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{}),
        );
      } else if (data is Map) {
        officersList = (data as Map<dynamic, dynamic>)
            .values
            .map((item) => item is Map
                ? Map<String, dynamic>.from(item)
                : <String, dynamic>{})
            .toList();
      }

      // Find and update officer
      final index = officersList.indexWhere(
        (item) => item['id'] == officer.id,
      );

      if (index == -1) {
        throw Exception('Officer not found in cluster');
      }

      officersList[index] = officer.toMap();

      // Update officers list
      await _database.child('users/$clusterId').update({
        'officers': officersList,
        'updated_at': DateTime.now().toIso8601String(),
      });

      return;
    } catch (e) {
      print('Error updating officer in cluster: $e');
      throw Exception('Failed to update officer in cluster: $e');
    }
  }

  @override
  Future<void> removeOfficerFromCluster({
    required String clusterId,
    required String officerId,
  }) async {
    try {
      // Get current officers list
      final snapshot = await _database.child('users/$clusterId/officers').get();

      if (!snapshot.exists || snapshot.value == null) {
        throw Exception('No officers found in cluster');
      }

      List<Map<String, dynamic>> officersList = [];
      final data = snapshot.value;

      if (data is List) {
        officersList = List<Map<String, dynamic>>.from(
          data.map((item) => item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{}),
        );
      } else if (data is Map) {
        officersList = (data as Map<dynamic, dynamic>)
            .values
            .map((item) => item is Map
                ? Map<String, dynamic>.from(item)
                : <String, dynamic>{})
            .toList();
      }

      // Remove officer
      officersList.removeWhere((item) => item['id'] == officerId);

      // Update officers list
      await _database.child('users/$clusterId').update({
        'officers': officersList,
        'updated_at': DateTime.now().toIso8601String(),
      });

      return;
    } catch (e) {
      print('Error removing officer from cluster: $e');
      throw Exception('Failed to remove officer from cluster: $e');
    }
  }

  // Tambahkan metode-metode berikut ke class RouteRepositoryImpl
  @override
  Future<List<UserModel.User>> getAllClusters() async {
    try {
      await _checkAuth();
      final snapshot = await _database
          .child('users')
          .orderByChild('role')
          .equalTo('patrol')
          .get();

      if (!snapshot.exists) {
        return [];
      }

      final clustersMap = Map<String, dynamic>.from(snapshot.value as Map);
      final clusters = <UserModel.User>[];

      for (var entry in clustersMap.entries) {
        try {
          final clusterData = Map<String, dynamic>.from(entry.value);
          clusterData['id'] = entry.key;
          clusters.add(UserModel.User.fromMap(clusterData));
        } catch (e) {
          print('Error parsing cluster data for ${entry.key}: $e');
        }
      }

      print('Retrieved ${clusters.length} clusters');
      return clusters;
    } catch (e) {
      print('Error getting all clusters: $e');
      throw Exception('Failed to get clusters: $e');
    }
  }

  @override
  Future<void> updateClusterCoordinates({
    required String clusterId,
    required List<List<double>> coordinates,
  }) async {
    try {
      await _checkAuth();
      await _database.child('users/$clusterId').update({
        'cluster_coordinates': coordinates,
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': _auth.currentUser?.uid,
      });
      print('Cluster coordinates updated successfully');
      return;
    } catch (e) {
      print('Error updating cluster coordinates: $e');
      throw Exception('Failed to update cluster coordinates: $e');
    }
  }

  @override
  Future<void> deleteCluster(String clusterId) async {
    try {
      await _checkAuth();

      // Optional: Archive instead of delete
      await _database.child('users/$clusterId').update({
        'status': 'deleted',
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': _auth.currentUser?.uid,
      });

      // Or actually delete (uncomment if needed)
      // await _database.child('users/$clusterId').remove();

      print('Cluster deleted/archived successfully');
      return;
    } catch (e) {
      print('Error deleting cluster: $e');
      throw Exception('Failed to delete cluster: $e');
    }
  }

  @override
  Future<UserModel.User?> getCurrentUserCluster() async {
    try {
      await _checkAuth();
      final userId = _auth.currentUser!.uid;

      final snapshot = await _database.child('users/$userId').get();
      if (!snapshot.exists) {
        return null;
      }

      final userData = Map<String, dynamic>.from(snapshot.value as Map);
      userData['id'] = userId;
      return UserModel.User.fromMap(userData);
    } catch (e) {
      print('Error getting current user cluster: $e');
      return null;
    }
  }

  @override
  Future<List<Officer>> getClusterOfficers(String clusterId) async {
    try {
      final snapshot = await _database.child('users/$clusterId/officers').get();

      if (!snapshot.exists || snapshot.value == null) {
        return [];
      }

      final dynamic officersData = snapshot.value;
      final officers = <Officer>[];

      if (officersData is List) {
        for (var i = 0; i < officersData.length; i++) {
          if (officersData[i] != null) {
            try {
              final officerMap = Map<String, dynamic>.from(officersData[i]);
              officers.add(Officer.fromMap(officerMap));
            } catch (e) {
              print('Error parsing officer at index $i: $e');
            }
          }
        }
      } else if (officersData is Map) {
        officersData.forEach((key, value) {
          if (value != null) {
            try {
              final officerMap = Map<String, dynamic>.from(value);
              officers.add(Officer.fromMap(officerMap));
            } catch (e) {
              print('Error parsing officer with key $key: $e');
            }
          }
        });
      }

      return officers;
    } catch (e) {
      print('Error getting cluster officers: $e');
      throw Exception('Failed to get cluster officers: $e');
    }
  }

// Metode untuk mendapatkan semua tugas yang terkait dengan cluster tertentu
  @override
  Future<List<PatrolTask>> getClusterTasks(String clusterId) async {
    try {
      // Dapatkan semua petugas dari cluster
      final officers = await getClusterOfficers(clusterId);
      final officerIds = officers.map((o) => o.id).toList();

      // Dapatkan semua tugas
      final allTasks = await getAllTasks();

      // Filter tugas berdasarkan petugas dalam cluster
      return allTasks
          .where((task) => officerIds.contains(task.userId))
          .toList();
    } catch (e) {
      print('Error getting cluster tasks: $e');
      throw Exception('Failed to get cluster tasks: $e');
    }
  }

// Metode untuk mencari cluster berdasarkan nama
  @override
  Future<List<UserModel.User>> searchClustersByName(String searchTerm) async {
    try {
      final allClusters = await getAllClusters();
      if (searchTerm.isEmpty) return allClusters;

      return allClusters
          .where((cluster) =>
              cluster.name.toLowerCase().contains(searchTerm.toLowerCase()))
          .toList();
    } catch (e) {
      print('Error searching clusters: $e');
      throw Exception('Failed to search clusters: $e');
    }
  }

  @override
  Future<void> updateCluster({
    required String clusterId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      await _checkAuth();
      await _database.child('users/$clusterId').update(updates);
      print('Cluster updated successfully');
    } catch (e) {
      print('Error updating cluster: $e');
      throw Exception('Failed to update cluster: $e');
    }
  }
}
