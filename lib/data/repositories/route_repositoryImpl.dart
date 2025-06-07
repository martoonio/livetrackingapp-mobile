// lib/data/repositories/route_repositoryImpl.dart

// import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:developer'; // Import for log

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
      final snapshot = await _database
          .child('tasks')
          .orderByChild('userId')
          .equalTo(userId)
          .get();

      if (!snapshot.exists) {
        return null;
      }

      Map<dynamic, dynamic> tasks;
      try {
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
          return null;
        }
      } catch (e) {
        // log('Error converting snapshot value to map in getCurrentTask: $e');
        return null;
      }

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
      } catch (e) {
        // log('Error finding active task in getCurrentTask: $e');
        activeTaskEntry = null;
      }

      if (activeTaskEntry == null || activeTaskEntry.key == null) {
        return null;
      }

      final taskData = activeTaskEntry.value as Map<dynamic, dynamic>;

      String? officerName;
      String? officerPhotoUrl;
      try {
        if (taskData['userId'] != null) {
          final officerId = taskData['userId'].toString();
          final clusterId = taskData['clusterId']?.toString();

          if (clusterId != null && clusterId.isNotEmpty) {
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
          }
        }
      } catch (e) {
        // log('Error fetching officer info in getCurrentTask: $e');
      }

      final task = _convertToPatrolTask({
        ...taskData,
        'taskId': activeTaskEntry.key,
        'officerName': officerName,
        'officerPhotoUrl': officerPhotoUrl,
      });

      final recalculatedTimeliness = determineTimelinessStatus(
          task.assignedStartTime,
          task.startTime,
          task.assignedEndTime,
          task.status);

      if (task.timeliness != recalculatedTimeliness) {
        await updateTask(task.taskId, {'timeliness': recalculatedTimeliness});
        return task.copyWith(timeliness: recalculatedTimeliness);
      }

      return task;
    } catch (e, stackTrace) {
      // log('Error in getCurrentTask: $e\n$stackTrace');
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
        final timeliness = determineTimelinessStatus(task.assignedStartTime,
            task.startTime, task.assignedEndTime, status);

        await _database.child('tasks').child(taskId).update({
          'timeliness': timeliness,
        });
      }
    } catch (e) {
      // log('Error in updateTaskStatus: $e');
      rethrow;
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
        // log('Not authenticated for updatePatrolLocation'); // Debug
      } else {
        // log('Authenticated user: ${user.uid} for updatePatrolLocation'); // Debug
      }

      final taskRef = _database.child('tasks').child(taskId);

      final timestampKey = timestamp.millisecondsSinceEpoch.toString();

      final locationData = {
        'coordinates': coordinates,
        'timestamp': timestamp.toIso8601String(),
      };

      try {
        await taskRef.child('route_path').child(timestampKey).set(locationData);
      } catch (e) {
        final updates = {
          'route_path/$timestampKey': locationData,
        };
        await taskRef.update(updates);
      }

      await taskRef.child('lastLocation').set(locationData);
    } catch (e, stackTrace) {
      // log('Failed to update location: $e\n$stackTrace');
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
              } catch (e) {
                // log('Error fetching officer info in getFinishedTasks: $e');
              }
            }

            final task = _convertToPatrolTask({
              ...taskData,
              'taskId': entry.key,
              'officerName': officerName,
              'officerPhotoUrl': officerPhotoUrl,
            });

            finishedTasks.add(task);
          }
        } catch (e) {
          // log('Error processing task entry in getFinishedTasks: $e');
        }
      });

      finishedTasks.sort((a, b) =>
          (b.endTime ?? DateTime.now()).compareTo(a.endTime ?? DateTime.now()));

      return finishedTasks;
    } catch (e) {
      // log('Error in getFinishedTasks: $e');
      return [];
    }
  }

  // --- PEMBAHARUAN KRITIS: watchCurrentTask menggunakan listener onChild... ---
  @override
  Stream<PatrolTask?> watchCurrentTask(String userId) {
    // Gunakan StreamController untuk memancarkan perubahan yang digabungkan dari beberapa listener
    final controller = StreamController<PatrolTask?>.broadcast();

    // Simpan referensi ke tugas yang sedang aktif secara lokal
    PatrolTask? currentActiveTask;

    // Listener untuk status 'active'
    final activeQuery = _database
        .child('tasks')
        .orderByChild('userId')
        .equalTo(userId)
        .orderByChild('status')
        .equalTo('active');
    activeQuery.onChildAdded.listen((event) => _handleChildEvent(
        event, controller, userId, 'active', 'added', currentActiveTask));
    activeQuery.onChildChanged.listen((event) => _handleChildEvent(
        event, controller, userId, 'active', 'changed', currentActiveTask));
    activeQuery.onChildRemoved.listen((event) => _handleChildEvent(
        event, controller, userId, 'active', 'removed', currentActiveTask));

    // Listener untuk status 'ongoing'
    final ongoingQuery = _database
        .child('tasks')
        .orderByChild('userId')
        .equalTo(userId)
        .orderByChild('status')
        .equalTo('ongoing');
    ongoingQuery.onChildAdded.listen((event) => _handleChildEvent(
        event, controller, userId, 'ongoing', 'added', currentActiveTask));
    ongoingQuery.onChildChanged.listen((event) => _handleChildEvent(
        event, controller, userId, 'ongoing', 'changed', currentActiveTask));
    ongoingQuery.onChildRemoved.listen((event) => _handleChildEvent(
        event, controller, userId, 'ongoing', 'removed', currentActiveTask));

    // Listener untuk status 'in_progress'
    final inProgressQuery = _database
        .child('tasks')
        .orderByChild('userId')
        .equalTo(userId)
        .orderByChild('status')
        .equalTo('in_progress');
    inProgressQuery.onChildAdded.listen((event) => _handleChildEvent(
        event, controller, userId, 'in_progress', 'added', currentActiveTask));
    inProgressQuery.onChildChanged.listen((event) => _handleChildEvent(event,
        controller, userId, 'in_progress', 'changed', currentActiveTask));
    inProgressQuery.onChildRemoved.listen((event) => _handleChildEvent(event,
        controller, userId, 'in_progress', 'removed', currentActiveTask));

    // Saat controller ditutup, pastikan listener juga dibatalkan
    controller.onCancel = () {
      // Tidak perlu membatalkan listener di sini, karena mereka adalah global.
      // Firebase Realtime Database secara otomatis mengelola listener berdasarkan Query yang sama.
      // Jika Anda memiliki listener terpisah yang dikelola oleh objek ini, batalkan di sini.
    };

    return controller.stream;
  }

  // Helper untuk memproses event onChild... dan memancarkan ke stream
  Future<void> _handleChildEvent(
    DatabaseEvent event,
    StreamController<PatrolTask?> controller,
    String userId,
    String relevantStatus,
    String eventType,
    PatrolTask? currentActiveTask, // Menerima referensi tugas aktif saat ini
  ) async {
    try {
      final taskId = event.snapshot.key;
      final taskData = event.snapshot.value as Map<dynamic, dynamic>?;

      if (eventType == 'removed') {
        if (currentActiveTask?.taskId == taskId) {
          // Jika tugas aktif saat ini dihapus, set ke null
          controller.sink.add(null);
        }
        return;
      }

      if (taskData == null) return;

      final status = taskData['status']?.toString().toLowerCase();

      // Perbarui currentActiveTask secara lokal jika ada yang cocok
      if (status == 'active' ||
          status == 'ongoing' ||
          status == 'in_progress') {
        final task = _convertToPatrolTask({
          ...taskData,
          'taskId': taskId,
        });
        currentActiveTask = task; // Update referensi lokal
        controller.sink.add(task);
      } else {
        // Jika tugas aktif berubah status menjadi tidak aktif
        if (currentActiveTask?.taskId == taskId) {
          controller.sink.add(null);
          currentActiveTask = null; // Set ke null
        }
      }
    } catch (e, stackTrace) {
      // log('Error handling child event for watchCurrentTask: $e\n$stackTrace');
      controller.addError(e);
    }
  }

  // --- PEMBAHARUAN KRITIS: watchFinishedTasks menggunakan listener onChild... ---
  @override
  Stream<List<PatrolTask>> watchFinishedTasks(String userId) {
    final controller = StreamController<List<PatrolTask>>.broadcast();
    List<PatrolTask> finishedTasks =
        []; // Daftar lokal untuk tasks yang selesai

    final finishedQuery = _database
        .child('tasks')
        .orderByChild('userId')
        .equalTo(userId)
        .orderByChild('status')
        .equalTo('finished');
    finishedQuery.onChildAdded.listen((event) =>
        _handleFinishedChildEvent(event, controller, finishedTasks, 'added'));
    finishedQuery.onChildChanged.listen((event) =>
        _handleFinishedChildEvent(event, controller, finishedTasks, 'changed'));
    finishedQuery.onChildRemoved.listen((event) =>
        _handleFinishedChildEvent(event, controller, finishedTasks, 'removed'));

    final cancelledQuery = _database
        .child('tasks')
        .orderByChild('userId')
        .equalTo(userId)
        .orderByChild('status')
        .equalTo('cancelled');
    cancelledQuery.onChildAdded.listen((event) =>
        _handleFinishedChildEvent(event, controller, finishedTasks, 'added'));
    cancelledQuery.onChildChanged.listen((event) =>
        _handleFinishedChildEvent(event, controller, finishedTasks, 'changed'));
    cancelledQuery.onChildRemoved.listen((event) =>
        _handleFinishedChildEvent(event, controller, finishedTasks, 'removed'));

    final expiredQuery = _database
        .child('tasks')
        .orderByChild('userId')
        .equalTo(userId)
        .orderByChild('status')
        .equalTo('expired');
    expiredQuery.onChildAdded.listen((event) =>
        _handleFinishedChildEvent(event, controller, finishedTasks, 'added'));
    expiredQuery.onChildChanged.listen((event) =>
        _handleFinishedChildEvent(event, controller, finishedTasks, 'changed'));
    expiredQuery.onChildRemoved.listen((event) =>
        _handleFinishedChildEvent(event, controller, finishedTasks, 'removed'));

    // Memuat data awal untuk inisialisasi daftar
    getFinishedTasks(userId).then((initialTasks) {
      finishedTasks = initialTasks;
      controller.sink.add(List.from(finishedTasks)); // Memancarkan data awal
    }).catchError((e) {
      // log('Error loading initial finished tasks: $e');
      controller.addError(e);
    });

    controller.onCancel = () {
      // Firebase Realtime Database secara otomatis mengelola listener berdasarkan Query yang sama.
    };

    return controller.stream;
  }

  // Helper untuk memproses event onChild... dan memancarkan ke stream finished tasks
  Future<void> _handleFinishedChildEvent(
    DatabaseEvent event,
    StreamController<List<PatrolTask>> controller,
    List<PatrolTask> finishedTasks, // Daftar lokal
    String eventType,
  ) async {
    try {
      final taskId = event.snapshot.key;
      final taskData = event.snapshot.value as Map<dynamic, dynamic>?;

      if (eventType == 'removed') {
        finishedTasks.removeWhere((task) => task.taskId == taskId);
      } else if (taskData != null) {
        final task = _convertToPatrolTask({
          ...taskData,
          'taskId': taskId,
        });

        // Perbarui officerName dan officerPhotoUrl secara asinkron
        // (Ini akan memanggil Firebase lagi, pertimbangkan caching jika terlalu sering)
        await task.fetchOfficerName(_database);

        final index = finishedTasks.indexWhere((t) => t.taskId == taskId);
        if (index != -1) {
          finishedTasks[index] = task;
        } else {
          // Hanya tambahkan jika statusnya 'finished'/'cancelled'/'expired'
          final status = task.status.toLowerCase();
          if (status == 'finished' ||
              status == 'cancelled' ||
              status == 'expired') {
            finishedTasks.add(task);
          } else {
            // Jika status berubah dari finished/cancelled/expired ke status aktif, hapus dari daftar
            finishedTasks.removeWhere((t) => t.taskId == taskId);
          }
        }
      }

      // Urutkan ulang daftar setelah perubahan
      finishedTasks.sort((a, b) =>
          (b.endTime ?? DateTime.now()).compareTo(a.endTime ?? DateTime.now()));

      controller.sink.add(List.from(
          finishedTasks)); // Memancarkan salinan daftar yang diperbarui
    } catch (e, stackTrace) {
      // log('Error handling finished child event: $e\n$stackTrace');
      controller.addError(e);
    }
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    try {
      if (value is String) {
        return DateTime.parse(value);
      } else if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } else if (value is Map && value['_seconds'] != null) {
        return DateTime.fromMillisecondsSinceEpoch(
            (value['_seconds'] as int) * 1000);
      }
    } catch (e) {
      // log('Error parsing datetime: $value, error: $e');
    }

    return null;
  }

  List<List<double>>? _parseRouteCoordinates(dynamic value) {
    if (value == null) return null;

    try {
      if (value is List) {
        return value
            .map<List<double>>((point) {
              if (point is List && point.length >= 2) {
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
      // log('Error parsing route coordinates: $e');
    }

    return null;
  }

  // --- PEMBAHARUAN KRITIS: _convertToPatrolTask TIDAK LAGI memuat routePath secara default ---
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
      // routePath: data['route_path'] != null ? Map<String, dynamic>.from(data['route_path'] as Map) : null, // HAPUS ATAU KOMENTARI BARIS INI
      clusterId: data['clusterId']?.toString() ?? '',
      mockLocationDetected: data['mockLocationDetected'] == true,
      mockLocationCount: data['mockLocationCount'] is num
          ? (data['mockLocationCount'] as num).toInt()
          : 0,
      finalReportPhotoUrl: data['finalReportPhotoUrl']?.toString(),
      finalReportNote: data['finalReportNote']?.toString(),
      finalReportTime: _parseDateTime(data['finalReportTime']),
      initialReportPhotoUrl: data['initialReportPhotoUrl']?.toString(),
      initialReportNote: data['initialReportNote']?.toString(),
      initialReportTime: _parseDateTime(data['initialReportTime']),
      officerName: data['officerName']?.toString() ?? '',
      clusterName: data['clusterName']?.toString() ?? '',
      timeliness: data['timeliness']
          ?.toString(), // Pastikan timeliness ada di PatrolTask
    );
  }

  // --- IMPLEMENTASI BARU: getTaskRoutePath untuk lazy loading ---
  @override
  Future<Map<String, dynamic>?> getTaskRoutePath(String taskId) async {
    try {
      final snapshot = await _database.child('tasks/$taskId/route_path').get();
      if (snapshot.exists && snapshot.value != null) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      // log('Error getting task route path for $taskId: $e');
      return null;
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
      // log('Error getting task by ID: $e');
      return null;
    }
  }

  @override
  Future<void> updateTask(String taskId, Map<String, dynamic> updates) async {
    try {
      final taskSnapshot = await _database.child('tasks').child(taskId).get();

      if (!taskSnapshot.exists) {
        throw Exception('Task not found');
      }

      final formattedUpdates = Map<String, dynamic>.from(updates);
      for (final key in formattedUpdates.keys) {
        final value = formattedUpdates[key];
        if (value is DateTime) {
          formattedUpdates[key] = value.toIso8601String();
        }
      }

      await _database.child('tasks').child(taskId).update(formattedUpdates);
    } catch (e, stackTrace) {
      // log('Failed to update task: $e\n$stackTrace');
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

      return taskId;
    } catch (e) {
      // log('Failed to create task: $e');
      throw Exception('Failed to create task: $e');
    }
  }

  @override
  Future<List<PatrolTask>> getAllTasks() async {
    try {
      final snapshot = await _database.child('tasks').get();

      if (!snapshot.exists || snapshot.value == null) {
        // log('No tasks found in database');
        return [];
      }

      final tasksMap = snapshot.value as Map<dynamic, dynamic>;
      // log('Found ${tasksMap.length} tasks in database');

      return _convertMapToTaskList(tasksMap);
    } catch (e) {
      // log('Error in getAllTasks: $e');
      return [];
    }
  }

  @override
  Future<List<PatrolTask>> getActiveTasks(
      {int limit = 50, String? lastKey}) async {
    try {
      log('getActiveTasks called: limit=$limit, lastKey=$lastKey');
      List<PatrolTask> allTasks = [];

      // Query for 'active' status
      Query activeQuery =
          _database.child('tasks').orderByChild('status').equalTo('active');
      if (lastKey != null) {
        log('Warning: lastKey for getActiveTasks is currently not fully implemented for compound query pagination.');
      }
      activeQuery =
          activeQuery.limitToLast(limit); // Fetch N most recent 'active' tasks

      // Query for 'ongoing' status
      Query ongoingQuery =
          _database.child('tasks').orderByChild('status').equalTo('ongoing');
      ongoingQuery = ongoingQuery
          .limitToLast(limit); // Fetch N most recent 'ongoing' tasks

      // Fetch both in parallel
      final activeSnapshotFuture = activeQuery.get();
      final ongoingSnapshotFuture = ongoingQuery.get();

      final activeSnapshot = await activeSnapshotFuture;
      if (activeSnapshot.exists && activeSnapshot.value != null) {
        allTasks.addAll(_convertMapToTaskList(
            activeSnapshot.value as Map<dynamic, dynamic>));
      }

      final ongoingSnapshot = await ongoingSnapshotFuture;
      if (ongoingSnapshot.exists && ongoingSnapshot.value != null) {
        allTasks.addAll(_convertMapToTaskList(
            ongoingSnapshot.value as Map<dynamic, dynamic>));
      }

      // Remove duplicates and sort to ensure consistent order
      final Map<String, PatrolTask> uniqueTasks = {};
      for (var task in allTasks) {
        uniqueTasks[task.taskId] = task;
      }
      final result = uniqueTasks.values.toList();
      result.sort((a, b) =>
          b.createdAt.compareTo(a.createdAt)); // Sort by createdAt DESC

      return result.take(limit).toList(); // Ensure final limit
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<PatrolTask>> getOngoingTasks(
      {int limit = 50, String? lastKey}) async {
    try {
      log('getOngoingTasks called: limit=$limit, lastKey=$lastKey');
      Query query =
          _database.child('tasks').orderByChild('status').equalTo('ongoing');

      if (lastKey != null) {
        log('Warning: lastKey for getOngoingTasks is currently not fully implemented for compound query pagination.');
      }
      query = query.limitToFirst(limit); // Fetch N most recent 'ongoing' tasks

      final snapshot = await query.get();
      if (!snapshot.exists) return [];

      final tasksMap = snapshot.value as Map<dynamic, dynamic>;
      final result = _convertMapToTaskList(tasksMap);
      result.sort((a, b) =>
          b.createdAt.compareTo(a.createdAt)); // Sort by createdAt DESC
      log('Found ${result.length} ongoing tasks');
      return result.take(limit).toList(); // Ensure final limit
    } catch (e) {
      log('Error in getOngoingTasks: $e');
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
      Query query = _database.child('tasks');

      final startTimestamp = startDate.millisecondsSinceEpoch;
      final endTimestamp = endDate.millisecondsSinceEpoch;

      if (status != null) {
        query = query.orderByChild('status').equalTo(status);
      } else {
        query = query.orderByChild('createdAt');
      }

      if (lastKey != null) {
        query = query.startAfter(lastKey);
      }

      query = query.limitToFirst(limit);

      final snapshot = await query.get();
      if (!snapshot.exists) return [];

      final tasksMap = snapshot.value as Map<dynamic, dynamic>;
      final tasks = _convertMapToTaskList(tasksMap);

      return tasks.where((task) {
        final taskTimestamp = task.createdAt.millisecondsSinceEpoch;
        return taskTimestamp >= startTimestamp && taskTimestamp <= endTimestamp;
      }).toList();
    } catch (e) {
      // log('Error in getTasksByDateRange: $e');
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
      // Get all tasks for the cluster first
      final snapshot = await _database
          .child('tasks')
          .orderByChild('clusterId')
          .equalTo(clusterId)
          .get();

      if (!snapshot.exists || snapshot.value == null) {
        return [];
      }

      final tasksMap = snapshot.value as Map<dynamic, dynamic>;
      List<PatrolTask> allTasks = _convertMapToTaskList(tasksMap);

      // Filter by status if specified
      if (status != null) {
        allTasks = allTasks
            .where((task) => task.status.toLowerCase() == status.toLowerCase())
            .toList();
      }

      // Sort by createdAt (newest first)
      allTasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Apply pagination client-side
      int startIndex = 0;
      if (lastKey != null) {
        // Find the index of the task with the given createdAt timestamp
        startIndex = allTasks.indexWhere(
                (task) => task.createdAt.toIso8601String() == lastKey) +
            1;
      }

      final endIndex = (startIndex + limit).clamp(0, allTasks.length);
      final paginatedTasks = allTasks.sublist(startIndex, endIndex);

      log('Fetched ${paginatedTasks.length} tasks for cluster $clusterId, status $status');
      return paginatedTasks;
    } catch (e, stackTrace) {
      log('Error in getClusterTasks for $clusterId: $e\n$stackTrace');
      return [];
    }
  }

  @override
  Future<List<PatrolTask>> getActiveAndCancelledTasks(String clusterId,
      {int limit = 20}) async {
    try {
      final snapshot = await _database
          .child('tasks')
          .orderByChild('clusterId')
          .equalTo(clusterId)
          .get();

      if (!snapshot.exists || snapshot.value == null) {
        return [];
      }

      final tasksMap = snapshot.value as Map<dynamic, dynamic>;
      final allTasks = _convertMapToTaskList(tasksMap);

      final filteredTasks = allTasks
          .where((task) =>
              task.status.toLowerCase() == 'active' ||
              task.status.toLowerCase() == 'cancelled')
          .toList();

      filteredTasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return filteredTasks.take(limit).toList();
    } catch (e) {
      // log('Error getting active and cancelled tasks for $clusterId: $e');
      return [];
    }
  }

  List<PatrolTask> _convertMapToTaskList(Map<dynamic, dynamic> tasksMap) {
    final tasks = <PatrolTask>[];

    tasksMap.forEach((key, value) {
      if (value is Map) {
        try {
          final taskData = Map<String, dynamic>.from(value);
          taskData['taskId'] = key.toString();

          if (_isValidTaskData(taskData)) {
            final task = _convertToPatrolTask(taskData);
            tasks.add(task);
          } else {
            // log('Invalid task data for key $key: missing required fields');
          }
        } catch (e) {
          // log('Error converting task $key: $e');
        }
      }
    });

    tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return tasks;
  }

  @override
  Future<List<PatrolTask>> getAllClusterTasks(String clusterId) async {
    try {
      // log('getAllClusterTasks called for: $clusterId');

      final snapshot = await _database
          .child('tasks')
          .orderByChild('clusterId')
          .equalTo(clusterId)
          .get();

      if (!snapshot.exists || snapshot.value == null) {
        // log('No tasks found for cluster $clusterId');
        return [];
      }

      final tasksMap = snapshot.value as Map<dynamic, dynamic>;
      final allTasks = _convertMapToTaskList(tasksMap);

      // log('Found ${allTasks.length} total tasks for cluster $clusterId');
      return allTasks;
    } catch (e) {
      // log('Error in getAllClusterTasks for $clusterId: $e');
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
      // log('getRecentTasks called: limit=$limit, lastKey=$lastKey');

      Query query = _database.child('tasks').orderByKey();

      if (lastKey != null) {
        query = query.endBefore(lastKey);
      }

      query = query.limitToLast(limit);

      final snapshot = await query.get();

      if (!snapshot.exists || snapshot.value == null) {
        // log('No recent tasks found');
        return [];
      }

      final tasksMap = snapshot.value as Map<dynamic, dynamic>;
      // log('Found ${tasksMap.length} recent tasks');

      return _convertMapToTaskList(tasksMap);
    } catch (e) {
      // log('Error in getRecentTasks: $e');
      return [];
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
        return value
            .whereType<String>()
            .where((item) => item.isNotEmpty)
            .toList();
      } else if (value is Map) {
        return value.values
            .where((item) => item != null)
            .map((item) => item.toString())
            .toList();
      }

      return [];
    } catch (e) {
      // log('Failed to get vehicles: $e');
      throw Exception('Failed to get vehicles: $e');
    }
  }

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
      // log('Failed to get cluster details: $e');
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
      final firebaseAuth = FirebaseAuth.instance;
      final userCredential = await firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final userId = userCredential.user!.uid;

      final now = DateTime.now().toIso8601String();
      await _database.child('users/$userId').set({
        'name': name,
        'email': email,
        'role': role,
        'cluster_coordinates': clusterCoordinates,
        'officers': [],
        'created_at': now,
        'updated_at': now,
      });

      await firebaseAuth.signOut();

      return;
    } catch (e) {
      // log('Failed to create cluster account: $e');
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
      // log('Failed to update cluster account: $e');
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

      final officerRef = _database.child('users/$clusterId/officers').push();

      final String officerId = officerRef.key!;

      final updatedOfficer = Officer(
        id: officerId,
        name: officer.name,
        shift: officer.shift,
        type: officer.type,
        clusterId: clusterId,
        photoUrl: officer.photoUrl,
      );

      await officerRef.set(updatedOfficer.toMap());

      await _database.child('users/$clusterId').update({
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': _auth.currentUser?.uid,
      });

      return;
    } catch (e) {
      // log('Failed to add officer to cluster: $e');
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

      if (task.endTime != null && task.startTime == null) {
        // log('Found corrupted task $taskId: has endTime but no startTime');

        fixes['endTime'] = null;
        fixes['status'] = 'active';
        fixes['distance'] = null;
        fixes['corruptionFixed'] = true;
        fixes['fixedAt'] = DateTime.now().toIso8601String();
        needsUpdate = true;
      }

      if (task.initialReportTime != null && task.assignedStartTime != null) {
        final reportTime = task.initialReportTime!;
        final scheduledTime = task.assignedStartTime!;

        if (reportTime
            .isBefore(scheduledTime.subtract(const Duration(hours: 1)))) {
          // log('Warning: Task $taskId has early initial report');
          fixes['earlyReportDetected'] = true;
          needsUpdate = true;
        }
      }

      if (task.status == 'finished' && task.startTime == null) {
        // log('Found status inconsistency in task $taskId');
        fixes['status'] = 'active';
        fixes['statusInconsistencyFixed'] = true;
        needsUpdate = true;
      }

      if (needsUpdate) {
        await updateTask(taskId, fixes);
        // log('Fixed data integrity issues for task $taskId');
      }
    } catch (e) {
      // log('Error checking task integrity for $taskId: $e');
    }
  }

  @override
  Future<void> fixCorruptedTasks() async {
    try {
      final snapshot = await _database.child('tasks').get();
      if (!snapshot.exists) return;

      final tasksMap = snapshot.value as Map<dynamic, dynamic>;
      int fixedCount = 0;

      for (var entry in tasksMap.entries) {
        final taskId = entry.key;
        final taskData = entry.value as Map<dynamic, dynamic>;

        if (taskData['endTime'] != null && taskData['startTime'] == null) {
          // log('Fixing corrupted task: $taskId');

          await _database.child('tasks').child(taskId).update({
            'endTime': null,
            'status': 'active',
            'distance': null,
            'corruptionFixed': true,
            'fixedAt': ServerValue.timestamp,
            'originalEndTime': taskData['endTime'],
          });

          fixedCount++;
        }
      }

      // log('Fixed $fixedCount corrupted tasks');
    } catch (e) {
      // log('Error fixing corrupted tasks: $e');
    }
  }

  @override
  Future<bool> validateTaskIntegrity(String taskId) async {
    try {
      final task = await getTaskById(taskId: taskId);
      if (task == null) return false;

      if (task.endTime != null && task.startTime == null) {
        return false;
      }

      if (task.status == 'finished' && task.startTime == null) {
        return false;
      }

      return true;
    } catch (e) {
      // log('Error validating task integrity: $e');
      return false;
    }
  }

  @override
  Future<void> updateOfficerInCluster({
    required String clusterId,
    required Officer officer,
  }) async {
    try {
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

      final index = officersList.indexWhere(
        (item) => item['id'] == officer.id,
      );

      if (index == -1) {
        throw Exception('Officer not found in cluster');
      }

      officersList[index] = officer.toMap();

      await _database.child('users/$clusterId').update({
        'officers': officersList,
        'updated_at': DateTime.now().toIso8601String(),
      });

      return;
    } catch (e) {
      // log('Failed to update officer in cluster: $e');
      throw Exception('Failed to update officer in cluster: $e');
    }
  }

  @override
  Future<void> removeOfficerFromCluster({
    required String clusterId,
    required String officerId,
  }) async {
    try {
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

      officersList.removeWhere((item) => item['id'] == officerId);

      await _database.child('users/$clusterId').update({
        'officers': officersList,
        'updated_at': DateTime.now().toIso8601String(),
      });

      return;
    } catch (e) {
      // log('Failed to remove officer from cluster: $e');
      throw Exception('Failed to remove officer from cluster: $e');
    }
  }

  @override
  Future<List<UserModel.User>> getAllClusters(
      {int limit = 50, String? lastKey}) async {
    try {
      await _checkAuth();
      // Perbaikan: Hanya satu orderByChild diizinkan per kueri.
      // Kita akan order berdasarkan 'role' dan filter dengan 'equalTo'
      // Firebase akan secara implisit menggunakan kunci (UID) sebagai tie-breaker.
      Query query =
          _database.child('users').orderByChild('role').equalTo('patrol');

      // Jika lastKey ada, gunakan untuk paginasi.
      // lastKey di sini diharapkan adalah kunci (UID) dari item terakhir yang dimuat.
      if (lastKey != null) {
        query = query.startAfter(lastKey);
      }
      query = query.limitToFirst(limit);

      final snapshot = await query.get();

      if (!snapshot.exists) {
        return [];
      }

      final clustersMap = Map<String, dynamic>.from(snapshot.value as Map);
      final clusters = <UserModel.User>[];

      // Konversi hasil snapshot ke daftar User model
      clustersMap.forEach((userId, userData) {
        if (userData is Map) {
          try {
            final clusterData = Map<String, dynamic>.from(userData);
            clusterData['id'] = userId.toString();
            clusters.add(UserModel.User.fromMap(clusterData));
          } catch (e) {
            log('Error converting cluster map entry: $e');
          }
        }
      });

      // Karena kita menggunakan `orderByChild('role').equalTo('patrol')` yang kemudian implicit `orderByKey()`,
      // hasilnya sudah terurut. Jika ingin urutan berdasarkan `name`, itu perlu client-side sorting
      // atau penyesuaian query yang lebih kompleks (misalnya, hanya `orderByChild('name')` dan filter role di client).

      log('Fetched ${clusters.length} clusters with limit $limit, lastKey $lastKey');
      return clusters;
    } catch (e) {
      log('Failed to get clusters: $e');
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
      // log('Failed to update cluster coordinates: $e');
      throw Exception('Failed to update cluster coordinates: $e');
    }
  }

  @override
  Future<void> deleteCluster(String clusterId) async {
    try {
      await _checkAuth();

      await _database.child('users/$clusterId').update({
        'status': 'deleted',
        'updated_at': DateTime.now().toIso8601String(),
        'updated_by': _auth.currentUser?.uid,
      });

      return;
    } catch (e) {
      // log('Failed to delete cluster: $e');
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
      // log('Error getting current user cluster: $e');
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
              // log('Error parsing officer from list: $e');
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
              // log('Error parsing officer from map entry: $e');
            }
          }
        });
      }

      return officers;
    } catch (e) {
      // log('Failed to get cluster officers: $e');
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
      // log('Failed to search clusters: $e');
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
      // log('Failed to update cluster: $e');
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
      await updateTask(taskId, {
        'mockLocationDetected': true,
        'mockLocationCount': mockData['count'] ?? 1,
        'lastMockDetection': mockData['timestamp'],
      });

      final database = FirebaseDatabase.instance.ref();

      await database
          .child('tasks/$taskId/mock_detections')
          .push()
          .set(mockData);

      await database.child('mock_location_logs').push().set({
        ...mockData,
        'taskId': taskId,
        'userId': userId,
        'detectionTime': ServerValue.timestamp,
      });

      return;
    } catch (e) {
      // log('Failed to log mock location: $e');
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

      detections.sort((a, b) =>
          (a['timestamp'] as String).compareTo(b['timestamp'] as String));

      return detections;
    } catch (e) {
      // log('Error getting mock location detections: $e');
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
      // log('Error getting mock location count: $e');
      return 0;
    }
  }

  String determineTimelinessStatus(DateTime? assignedStartTime,
      DateTime? startTime, DateTime? assignedEndTime, String status) {
    if (startTime == null) {
      return 'idle';
    }

    if (assignedStartTime != null) {
      final lateThreshold = assignedStartTime.add(const Duration(minutes: 10));
      final earlyThreshold =
          assignedStartTime.subtract(const Duration(minutes: 10));

      if (startTime.isAfter(lateThreshold)) {
        if (assignedEndTime != null && startTime.isAfter(assignedEndTime)) {
          return 'pastDue';
        }
        return 'late';
      } else if (startTime.isAfter(earlyThreshold) ||
          startTime.isAtSameMomentAs(earlyThreshold)) {
        return 'ontime';
      } else {
        return 'early';
      }
    }

    return 'ontime';
  }

  Future<void> updateTaskTimeliness(String taskId) async {
    try {
      final task = await getTaskById(taskId: taskId);
      if (task == null) return;

      final timeliness = determineTimelinessStatus(task.assignedStartTime,
          task.startTime, task.assignedEndTime, task.status);

      if (task.timeliness != timeliness) {
        await updateTask(taskId, {'timeliness': timeliness});
      }
    } catch (e) {
      // log('Error updating task timeliness: $e');
    }
  }
}
