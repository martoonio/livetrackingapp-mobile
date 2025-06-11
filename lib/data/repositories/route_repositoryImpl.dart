import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import '../../domain/entities/patrol_task.dart';
import '../../domain/repositories/route_repository.dart';
import '../../domain/entities/user.dart' as UserModel;

class RouteRepositoryImpl implements RouteRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
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
      log('getCurrentTask called for userId: $userId');

      final snapshot = await _firestore
          .collection('tasks')
          .where('userId', isEqualTo: userId)
          .where('status', whereIn: ['active', 'ongoing', 'in_progress'])
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        log('No tasks found for userId: $userId');
        return null;
      }

      final taskDoc = snapshot.docs.first;
      final taskData = taskDoc.data();
      taskData['taskId'] = taskDoc.id;

      // Load officer info
      await _loadOfficerInfoForTask(taskData);

      // Convert to PatrolTask
      final task = _convertToPatrolTask(taskData);

      // Update timeliness if needed
      final recalculatedTimeliness = determineTimelinessStatus(
          task.assignedStartTime,
          task.startTime,
          task.assignedEndTime,
          task.status);

      if (task.timeliness != recalculatedTimeliness) {
        await updateTask(task.taskId, {'timeliness': recalculatedTimeliness});
        return task.copyWith(timeliness: recalculatedTimeliness);
      }

      log('Returning task: ${task.taskId} with status: ${task.status}');
      return task;
    } catch (e, stackTrace) {
      log('Error in getCurrentTask: $e\n$stackTrace');
      return null;
    }
  }

  @override
  Future<void> updateTaskStatus(String taskId, String status) async {
    try {
      final task = await getTaskById(taskId: taskId);

      await _firestore.collection('tasks').doc(taskId).update({
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (task != null) {
        // Update timeliness after status change
        final timeliness = determineTimelinessStatus(task.assignedStartTime,
            task.startTime, task.assignedEndTime, status);

        await _firestore.collection('tasks').doc(taskId).update({
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
      final user = _auth.currentUser;
      if (user == null) {
      } else {}

      // Create timestamp key
      final timestampKey = timestamp.millisecondsSinceEpoch.toString();

      // ✅ FIXED: Format location data as Map instead of nested array
      final locationData = {
        'lat': coordinates.length > 0 ? coordinates[0] : 0.0,
        'lng': coordinates.length > 1 ? coordinates[1] : 0.0,
        'timestamp': timestamp.toIso8601String(),
      };

      // Update route path
      await _firestore.collection('tasks').doc(taskId).update({
        'route_path.$timestampKey': locationData,
        'lastLocation': locationData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, stackTrace) {
      throw Exception('Failed to update location: $e');
    }
  }

  @override
  Future<List<PatrolTask>> getFinishedTasks(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('tasks')
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'finished')
          .orderBy('endTime', descending: true)
          .get();

      if (snapshot.docs.isEmpty) {
        return [];
      }

      List<PatrolTask> finishedTasks = [];

      for (var doc in snapshot.docs) {
        try {
          final taskData = doc.data();
          taskData['taskId'] = doc.id;

          // Get officer name if possible
          await _loadOfficerInfoForTask(taskData);

          final task = _convertToPatrolTask(taskData);
          finishedTasks.add(task);
        } catch (e) {
          // Continue processing other tasks
        }
      }

      return finishedTasks;
    } catch (e) {
      return [];
    }
  }

  @override
  Stream<PatrolTask?> watchCurrentTask(String userId) {
    return _firestore
        .collection('tasks')
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['active', 'ongoing', 'in_progress'])
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return null;
          }

          try {
            final taskDoc = snapshot.docs.first;
            final taskData = taskDoc.data();
            taskData['taskId'] = taskDoc.id;

            return _convertToPatrolTask(taskData);
          } catch (e, stackTrace) {
            return null;
          }
        })
        .handleError((error) {
          return null;
        });
  }

  @override
  Stream<List<PatrolTask>> watchFinishedTasks(String userId) {
    return _firestore
        .collection('tasks')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'finished')
        .orderBy('endTime', descending: true)
        .snapshots()
        .map((snapshot) {
      try {
        final finishedTasks = snapshot.docs.map((doc) {
          final taskData = doc.data();
          taskData['taskId'] = doc.id;
          return _convertToPatrolTask(taskData);
        }).toList();

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
        return DateTime.parse(value);
      } else if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } else if (value is Timestamp) {
        return value.toDate();
      } else if (value is Map && value['_seconds'] != null) {
        // Firestore Timestamp format
        return DateTime.fromMillisecondsSinceEpoch(
            (value['_seconds'] as int) * 1000);
      }
    } catch (e) {
      print('Error parsing datetime: $value, error: $e');
    }

    return null;
  }

  List<List<double>>? _parseRouteCoordinates(dynamic value) {
    if (value == null) return null;

    try {
      if (value is List) {
        return value
            .map<List<double>>((point) {
              // ✅ Handle new Firestore format (Map with lat/lng)
              if (point is Map) {
                final lat = point['lat'];
                final lng = point['lng'];
                if (lat != null && lng != null) {
                  return [
                    (lat as num).toDouble(),
                    (lng as num).toDouble(),
                  ];
                }
              }
              // ✅ Handle legacy format (nested array)
              else if (point is List && point.length >= 2) {
                return [
                  (point[0] as num).toDouble(),
                  (point[1] as num).toDouble(),
                ];
              }
              return <double>[];
            })
            .where((point) => point.isNotEmpty)
            .toList();
      }
    } catch (e) {
      print('Error parsing route coordinates: $e');
    }

    return null;
  }

  PatrolTask _convertToPatrolTask(Map<String, dynamic> data) {
    return PatrolTask(
      taskId: data['taskId']?.toString() ?? '',
      userId: data['userId']?.toString() ??
          data['assignedOfficerId']?.toString() ??
          '',
      status: data['status']?.toString() ?? 'unknown',
      assignedStartTime: _parseDateTime(data['assignedStartTime']),
      assignedEndTime: _parseDateTime(data['assignedEndTime']),
      startTime: _parseDateTime(data['startTime']),
      endTime: _parseDateTime(data['endTime']),
      distance:
          data['distance'] != null ? (data['distance'] as num).toDouble() : 0.0,
      createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
      assignedRoute: _parseRouteCoordinates(
          data['assigned_route'] ?? data['assignedRoute']),
      routePath: data['route_path'] != null
          ? Map<String, dynamic>.from(data['route_path'] as Map)
          : null,
      clusterId: data['clusterId']?.toString() ?? '',
      mockLocationDetected: data['mockLocationDetected'] == true,
      timeliness: data['timeliness']?.toString() ?? 'unknown',
      mockLocationCount: data['mockLocationCount'] is num
          ? (data['mockLocationCount'] as num).toInt()
          : 0,
      // Additional fields
      finalReportPhotoUrl: data['finalReportPhotoUrl']?.toString(),
      finalReportNote: data['finalReportNote']?.toString(),
      finalReportTime: _parseDateTime(data['finalReportTime']),
      initialReportPhotoUrl: data['initialReportPhotoUrl']?.toString(),
      initialReportNote: data['initialReportNote']?.toString(),
      initialReportTime: _parseDateTime(data['initialReportTime']),
      // Officer info
      officerName: data['officerName']?.toString() ?? '',
      clusterName: data['clusterName']?.toString() ?? '',
    );
  }

  @override
  Future<PatrolTask?> getTaskById({required String taskId}) async {
    try {
      final doc = await _firestore.collection('tasks').doc(taskId).get();

      if (!doc.exists) {
        return null;
      }

      final taskData = doc.data()!;
      taskData['taskId'] = doc.id;
      return _convertToPatrolTask(taskData);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> updateTask(String taskId, Map<String, dynamic> updates) async {
    try {
      // Format any DateTime objects in updates to Timestamp
      final formattedUpdates = Map<String, dynamic>.from(updates);
      for (final key in formattedUpdates.keys) {
        final value = formattedUpdates[key];
        if (value is DateTime) {
          formattedUpdates[key] = Timestamp.fromDate(value);
        }
      }

      formattedUpdates['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection('tasks').doc(taskId).update(formattedUpdates);
    } catch (e, stackTrace) {
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

      // ✅ FIXED: Convert nested array to Firestore-compatible format
      final List<Map<String, double>> convertedRoute =
          assignedRoute.map((point) {
        if (point.length >= 2) {
          return {
            'lat': point[0],
            'lng': point[1],
          };
        }
        return {'lat': 0.0, 'lng': 0.0};
      }).toList();

      final newTask = {
        'clusterId': clusterId,
        'vehicleId': vehicleId,
        'userId': assignedOfficerId,
        'assigned_route':
            convertedRoute, // ✅ Use converted format instead of nested array
        'assignedStartTime': assignedStartTime != null
            ? Timestamp.fromDate(assignedStartTime)
            : null,
        'assignedEndTime': assignedEndTime != null
            ? Timestamp.fromDate(assignedEndTime)
            : null,
        'officerName': officerName,
        'clusterName': clusterName,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'route_path': {},
        'lastLocation': null,
      };

      final docRef = await _firestore.collection('tasks').add(newTask);
      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create task: $e');
    }
  }

  @override
  Future<List<PatrolTask>> getAllTasks({
    int limit = 50,
    String? status,
    String? lastKey,
  }) async {
    try {
      log('getAllTasks called: limit=$limit, status=$status, lastKey=$lastKey');

      Query query =
          _firestore.collection('tasks').orderBy('createdAt', descending: true);

      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }

      if (lastKey != null) {
        final lastDoc = await _firestore.collection('tasks').doc(lastKey).get();
        if (lastDoc.exists) {
          query = query.startAfterDocument(lastDoc);
        }
      }

      query = query.limit(limit);

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        log('No tasks found');
        return [];
      }

      List<PatrolTask> allTasks = [];

      for (var doc in snapshot.docs) {
        try {
          final taskData = doc.data() as Map<String, dynamic>;
          taskData['taskId'] = doc.id;

          if (_isValidTaskData(taskData)) {
            final task = _convertToPatrolTask(taskData);
            allTasks.add(task);
          }
        } catch (e) {
          log('Error processing task ${doc.id}: $e');
        }
      }

      log('Fetched ${allTasks.length} tasks total');
      return allTasks;
    } catch (e, stackTrace) {
      log('Error in getAllTasks: $e\n$stackTrace');
      return [];
    }
  }

  @override
  Future<List<PatrolTask>> getActiveTasks({int limit = 50}) async {
    try {
      final snapshot = await _firestore
          .collection('tasks')
          .where('status', whereIn: ['active', 'ongoing'])
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      List<PatrolTask> allTasks = [];

      for (var doc in snapshot.docs) {
        try {
          final taskData = doc.data();
          taskData['taskId'] = doc.id;
          allTasks.add(_convertToPatrolTask(taskData));
        } catch (e) {
          // Continue processing other tasks
        }
      }

      return allTasks;
    } catch (e) {
      print('Error in getActiveTasks: $e');
      return [];
    }
  }

  @override
  Future<List<PatrolTask>> getOngoingTasks({int limit = 50}) async {
    try {
      final snapshot = await _firestore
          .collection('tasks')
          .where('status', isEqualTo: 'ongoing')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final taskData = doc.data();
        taskData['taskId'] = doc.id;
        return _convertToPatrolTask(taskData);
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<PatrolTask>> getTasksByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    String? status,
    String? clusterId,
    int limit = 50,
    String? lastKey,
  }) async {
    try {
      Query query = _firestore.collection('tasks');

      // Filter by date range
      query = query
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate));

      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }

      if (clusterId != null) {
        query = query.where('clusterId', isEqualTo: clusterId);
      }

      query = query.orderBy('createdAt', descending: true).limit(limit);

      final snapshot = await query.get();

      return snapshot.docs.map((doc) {
        final taskData = doc.data() as Map<String, dynamic>;
        taskData['taskId'] = doc.id;
        return _convertToPatrolTask(taskData);
      }).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<PatrolTask>> getClusterTasks(
    String clusterId, {
    int limit = 20,
    String? status,
    String? lastKey,
  }) async {
    try {
      log('getClusterTasks called: clusterId=$clusterId, limit=$limit, status=$status, lastKey=$lastKey');

      Query query = _firestore
          .collection('tasks')
          .where('clusterId', isEqualTo: clusterId)
          .orderBy('createdAt', descending: true);

      if (status != null) {
        query = query.where('status', isEqualTo: status);
      }

      if (lastKey != null) {
        final lastDoc = await _firestore.collection('tasks').doc(lastKey).get();
        if (lastDoc.exists) {
          query = query.startAfterDocument(lastDoc);
        }
      }

      query = query.limit(limit);

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        log('No tasks found for cluster $clusterId');
        return [];
      }

      List<PatrolTask> allTasks = [];

      for (var doc in snapshot.docs) {
        try {
          final taskData = doc.data() as Map<String, dynamic>;
          taskData['taskId'] = doc.id;

          // Load officer info
          await _loadOfficerInfoForTask(taskData);

          if (_isValidTaskData(taskData)) {
            final task = _convertToPatrolTask(taskData);
            allTasks.add(task);
          }
        } catch (e) {
          log('Error processing task ${doc.id}: $e');
        }
      }

      log('Fetched ${allTasks.length} tasks for cluster $clusterId, status $status');
      return allTasks;
    } catch (e, stackTrace) {
      log('Error in getClusterTasks for $clusterId: $e\n$stackTrace');
      return [];
    }
  }

  Future<void> _loadOfficerInfoForTask(Map<String, dynamic> taskData) async {
    try {
      if (taskData['userId'] != null && taskData['clusterId'] != null) {
        final officerId = taskData['userId'].toString();
        final clusterId = taskData['clusterId'].toString();

        if (clusterId.isNotEmpty) {
          final clusterDoc =
              await _firestore.collection('users').doc(clusterId).get();

          if (clusterDoc.exists) {
            final clusterData = clusterDoc.data()!;
            final officers = clusterData['officers'] as List?;

            if (officers != null) {
              for (var officer in officers) {
                if (officer != null && officer['id'] == officerId) {
                  taskData['officerName'] = officer['name']?.toString() ?? '';
                  taskData['officerPhotoUrl'] =
                      officer['photo_url']?.toString() ?? '';
                  break;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      log('Error loading officer info for task: $e');
      // Set default values if error
      taskData['officerName'] = taskData['officerName'] ??
          'Officer #${taskData['userId']?.toString().substring(0, 6) ?? 'Unknown'}';
      taskData['officerPhotoUrl'] = taskData['officerPhotoUrl'] ?? '';
    }
  }

  @override
  Future<List<PatrolTask>> getActiveAndCancelledTasks(String clusterId,
      {int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection('tasks')
          .where('clusterId', isEqualTo: clusterId)
          .where('status', whereIn: ['active', 'cancelled'])
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) {
        final taskData = doc.data();
        taskData['taskId'] = doc.id;
        return _convertToPatrolTask(taskData);
      }).toList();
    } catch (e) {
      print('Error getting active and cancelled tasks for $clusterId: $e');
      return [];
    }
  }

  @override
  Future<List<PatrolTask>> getAllClusterTasks(String clusterId) async {
    try {
      print('getAllClusterTasks called for: $clusterId');

      final snapshot = await _firestore
          .collection('tasks')
          .where('clusterId', isEqualTo: clusterId)
          .orderBy('createdAt', descending: true)
          .get();

      if (snapshot.docs.isEmpty) {
        print('No tasks found for cluster $clusterId');
        return [];
      }

      final allTasks = snapshot.docs.map((doc) {
        final taskData = doc.data();
        taskData['taskId'] = doc.id;
        return _convertToPatrolTask(taskData);
      }).toList();

      print('Found ${allTasks.length} total tasks for cluster $clusterId');
      return allTasks;
    } catch (e) {
      print('Error in getAllClusterTasks for $clusterId: $e');
      return [];
    }
  }

  bool _isValidTaskData(Map<String, dynamic> taskData) {
    return taskData['taskId'] != null &&
        taskData['taskId'].toString().isNotEmpty &&
        taskData['clusterId'] != null &&
        taskData['clusterId'].toString().isNotEmpty;
  }

  @override
  Future<List<PatrolTask>> getRecentTasks({
    int limit = 50,
    String? lastKey,
  }) async {
    try {
      print('getRecentTasks called: limit=$limit, lastKey=$lastKey');

      Query query =
          _firestore.collection('tasks').orderBy('createdAt', descending: true);

      if (lastKey != null) {
        final lastDoc = await _firestore.collection('tasks').doc(lastKey).get();
        if (lastDoc.exists) {
          query = query.startAfterDocument(lastDoc);
        }
      }

      query = query.limit(limit);

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        print('No recent tasks found');
        return [];
      }

      print('Found ${snapshot.docs.length} recent tasks');

      return snapshot.docs.map((doc) {
        final taskData = doc.data() as Map<String, dynamic>;
        taskData['taskId'] = doc.id;
        return _convertToPatrolTask(taskData);
      }).toList();
    } catch (e) {
      print('Error in getRecentTasks: $e');
      return [];
    }
  }

  @override
  Future<List<String>> getAllVehicles() async {
    try {
      await _checkAuth();
      final doc = await _firestore.collection('config').doc('vehicles').get();

      if (!doc.exists) {
        return [];
      }

      final data = doc.data()!;
      final vehicles = data['list'] as List?;

      if (vehicles != null) {
        return vehicles.map((vehicle) => vehicle.toString()).toList();
      }

      return [];
    } catch (e) {
      throw Exception('Failed to get vehicles: $e');
    }
  }

  @override
  Future<UserModel.User> getClusterById(String clusterId) async {
    try {
      final doc = await _firestore.collection('users').doc(clusterId).get();

      if (!doc.exists) {
        throw Exception('Cluster not found');
      }

      final userData = doc.data()!;
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

      // ✅ FIXED: Convert nested array to Firestore-compatible format
      final List<Map<String, double>> convertedCoordinates =
          clusterCoordinates.map((point) {
        if (point.length >= 2) {
          return {
            'lat': point[0],
            'lng': point[1],
          };
        }
        return {'lat': 0.0, 'lng': 0.0};
      }).toList();

      // Create user data in Firestore
      await _firestore.collection('users').doc(userId).set({
        'name': name,
        'email': email,
        'role': role,
        'cluster_coordinates': convertedCoordinates, // ✅ Use converted format
        'officers': [], // Empty officers list initially
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      await firebaseAuth.signOut();

      return;
    } catch (e) {
      throw Exception('Failed to create cluster account: $e');
    }
  }

  Future<void> updateClusterAccount(UserModel.User cluster) async {
    try {
      // ✅ FIXED: Convert cluster coordinates if they exist
      List<Map<String, double>>? convertedCoordinates;
      if (cluster.clusterCoordinates != null) {
        convertedCoordinates = cluster.clusterCoordinates!.map((point) {
          if (point.length >= 2) {
            return {
              'lat': point[0],
              'lng': point[1],
            };
          }
          return {'lat': 0.0, 'lng': 0.0};
        }).toList();
      }

      final updates = {
        'name': cluster.name,
        'role': cluster.role,
        'cluster_coordinates': convertedCoordinates, // ✅ Use converted format
        'updated_at': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('users').doc(cluster.id).update(updates);
      return;
    } catch (e) {
      throw Exception('Failed to update cluster account: $e');
    }
  }

  @override
  Future<void> addOfficerToCluster({
    required String clusterId,
    required Officer officer,
  }) async {
    try {
      await _checkAuth();

      // Generate new officer ID
      final officerId = _firestore.collection('temp').doc().id;

      // Create officer with generated ID
      final updatedOfficer = Officer(
        id: officerId,
        name: officer.name,
        shift: officer.shift,
        type: officer.type,
        clusterId: clusterId,
        photoUrl: officer.photoUrl,
      );

      // Add officer to the officers array
      await _firestore.collection('users').doc(clusterId).update({
        'officers': FieldValue.arrayUnion([updatedOfficer.toMap()]),
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': _auth.currentUser?.uid,
      });

      return;
    } catch (e) {
      throw Exception('Failed to add officer to cluster: $e');
    }
  }

  @override
  Future<void> checkAndFixTaskIntegrity(String taskId) async {
    try {
      final task = await getTaskById(taskId: taskId);
      if (task == null) return;

      bool needsUpdate = false;
      Map<String, dynamic> fixes = {};

      // Check 1: Has endTime but no startTime
      if (task.endTime != null && task.startTime == null) {
        print('Found corrupted task $taskId: has endTime but no startTime');

        fixes['endTime'] = null;
        fixes['status'] = 'active';
        fixes['distance'] = null;
        fixes['corruptionFixed'] = true;
        fixes['fixedAt'] = FieldValue.serverTimestamp();
        needsUpdate = true;
      }

      // Check 2: Status inconsistency
      if (task.status == 'finished' && task.startTime == null) {
        print('Found status inconsistency in task $taskId');
        fixes['status'] = 'active';
        fixes['statusInconsistencyFixed'] = true;
        needsUpdate = true;
      }

      if (needsUpdate) {
        await updateTask(taskId, fixes);
        print('Fixed data integrity issues for task $taskId');
      }
    } catch (e) {
      print('Error checking task integrity for $taskId: $e');
    }
  }

  @override
  Future<void> fixCorruptedTasks() async {
    try {
      final snapshot = await _firestore.collection('tasks').get();
      if (snapshot.docs.isEmpty) return;

      int fixedCount = 0;

      for (var doc in snapshot.docs) {
        final taskData = doc.data();

        // Find corrupted tasks
        if (taskData['endTime'] != null && taskData['startTime'] == null) {
          print('Fixing corrupted task: ${doc.id}');

          await _firestore.collection('tasks').doc(doc.id).update({
            'endTime': null,
            'status': 'active',
            'distance': null,
            'corruptionFixed': true,
            'fixedAt': FieldValue.serverTimestamp(),
            'originalEndTime': taskData['endTime'], // Backup original data
          });

          fixedCount++;
        }
      }

      print('Fixed $fixedCount corrupted tasks');
    } catch (e) {
      print('Error fixing corrupted tasks: $e');
    }
  }

  @override
  Future<bool> validateTaskIntegrity(String taskId) async {
    try {
      final task = await getTaskById(taskId: taskId);
      if (task == null) return false;

      // Check for corruption signs
      if (task.endTime != null && task.startTime == null) {
        return false;
      }

      if (task.status == 'finished' && task.startTime == null) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> updateOfficerInCluster({
    required String clusterId,
    required Officer officer,
  }) async {
    try {
      // Get current cluster data
      final clusterDoc =
          await _firestore.collection('users').doc(clusterId).get();

      if (!clusterDoc.exists) {
        throw Exception('Cluster not found');
      }

      final clusterData = clusterDoc.data()!;
      final officers =
          List<Map<String, dynamic>>.from(clusterData['officers'] ?? []);

      // Find and update officer
      final index = officers.indexWhere((item) => item['id'] == officer.id);

      if (index == -1) {
        throw Exception('Officer not found in cluster');
      }

      officers[index] = officer.toMap();

      // Update officers list
      await _firestore.collection('users').doc(clusterId).update({
        'officers': officers,
        'updated_at': FieldValue.serverTimestamp(),
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
      // Get current cluster data
      final clusterDoc =
          await _firestore.collection('users').doc(clusterId).get();

      if (!clusterDoc.exists) {
        throw Exception('Cluster not found');
      }

      final clusterData = clusterDoc.data()!;
      final officers =
          List<Map<String, dynamic>>.from(clusterData['officers'] ?? []);

      // Remove officer
      officers.removeWhere((item) => item['id'] == officerId);

      // Update officers list
      await _firestore.collection('users').doc(clusterId).update({
        'officers': officers,
        'updated_at': FieldValue.serverTimestamp(),
      });

      return;
    } catch (e) {
      throw Exception('Failed to remove officer from cluster: $e');
    }
  }

  @override
  Future<List<UserModel.User>> getAllClusters() async {
    try {
      await _checkAuth();

      // ✅ CHANGED: Add more debug logging
      log('getAllClusters: Starting to fetch clusters...');

      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'patrol')
          .get();

      log('getAllClusters: Found ${snapshot.docs.length} documents with role=patrol');

      if (snapshot.docs.isEmpty) {
        log('getAllClusters: No clusters found in Firestore');
        return [];
      }

      final clusters = <UserModel.User>[];

      for (var doc in snapshot.docs) {
        try {
          final clusterData = doc.data();
          clusterData['id'] = doc.id;

          // ✅ ADDED: Debug log for each document
          log('getAllClusters: Processing document ${doc.id} with data: ${clusterData.keys.toList()}');

          // ✅ ADDED: Check if required fields exist
          if (clusterData['name'] == null) {
            log('getAllClusters: Document ${doc.id} missing name field, skipping');
            continue;
          }

          if (clusterData['email'] == null) {
            log('getAllClusters: Document ${doc.id} missing email field, skipping');
            continue;
          }

          // ✅ ADDED: Ensure role is exactly 'patrol'
          final role = clusterData['role']?.toString()?.toLowerCase();
          if (role != 'patrol') {
            log('getAllClusters: Document ${doc.id} has role "$role", expected "patrol", skipping');
            continue;
          }

          final cluster = UserModel.User.fromMap(clusterData);
          clusters.add(cluster);

          log('getAllClusters: Successfully added cluster: ${cluster.name} (${cluster.id})');
        } catch (e, stackTrace) {
          // ✅ IMPROVED: Better error logging
          log('getAllClusters: Error processing document ${doc.id}: $e');
          log('getAllClusters: Stack trace: $stackTrace');
          // Continue processing other clusters
        }
      }

      log('getAllClusters: Fetched ${clusters.length} valid clusters total');
      return clusters;
    } catch (e, stackTrace) {
      // ✅ IMPROVED: Better error logging
      log('getAllClusters: Fatal error: $e');
      log('getAllClusters: Stack trace: $stackTrace');
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

      // ✅ FIXED: Convert nested array to Firestore-compatible format
      final List<Map<String, double>> convertedCoordinates =
          coordinates.map((point) {
        if (point.length >= 2) {
          return {
            'lat': point[0],
            'lng': point[1],
          };
        }
        return {'lat': 0.0, 'lng': 0.0};
      }).toList();

      await _firestore.collection('users').doc(clusterId).update({
        'cluster_coordinates': convertedCoordinates, // ✅ Use converted format
        'updated_at': FieldValue.serverTimestamp(),
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

      // Archive instead of delete
      await _firestore.collection('users').doc(clusterId).update({
        'status': 'deleted',
        'updated_at': FieldValue.serverTimestamp(),
        'updated_by': _auth.currentUser?.uid,
      });

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

      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) {
        return null;
      }

      final userData = doc.data()!;
      userData['id'] = userId;
      return UserModel.User.fromMap(userData);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<Officer>> getClusterOfficers(String clusterId) async {
    try {
      final doc = await _firestore.collection('users').doc(clusterId).get();

      if (!doc.exists) {
        return [];
      }

      final clusterData = doc.data()!;
      final officersData = clusterData['officers'] as List?;

      if (officersData == null) {
        return [];
      }

      final officers = <Officer>[];

      for (var officerData in officersData) {
        if (officerData != null) {
          try {
            final officerMap = Map<String, dynamic>.from(officerData);
            officers.add(Officer.fromMap(officerMap));
          } catch (e) {
            // Continue processing other officers
          }
        }
      }

      return officers;
    } catch (e) {
      throw Exception('Failed to get cluster officers: $e');
    }
  }

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
      updates['updated_at'] = FieldValue.serverTimestamp();
      await _firestore.collection('users').doc(clusterId).update(updates);
    } catch (e) {
      throw Exception('Failed to update cluster: $e');
    }
  }

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

      // Catat detail percobaan ke subcollection
      await _firestore
          .collection('tasks')
          .doc(taskId)
          .collection('mock_detections')
          .add(mockData);

      // Simpan juga di koleksi terpisah untuk analisis
      await _firestore.collection('mock_location_logs').add({
        ...mockData,
        'taskId': taskId,
        'userId': userId,
        'detectionTime': FieldValue.serverTimestamp(),
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
      final snapshot = await _firestore
          .collection('tasks')
          .doc(taskId)
          .collection('mock_detections')
          .orderBy('timestamp')
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<int> getMockLocationCount(String taskId) async {
    try {
      final doc = await _firestore.collection('tasks').doc(taskId).get();

      if (!doc.exists) {
        return 0;
      }

      final taskData = doc.data()!;
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
