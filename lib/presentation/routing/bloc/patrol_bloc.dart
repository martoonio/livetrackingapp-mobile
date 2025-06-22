import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/presentation/patrol/services/local_patrol_service.dart';
import 'package:livetrackingapp/presentation/report/bloc/report_bloc.dart';
import 'package:livetrackingapp/presentation/report/bloc/report_event.dart';
import '../../../domain/entities/patrol_task.dart';
import '../../../domain/repositories/route_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import '../../../services/det_device_info.dart';
import '../../../services/location_validator.dart';
import 'package:livetrackingapp/notification_utils.dart';

// Events
abstract class PatrolEvent {}

class LoadRouteData extends PatrolEvent {
  final String userId;
  LoadRouteData({required this.userId});
}

class StartPatrol extends PatrolEvent {
  final DateTime startTime;
  final PatrolTask task;

  StartPatrol({
    required this.startTime,
    required this.task,
  });

  List<Object> get props => [startTime, task];
}

class CheckOngoingPatrol extends PatrolEvent {
  final String userId;
  CheckOngoingPatrol({required this.userId});
}

class UpdatePatrolLocation extends PatrolEvent {
  final Position position;
  final DateTime timestamp;

  UpdatePatrolLocation({
    required this.position,
    required this.timestamp,
  });
}

class StopPatrol extends PatrolEvent {
  final DateTime endTime;
  final double distance;
  final Map<String, dynamic>? finalRoutePath;

  StopPatrol({
    required this.endTime,
    required this.distance,
    this.finalRoutePath,
  });
}

class LoadPatrolHistory extends PatrolEvent {
  final String userId;

  LoadPatrolHistory({required this.userId});

  List<Object?> get props => [userId];
}

class UpdateCurrentTask extends PatrolEvent {
  final PatrolTask task;
  UpdateCurrentTask({required this.task});
  List<Object?> get props => [task];
}

class UpdateFinishedTasks extends PatrolEvent {
  final List<PatrolTask> tasks;
  UpdateFinishedTasks({required this.tasks});
  List<Object?> get props => [tasks];
}

class ResumePatrol extends PatrolEvent {
  final PatrolTask task;
  final DateTime startTime;
  final double currentDistance;
  final Map<String, dynamic>? existingRoutePath;

  ResumePatrol({
    required this.task,
    required this.startTime,
    required this.currentDistance,
    this.existingRoutePath,
  });
}

class CheckMissedCheckpoints extends PatrolEvent {
  final PatrolTask task;
  CheckMissedCheckpoints({required this.task});
}

class SyncOfflineData extends PatrolEvent {}

class DebugOfflineData extends PatrolEvent {}

class SubmitFinalReport extends PatrolEvent {
  final String photoUrl;
  final String? note;
  final DateTime reportTime;

  SubmitFinalReport({
    required this.photoUrl,
    this.note,
    required this.reportTime,
  });

  @override
  List<Object?> get props => [photoUrl, note, reportTime];
}

class SubmitInitialReport extends PatrolEvent {
  final String photoUrl;
  final String? note;
  final DateTime reportTime;

  SubmitInitialReport({
    required this.photoUrl,
    this.note,
    required this.reportTime,
  });

  @override
  List<Object?> get props => [photoUrl, note, reportTime];
}

class UpdateConnectivityStatus extends PatrolEvent {
  final bool isOffline;

  UpdateConnectivityStatus({required this.isOffline});

  @override
  List<Object> get props => [isOffline];
}

class UpdateMockCount extends PatrolEvent {
  final int mockCount;

  UpdateMockCount({required this.mockCount});

  @override
  List<Object> get props => [mockCount];
}

// States
abstract class PatrolState {}

class PatrolInitial extends PatrolState {}

class PatrolLoading extends PatrolState {}

class PatrolLoaded extends PatrolState {
  final PatrolTask? task;
  final bool isPatrolling;
  final List<Position>? currentPatrolPath;
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? assignedStartTime;
  final DateTime? assignedEndTime;
  final double? distance;
  final Map<String, dynamic>? routePath;
  final List<PatrolTask> finishedTasks;
  final bool isSyncing;
  final bool isOffline;
  final bool mockLocationDetected;
  final DateTime? lastMockDetection;
  final int mockLocationCount;

  PatrolLoaded({
    this.task,
    this.isPatrolling = false,
    this.currentPatrolPath,
    this.startTime,
    this.endTime,
    this.assignedStartTime,
    this.assignedEndTime,
    this.distance,
    this.routePath,
    this.finishedTasks = const [],
    this.isSyncing = false,
    this.isOffline = false,
    this.mockLocationDetected = false,
    this.lastMockDetection,
    this.mockLocationCount = 0,
  });

  @override
  List<Object?> get props => [
        task,
        isPatrolling,
        startTime,
        endTime,
        assignedStartTime,
        assignedEndTime,
        distance,
        currentPatrolPath,
        routePath,
        finishedTasks,
        isSyncing,
        isOffline,
        mockLocationDetected,
        lastMockDetection,
        mockLocationCount,
      ];

  PatrolLoaded copyWith({
    PatrolTask? task,
    bool? isPatrolling,
    double? distance,
    DateTime? startTime,
    DateTime? endTime,
    DateTime? assignedStartTime,
    DateTime? assignedEndTime,
    List<Position>? currentPatrolPath,
    Map<String, dynamic>? routePath,
    List<PatrolTask>? finishedTasks,
    bool? isSyncing,
    bool? isOffline,
    bool? mockLocationDetected,
    DateTime? lastMockDetection,
    int? mockLocationCount,
  }) {
    return PatrolLoaded(
      task: task ?? this.task,
      isPatrolling: isPatrolling ?? this.isPatrolling,
      currentPatrolPath: currentPatrolPath ?? this.currentPatrolPath,
      distance: distance ?? this.distance,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      assignedStartTime: assignedStartTime ?? this.assignedStartTime,
      assignedEndTime: assignedEndTime ?? this.assignedEndTime,
      routePath: routePath ?? this.routePath,
      finishedTasks: finishedTasks ?? this.finishedTasks,
      isSyncing: isSyncing ?? this.isSyncing,
      isOffline: isOffline ?? this.isOffline,
      mockLocationDetected: mockLocationDetected ?? this.mockLocationDetected,
      lastMockDetection: lastMockDetection ?? this.lastMockDetection,
      mockLocationCount: mockLocationCount ?? this.mockLocationCount,
    );
  }
}

class PatrolError extends PatrolState {
  final String message;
  PatrolError(this.message);
}

// BLoC
class PatrolBloc extends Bloc<PatrolEvent, PatrolState> {
  final RouteRepository repository;
  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription<PatrolTask?>? _taskSubscription;
  StreamSubscription<List<PatrolTask>>? _historySubscription;
  StreamSubscription<dynamic>? _connectivitySubscription;
  Box<dynamic>? _offlineLocationBox;
  bool _isConnected = true;

  // Tambahkan periodic timer untuk memeriksa timeliness secara berkala
  Timer? _timelinessTimer;

  double? _clusterValidationRadius;

  // ✅ Tambahkan buffer untuk prevent race condition
  bool _localPatrollingState = false;
  String? _localPatrollingTaskId;
  Timer? _stateStabilityTimer;

  PatrolBloc({required this.repository}) : super(PatrolInitial()) {
    on<LoadRouteData>(_onLoadRouteData);
    on<StartPatrol>(_onStartPatrol);
    on<UpdatePatrolLocation>(_onUpdatePatrolLocation);
    on<StopPatrol>(_onStopPatrol);
    on<UpdateTask>(_onUpdateTask);
    on<LoadPatrolHistory>(_onLoadPatrolHistory);
    on<UpdateFinishedTasks>(_onUpdateFinishedTasks);
    on<UpdateCurrentTask>(_onUpdateCurrentTask);
    on<CheckOngoingPatrol>(_onCheckOngoingPatrol);
    on<ResumePatrol>(_onResumePatrol);
    on<SyncOfflineData>(_onSyncOfflineData);
    on<DebugOfflineData>(_onDebugOfflineData);
    on<SubmitFinalReport>(_onSubmitFinalReport);
    on<SubmitInitialReport>(_onSubmitInitialReport);
    on<UpdateMockCount>(_onUpdateMockCount);
    on<UpdateConnectivityStatus>(_onUpdateConnectivityStatus);
    on<CheckMissedCheckpoints>(_onCheckMissedCheckpoints);

    _initializeStorage();
    _setupConnectivityMonitoring();

    // Setup timer to check timeliness periodically
    _startTimelinessTimer();
  }

  Future<void> _loadClusterValidationRadius(String clusterId) async {
    if (clusterId.isEmpty) {
      _clusterValidationRadius = 50.0; // Default fallback
      return;
    }

    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('users')
          .child(clusterId)
          .child('checkpoint_validation_radius')
          .get();

      if (snapshot.exists && snapshot.value != null) {
        _clusterValidationRadius = (snapshot.value as num).toDouble();
        print(
            'PatrolBloc: Loaded cluster validation radius: ${_clusterValidationRadius}m for cluster $clusterId');
      } else {
        _clusterValidationRadius = 50.0; // Default fallback
        print(
            'PatrolBloc: No cluster validation radius found, using default: 50m');
      }
    } catch (e) {
      print('PatrolBloc: Error loading cluster validation radius: $e');
      _clusterValidationRadius = 50.0; // Default fallback
    }
  }

  void _onDebugOfflineData(
    DebugOfflineData event,
    Emitter<PatrolState> emit,
  ) {
    debugPrintOfflineData();
  }

  void _onUpdateConnectivityStatus(
      UpdateConnectivityStatus event, Emitter<PatrolState> emit) {
    if (state is PatrolLoaded) {
      final currentState = state as PatrolLoaded;
      emit(currentState.copyWith(isOffline: event.isOffline));

      // Trigger sinkronisasi jika kembali online
      if (!event.isOffline) {
        add(SyncOfflineData());

        // Note: Report sync should be handled by the UI layer, not here
        // Since we don't have access to BuildContext in the bloc
      }
    }
  }

  Future<void> _onUpdateTask(
    UpdateTask event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      if (_isConnected) {
        await repository.updateTask(
          event.taskId,
          event.updates,
        );
      } else {
        if (_offlineLocationBox != null) {
          final key =
              'task_update_${event.taskId}_${DateTime.now().millisecondsSinceEpoch}';
          await _offlineLocationBox!.put(key, {
            'taskId': event.taskId,
            'updates': event.updates,
          });
        }
      }

      if (state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;
        final isInProgress = event.updates['status'] == 'ongoing';

        emit(PatrolLoaded(
          task: currentState.task!.copyWith(
            status: event.updates['status'] as String?,
            startTime: event.updates['startTime'] != null
                ? DateTime.parse(event.updates['startTime'] as String)
                : null,
          ),
          isPatrolling: isInProgress,
          isOffline: !_isConnected,
        ));
      }
    } catch (e) {
      emit(PatrolError('Failed to update task: $e'));
    }
  }

  void debugPrintOfflineData() {
    if (_offlineLocationBox == null || _offlineLocationBox!.isEmpty) {
      return;
    }

    // Group by type
    final stopKeys = _offlineLocationBox!.keys
        .where((k) => k.toString().startsWith('patrol_stop_'))
        .toList();

    final startKeys = _offlineLocationBox!.keys
        .where((k) => k.toString().startsWith('patrol_start_'))
        .toList();

    final updateKeys = _offlineLocationBox!.keys
        .where((k) => k.toString().startsWith('task_update_'))
        .toList();

    final locationKeys = _offlineLocationBox!.keys
        .where((k) =>
            !k.toString().startsWith('patrol_') &&
            !k.toString().startsWith('task_'))
        .toList();

    for (final key in startKeys) {
      final data = _offlineLocationBox!.get(key);
    }

    for (final key in stopKeys) {
      final data = _offlineLocationBox!.get(key);
    }

    for (final key in updateKeys) {
      final data = _offlineLocationBox!.get(key);
    }

    if (locationKeys.length > 10) {
      for (final key in locationKeys.take(5)) {
        final data = _offlineLocationBox!.get(key);
      }
      for (final key in locationKeys.skip(locationKeys.length - 5)) {
        final data = _offlineLocationBox!.get(key);
      }
    } else {
      for (final key in locationKeys) {
        final data = _offlineLocationBox!.get(key);
      }
    }
  }

  Future<void> _initializeStorage() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await Hive.initFlutter(dir.path);
      _offlineLocationBox = await Hive.openBox('offline_locations');
    } catch (e) {}
  }

  void _setupConnectivityMonitoring() {
    // ✅ Initial connectivity check dengan validation
    // _checkInitialConnectivity();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) async {
        final result =
            results.isNotEmpty ? results.first : ConnectivityResult.none;
        final wasConnected = _isConnected;

        // ✅ Basic connectivity check
        _isConnected = (result != ConnectivityResult.none);

        // ✅ Only trigger sync if truly reconnected dan ada data
        if (!wasConnected && _isConnected) {
          print('🌐 Connectivity restored, checking if sync needed...');

          // Delay sync untuk stabilkan koneksi
          await Future.delayed(Duration(seconds: 3));

          // Double-check connectivity masih stabil
          try {
            final testResponse = await FirebaseDatabase.instance
                .ref('.info/connected')
                .get()
                .timeout(Duration(seconds: 5));

            final reallyConnected =
                testResponse.exists && (testResponse.value == true);

            if (reallyConnected &&
                _offlineLocationBox != null &&
                _offlineLocationBox!.isNotEmpty) {
              print('✅ Stable connection confirmed, triggering sync...');
              add(SyncOfflineData());
            } else {
              print('⚠️ Connection not stable or no data to sync');
            }
          } catch (e) {
            print('❌ Connection test failed: $e');
          }
        }

        // Update state
        if (state is PatrolLoaded) {
          final currentState = state as PatrolLoaded;
          emit(currentState.copyWith(isOffline: !_isConnected));
        }
      },
    );
  }

  // lib/presentation/routing/bloc/patrol_bloc.dart
// Update method _onSyncOfflineData:

  Future<void> _onSyncOfflineData(
    SyncOfflineData event,
    Emitter<PatrolState> emit,
  ) async {
    print('🔄 Starting offline data sync...');

    // ✅ PERBAIKAN: Enhanced connectivity validation
    bool isReallyConnected = false;

    try {
      // 1. Check basic connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        print('❌ No connectivity detected - aborting sync');
        return;
      }

      // 2. Test actual internet connection with quick ping
      try {
        final testResponse = await FirebaseDatabase.instance
            .ref('.info/connected')
            .get()
            .timeout(Duration(seconds: 5));

        isReallyConnected = testResponse.exists && (testResponse.value == true);
        print('🌐 Firebase connection test: $isReallyConnected');
      } catch (e) {
        print('❌ Firebase connection test failed: $e');
        isReallyConnected = false;
      }

      if (!isReallyConnected) {
        print('❌ No stable internet connection - aborting sync');
        return;
      }
    } catch (e) {
      print('❌ Connectivity check failed: $e');
      return;
    }

    if (_offlineLocationBox == null) {
      print('⚠️ No offline storage available');
      return;
    }

    if (_offlineLocationBox!.isEmpty) {
      print('ℹ️ No offline data to sync');
      return;
    }

    try {
      if (state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;
        emit(currentState.copyWith(isSyncing: true));

        print('🔄 Starting sync with stable connection...');
        print('📊 Total offline items: ${_offlineLocationBox!.length}');

        // ✅ PERBAIKAN: Collect all successful syncs untuk batch delete
        List<String> successfulSyncs = [];

        // ✅ 1. SYNC PATROL START DATA dengan enhanced error handling
        await _syncPatrolStartData(successfulSyncs);

        // ✅ 2. SYNC PATROL STOP DATA
        await _syncPatrolStopData(successfulSyncs);

        // ✅ 3. SYNC LOCATION DATA dengan improved batching
        await _syncLocationData(successfulSyncs);

        // ✅ 4. SYNC MOCK DETECTION DATA
        await _syncMockDetectionData(successfulSyncs);

        // ✅ 5. SYNC TASK UPDATE DATA
        await _syncTaskUpdateData(successfulSyncs);

        // ✅ PERBAIKAN: Batch delete only successful syncs
        await _batchDeleteSuccessfulSyncs(successfulSyncs);

        // ✅ Update state
        emit(currentState.copyWith(
          isSyncing: false,
          isOffline: false,
        ));

        final remainingItems = _offlineLocationBox!.length;
        print('📊 Sync completed. Remaining items: $remainingItems');

        if (remainingItems > 0) {
          print('⚠️ Some items failed to sync and were preserved');
          _debugRemainingOfflineData();
        } else {
          print('✅ All offline data synced successfully');
        }
      }
    } catch (e, stack) {
      print('❌ Error during offline sync: $e');
      print('📍 Stack trace: $stack');

      if (state is PatrolLoaded) {
        emit((state as PatrolLoaded).copyWith(isSyncing: false));
      }
    }
  }

// ✅ PERBAIKAN: Enhanced sync methods dengan better error handling

  Future<void> _syncPatrolStartData(List<String> successfulSyncs) async {
    final startKeys = _offlineLocationBox!.keys
        .where((k) => k.toString().startsWith('patrol_start_'))
        .toList();

    print('🔄 Syncing ${startKeys.length} patrol start records...');

    for (final key in startKeys) {
      try {
        final data = _offlineLocationBox!.get(key);
        if (data != null && data is Map) {
          final taskId = data['taskId'] as String;
          final updateData = Map<String, dynamic>.from(data)..remove('taskId');

          print('🔄 Syncing patrol start for: $taskId');

          // ✅ PERBAIKAN: Realistic timeout dan better retry
          bool syncSuccess = await _performReliableUpdate(
            taskId,
            updateData,
            operation: 'patrol_start',
          );

          if (syncSuccess) {
            successfulSyncs.add(key.toString());
            print('✅ Patrol start synced: $taskId');
          } else {
            print('❌ Failed to sync patrol start: $taskId - preserving data');
          }
        }
      } catch (e) {
        print('❌ Error syncing patrol start $key: $e');
      }
    }
  }

  Future<void> _syncPatrolStopData(List<String> successfulSyncs) async {
    final stopKeys = _offlineLocationBox!.keys
        .where((k) => k.toString().startsWith('patrol_stop_'))
        .toList();

    print('🔄 Syncing ${stopKeys.length} patrol stop records...');

    for (final key in stopKeys) {
      try {
        final data = _offlineLocationBox!.get(key);
        if (data != null && data is Map) {
          final taskId = data['taskId'] as String;
          final endTime = DateTime.parse(data['endTime'] as String);
          final distance = data['distance'] as double;

          print('🔄 Syncing patrol stop for: $taskId');

          bool syncSuccess = await _performReliableTaskStatusUpdate(
            taskId,
            endTime,
            distance,
          );

          if (syncSuccess) {
            successfulSyncs.add(key.toString());
            print('✅ Patrol stop synced: $taskId');
          } else {
            print('❌ Failed to sync patrol stop: $taskId - preserving data');
          }
        }
      } catch (e) {
        print('❌ Error syncing patrol stop $key: $e');
      }
    }
  }

  Future<void> _syncLocationData(List<String> successfulSyncs) async {
    final locationKeys = _offlineLocationBox!.keys
        .where((k) =>
            !k.toString().startsWith('patrol_stop_') &&
            !k.toString().startsWith('task_update_') &&
            !k.toString().startsWith('patrol_start_') &&
            !k.toString().startsWith('mock_detection_'))
        .toList();

    print('🔄 Syncing ${locationKeys.length} location records...');

    // ✅ PERBAIKAN: Group by task dan batch process
    final locationDataByTask = <String, Map<String, dynamic>>{};

    for (final key in locationKeys) {
      try {
        final data = _offlineLocationBox!.get(key);
        if (data != null && data is Map && data['taskId'] != null) {
          final taskId = data['taskId'] as String;
          final timestamp = data['timestamp'] as String;
          final latitude = data['latitude'] as double;
          final longitude = data['longitude'] as double;

          // ✅ Enhanced coordinate validation
          if (_isValidCoordinate(latitude, longitude)) {
            locationDataByTask[taskId] ??= {};
            locationDataByTask[taskId]![key.toString()] = {
              'coordinates': [latitude, longitude],
              'timestamp': timestamp,
            };
          } else {
            print(
                '⚠️ Invalid coordinates skipped: lat=$latitude, lng=$longitude');
            // Mark for deletion since it's invalid data
            successfulSyncs.add(key.toString());
          }
        }
      } catch (e) {
        print('❌ Error processing location data $key: $e');
      }
    }

    // ✅ Sync location data per task dengan enhanced merging
    for (final taskId in locationDataByTask.keys) {
      try {
        print(
            '🔄 Syncing ${locationDataByTask[taskId]!.length} location points for: $taskId');

        bool syncSuccess = await _performReliableLocationSync(
          taskId,
          locationDataByTask[taskId]!,
        );

        if (syncSuccess) {
          // Mark all location points for this task as successful
          successfulSyncs.addAll(locationDataByTask[taskId]!.keys);
          print('✅ Location data synced for task: $taskId');
        } else {
          print(
              '❌ Failed to sync location data for task: $taskId - preserving data');
        }
      } catch (e) {
        print('❌ Error syncing location data for $taskId: $e');
      }
    }
  }

  Future<void> _syncMockDetectionData(List<String> successfulSyncs) async {
    final mockDetectionKeys = _offlineLocationBox!.keys
        .where((k) => k.toString().startsWith('mock_detection_'))
        .toList();

    if (mockDetectionKeys.isEmpty) return;

    print('🔄 Syncing ${mockDetectionKeys.length} mock detection records...');

    for (final key in mockDetectionKeys) {
      try {
        final data = _offlineLocationBox!.get(key);
        if (data != null && data is Map) {
          final taskId = data['taskId'] as String;

          bool syncSuccess =
              await _performReliableMockDetectionSync(taskId, data);

          if (syncSuccess) {
            successfulSyncs.add(key.toString());
            print('✅ Mock detection synced: $taskId');
          } else {
            print('❌ Failed to sync mock detection: $taskId - preserving data');
          }
        }
      } catch (e) {
        print('❌ Error syncing mock detection $key: $e');
      }
    }
  }

  Future<void> _syncTaskUpdateData(List<String> successfulSyncs) async {
    final updateKeys = _offlineLocationBox!.keys
        .where((k) => k.toString().startsWith('task_update_'))
        .toList();

    print('🔄 Syncing ${updateKeys.length} task update records...');

    for (final key in updateKeys) {
      try {
        final data = _offlineLocationBox!.get(key);
        if (data != null && data is Map) {
          final taskId = data['taskId'] as String;
          final updates = data['updates'] as Map<dynamic, dynamic>;

          bool syncSuccess = await _performReliableUpdate(
            taskId,
            Map<String, dynamic>.from(updates),
            operation: 'task_update',
          );

          if (syncSuccess) {
            successfulSyncs.add(key.toString());
            print('✅ Task update synced: $taskId');
          } else {
            print('❌ Failed to sync task update: $taskId - preserving data');
          }
        }
      } catch (e) {
        print('❌ Error syncing task update $key: $e');
      }
    }
  }

// ✅ PERBAIKAN: Batch delete dengan error handling
  Future<void> _batchDeleteSuccessfulSyncs(List<String> successfulSyncs) async {
    if (successfulSyncs.isEmpty) {
      print('ℹ️ No successful syncs to delete');
      return;
    }

    print(
        '🗑️ Batch deleting ${successfulSyncs.length} successfully synced items...');

    int deletedCount = 0;
    for (final key in successfulSyncs) {
      try {
        await _offlineLocationBox!.delete(key);
        deletedCount++;
      } catch (e) {
        print('❌ Error deleting key $key: $e');
      }
    }

    print(
        '✅ Successfully deleted $deletedCount/${successfulSyncs.length} items');
  }

// ✅ PERBAIKAN: Reliable update dengan proper error handling
  Future<bool> _performReliableUpdate(
      String taskId, Map<String, dynamic> updateData,
      {required String operation}) async {
    const maxRetries = 2; // Reduced retries untuk koneksi buruk
    const baseTimeout = 8; // Shorter timeout

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🔄 $operation attempt $attempt/$maxRetries for $taskId');

        await repository.updateTask(taskId, {
          ...updateData,
          'syncedAt': DateTime.now().toIso8601String(),
        }).timeout(
          Duration(seconds: baseTimeout * attempt), // Progressive timeout
          onTimeout: () => throw Exception(
              '$operation timeout after ${baseTimeout * attempt}s'),
        );

        print('✅ $operation successful on attempt $attempt');
        return true;
      } catch (e) {
        print('❌ $operation attempt $attempt failed: $e');

        if (attempt < maxRetries) {
          // Shorter delay untuk koneksi buruk
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }

    print('❌ All $operation attempts failed for $taskId');
    return false;
  }

// ✅ PERBAIKAN: Reliable task status update
  Future<bool> _performReliableTaskStatusUpdate(
    String taskId,
    DateTime endTime,
    double distance,
  ) async {
    const maxRetries = 2;
    const baseTimeout = 8;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🔄 Task status update attempt $attempt/$maxRetries for $taskId');

        // Update status first
        await repository.updateTaskStatus(taskId, 'finished').timeout(
              Duration(seconds: baseTimeout),
              onTimeout: () => throw Exception('Status update timeout'),
            );

        // Then update details
        await repository.updateTask(taskId, {
          'endTime': endTime.toIso8601String(),
          'distance': distance,
          'status': 'finished',
          'syncedAt': DateTime.now().toIso8601String(),
        }).timeout(
          Duration(seconds: baseTimeout),
          onTimeout: () => throw Exception('Task update timeout'),
        );

        print('✅ Task status update successful on attempt $attempt');
        return true;
      } catch (e) {
        print('❌ Task status update attempt $attempt failed: $e');

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }

    return false;
  }

// ✅ PERBAIKAN: Reliable location sync dengan smart merging
  Future<bool> _performReliableLocationSync(
    String taskId,
    Map<String, dynamic> locationData,
  ) async {
    const maxRetries = 2;
    const baseTimeout = 10;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('🔄 Location sync attempt $attempt/$maxRetries for $taskId');

        // ✅ Get existing route path dengan timeout
        Map<String, dynamic> existingRoutePath = {};
        try {
          final taskSnapshot = await repository
              .getTaskById(taskId: taskId)
              .timeout(Duration(seconds: 5));

          if (taskSnapshot?.routePath != null) {
            existingRoutePath =
                Map<String, dynamic>.from(taskSnapshot!.routePath as Map);
            print(
                '📍 Found ${existingRoutePath.length} existing points in Firebase');
          }
        } catch (e) {
          print('⚠️ Could not get existing route path: $e');
          // Continue with empty existing path
        }

        // ✅ Smart merging - avoid duplicates
        final mergedRoutePath = Map<String, dynamic>.from(existingRoutePath);
        int newPointsAdded = 0;

        locationData.forEach((key, value) {
          if (!mergedRoutePath.containsKey(key)) {
            mergedRoutePath[key] = value;
            newPointsAdded++;
          }
        });

        if (newPointsAdded == 0) {
          print('ℹ️ No new points to add - all already exist');
          return true; // Consider this successful
        }

        // ✅ Calculate latest location
        Map<String, dynamic>? latestLocation;
        if (mergedRoutePath.isNotEmpty) {
          try {
            final sortedEntries = mergedRoutePath.entries.toList()
              ..sort((a, b) => (b.value['timestamp'] as String)
                  .compareTo(a.value['timestamp'] as String));

            if (sortedEntries.isNotEmpty) {
              latestLocation =
                  Map<String, dynamic>.from(sortedEntries.first.value as Map);
            }
          } catch (e) {
            print('⚠️ Error calculating latest location: $e');
          }
        }

        // ✅ Prepare update data
        final updateData = {
          'route_path': mergedRoutePath,
          'syncedAt': DateTime.now().toIso8601String(),
        };

        if (latestLocation != null) {
          updateData['lastLocation'] = latestLocation;
        }

        // ✅ Perform update dengan timeout
        await repository.updateTask(taskId, updateData).timeout(
              Duration(seconds: baseTimeout),
              onTimeout: () => throw Exception('Route update timeout'),
            );

        print('✅ Location sync successful on attempt $attempt');
        print(
            '📊 Added $newPointsAdded new points, total: ${mergedRoutePath.length}');
        return true;
      } catch (e) {
        print('❌ Location sync attempt $attempt failed: $e');

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }

    return false;
  }

// ✅ PERBAIKAN: Reliable mock detection sync
  Future<bool> _performReliableMockDetectionSync(
    String taskId,
    Map<dynamic, dynamic> data,
  ) async {
    const maxRetries = 2;
    const baseTimeout = 8;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print(
            '🔄 Mock detection sync attempt $attempt/$maxRetries for $taskId');

        // Update task
        await repository.updateTask(taskId, {
          'mockLocationDetected': true,
          'mockLocationCount': data['mockCount'] ?? 1,
          'lastMockDetection': data['timestamp'],
          'syncedAt': DateTime.now().toIso8601String(),
        }).timeout(
          Duration(seconds: baseTimeout),
          onTimeout: () => throw Exception('Mock detection update timeout'),
        );

        // Log to Firebase
        final database = FirebaseDatabase.instance.ref();
        await database.child('tasks/$taskId/mock_detections').push().set({
          'timestamp': data['timestamp'],
          'coordinates': [data['latitude'], data['longitude']],
          'accuracy': data['accuracy'],
          'speed': data['speed'],
          'altitude': data['altitude'],
          'heading': data['heading'],
          'count': data['mockCount'],
          'syncedFromOffline': true,
        }).timeout(
          Duration(seconds: baseTimeout),
          onTimeout: () => throw Exception('Mock log timeout'),
        );

        print('✅ Mock detection sync successful on attempt $attempt');
        return true;
      } catch (e) {
        print('❌ Mock detection sync attempt $attempt failed: $e');

        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }

    return false;
  }

// ✅ PERBAIKAN: Enhanced coordinate validation
  bool _isValidCoordinate(double latitude, double longitude) {
    return latitude.abs() <= 90 &&
        longitude.abs() <= 180 &&
        latitude != 0.0 &&
        longitude != 0.0 &&
        !latitude.isNaN &&
        !longitude.isNaN &&
        !latitude.isInfinite &&
        !longitude.isInfinite;
  }

// ✅ PERBAIKAN: Helper method untuk debug remaining data
  void _debugRemainingOfflineData() {
    if (_offlineLocationBox == null) return;

    print('🔍 DEBUG: Remaining offline data:');
    for (final key in _offlineLocationBox!.keys) {
      try {
        final data = _offlineLocationBox!.get(key);
        if (data is Map) {
          print(
              '   - $key: ${data['taskId'] ?? 'no taskId'} | ${data['timestamp'] ?? 'no timestamp'}');
        }
      } catch (e) {
        print('   - $key: error reading data');
      }
    }
  }

  Future<void> _onCheckOngoingPatrol(
    CheckOngoingPatrol event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      final task = await repository.getCurrentTask(event.userId);

      if (task != null &&
          (task.status == 'ongoing' || task.status == 'active')) {
        emit(PatrolLoaded(
          task: task,
          isPatrolling: true,
          routePath: task.routePath,
          isOffline: !_isConnected,
        ));

        _startLocationTracking();
      } else {}
    } catch (e) {
      emit(PatrolError('Failed to check ongoing patrol: $e'));
    }
  }

  Future<void> _onResumePatrol(
    ResumePatrol event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      print('🔄 PatrolBloc: Resuming patrol for task: ${event.task.taskId}');

      // ✅ STEP 1: Prepare updated task with all data
      final updatedTask = event.task.copyWith(
        status: 'ongoing',
        startTime: event.startTime,
        distance: event.currentDistance,
        routePath: event.existingRoutePath,
      );

      // ✅ STEP 2: Emit state immediately for UI responsiveness
      emit(PatrolLoaded(
        task: updatedTask,
        isPatrolling: true,
        distance: event.currentDistance,
        startTime: event.startTime,
        routePath: event.existingRoutePath,
        isOffline: !_isConnected,
      ));

      // ✅ STEP 3: Start location tracking immediately
      _startLocationTracking();

      // ✅ STEP 4: Sync to Firebase in background
      try {
        print('🔄 Syncing resume state to Firebase...');

        DatabaseReference _firebaseDatabase = FirebaseDatabase.instance.ref();
        final taskRef = _firebaseDatabase.child('tasks/${event.task.taskId}');

        final resumeUpdate = {
          'status': 'ongoing',
          'startTime': event.startTime.toIso8601String(),
          'distance': event.currentDistance,
          'lastUpdated': DateTime.now().toIso8601String(),
          'resumedAt': DateTime.now().toIso8601String(),
        };

        // Include route path if available
        if (event.existingRoutePath != null &&
            event.existingRoutePath!.isNotEmpty) {
          resumeUpdate['route_path'] = event.existingRoutePath!;
          print(
              '🔄 Including route path: ${event.existingRoutePath!.length} points');
        }

        await taskRef.update(resumeUpdate).timeout(
              Duration(seconds: 15),
              onTimeout: () => throw Exception('Resume sync timeout'),
            );

        print('✅ Resume state synced to Firebase successfully');
      } catch (firebaseError) {
        print('❌ Failed to sync resume state to Firebase: $firebaseError');
        // Continue anyway - local state is more important for UX
      }

      print('✅ Patrol resumed successfully in BLoC');
    } catch (e) {
      print('❌ Error resuming patrol in BLoC: $e');
      emit(PatrolError('Failed to resume patrol: $e'));
    }
  }

  Future<void> _onLoadPatrolHistory(
    LoadPatrolHistory event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      emit(PatrolLoading());

      if (!_isConnected) {
        emit(PatrolLoaded(
          finishedTasks: [],
          isOffline: true,
        ));
        return;
      }

      PatrolTask? currentTask;
      List<PatrolTask> finishedTasks = [];

      try {
        currentTask = await repository.getCurrentTask(event.userId);
      } catch (e) {
        currentTask = null;
      }

      try {
        finishedTasks = await repository.getFinishedTasks(event.userId);
      } catch (e) {
        finishedTasks = [];
      }

      bool isActiveTask = false;
      if (currentTask != null) {
        final status = currentTask.status.toLowerCase();
        isActiveTask = (status == 'active' ||
            status == 'ongoing' ||
            status == 'in_progress');
      }

      emit(PatrolLoaded(
        task: currentTask,
        finishedTasks: finishedTasks,
        distance: currentTask?.distance,
        isPatrolling: isActiveTask,
        startTime: currentTask?.startTime,
        routePath: currentTask?.routePath as Map<String, dynamic>?,
        isOffline: !_isConnected,
      ));
    } catch (e, stack) {
      emit(PatrolError('Failed to load patrol history: $e'));
    }
  }

  void _onUpdateFinishedTasks(
    UpdateFinishedTasks event,
    Emitter<PatrolState> emit,
  ) {
    if (state is PatrolLoaded) {
      final currentState = state as PatrolLoaded;
      emit(currentState.copyWith(finishedTasks: event.tasks));
    } else {
      emit(PatrolLoaded(
        finishedTasks: event.tasks,
        isOffline: !_isConnected,
      ));
    }
  }

  void _onUpdateCurrentTask(
    UpdateCurrentTask event,
    Emitter<PatrolState> emit,
  ) {
    try {
      if (event.task.clusterId.isNotEmpty) {
        _loadClusterValidationRadius(event.task.clusterId);
      }
      final isActiveTask = event.task.status == 'active' ||
          event.task.status == 'ongoing' ||
          event.task.status == 'in_progress';

      if (state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;
        emit(currentState.copyWith(
          task: event.task,
          isPatrolling: event.task.status == 'ongoing' ||
              event.task.status == 'in_progress',
        ));
      } else {
        emit(PatrolLoaded(
          task: event.task,
          isPatrolling: event.task.status == 'ongoing' ||
              event.task.status == 'in_progress',
          finishedTasks: const [],
          isOffline: !_isConnected,
        ));
      }
    } catch (e) {
      emit(PatrolError('Failed to update current task: $e'));
    }
  }

  Future<void> _onLoadRouteData(
    LoadRouteData event,
    Emitter<PatrolState> emit,
  ) async {
    emit(PatrolLoading());
    try {
      await _taskSubscription?.cancel();
      await _historySubscription?.cancel();

      if (!_isConnected) {
        emit(PatrolLoaded(
          finishedTasks: [],
          isOffline: true,
        ));
        return;
      }

      _taskSubscription = repository.watchCurrentTask(event.userId).listen(
        (task) {
          if (task != null) {
            add(UpdateCurrentTask(task: task));
          }
        },
        onError: (error) {
          emit(PatrolError('Failed to watch current task: $error'));
        },
      );

      _historySubscription = repository.watchFinishedTasks(event.userId).listen(
        (tasks) {
          add(UpdateFinishedTasks(tasks: tasks));
        },
        onError: (error) {
          emit(PatrolError('Failed to watch finished tasks: $error'));
        },
      );
    } catch (e) {
      emit(PatrolError(e.toString()));
    }
  }

  Future<void> _onStartPatrol(
    StartPatrol event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      // ✅ Set local state IMMEDIATELY
      _localPatrollingState = true;
      _localPatrollingTaskId = event.task.taskId;

      emit(PatrolLoading());

      final isValid = await repository.validateTaskIntegrity(event.task.taskId);
      if (!isValid) {
        // Try to fix the task
        await repository.checkAndFixTaskIntegrity(event.task.taskId);

        // Re-validate
        final isStillValid =
            await repository.validateTaskIntegrity(event.task.taskId);
        if (!isStillValid) {
          emit(PatrolError(
              'Task has integrity issues and cannot be started. Please contact admin.'));
          return;
        }
      }

      if (event.task.clusterId.isNotEmpty) {
        await _loadClusterValidationRadius(event.task.clusterId);
      }

      // TAMBAHAN: Validate task state sebelum start
      if (event.task.status == 'finished' || event.task.status == 'cancelled') {
        emit(PatrolError(
            'Cannot start patrol: task is already ${event.task.status}'));
        return;
      }

      // TAMBAHAN: Validate scheduled time
      final now = DateTime.now();
      final scheduledStart = event.task.assignedStartTime;
      if (scheduledStart != null) {
        final timeDiff = now.difference(scheduledStart).inMinutes;
        // Allow starting 30 minutes early or late
        if (timeDiff < -30) {
          emit(PatrolError(
              'Cannot start patrol: too early (${timeDiff.abs()} minutes before scheduled time)'));
          return;
        }
        if (timeDiff > 60) {
          emit(PatrolError(
              'Cannot start patrol: too late (${timeDiff} minutes after scheduled time)'));
          return;
        }
      }

      // ✅ Update state SEBELUM database operations
      final routePath = <String, dynamic>{};
      final timeliness = _calculateTimeliness(event.task.assignedStartTime,
          event.startTime, event.task.assignedEndTime, 'ongoing');

      final updatedTask = PatrolTask(
        taskId: event.task.taskId,
        userId: event.task.userId,
        status: 'ongoing',
        startTime: event.startTime,
        endTime: null,
        assignedStartTime: event.task.assignedStartTime,
        assignedEndTime: event.task.assignedEndTime,
        assignedRoute: event.task.assignedRoute,
        distance: 0.0,
        createdAt: event.task.createdAt,
        routePath: routePath,
        lastLocation: event.task.lastLocation,
        timeliness: timeliness,
        // TAMBAHAN: Copy other important fields
        clusterId: event.task.clusterId,
        clusterName: event.task.clusterName,
        officerName: event.task.officerName,
        officerPhotoUrl: event.task.officerPhotoUrl,
        initialReportPhotoUrl: event.task.initialReportPhotoUrl,
        initialReportNote: event.task.initialReportNote,
        initialReportTime: event.task.initialReportTime,
      );

      // ✅ Emit state SEBELUM database update
      emit(PatrolLoaded(
        task: updatedTask,
        isPatrolling: true,
        startTime: event.startTime,
        routePath: routePath,
        distance: 0.0,
        isOffline: !_isConnected,
      ));

      // Database update dalam background
      final updateData = {
        'status': 'ongoing',
        'startTime': event.startTime.toIso8601String(),
        'timeliness': timeliness,
        'endTime': null,
        'distance': 0.0,
        'actualStartTime': event.startTime.toIso8601String(),
        'startedFromApp': true,
      };

      if (_isConnected) {
        await repository.updateTask(event.task.taskId, updateData);
      } else {
        if (_offlineLocationBox != null) {
          await _offlineLocationBox!.put('patrol_start_${event.task.taskId}', {
            'taskId': event.task.taskId,
            ...updateData,
          });
        }
      }

      // ✅ Start location tracking IMMEDIATELY
      _startLocationTracking();

      // ✅ Stabilkan state
      _startStateStabilityTimer(event.task.taskId);

      print(
          'Patrol started with immediate UI update for task ${event.task.taskId}');
    } catch (e, stackTrace) {
      _localPatrollingState = false;
      _localPatrollingTaskId = null;
      print('Error in _onStartPatrol: $e');
      emit(PatrolError('Failed to start patrol: $e'));
    }
  }

  // ✅ Override method untuk cek patrolling status
  bool get isCurrentlyPatrolling {
    if (_localPatrollingState && _localPatrollingTaskId != null) {
      return true;
    }

    if (state is PatrolLoaded) {
      final currentState = state as PatrolLoaded;
      return currentState.isPatrolling;
    }

    return false;
  }

  // ✅ Timer untuk stabilkan state setelah database update
  void _startStateStabilityTimer(String taskId) {
    _stateStabilityTimer?.cancel();
    _stateStabilityTimer = Timer(Duration(seconds: 3), () {
      // Setelah 3 detik, trust database state
      if (_localPatrollingTaskId == taskId) {
        _localPatrollingState = false;
        _localPatrollingTaskId = null;
        print('State stability timer completed for task $taskId');
      }
    });
  }

  Future<void> _onUpdatePatrolLocation(
    UpdatePatrolLocation event,
    Emitter<PatrolState> emit,
  ) async {
    if (state is PatrolLoaded) {
      final currentState = state as PatrolLoaded;

      final shouldProcessLocation = isCurrentlyPatrolling &&
          currentState.task != null &&
          (currentState.isPatrolling || _localPatrollingState);

      if (shouldProcessLocation) {
        try {
          // ✅ Validate coordinates before processing
          if (!_isValidCoordinate(
              event.position.latitude, event.position.longitude)) {
            print(
                '⚠️ Invalid coordinates received, skipping: ${event.position.latitude}, ${event.position.longitude}');
            return;
          }

          final List<double> coordinates = [
            event.position.latitude,
            event.position.longitude
          ];

          final timestampKey =
              event.timestamp.millisecondsSinceEpoch.toString();
          final locationData = {
            'coordinates': coordinates,
            'timestamp': event.timestamp.toIso8601String(),
          };

          // ✅ Update local route path
          Map<String, dynamic> currentRoutePath =
              Map<String, dynamic>.from(currentState.routePath ?? {});

          // ✅ Check duplicate timestamps
          if (currentRoutePath.containsKey(timestampKey)) {
            print('⚠️ Duplicate timestamp detected, skipping: $timestampKey');
            return;
          }

          currentRoutePath[timestampKey] = locationData;

          bool databaseUpdateSuccess = false;
          if (_isConnected) {
            try {
              // ✅ PERBAIKAN: More robust Firebase update dengan timeout
              await repository
                  .updatePatrolLocation(
                    currentState.task!.taskId,
                    coordinates,
                    event.timestamp,
                  )
                  .timeout(
                    Duration(seconds: 8),
                    onTimeout: () => throw Exception('Location update timeout'),
                  );
              databaseUpdateSuccess = true;
              print('✅ Location updated to Firebase successfully');
            } catch (e) {
              print('❌ Failed to update Firebase location: $e');
              databaseUpdateSuccess = false;
            }
          }

          // ✅ PERBAIKAN: Always save to offline storage sebagai backup
          if (_offlineLocationBox != null) {
            try {
              await _offlineLocationBox!.put(timestampKey, {
                'latitude': event.position.latitude,
                'longitude': event.position.longitude,
                'timestamp': event.timestamp.toIso8601String(),
                'taskId': currentState.task!.taskId,
                'coordinates': coordinates,
                'locationData': locationData,
                'synced': databaseUpdateSuccess, // ✅ Mark sync status
              });
              print('💾 Location saved to offline storage: $timestampKey');
            } catch (e) {
              print('❌ Failed to save to offline storage: $e');
            }
          }

          // ✅ Update state
          final updatedTask = currentState.task!.copyWith(
            routePath: currentRoutePath,
            distance: _calculateNewDistance(currentState, event.position),
            lastLocation: locationData,
          );

          emit(currentState.copyWith(
            currentPatrolPath: [
              ...?currentState.currentPatrolPath,
              event.position
            ],
            routePath: currentRoutePath,
            distance: updatedTask.distance,
            task: updatedTask,
            isOffline: !_isConnected,
            isPatrolling: true,
          ));

          print(
              '✅ Location processed: ${coordinates}, total points: ${currentRoutePath.length}');
        } catch (e, stackTrace) {
          print('❌ Error processing location: $e');
          print('Stack trace: $stackTrace');
        }
      }
    }
  }

// ✅ Helper method untuk calculate distance
  double _calculateNewDistance(
      PatrolLoaded currentState, Position newPosition) {
    double newDistance = currentState.distance ?? 0.0;

    if (currentState.currentPatrolPath != null &&
        currentState.currentPatrolPath!.isNotEmpty) {
      final lastPosition = currentState.currentPatrolPath!.last;
      final distanceInMeters = Geolocator.distanceBetween(
        lastPosition.latitude,
        lastPosition.longitude,
        newPosition.latitude,
        newPosition.longitude,
      );

      if (distanceInMeters > 1.0 && distanceInMeters < 1000.0) {
        // Reasonable distance
        newDistance += distanceInMeters;
      }
    }

    return newDistance;
  }

  Future<void> _onStopPatrol(
      StopPatrol event, Emitter<PatrolState> emit) async {
    try {
      // print('🛑 Stopping patrol for task: ${event.taskId ?? "unknown"}');

      if (state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;

        // Emit stopping state first
        emit(currentState.copyWith(
          isSyncing: true,
          isPatrolling: false,
        ));

        if (currentState.task != null) {
          final taskId = currentState.task!.taskId;

          // ✅ ENHANCED: Multiple status update attempts
          for (int attempt = 1; attempt <= 3; attempt++) {
            try {
              print('🔄 Status update attempt $attempt/3');

              // Update task status to finished
              await repository.updateTaskStatus(taskId, 'finished').timeout(
                    Duration(seconds: 10),
                    onTimeout: () => throw Exception('Status update timeout'),
                  );

              // Update additional fields
              await repository.updateTask(taskId, {
                'endTime': event.endTime.toIso8601String(),
                'distance': event.distance,
                'status': 'finished',
                'route_path': event.finalRoutePath,
                // 'completedAt': DateTime.now().toIso8601String(),
                'lastUpdated': DateTime.now().toIso8601String(),
                // 'syncVersion': DateTime.now().millisecondsSinceEpoch,
              }).timeout(
                Duration(seconds: 15),
                onTimeout: () => throw Exception('Task update timeout'),
              );

              // ✅ CRITICAL: Force immediate status verification
              await Future.delayed(Duration(seconds: 1));

              final verifyTask = await repository
                  .getTaskById(taskId: taskId)
                  .timeout(Duration(seconds: 10));

              if (verifyTask?.status == 'finished') {
                print('✅ Status update verified on attempt $attempt');
                break;
              } else {
                throw Exception(
                    'Status verification failed: ${verifyTask?.status}');
              }
            } catch (e) {
              print('❌ Status update attempt $attempt failed: $e');

              if (attempt == 3) {
                throw Exception('All status update attempts failed');
              }

              await Future.delayed(Duration(seconds: attempt));
            }
          }

          // ✅ ENHANCED: Update local storage to completed immediately
          try {
            await LocalPatrolService.updatePatrolField(
              taskId: taskId,
              updates: {
                'status': 'finished',
                'endTime': event.endTime.toIso8601String(),
                'distance': event.distance,
                'syncedToFirebase': true,
                'completedAt': DateTime.now().toIso8601String(),
              },
            );
          } catch (localError) {
            print('❌ Error updating local status: $localError');
          }

          // Update state
          final updatedTask = currentState.task!.copyWith(
            status: 'finished',
            endTime: event.endTime,
            distance: event.distance,
            routePath: event.finalRoutePath,
          );

          emit(PatrolLoaded(
            task: updatedTask,
            isPatrolling: false,
            distance: event.distance,
            routePath: event.finalRoutePath,
            isSyncing: false,
            isOffline: false,
          ));

          print('✅ Patrol stopped successfully and status updated to finished');
        } else {
          print('⚠️ No task found in current state for stopping');
          emit(currentState.copyWith(
            isPatrolling: false,
            isSyncing: false,
          ));
        }
      }
    } catch (e) {
      print('❌ Error stopping patrol: $e');

      if (state is PatrolLoaded) {
        emit((state as PatrolLoaded).copyWith(
          isSyncing: false,
          isPatrolling: false,
        ));
      }
    }
  }

  // TAMBAHAN: Method untuk check dan fix data integrity
  Future<void> checkAndFixTaskIntegrity(String taskId) async {
    try {
      final task = await repository.getTaskById(taskId: taskId);
      if (task == null) return;

      bool needsUpdate = false;
      Map<String, dynamic> fixes = {};

      // Check 1: Has endTime but no startTime
      if (task.endTime != null && task.startTime == null) {
        print('Found corrupted task $taskId: has endTime but no startTime');

        // Option 1: Reset to active state
        fixes['endTime'] = null;
        fixes['status'] = 'active';
        fixes['distance'] = null;
        fixes['corruptionFixed'] = true;
        fixes['fixedAt'] = DateTime.now().toIso8601String();
        needsUpdate = true;
      }

      // Check 2: Has initialReportTime but wrong timing
      if (task.initialReportTime != null && task.assignedStartTime != null) {
        final reportTime = task.initialReportTime!;
        final scheduledTime = task.assignedStartTime!;

        // If report was made significantly before scheduled time
        if (reportTime.isBefore(scheduledTime.subtract(Duration(hours: 1)))) {
          print('Warning: Task $taskId has early initial report');
          fixes['earlyReportDetected'] = true;
          needsUpdate = true;
        }
      }

      // Check 3: Status inconsistency
      if (task.status == 'finished' && task.startTime == null) {
        print('Found status inconsistency in task $taskId');
        fixes['status'] = 'active';
        fixes['statusInconsistencyFixed'] = true;
        needsUpdate = true;
      }

      if (needsUpdate) {
        await repository.updateTask(taskId, fixes);
        print('Fixed data integrity issues for task $taskId');
      }
    } catch (e) {
      print('Error checking task integrity for $taskId: $e');
    }
  }

  void _startLocationTracking() {
    _locationSubscription?.cancel();

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(
      (Position position) {
        if (state is PatrolLoaded) {
          final currentState = state as PatrolLoaded;
          if (currentState.isPatrolling) {
            add(UpdatePatrolLocation(
              position: position,
              timestamp: DateTime.now(),
            ));
          } else {}
        }
      },
      onError: (error) {},
      cancelOnError: false,
    );
  }

  void _startTimelinessTimer() {
    _timelinessTimer?.cancel();
    _timelinessTimer = Timer.periodic(Duration(minutes: 1), (timer) {
      if (state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;
        if (currentState.task != null) {
          _checkAndUpdateTimeliness(currentState.task!);
        }
      }
    });
  }

  Future<void> _checkAndUpdateTimeliness(PatrolTask task) async {
    if (!_isConnected) return;

    try {
      // Recalculate timeliness
      final newTimeliness = _calculateTimeliness(task.assignedStartTime,
          task.startTime, task.assignedEndTime, task.status);

      // Only update if changed
      if (task.timeliness != newTimeliness) {
        await repository.updateTask(task.taskId, {'timeliness': newTimeliness});

        // Update state
        if (state is PatrolLoaded) {
          final currentState = state as PatrolLoaded;
          emit(currentState.copyWith(
            task: task.copyWith(timeliness: newTimeliness),
          ));
        }
      }
    } catch (e) {}
  }

  String _calculateTimeliness(DateTime? assignedStartTime, DateTime? startTime,
      DateTime? assignedEndTime, String status) {
    // Case 1: Belum dimulai
    if (startTime == null) {
      return 'idle';
    }

    // Case 2: Sudah dimulai, cek ketepatan waktu
    if (assignedStartTime != null) {
      // Ambang batas terlambat - 10 menit setelah jadwal
      final lateThreshold = assignedStartTime.add(Duration(minutes: 10));
      // Ambang batas terlalu awal - 10 menit sebelum jadwal
      final earlyThreshold = assignedStartTime.subtract(Duration(minutes: 10));

      // Jika terlambat lebih dari 10 menit
      if (startTime.isAfter(lateThreshold)) {
        // Jika melewati batas waktu akhir yang dijadwalkan
        if (assignedEndTime != null && startTime.isAfter(assignedEndTime)) {
          return 'pastDue';
        }
        return 'late';
      }
      // Jika dalam rentang -10 sampai +10 menit
      else if (startTime.isAfter(earlyThreshold) ||
          startTime.isAtSameMomentAs(earlyThreshold)) {
        return 'ontime';
      }
      // Jika terlalu awal (lebih dari 10 menit sebelum jadwal)
      else {
        return 'early';
      }
    }

    return 'ontime'; // Default jika tidak ada jadwal awal
  }

  Future<void> _onUpdateMockCount(
    UpdateMockCount event,
    Emitter<PatrolState> emit,
  ) async {
    if (state is PatrolLoaded) {
      final currentState = state as PatrolLoaded;
      emit(currentState.copyWith(
        mockLocationCount: event.mockCount,
        mockLocationDetected: true,
        lastMockDetection: DateTime.now(),
      ));
    }
  }

  @override
  Future<void> close() async {
    _stateStabilityTimer?.cancel();
    _timelinessTimer?.cancel();
    await _locationSubscription?.cancel();
    await _taskSubscription?.cancel();
    await _historySubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _offlineLocationBox?.close();

    _clusterValidationRadius = null;
    return super.close();
  }

  Future<void> _onSubmitFinalReport(
    SubmitFinalReport event,
    Emitter<PatrolState> emit,
  ) async {
    if (state is PatrolLoaded) {
      final currentState = state as PatrolLoaded;

      try {
        emit(PatrolLoading());

        final updatedTask = currentState.task?.copyWith(
          finalReportPhotoUrl: event.photoUrl,
          finalReportNote: event.note,
          finalReportTime: event.reportTime,
        );

        if (updatedTask != null) {
          await repository.updateTask(
            updatedTask.taskId,
            {
              'finalReportPhotoUrl': event.photoUrl,
              'finalReportNote': event.note,
              'finalReportTime': event.reportTime.toIso8601String(),
            },
          );

          emit(PatrolLoaded(
            task: updatedTask,
            isPatrolling: currentState.isPatrolling,
            distance: currentState.distance,
            finishedTasks: currentState.finishedTasks,
            routePath: currentState.routePath,
            isOffline: currentState.isOffline,
          ));
        }
      } catch (e) {
        emit(PatrolError('Failed to submit final report: $e'));
        emit(currentState);
      }
    }
  }

  Future<void> _onSubmitInitialReport(
    SubmitInitialReport event,
    Emitter<PatrolState> emit,
  ) async {
    if (state is PatrolLoaded) {
      final currentState = state as PatrolLoaded;

      try {
        // ✅ LANGSUNG set local patrolling state untuk mencegah race condition
        _localPatrollingState = true;
        _localPatrollingTaskId = currentState.task?.taskId;

        final updatedTask = currentState.task?.copyWith(
          initialReportPhotoUrl: event.photoUrl,
          initialReportNote: event.note,
          initialReportTime: event.reportTime,
        );

        if (updatedTask != null) {
          // ✅ Update state SEBELUM database call
          emit(currentState.copyWith(
            task: updatedTask,
            isPatrolling: true, // Langsung set true di UI
          ));

          // Database update dalam background
          await repository.updateTask(
            updatedTask.taskId,
            {
              'initialReportPhotoUrl': event.photoUrl,
              'initialReportNote': event.note,
              'initialReportTime': event.reportTime.toIso8601String(),
            },
          );

          // ✅ Stabilkan state setelah database update
          _startStateStabilityTimer(updatedTask.taskId);
        }
      } catch (e) {
        // Reset local state jika error
        _localPatrollingState = false;
        _localPatrollingTaskId = null;
        emit(PatrolError('Failed to submit initial report: $e'));
      }
    }
  }

  // Di patrol_bloc.dart
  Future<void> _onCheckMissedCheckpoints(
    CheckMissedCheckpoints event,
    Emitter<PatrolState> emit,
  ) async {
    // ✅ Enhanced logging
    print('🔍 Checking missed checkpoints for task: ${event.task.taskId}');
    print('   - Task status: ${event.task.status}');
    print('   - Is connected: $_isConnected');
    print(
        '   - Assigned route points: ${event.task.assignedRoute?.length ?? 0}');

    // ✅ Check jika patroli sudah selesai dan online
    if (!_isConnected) {
      print('⚠️ Offline - skipping missed checkpoints check');
      return;
    }

    if (event.task.status != 'finished') {
      print('⚠️ Task not finished - skipping missed checkpoints check');
      return;
    }

    try {
      final task = event.task;

      // ✅ Load cluster validation radius
      if (task.clusterId.isNotEmpty) {
        await _loadClusterValidationRadius(task.clusterId);
        print(
            '📏 Loaded cluster validation radius: $_clusterValidationRadius m');
      }

      // ✅ Get validation radius with proper priority
      final double validationRadius = _getValidationRadius(task);
      print('📏 Using validation radius: $validationRadius m');

      // ✅ Validate assigned route exists
      if (task.assignedRoute == null || task.assignedRoute!.isEmpty) {
        print('⚠️ No assigned route found - skipping validation');
        return;
      }

      // ✅ Get actual route path from task
      List<LatLng> actualRoutePath = [];

      // ✅ PERBAIKAN: Get route path dari berbagai sumber
      if (task.routePath != null && task.routePath!.isNotEmpty) {
        try {
          // Convert route_path to LatLng list
          final sortedEntries = task.routePath!.entries.toList()
            ..sort((a, b) => (a.value['timestamp'] as String)
                .compareTo(b.value['timestamp'] as String));

          for (var entry in sortedEntries) {
            if (entry.value is Map && entry.value['coordinates'] != null) {
              final coordinates = entry.value['coordinates'] as List;
              if (coordinates.length >= 2) {
                final lat = (coordinates[0] as num).toDouble();
                final lng = (coordinates[1] as num).toDouble();

                // ✅ Validate coordinates
                if (lat.abs() <= 90 &&
                    lng.abs() <= 180 &&
                    lat != 0.0 &&
                    lng != 0.0) {
                  actualRoutePath.add(LatLng(lat, lng));
                }
              }
            }
          }

          print(
              '📍 Extracted ${actualRoutePath.length} valid route points from task.routePath');
        } catch (e) {
          print('❌ Error extracting route path: $e');
        }
      }

      // ✅ Fallback: Try to get from current state
      if (actualRoutePath.isEmpty && state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;
        if (currentState.routePath != null &&
            currentState.routePath!.isNotEmpty) {
          try {
            final sortedEntries = currentState.routePath!.entries.toList()
              ..sort((a, b) => (a.value['timestamp'] as String)
                  .compareTo(b.value['timestamp'] as String));

            for (var entry in sortedEntries) {
              if (entry.value is Map && entry.value['coordinates'] != null) {
                final coordinates = entry.value['coordinates'] as List;
                if (coordinates.length >= 2) {
                  final lat = (coordinates[0] as num).toDouble();
                  final lng = (coordinates[1] as num).toDouble();

                  if (lat.abs() <= 90 &&
                      lng.abs() <= 180 &&
                      lat != 0.0 &&
                      lng != 0.0) {
                    actualRoutePath.add(LatLng(lat, lng));
                  }
                }
              }
            }

            print(
                '📍 Extracted ${actualRoutePath.length} valid route points from state.routePath');
          } catch (e) {
            print('❌ Error extracting route path from state: $e');
          }
        }
      }

      if (actualRoutePath.isEmpty) {
        print('⚠️ No actual route path found - cannot validate checkpoints');
        return;
      }

      // ✅ Convert assigned route to LatLng for validation
      List<LatLng> assignedCheckpoints = [];
      for (var checkpoint in task.assignedRoute!) {
        if (checkpoint.length >= 2) {
          assignedCheckpoints.add(LatLng(
            checkpoint[0].toDouble(),
            checkpoint[1].toDouble(),
          ));
        }
      }

      print(
          '🎯 Validating ${assignedCheckpoints.length} checkpoints against ${actualRoutePath.length} route points');

      // ✅ Check each assigned checkpoint
      List<List<double>> missedCheckpoints = [];

      for (int i = 0; i < assignedCheckpoints.length; i++) {
        final checkpoint = assignedCheckpoints[i];
        bool checkpointVisited = false;

        // ✅ Check if any actual route point is within validation radius
        for (final routePoint in actualRoutePath) {
          final distance = Geolocator.distanceBetween(
            checkpoint.latitude,
            checkpoint.longitude,
            routePoint.latitude,
            routePoint.longitude,
          );

          if (distance <= validationRadius) {
            checkpointVisited = true;
            print(
                '✅ Checkpoint ${i + 1} visited (distance: ${distance.toStringAsFixed(1)}m)');
            break;
          }
        }

        if (!checkpointVisited) {
          missedCheckpoints.add([checkpoint.latitude, checkpoint.longitude]);
          print(
              '❌ Checkpoint ${i + 1} MISSED (lat: ${checkpoint.latitude}, lng: ${checkpoint.longitude})');
        }
      }

      print(
          '📊 Validation result: ${missedCheckpoints.length} missed out of ${assignedCheckpoints.length} checkpoints');

      // ✅ Send notification if there are missed checkpoints
      if (missedCheckpoints.isNotEmpty) {
        print('🚨 Sending missed checkpoints notification...');

        try {
          // ✅ PERBAIKAN: Use correct function name and enhanced parameters
          await sendMissedCheckpointsNotificationWithRadius(
            patrolTaskId: task.taskId,
            officerName:
                task.officerName.isNotEmpty ? task.officerName : 'Petugas',
            clusterName:
                task.clusterName.isNotEmpty ? task.clusterName : 'Tatar',
            officerId: task.userId,
            missedCheckpoints: missedCheckpoints,
            clusterId: task.clusterId,
          );

          print('✅ Missed checkpoints notification sent successfully');

          // ✅ Update task with missed checkpoints info
          try {
            await repository.updateTask(
              task.taskId,
              {
                'missedCheckpoints': true,
                'missedCheckpointsCount': missedCheckpoints.length,
                'missedCheckpointsList': missedCheckpoints,
                'validationRadius': validationRadius,
                'checkpointsValidatedAt': DateTime.now().toIso8601String(),
              },
            );
            print('✅ Task updated with missed checkpoints info');
          } catch (updateError) {
            print(
                '❌ Failed to update task with missed checkpoints: $updateError');
          }
        } catch (notificationError) {
          print(
              '❌ Failed to send missed checkpoints notification: $notificationError');
        }
      } else {
        print('✅ All checkpoints visited - no notification needed');

        // ✅ Update task to indicate successful validation
        try {
          await repository.updateTask(
            task.taskId,
            {
              'missedCheckpoints': false,
              'missedCheckpointsCount': 0,
              'allCheckpointsVisited': true,
              'validationRadius': validationRadius,
              'checkpointsValidatedAt': DateTime.now().toIso8601String(),
            },
          );
          print('✅ Task updated - all checkpoints validated');
        } catch (updateError) {
          print('❌ Failed to update task validation: $updateError');
        }
      }
    } catch (e, stackTrace) {
      print('❌ Error in missed checkpoints check: $e');
      print('📍 Stack trace: $stackTrace');
    }
  }

// ✅ Enhanced validation radius method
  double _getValidationRadius(PatrolTask? task) {
    // Priority: Cluster radius → Task radius → Default
    final radius = _clusterValidationRadius ?? task?.validationRadius ?? 50.0;
    print(
        '📏 Validation radius determined: $radius m (cluster: $_clusterValidationRadius, task: ${task?.validationRadius})');
    return radius;
  }
}

class UpdateTask extends PatrolEvent {
  final String taskId;
  final Map<String, dynamic> updates;

  UpdateTask({
    required this.taskId,
    required this.updates,
  });

  List<Object> get props => [taskId, updates];
}
