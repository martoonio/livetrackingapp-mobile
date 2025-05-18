import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import '../../../domain/entities/patrol_task.dart';
import '../../../domain/repositories/route_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

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

  ResumePatrol({
    required this.task,
    required this.startTime,
    required this.currentDistance,
  });
}

class SyncOfflineData extends PatrolEvent {}

class DebugOfflineData extends PatrolEvent {}

// Tambahkan event baru
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
  });

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
    );
  }
}

class PatrolError extends PatrolState {
  final String message;
  PatrolError(this.message);
}

// BLoC
class PatrolBloc extends Bloc<PatrolEvent, PatrolState> {
  // Di dalam deklarasi class PatrolBloc
  final RouteRepository repository;
  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription<PatrolTask?>? _taskSubscription;
  StreamSubscription<List<PatrolTask>>? _historySubscription;
  StreamSubscription<dynamic>?
      _connectivitySubscription; // Ubah tipe ke dynamic
  Box<dynamic>? _offlineLocationBox;
  bool _isConnected = true;

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
    on<SubmitFinalReport>(_onSubmitFinalReport); // Tambahkan ini

    // Setup connectivity monitoring and local storage
    _initializeStorage();
    _setupConnectivityMonitoring();
  }

  void _onDebugOfflineData(
    DebugOfflineData event,
    Emitter<PatrolState> emit,
  ) {
    debugPrintOfflineData();
  }

  // Debugging method to print all offline data
  void debugPrintOfflineData() {
    if (_offlineLocationBox == null || _offlineLocationBox!.isEmpty) {
      print('No offline data to display');
      return;
    }

    print('\n===== OFFLINE DATA CONTENTS =====');
    print('Total items: ${_offlineLocationBox!.length}');

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

    print('\n-- PATROL STARTS: ${startKeys.length} --');
    for (final key in startKeys) {
      final data = _offlineLocationBox!.get(key);
      print('$key: $data');
    }

    print('\n-- PATROL STOPS: ${stopKeys.length} --');
    for (final key in stopKeys) {
      final data = _offlineLocationBox!.get(key);
      print('$key: $data');
    }

    print('\n-- TASK UPDATES: ${updateKeys.length} --');
    for (final key in updateKeys) {
      final data = _offlineLocationBox!.get(key);
      print('$key: $data');
    }

    print('\n-- LOCATION POINTS: ${locationKeys.length} --');
    if (locationKeys.length > 10) {
      for (final key in locationKeys.take(5)) {
        final data = _offlineLocationBox!.get(key);
        print('$key: $data');
      }
      print('... (showing 5 of ${locationKeys.length})');
      for (final key in locationKeys.skip(locationKeys.length - 5)) {
        final data = _offlineLocationBox!.get(key);
        print('$key: $data');
      }
    } else {
      for (final key in locationKeys) {
        final data = _offlineLocationBox!.get(key);
        print('$key: $data');
      }
    }

    print('===============================\n');
  }

  // Initialize local storage
  Future<void> _initializeStorage() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await Hive.initFlutter(dir.path);
      _offlineLocationBox = await Hive.openBox('offline_locations');
      print('Local storage initialized');
    } catch (e) {
      print('Error initializing local storage: $e');
    }
  }

  // Setup connectivity monitoring
// Setup connectivity monitoring
  void _setupConnectivityMonitoring() {
    Connectivity().checkConnectivity().then((result) {
      _isConnected = (result != ConnectivityResult.none);
      print('Initial connection status: $_isConnected');
    });

    // Perbaikan error tipe dengan menyesuaikan parameter fungsi
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        // Gunakan hasil pertama atau anggap tidak ada koneksi jika list kosong
        final result =
            results.isNotEmpty ? results.first : ConnectivityResult.none;

        final wasConnected = _isConnected;
        _isConnected = (result != ConnectivityResult.none);

        print('Connection status changed: $_isConnected');

        // Update UI to show offline/online status
        if (state is PatrolLoaded) {
          final currentState = state as PatrolLoaded;
          emit(currentState.copyWith(isOffline: !_isConnected));
        }

        // If reconnected, try to sync offline data
        if (!wasConnected && _isConnected) {
          print('Reconnected to network, syncing offline data...');
          add(SyncOfflineData());
        }
      },
    );
  }

  // Handle syncing offline data when connection is restored
  // Handle syncing offline data when connection is restored
  Future<void> _onSyncOfflineData(
    SyncOfflineData event,
    Emitter<PatrolState> emit,
  ) async {
    if (!_isConnected || _offlineLocationBox == null) return;

    try {
      print('Starting to sync offline data...');
      print('Total offline items: ${_offlineLocationBox!.length}');
      print('Keys: ${_offlineLocationBox!.keys.toList()}');

      if (_offlineLocationBox!.isEmpty) {
        print('No offline data to sync');
        return;
      }

      // Get current state and set syncing flag
      if (state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;
        emit(currentState.copyWith(isSyncing: true));

        // Debug: print task info
        print('Current task: ${currentState.task?.taskId}');
        print(
            'Current route path length: ${currentState.routePath?.length ?? 0}');

        // Check for patrol stop data first
        final stopKeyPattern = 'patrol_stop_';
        final stopKeys = _offlineLocationBox!.keys
            .where((k) => k.toString().startsWith(stopKeyPattern))
            .toList();

        // Debug stop keys
        print('Found ${stopKeys.length} stop records to sync');

        // Collate all location points by taskId
        final locationDataByTask = <String, Map<String, dynamic>>{};

        // Find all location points (non-stop keys) and organize by task ID
        final locationKeys = _offlineLocationBox!.keys
            .where((k) =>
                !k.toString().startsWith(stopKeyPattern) &&
                !k.toString().startsWith('task_update_') &&
                !k.toString().startsWith('patrol_start_'))
            .toList();

        print('Found ${locationKeys.length} location points to sync');

        // Organize points by task ID
        for (final key in locationKeys) {
          final data = _offlineLocationBox!.get(key);
          if (data != null && data is Map && data['taskId'] != null) {
            final taskId = data['taskId'] as String;
            final timestamp = data['timestamp'] as String;
            final latitude = data['latitude'] as double;
            final longitude = data['longitude'] as double;

            // Initialize map for this task if needed
            locationDataByTask[taskId] ??= {};

            // Add point to route_path
            locationDataByTask[taskId]?[key.toString()] = {
              'coordinates': [latitude, longitude],
              'timestamp': timestamp,
            };
          }
        }

        print('Organized points for ${locationDataByTask.length} tasks');

        // First, process location data to build complete route paths
        for (final taskId in locationDataByTask.keys) {
          try {
            print(
                'Processing ${locationDataByTask[taskId]!.length} points for task $taskId');

            // Fetch current route_path from database to merge with
            Map<String, dynamic> existingRoutePath = {};
            try {
              final taskSnapshot = await repository.getTaskById(taskId: taskId);
              if (taskSnapshot != null && taskSnapshot.routePath != null) {
                existingRoutePath =
                    Map<String, dynamic>.from(taskSnapshot.routePath as Map);
                print(
                    'Found existing route_path with ${existingRoutePath.length} points');
              }
            } catch (e) {
              print('Error fetching existing route_path: $e');
            }

            // Merge with local points
            final mergedRoutePath = {
              ...existingRoutePath,
              ...locationDataByTask[taskId]!
            };
            print('Merged route_path now has ${mergedRoutePath.length} points');

            // Update route_path in database
            await repository.updateTask(
              taskId,
              {'route_path': mergedRoutePath},
            );
            print('Successfully updated route_path for task $taskId');

            // Delete synced points
            for (final key in locationDataByTask[taskId]!.keys) {
              await _offlineLocationBox!.delete(key);
            }
          } catch (e) {
            print('Error syncing route_path for task $taskId: $e');
          }
        }

        // Now process stop records
        if (stopKeys.isNotEmpty) {
          print('Processing patrol stop data...');
          for (final key in stopKeys) {
            final data = _offlineLocationBox!.get(key);
            if (data != null && data is Map) {
              final taskId = data['taskId'] as String;
              final endTime = DateTime.parse(data['endTime'] as String);
              final distance = data['distance'] as double;

              try {
                print('Syncing stop data for task $taskId');
                print('End time: $endTime, Distance: $distance');

                // Update task status
                await repository.updateTaskStatus(taskId, 'finished');

                // Update endTime and distance
                await repository.updateTask(
                  taskId,
                  {
                    'endTime': endTime.toIso8601String(),
                    'distance': distance,
                    'status': 'finished',
                  },
                );

                print('Synced patrol stop data for task $taskId');
                await _offlineLocationBox!.delete(key);
              } catch (e) {
                print('Failed to sync patrol stop data: $e');
              }
            }
          }
        }

        // Process any task updates
        final updateKeyPattern = 'task_update_';
        final updateKeys = _offlineLocationBox!.keys
            .where((k) => k.toString().startsWith(updateKeyPattern))
            .toList();

        print('Found ${updateKeys.length} task updates to sync');

        for (final key in updateKeys) {
          final data = _offlineLocationBox!.get(key);
          if (data != null && data is Map) {
            final taskId = data['taskId'] as String;
            final updates = data['updates'] as Map<dynamic, dynamic>;

            try {
              print('Syncing task update for $taskId: $updates');
              await repository.updateTask(
                taskId,
                Map<String, dynamic>.from(updates),
              );
              await _offlineLocationBox!.delete(key);
            } catch (e) {
              print('Failed to sync task update: $e');
            }
          }
        }

        // Get updated finished tasks
        List<PatrolTask> finishedTasks = [];
        try {
          if (currentState.task != null) {
            finishedTasks =
                await repository.getFinishedTasks(currentState.task!.userId);
            print(
                'Retrieved ${finishedTasks.length} finished tasks after sync');
          }
        } catch (e) {
          print('Failed to refresh finished tasks: $e');
          finishedTasks = currentState.finishedTasks;
        }

        print('Offline data sync completed.');
        emit(currentState.copyWith(
          isSyncing: false,
          finishedTasks: finishedTasks,
        ));

        // Check if any data remains
        print('Remaining offline items: ${_offlineLocationBox!.length}');
        if (_offlineLocationBox!.length > 0) {
          print('Remaining keys: ${_offlineLocationBox!.keys.toList()}');
        }
      }
    } catch (e, stack) {
      print('Error syncing offline data: $e');
      print('Stack trace: $stack');
      if (state is PatrolLoaded) {
        emit((state as PatrolLoaded).copyWith(isSyncing: false));
      }
    }
  }

  Future<void> _onCheckOngoingPatrol(
    CheckOngoingPatrol event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      print('Checking for ongoing patrol for user: ${event.userId}');

      final task = await repository.getCurrentTask(event.userId);

      if (task != null &&
          (task.status == 'ongoing' || task.status == 'active')) {
        print('Found ongoing patrol task: ${task.taskId}');
        print('Task start time: ${task.startTime}');

        // Emit loaded state with ongoing patrol
        emit(PatrolLoaded(
          task: task,
          isPatrolling: true,
          routePath: task.routePath,
          isOffline: !_isConnected,
        ));

        // Restart location tracking
        _startLocationTracking();

        print('Resumed patrol tracking');
      } else {
        print('No ongoing patrol found');
      }
    } catch (e) {
      print('Error checking ongoing patrol: $e');
      emit(PatrolError('Failed to check ongoing patrol: $e'));
    }
  }

  Future<void> _onResumePatrol(
    ResumePatrol event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      print('Resuming patrol for task: ${event.task.taskId}');

      // Emit loaded state with resumed patrol
      emit(PatrolLoaded(
        task: event.task,
        isPatrolling: true,
        startTime: event.startTime,
        distance: event.currentDistance,
        routePath: event.task.routePath as Map<String, dynamic>?,
        finishedTasks:
            state is PatrolLoaded ? (state as PatrolLoaded).finishedTasks : [],
        isOffline: !_isConnected,
      ));

      // Restart location tracking
      _startLocationTracking();

      print('Resumed patrol tracking');
    } catch (e) {
      print('Error resuming patrol: $e');
      emit(PatrolError('Failed to resume patrol: $e'));
    }
  }

  Future<void> _onLoadPatrolHistory(
    LoadPatrolHistory event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      print('Loading patrol history for user: ${event.userId}');
      emit(PatrolLoading());

      if (!_isConnected) {
        print('Offline: Unable to load patrol history');
        emit(PatrolLoaded(
          finishedTasks: [],
          isOffline: true,
        ));
        return;
      }

      // Get current active task and finished tasks in parallel
      final currentTaskFuture = repository.getCurrentTask(event.userId);
      final finishedTasksFuture = repository.getFinishedTasks(event.userId);

      final results =
          await Future.wait([currentTaskFuture, finishedTasksFuture]);
      final currentTask = results[0] as PatrolTask?;
      final finishedTasks = results[1] as List<PatrolTask>;

      print('Loaded ${finishedTasks.length} finished tasks');

      // Always emit PatrolLoaded, even without current task
      emit(PatrolLoaded(
        task: currentTask,
        finishedTasks: finishedTasks,
        distance: currentTask?.distance,
        isPatrolling: currentTask?.status == 'ongoing',
        isOffline: !_isConnected,
      ));
    } catch (e) {
      print('Error in _onLoadPatrolHistory: $e');
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
      print('Updating current task: ${event.task.taskId}');

      if (state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;
        emit(currentState.copyWith(
          task: event.task,
          isPatrolling: event.task.status == 'ongoing',
        ));
      } else {
        emit(PatrolLoaded(
          task: event.task,
          isPatrolling: event.task.status == 'ongoing',
          finishedTasks: const [],
          isOffline: !_isConnected,
        ));
      }
    } catch (e) {
      print('Error updating current task: $e');
      emit(PatrolError('Failed to update current task: $e'));
    }
  }

  Future<void> _onLoadRouteData(
    LoadRouteData event,
    Emitter<PatrolState> emit,
  ) async {
    emit(PatrolLoading());
    try {
      // Cancel existing subscriptions
      await _taskSubscription?.cancel();
      await _historySubscription?.cancel();

      // If offline, load minimal state
      if (!_isConnected) {
        print('Offline: Limited route data loading');
        emit(PatrolLoaded(
          finishedTasks: [],
          isOffline: true,
        ));
        return;
      }

      // Start listening to current task stream
      _taskSubscription = repository.watchCurrentTask(event.userId).listen(
        (task) {
          if (task != null) {
            add(UpdateCurrentTask(task: task));
          }
        },
        onError: (error) {
          print('Task stream error: $error');
          emit(PatrolError('Failed to watch current task: $error'));
        },
      );

      // Start listening to finished tasks stream
      _historySubscription = repository.watchFinishedTasks(event.userId).listen(
        (tasks) {
          add(UpdateFinishedTasks(tasks: tasks));
        },
        onError: (error) {
          print('History stream error: $error');
          emit(PatrolError('Failed to watch finished tasks: $error'));
        },
      );
    } catch (e) {
      print('Error loading route data: $e');
      emit(PatrolError(e.toString()));
    }
  }

  Future<void> _onStartPatrol(
    StartPatrol event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      print('Starting patrol for task: ${event.task.taskId}');
      print('Connection status: ${_isConnected ? "Online" : "Offline"}');

      // Emit loading state terlebih dahulu
      emit(PatrolLoading());

      // Initialize empty routePath
      final routePath = <String, dynamic>{};

      // Create updated task object with the new status
      final updatedTask = PatrolTask(
        taskId: event.task.taskId,
        userId: event.task.userId,
        vehicleId: event.task.vehicleId,
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
      );

      // If online, update database
      if (_isConnected) {
        // Update task status in database
        await repository.updateTask(
          event.task.taskId,
          {
            'status': 'ongoing',
            'startTime': event.startTime.toIso8601String(),
          },
        );
      } else {
        // If offline, store start info locally
        if (_offlineLocationBox != null) {
          await _offlineLocationBox!.put('patrol_start_${event.task.taskId}', {
            'taskId': event.task.taskId,
            'startTime': event.startTime.toIso8601String(),
            'status': 'ongoing',
          });
          print('Saved patrol start data to offline storage');
        }
      }

      // Emit new state with isPatrolling = true and the updated task
      emit(PatrolLoaded(
        task: updatedTask,
        isPatrolling: true,
        startTime: event.startTime,
        routePath: routePath,
        distance: 0.0,
        isOffline: !_isConnected,
      ));

      // Start location tracking
      _startLocationTracking();

      print('Patrol started successfully');
    } catch (e, stackTrace) {
      print('Error starting patrol: $e');
      print('Stack trace: $stackTrace');
      emit(PatrolError('Failed to start patrol: $e'));
    }
  }

  Future<void> _onUpdateTask(
    UpdateTask event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      print('Updating task: ${event.taskId}');

      if (_isConnected) {
        await repository.updateTask(
          event.taskId,
          event.updates,
        );
      } else {
        // Store update for later sync
        if (_offlineLocationBox != null) {
          final key =
              'task_update_${event.taskId}_${DateTime.now().millisecondsSinceEpoch}';
          await _offlineLocationBox!.put(key, {
            'taskId': event.taskId,
            'updates': event.updates,
          });
          print('Saved task update to offline storage');
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
        print('Task updated successfully with isPatrolling: $isInProgress');
      }
    } catch (e) {
      print('Error in _onUpdateTask: $e');
      emit(PatrolError('Failed to update task: $e'));
    }
  }

  Future<void> _onUpdatePatrolLocation(
    UpdatePatrolLocation event,
    Emitter<PatrolState> emit,
  ) async {
    if (state is PatrolLoaded) {
      final currentState = state as PatrolLoaded;
      if (currentState.isPatrolling && currentState.task != null) {
        try {
          print('=== UPDATING LOCATION ===');
          print('Task ID: ${currentState.task!.taskId}');
          print(
              'Position: ${event.position.latitude}, ${event.position.longitude}');
          print('Connection status: ${_isConnected ? "Online" : "Offline"}');

          // Prepare location data
          final List<double> coordinates = [
            event.position.latitude,
            event.position.longitude
          ];

          final timestampKey =
              event.timestamp.millisecondsSinceEpoch.toString();

          // Create location data object for state update
          final locationData = {
            'coordinates': coordinates,
            'timestamp': event.timestamp.toIso8601String(),
          };

          // Try to update database if online
          bool databaseUpdateSuccess = false;
          if (_isConnected) {
            try {
              await repository.updatePatrolLocation(
                currentState.task!.taskId,
                coordinates,
                event.timestamp,
              );
              databaseUpdateSuccess = true;
              print('Database location update successful');
            } catch (e) {
              print('Error updating database with location: $e');
            }
          }

          // If offline or database update failed, save to local storage
          if (!_isConnected || !databaseUpdateSuccess) {
            if (_offlineLocationBox != null) {
              await _offlineLocationBox!.put(timestampKey, {
                'latitude': event.position.latitude,
                'longitude': event.position.longitude,
                'timestamp': event.timestamp.toIso8601String(),
                'taskId': currentState.task!.taskId,
              });

              // Debug: show offline storage status
              print('Saved location to offline storage. Key: $timestampKey');
              print(
                  'Offline storage now has ${_offlineLocationBox!.length} items');
              if (_offlineLocationBox!.length % 10 == 0) {
                print(
                    'Offline storage keys: ${_offlineLocationBox!.keys.take(5).toList()}... (showing first 5)');
              }
            }
          }

          // Calculate new distance
          double newDistance = currentState.distance ?? 0.0;
          if (currentState.currentPatrolPath != null &&
              currentState.currentPatrolPath!.isNotEmpty) {
            final lastPosition = currentState.currentPatrolPath!.last;
            final distanceInMeters = Geolocator.distanceBetween(
              lastPosition.latitude,
              lastPosition.longitude,
              event.position.latitude,
              event.position.longitude,
            );

            // Only add if distance is significant (>1m) to avoid noise
            if (distanceInMeters > 1.0) {
              newDistance += distanceInMeters;
            }
          }

          // Update local state's routePath
          Map<String, dynamic> updatedRoutePath = {};

          // Preserve existing route path if available
          if (currentState.routePath != null) {
            updatedRoutePath =
                Map<String, dynamic>.from(currentState.routePath!);
          }

          // Add new point
          updatedRoutePath[timestampKey] = locationData;

          // Update total distance in database periodically if online
          if (_isConnected && updatedRoutePath.length % 5 == 0) {
            try {
              await repository.updateTask(
                currentState.task!.taskId,
                {
                  'distance': newDistance,
                  'route_path': updatedRoutePath
                }, // Save route_path here too
              );
              print(
                  'Updated distance and route_path in database: $newDistance meters');
            } catch (e) {
              print('Error updating distance and route_path: $e');
            }
          }

          // Update task with the new route_path
          final updatedTask = currentState.task!.copyWith(
            routePath: updatedRoutePath,
            distance: newDistance,
          );

          // Emit updated state
          emit(currentState.copyWith(
            currentPatrolPath: [
              ...?currentState.currentPatrolPath,
              event.position
            ],
            routePath: updatedRoutePath,
            distance: newDistance,
            task: updatedTask,
            isOffline: !_isConnected,
          ));

          print('State updated with ${updatedRoutePath.length} route points');
          print('Total distance: $newDistance meters');
        } catch (e, stackTrace) {
          print('Error in location update flow: $e');
          print('Stack trace: $stackTrace');
          // Don't emit error state to prevent disrupting tracking
        }
      }
    }
  }

  Future<void> _onStopPatrol(
    StopPatrol event,
    Emitter<PatrolState> emit,
  ) async {
    if (state is PatrolLoaded) {
      final currentState = state as PatrolLoaded;
      try {
        print('=== Stopping Patrol ===');
        print('Task ID: ${currentState.task?.taskId}');
        print('Connection status: ${_isConnected ? "Online" : "Offline"}');
        print('Route path points: ${currentState.routePath?.length ?? 0}');
        print('Final route path points: ${event.finalRoutePath?.length ?? 0}');

        // Pick the larger of the two route paths
        Map<String, dynamic>? routePathToSave = currentState.routePath;
        if (event.finalRoutePath != null) {
          if (routePathToSave == null ||
              (event.finalRoutePath!.length > routePathToSave.length)) {
            routePathToSave = event.finalRoutePath;
          }
        }

        print(
            'Selected route path with ${routePathToSave?.length ?? 0} points');

        // Try to sync any offline data first if we're online
        if (_isConnected) {
          await _onSyncOfflineData(SyncOfflineData(), emit);
        }

        // If online, update the task in the database
        if (_isConnected) {
          // Update task status
          await repository.updateTaskStatus(
              currentState.task!.taskId, 'finished');

          // Update endTime and distance
          await repository.updateTask(
            currentState.task!.taskId,
            {
              'endTime': event.endTime.toIso8601String(),
              'distance': event.distance,
            },
          );

          // Save route path for summary
          if (routePathToSave != null && routePathToSave.isNotEmpty) {
            print('Saving route path with ${routePathToSave.length} entries');

            // Update task with final path
            await repository.updateTask(
              currentState.task!.taskId,
              {
                'route_path': routePathToSave,
                'status': 'finished',
              },
            );
          }
        } else {
          // If offline, save completion data locally
          if (_offlineLocationBox != null) {
            await _offlineLocationBox!
                .put('patrol_stop_${currentState.task!.taskId}', {
              'taskId': currentState.task!.taskId,
              'endTime': event.endTime.toIso8601String(),
              'distance': event.distance,
              'status': 'finished',
              'route_path_length':
                  routePathToSave?.length ?? 0, // Track for debug
            });

            print('Saved patrol completion data to offline storage');

            // Debug all offline data
            debugPrintOfflineData();

            // Show offline message to user
            emit(PatrolError(
                'Patroli berhasil dihentikan dalam mode offline. Data akan disinkronkan saat koneksi tersedia.'));

            // Return to prevent further state changes until we're online
            Future.delayed(const Duration(seconds: 2), () {
              emit(currentState.copyWith(
                isPatrolling: false,
                endTime: event.endTime,
                isOffline: true,
              ));
            });
            return;
          }
        }

        // Cancel location tracking
        _locationSubscription?.cancel();
        _locationSubscription = null;

        // Get updated finished tasks if online
        List<PatrolTask> finishedTasks = [];
        if (_isConnected) {
          finishedTasks =
              await repository.getFinishedTasks(currentState.task!.userId);
        } else {
          finishedTasks = currentState.finishedTasks;
        }

        // Emit new state
        emit(currentState.copyWith(
          isPatrolling: false,
          currentPatrolPath: null,
          endTime: event.endTime,
          finishedTasks: finishedTasks,
          isOffline: !_isConnected,
        ));

        print('Patrol stopped successfully');
      } catch (e, stackTrace) {
        print('Error stopping patrol: $e');
        print('Stack trace: $stackTrace');
        emit(PatrolError('Failed to stop patrol: $e'));
      }
    }
  }

  void _startLocationTracking() {
    print('Starting location tracking service...');

    // Always cancel existing subscription first
    _locationSubscription?.cancel();

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      (Position position) {
        print('New position: ${position.latitude}, ${position.longitude}');

        // Check if we're in a patrolling state more robustly
        if (state is PatrolLoaded) {
          final currentState = state as PatrolLoaded;
          if (currentState.isPatrolling) {
            add(UpdatePatrolLocation(
              position: position,
              timestamp: DateTime.now(),
            ));
          } else {
            print(
                'Position update received but not patrolling, skipping update');
          }
        }
      },
      onError: (error) {
        print('Location tracking error: $error');
        // Don't emit error state to prevent disrupting tracking
      },
      cancelOnError: false, // Keep tracking even if errors occur
    );
  }

  @override
  Future<void> close() async {
    await _locationSubscription?.cancel();
    await _taskSubscription?.cancel();
    await _historySubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _offlineLocationBox?.close();
    return super.close();
  }

  // Tambahkan handler event baru
  // Perbaiki method _onSubmitFinalReport
  Future<void> _onSubmitFinalReport(
    SubmitFinalReport event,
    Emitter<PatrolState> emit,
  ) async {
    if (state is PatrolLoaded) {
      final currentState = state as PatrolLoaded;

      try {
        emit(PatrolLoading());

        // Perbarui task dengan final report
        final updatedTask = currentState.task?.copyWith(
          finalReportPhotoUrl: event.photoUrl,
          finalReportNote: event.note,
          finalReportTime: event.reportTime,
        );

        if (updatedTask != null) {
          // Update task di database - PERBAIKAN DISINI
          // Ganti updatePatrolTask dengan updateTask
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
        // Emit kembali state sebelumnya
        emit(currentState);
      }
    }
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
