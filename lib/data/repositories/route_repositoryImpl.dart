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
      // Debug print

      final snapshot = await _database
          .child('tasks')
          .orderByChild('userId')
          .equalTo(userId)
          .get();

      if (!snapshot.exists) {
        return null;
      }

      // PERBAIKAN: Cek tipe data sebelum casting
      Map<dynamic, dynamic> tasks;
      try {
        if (snapshot.value is Map) {
          tasks = snapshot.value as Map<dynamic, dynamic>;
        } else if (snapshot.value is List) {
          // Handle jika bentuknya List
          final list = snapshot.value as List;
          tasks = {};
          for (int i = 0; i < list.length; i++) {
            if (list[i] != null) {
              tasks[i.toString()] = list[i];
            }
          }
        } else {
          return null;
        }
      } catch (e) {
        return null;
      }

      // Debugging
      tasks.forEach((key, value) {
        if (value is Map) {
        } else {}
      });

      // Perbaikan: Mencari tugas dengan status active, ongoing, atau in_progress
      MapEntry<dynamic, dynamic>? activeTaskEntry;
      try {
        activeTaskEntry = tasks.entries.firstWhere(
          (entry) {
            if (entry.value is! Map) return false;

            final task = entry.value as Map<dynamic, dynamic>;
            final status = task['status']?.toString().toLowerCase();
            return status == 'active' ||
                status == 'ongoing' ||
                status == 'in_progress';
          },
          orElse: () => MapEntry(null, null),
        );

        if (activeTaskEntry.key != null) {
        } else {
          return null;
        }
      } catch (e) {
        activeTaskEntry = null;
      }

      if (activeTaskEntry == null || activeTaskEntry.key == null) {
        return null;
      }

      // Create PatrolTask with the task data
      final taskData = activeTaskEntry.value as Map<dynamic, dynamic>;

      // Add officer name to task if possible
      String? officerName;
      String? officerPhotoUrl;
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
              // PERBAIKAN: Handle tipe data dengan benar
              if (officerSnapshot.value is Map) {
                final officerData = officerSnapshot.value as Map;
                if (officerData.containsKey(officerId) &&
                    officerData[officerId] is Map) {
                  officerName = officerData[officerId]['name']?.toString();
                  officerPhotoUrl =
                      officerData[officerId]['photoUrl']?.toString();
                }
              }
            }
          }
        }
      } catch (e) {}

      final task = _convertToPatrolTask({
        ...taskData,
        'taskId': activeTaskEntry.key,
        'officerName': officerName,
        'officerPhotoUrl': officerPhotoUrl,
      });

      // Check if timeliness needs update
      final recalculatedTimeliness = determineTimelinessStatus(
          task.assignedStartTime,
          task.startTime,
          task.assignedEndTime,
          task.status);

      // Update timeliness in database if needed
      if (task.timeliness != recalculatedTimeliness) {
        await updateTask(task.taskId, {'timeliness': recalculatedTimeliness});
        return task.copyWith(timeliness: recalculatedTimeliness);
      }

      return task;
    } catch (e, stackTrace) {
      return null;
    }
  }

  @override
  Future<void> updateTaskStatus(String taskId, String status) async {
    try {
      final task = await getTaskById(taskId: taskId);

      await _database.child('tasks').child(taskId).update({
        'status': status,
      });

      if (task != null) {
        // Update timeliness after status change
        final timeliness = determineTimelinessStatus(task.assignedStartTime,
            task.startTime, task.assignedEndTime, status);

        await _database.child('tasks').child(taskId).update({
          'timeliness': timeliness,
        });
      }
    } catch (e) {
      throw e;
    }
  }

  @override
  Future<void> updatePatrolLocation(
    String taskId,
    List<double> coordinates,
    DateTime timestamp,
  ) async {
    try {
      // Skip auth check to avoid permission issues
      final user = _auth.currentUser;
      if (user == null) {
      } else {}

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
      } catch (e) {
        // Try alternative approach with update()
        final updates = {
          'route_path/$timestampKey': locationData,
        };
        await taskRef.update(updates);
      }

      // Also update lastLocation
      await taskRef.child('lastLocation').set(locationData);
    } catch (e, stackTrace) {
      throw Exception('Failed to update location: $e');
    }
  }

  @override
  Future<List<PatrolTask>> getFinishedTasks(String userId) async {
    try {
      final snapshot = await _database
          .child('tasks')
          .orderByChild('userId')
          .equalTo(userId)
          .get();

      if (!snapshot.exists) {
        return [];
      }

      // PERBAIKAN: Cek tipe data sebelum casting
      Map<dynamic, dynamic> tasks;
      if (snapshot.value is Map) {
        tasks = snapshot.value as Map<dynamic, dynamic>;
      } else if (snapshot.value is List) {
        final list = snapshot.value as List;
        tasks = {};
        for (int i = 0; i < list.length; i++) {
          if (list[i] != null) {
            tasks[i.toString()] = list[i];
          }
        }
      } else {
        return [];
      }

      List<PatrolTask> finishedTasks = [];

      await Future.forEach(tasks.entries,
          (MapEntry<dynamic, dynamic> entry) async {
        try {
          if (entry.value is! Map) {
            return;
          }

          final taskData = entry.value as Map<dynamic, dynamic>;
          final status = taskData['status']?.toString() ?? '';

          if (status.toLowerCase() == 'finished') {
            // Get officer name if possible
            String? officerName;
            String? officerPhotoUrl;

            if (taskData['clusterId'] != null) {
              final clusterId = taskData['clusterId'].toString();
              final officerId = taskData['userId'].toString();

              try {
                final officerSnapshot = await _database
                    .child('users/$clusterId/officers')
                    .orderByKey()
                    .equalTo(officerId)
                    .get();

                if (officerSnapshot.exists) {
                  if (officerSnapshot.value is Map) {
                    final officerData = officerSnapshot.value as Map;
                    if (officerData.containsKey(officerId) &&
                        officerData[officerId] is Map) {
                      officerName = officerData[officerId]['name']?.toString();
                      officerPhotoUrl =
                          officerData[officerId]['photoUrl']?.toString();
                    }
                  }
                }
              } catch (e) {}
            }

            final task = _convertToPatrolTask({
              ...taskData,
              'taskId': entry.key,
              'officerName': officerName,
              'officerPhotoUrl': officerPhotoUrl,
            });

            finishedTasks.add(task);
          }
        } catch (e) {}
      });

      // Sort by end time, most recent first
      finishedTasks.sort((a, b) =>
          (b.endTime ?? DateTime.now()).compareTo(a.endTime ?? DateTime.now()));

      return finishedTasks;
    } catch (e) {
      return [];
    }
  }

// Update watchCurrentTask to handle in_progress status
  @override
  Stream<PatrolTask?> watchCurrentTask(String userId) {
    // Debug print

    return _database
        .child('tasks')
        .orderByChild('userId')
        .equalTo(userId)
        .onValue
        .map((event) {
      if (!event.snapshot.exists) {
        return null;
      }

      try {
        final tasksMap = event.snapshot.value as Map<dynamic, dynamic>;

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
          return null;
        }

        // Log assigned start/end times for debugging
        final taskData = activeTaskEntry.value as Map<dynamic, dynamic>;

        // Create PatrolTask with the task data
        return _convertToPatrolTask({
          ...taskData,
          'taskId': activeTaskEntry.key,
        });
      } catch (e, stackTrace) {
        return null;
      }
    }).handleError((error) {
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
    } catch (e) {}
    return null;
  }

  // Perbaiki metode _convertToPatrolTask untuk menangani semua properti penting

  PatrolTask _convertToPatrolTask(Map<dynamic, dynamic> data) {
    // Debug print
    try {
      final startTime = _parseDateTime(data['startTime']);
      final assignedStartTime = _parseDateTime(data['assignedStartTime']);
      final assignedEndTime = _parseDateTime(data['assignedEndTime']);
      final status = data['status']?.toString() ?? 'active';

      String timeliness = data['timeliness']?.toString() ??
          determineTimelinessStatus(
              assignedStartTime, startTime, assignedEndTime, status);
      final task = PatrolTask(
        taskId: data['taskId']?.toString() ?? '',
        userId: data['userId']?.toString() ?? '',
        // vehicleId: data['vehicleId']?.toString() ?? '',
        officerName:
            data['officerName']?.toString(), // Support for officer name
        officerPhotoUrl:
            data['officerPhotoUrl']?.toString(), // Support for officer photo
        assignedRoute: data['assigned_route'] != null
            ? (data['assigned_route'] as List)
                .map((point) => (point as List)
                    .map((coord) => (coord as num).toDouble())
                    .toList())
                .toList()
            : null,
        status: data['status']?.toString() ?? 'active',
        timeliness: timeliness,
        distance: data['distance'] != null
            ? (data['distance'] as num).toDouble()
            : null,
        routePath: data['route_path'] != null
            ? Map<String, dynamic>.from(data['route_path'] as Map)
            : null,
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
        expiredAt: _parseDateTime(data['expiredAt']),
        cancelledAt: _parseDateTime(data['cancelledAt']),
        startTime: _parseDateTime(data['startTime']),
        endTime: _parseDateTime(data['endTime']),
        assignedStartTime: _parseDateTime(data['assignedStartTime']),
        assignedEndTime: _parseDateTime(data['assignedEndTime']),
        clusterId: data['clusterId']?.toString() ?? '', // Add clusterId support
        finalReportPhotoUrl: data['finalReportPhotoUrl']?.toString(),
        finalReportNote: data['finalReportNote']?.toString(),
        finalReportTime: _parseDateTime(data['finalReportTime']),
        initialReportPhotoUrl: data['initialReportPhotoUrl']?.toString(),
        initialReportNote: data['initialReportNote']?.toString(),
        initialReportTime: _parseDateTime(data['initialReportTime']),
        mockLocationDetected: data['mockLocationDetected'] == true,
        mockLocationCount: data['mockLocationCount'] is num
            ? (data['mockLocationCount'] as num).toInt()
            : 0,
      );

      return task;
    } catch (e, stackTrace) {
      // Debug print

      // Return a default task instead of rethrowing
      return PatrolTask(
        taskId: data['taskId']?.toString() ?? '',
        userId: data['userId']?.toString() ?? '',
        // vehicleId: data['vehicleId']?.toString() ?? '',
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
  Future<PatrolTask?> getTaskById({required String taskId}) async {
    try {
      final snapshot = await _database.child('tasks/$taskId').get();

      if (!snapshot.exists) {
        return null;
      }

      final taskData = Map<String, dynamic>.from(snapshot.value as Map);
      return _convertToPatrolTask(taskData);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> updateTask(String taskId, Map<String, dynamic> updates) async {
    try {
      // Debug print

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

      // Debug print
    } catch (e, stackTrace) {
      // Debug print
      throw Exception('Failed to update task: $e');
    }
  }

  @override
  Future<String> createTask({
    required String clusterId,
    required String vehicleId,
    required List<List<double>> assignedRoute,
    required String? assignedOfficerId,
    required DateTime? assignedStartTime,
    required DateTime? assignedEndTime,
    required String? officerName,
    required String? clusterName,
  }) async {
    try {
      await _checkAuth();
      final taskRef = _database.child('tasks').push();

      // Simpan ID task untuk dikembalikan
      final String taskId = taskRef.key!;

      final newTask = {
        'clusterId': clusterId,
        'taskId': taskId,
        'vehicleId': vehicleId,
        'userId': assignedOfficerId,
        'assigned_route': assignedRoute,
        'assignedStartTime': assignedStartTime?.toIso8601String(),
        'assignedEndTime': assignedEndTime?.toIso8601String(),
        'officerName': officerName,
        'clusterName': clusterName,
        'status': 'active',
        'createdAt': DateTime.now().toIso8601String(),
        'route_path': null,
        'lastLocation': null,
      };

      await taskRef.set(newTask);

      // Kembalikan ID task
      return taskId;
    } catch (e) {
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

      return tasks;
    } catch (e) {
      throw Exception('Failed to get tasks: $e');
    }
  }

  @override
  Future<List<String>> getAllVehicles() async {
    try {
      await _checkAuth();
      final snapshot = await _database.child('vehicle').get();

      if (!snapshot.exists) {
        return [];
      }

      final value = snapshot.value;

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

      return [];
    } catch (e) {
      throw Exception('Failed to get vehicles: $e');
    }
  }

  //Tatar Logic
  // Tambahkan implementasi method-method baru ini ke AdminRepositoryImpl

  @override
  Future<UserModel.User> getClusterById(String clusterId) async {
    try {
      final snapshot = await _database.child('users/$clusterId').get();

      if (!snapshot.exists) {
        throw Exception('Tatar not found');
      }

      final data = snapshot.value as Map<dynamic, dynamic>;
      final userData = Map<String, dynamic>.from(data);
      userData['id'] = clusterId;

      return UserModel.User.fromMap(userData);
    } catch (e) {
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

      await firebaseAuth.signOut();

      return;
    } catch (e) {
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
        type: officer.type,
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

      return;
    } catch (e) {
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
        } catch (e) {}
      }

      return clusters;
    } catch (e) {
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
      return;
    } catch (e) {
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

      return;
    } catch (e) {
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
            } catch (e) {}
          }
        }
      } else if (officersData is Map) {
        officersData.forEach((key, value) {
          if (value != null) {
            try {
              final officerMap = Map<String, dynamic>.from(value);
              officers.add(Officer.fromMap(officerMap));
            } catch (e) {}
          }
        });
      }

      return officers;
    } catch (e) {
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
    } catch (e) {
      throw Exception('Failed to update cluster: $e');
    }
  }

  // Tambahkan metode berikut di class RouteRepositoryImpl

  @override
  Future<void> logMockLocationDetection({
    required String taskId,
    required String userId,
    required Map<String, dynamic> mockData,
  }) async {
    try {
      // Update flag pada task
      await updateTask(taskId, {
        'mockLocationDetected': true,
        'mockLocationCount': mockData['count'] ?? 1,
        'lastMockDetection': mockData['timestamp'],
      });

      // Catat detail percobaan ke node khusus di database
      final database = FirebaseDatabase.instance.ref();

      // Simpan di task
      await database
          .child('tasks/$taskId/mock_detections')
          .push()
          .set(mockData);

      // Simpan juga di koleksi terpisah untuk analisis
      await database.child('mock_location_logs').push().set({
        ...mockData,
        'taskId': taskId,
        'userId': userId,
        'detectionTime': ServerValue.timestamp,
      });

      return;
    } catch (e) {
      throw Exception('Failed to log mock location: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getMockLocationDetections(
      String taskId) async {
    try {
      final snapshot =
          await _database.child('tasks/$taskId/mock_detections').get();

      if (!snapshot.exists) {
        return [];
      }

      final detectionsMap = snapshot.value as Map<dynamic, dynamic>;
      List<Map<String, dynamic>> detections = [];

      detectionsMap.forEach((key, value) {
        if (value is Map) {
          detections.add(Map<String, dynamic>.from(value));
        }
      });

      // Sort by timestamp
      detections.sort((a, b) =>
          (a['timestamp'] as String).compareTo(b['timestamp'] as String));

      return detections;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<int> getMockLocationCount(String taskId) async {
    try {
      final taskSnapshot = await _database.child('tasks/$taskId').get();

      if (!taskSnapshot.exists) {
        return 0;
      }

      final taskData = taskSnapshot.value as Map<dynamic, dynamic>;
      final count = taskData['mockLocationCount'];

      if (count is int) {
        return count;
      } else if (count is num) {
        return count.toInt();
      }

      return 0;
    } catch (e) {
      return 0;
    }
  }

  String determineTimelinessStatus(DateTime? assignedStartTime,
      DateTime? startTime, DateTime? assignedEndTime, String status) {
    // Jika belum dimulai, status 'idle'
    if (startTime == null) {
      return 'idle';
    }

    if (assignedStartTime != null) {
      // Batas waktu toleransi - 10 menit dari jadwal
      final lateThreshold = assignedStartTime.add(Duration(minutes: 10));
      final earlyThreshold = assignedStartTime.subtract(Duration(minutes: 10));

      // Jika waktu mulai lebih dari 10 menit setelah jadwal
      if (startTime.isAfter(lateThreshold)) {
        // Jika juga melebihi waktu akhir
        if (assignedEndTime != null && startTime.isAfter(assignedEndTime)) {
          return 'pastDue';
        }
        return 'late';
      }
      // Jika waktu mulai dalam rentang -10 hingga +10 menit dari jadwal
      else if (startTime.isAfter(earlyThreshold) ||
          startTime.isAtSameMomentAs(earlyThreshold)) {
        return 'ontime';
      }
      // Jika terlalu awal (lebih dari 10 menit sebelum jadwal)
      else {
        return 'early';
      }
    }

    // Default jika assignedStartTime null
    return 'ontime';
  }

  Future<void> updateTaskTimeliness(String taskId) async {
    try {
      final task = await getTaskById(taskId: taskId);
      if (task == null) return;

      // Recalculate timeliness
      final timeliness = determineTimelinessStatus(task.assignedStartTime,
          task.startTime, task.assignedEndTime, task.status);

      // Only update if timeliness changed
      if (task.timeliness != timeliness) {
        await updateTask(taskId, {'timeliness': timeliness});
      }
    } catch (e) {}
  }
}
