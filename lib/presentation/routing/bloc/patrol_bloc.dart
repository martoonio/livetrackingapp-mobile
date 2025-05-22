import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
      if (!event.isOffline && _offlineLocationBox != null) {
        add(SyncOfflineData());
      }
    }
  }

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

  void _setupConnectivityMonitoring() {
    Connectivity().checkConnectivity().then((result) {
      _isConnected = (result != ConnectivityResult.none);
      print('Initial connection status: $_isConnected');
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final result =
            results.isNotEmpty ? results.first : ConnectivityResult.none;

        final wasConnected = _isConnected;
        _isConnected = (result != ConnectivityResult.none);

        print('Connection status changed: $_isConnected');

        if (state is PatrolLoaded) {
          final currentState = state as PatrolLoaded;
          emit(currentState.copyWith(isOffline: !_isConnected));
        }

        if (!wasConnected && _isConnected) {
          print('Reconnected to network, syncing offline data...');
          add(SyncOfflineData());
        }
      },
    );
  }

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

      if (state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;
        emit(currentState.copyWith(isSyncing: true));

        print('Current task: ${currentState.task?.taskId}');
        print(
            'Current route path length: ${currentState.routePath?.length ?? 0}');

        final stopKeyPattern = 'patrol_stop_';
        final stopKeys = _offlineLocationBox!.keys
            .where((k) => k.toString().startsWith(stopKeyPattern))
            .toList();

        print('Found ${stopKeys.length} stop records to sync');

        final locationDataByTask = <String, Map<String, dynamic>>{};

        final locationKeys = _offlineLocationBox!.keys
            .where((k) =>
                !k.toString().startsWith(stopKeyPattern) &&
                !k.toString().startsWith('task_update_') &&
                !k.toString().startsWith('patrol_start_') &&
                !k.toString().startsWith('mock_detection_'))
            .toList();

        print('Found ${locationKeys.length} location points to sync');

        for (final key in locationKeys) {
          final data = _offlineLocationBox!.get(key);
          if (data != null && data is Map && data['taskId'] != null) {
            final taskId = data['taskId'] as String;
            final timestamp = data['timestamp'] as String;
            final latitude = data['latitude'] as double;
            final longitude = data['longitude'] as double;

            locationDataByTask[taskId] ??= {};

            locationDataByTask[taskId]?[key.toString()] = {
              'coordinates': [latitude, longitude],
              'timestamp': timestamp,
            };
          }
        }

        print('Organized points for ${locationDataByTask.length} tasks');

        for (final taskId in locationDataByTask.keys) {
          try {
            print(
                'Processing ${locationDataByTask[taskId]!.length} points for task $taskId');

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

            final mergedRoutePath = {
              ...existingRoutePath,
              ...locationDataByTask[taskId]!
            };
            print('Merged route_path now has ${mergedRoutePath.length} points');

            await repository.updateTask(
              taskId,
              {'route_path': mergedRoutePath},
            );
            print('Successfully updated route_path for task $taskId');

            for (final key in locationDataByTask[taskId]!.keys) {
              await _offlineLocationBox!.delete(key);
            }
          } catch (e) {
            print('Error syncing route_path for task $taskId: $e');
          }
        }

        final mockDetectionKeys = _offlineLocationBox!.keys
            .where((k) => k.toString().startsWith('mock_detection_'))
            .toList();

        if (mockDetectionKeys.isNotEmpty) {
          print(
              'Found ${mockDetectionKeys.length} offline mock location detections');
          final database = FirebaseDatabase.instance.ref();

          for (final key in mockDetectionKeys) {
            try {
              final data = _offlineLocationBox!.get(key);
              if (data != null && data is Map) {
                final taskId = data['taskId'] as String;

                await repository.updateTask(
                  taskId,
                  {
                    'mockLocationDetected': true,
                    'mockLocationCount': data['mockCount'] ?? 1,
                    'lastMockDetection': data['timestamp'],
                  },
                );

                await database
                    .child('tasks/$taskId/mock_detections')
                    .push()
                    .set({
                  'timestamp': data['timestamp'],
                  'coordinates': [data['latitude'], data['longitude']],
                  'accuracy': data['accuracy'],
                  'speed': data['speed'],
                  'altitude': data['altitude'],
                  'heading': data['heading'],
                  'count': data['mockCount'],
                  'syncedFromOffline': true,
                });

                await database.child('mock_location_logs').push().set({
                  'timestamp': data['timestamp'],
                  'coordinates': [data['latitude'], data['longitude']],
                  'accuracy': data['accuracy'] ?? 0,
                  'speed': data['speed'] ?? 0,
                  'altitude': data['altitude'] ?? 0,
                  'heading': data['heading'] ?? 0,
                  'count': data['mockCount'] ?? 1,
                  'taskId': taskId,
                  'userId': data['userId'],
                  'detectionTime': ServerValue.timestamp,
                  'syncedFromOffline': true,
                  'deviceInfo':
                      data['deviceInfo'] ?? {'syncedFromOffline': true},
                });

                await _offlineLocationBox!.delete(key);
                print('Synced offline mock location detection: $key');
              }
            } catch (e) {
              print('Error syncing mock location detection: $e');
            }
          }
        }

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

                await repository.updateTaskStatus(taskId, 'finished');

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

        emit(PatrolLoaded(
          task: task,
          isPatrolling: true,
          routePath: task.routePath,
          isOffline: !_isConnected,
        ));

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

      Map<String, dynamic> initialRoutePath = {};

      if (_isConnected) {
        try {
          final taskSnapshot =
              await repository.getTaskById(taskId: event.task.taskId);
          if (taskSnapshot != null && taskSnapshot.routePath != null) {
            final dbRoutePath =
                Map<String, dynamic>.from(taskSnapshot.routePath as Map);
            dbRoutePath.forEach((key, value) {
              initialRoutePath[key.toString()] = value;
            });
            print(
                'Fetched route path from database with ${initialRoutePath.length} points');
          }
        } catch (e) {
          print('Failed to fetch route path from database on resume: $e');
        }
      }

      // Jika dari database kosong atau tidak ada koneksi, coba dari event/task object
      if (initialRoutePath.isEmpty) {
        if (event.existingRoutePath != null &&
            event.existingRoutePath!.isNotEmpty) {
          event.existingRoutePath!.forEach((key, value) {
            initialRoutePath[key.toString()] = value;
          });
          print(
              'Using provided existingRoutePath from event with ${initialRoutePath.length} points');
        } else if (event.task.routePath != null) {
          try {
            final taskRoutePath =
                Map<String, dynamic>.from(event.task.routePath as Map);
            taskRoutePath.forEach((key, value) {
              initialRoutePath[key.toString()] = value;
            });
            print(
                'Using route path from task object with ${initialRoutePath.length} points');
          } catch (e) {
            print('Error converting task route path on resume: $e');
          }
        }
      }

      emit(PatrolLoaded(
        task: event.task,
        isPatrolling: true,
        startTime: event.startTime,
        distance: event.currentDistance,
        routePath:
            initialRoutePath, // Menggunakan initialRoutePath yang sudah digabungkan
        finishedTasks:
            state is PatrolLoaded ? (state as PatrolLoaded).finishedTasks : [],
        isOffline: !_isConnected,
      ));

      _startLocationTracking();

      print(
          'Resumed patrol tracking with ${initialRoutePath.length} route points');
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

      PatrolTask? currentTask;
      List<PatrolTask> finishedTasks = [];

      try {
        currentTask = await repository.getCurrentTask(event.userId);
        print('Current task loaded: ${currentTask?.taskId}');
      } catch (e) {
        print('Error loading current task: $e');
        currentTask = null;
      }

      try {
        finishedTasks = await repository.getFinishedTasks(event.userId);
        print('Loaded ${finishedTasks.length} finished tasks');
      } catch (e) {
        print('Error loading finished tasks: $e');
        finishedTasks = [];
      }

      bool isActiveTask = false;
      if (currentTask != null) {
        final status = currentTask.status.toLowerCase();
        isActiveTask = (status == 'active' ||
            status == 'ongoing' ||
            status == 'in_progress');
        print(
            'Current task status: ${currentTask.status}, isActiveTask: $isActiveTask');
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
      print(
          'Updating current task: ${event.task.taskId}, status: ${event.task.status}');

      final isActiveTask = event.task.status == 'active' ||
          event.task.status == 'ongoing' ||
          event.task.status == 'in_progress';

      print('Task is active: $isActiveTask');

      if (state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;
        emit(currentState.copyWith(
          task: event.task,
          isPatrolling: event.task.status == 'ongoing' ||
              event.task.status == 'in_progress',
        ));
        print('Updated current task in existing PatrolLoaded state');
      } else {
        emit(PatrolLoaded(
          task: event.task,
          isPatrolling: event.task.status == 'ongoing' ||
              event.task.status == 'in_progress',
          finishedTasks: const [],
          isOffline: !_isConnected,
        ));
        print('Created new PatrolLoaded state with task');
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
      await _taskSubscription?.cancel();
      await _historySubscription?.cancel();

      if (!_isConnected) {
        print('Offline: Limited route data loading');
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
          print('Task stream error: $error');
          emit(PatrolError('Failed to watch current task: $error'));
        },
      );

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

      emit(PatrolLoading());

      final routePath = <String, dynamic>{};

      // Calculate initial timeliness
      final timeliness = _calculateTimeliness(event.task.assignedStartTime,
          event.startTime, event.task.assignedEndTime, 'ongoing');

      final updatedTask = PatrolTask(
        taskId: event.task.taskId,
        userId: event.task.userId,
        // vehicleId: event.task.vehicleId,
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
      );

      if (_isConnected) {
        await repository.updateTask(
          event.task.taskId,
          {
            'status': 'ongoing',
            'startTime': event.startTime.toIso8601String(),
            'timeliness': timeliness,
          },
        );
      } else {
        if (_offlineLocationBox != null) {
          await _offlineLocationBox!.put('patrol_start_${event.task.taskId}', {
            'taskId': event.task.taskId,
            'startTime': event.startTime.toIso8601String(),
            'status': 'ongoing',
          });
          print('Saved patrol start data to offline storage');
        }
      }

      emit(PatrolLoaded(
        task: updatedTask,
        isPatrolling: true,
        startTime: event.startTime,
        routePath: routePath,
        distance: 0.0,
        isOffline: !_isConnected,
      ));

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

          final isMocked =
              await LocationValidator.isLocationMocked(event.position);

          if (isMocked) {
            print(
                'MOCK LOCATION DETECTED: ${event.position.latitude}, ${event.position.longitude}');

            final newMockCount = currentState.mockLocationCount + 1;
            print('New mock count: $newMockCount');

            final mockData = {
              'timestamp': event.timestamp.toIso8601String(),
              'coordinates': [
                event.position.latitude,
                event.position.longitude,
              ],
              'accuracy': event.position.accuracy,
              'speed': event.position.speed,
              'altitude': event.position.altitude,
              'heading': event.position.heading,
              'count': newMockCount,
              'deviceInfo': await getDeviceInfo(), // Ambil info perangkat
            };

            if (_isConnected) {
              try {
                await repository.logMockLocationDetection(
                  taskId: currentState.task!.taskId,
                  userId: currentState.task!.userId,
                  mockData: mockData,
                );

                // // --- DIHAPUS: KIRIM NOTIFIKASI MOCK LOCATION KE COMMAND CENTER ---
                // // Logika ini dipindahkan ke MapScreen
                // if (currentState.task != null && currentState.task!.officerName != null && currentState.task!.clusterName != null) {
                //   await sendMockLocationNotificationToCommandCenter(
                //     patrolTaskId: currentState.task!.taskId,
                //     officerId: currentState.task!.userId,
                //     officerName: currentState.task!.officerName,
                //     clusterName: currentState.task!.clusterName,
                //     latitude: event.position.latitude,
                //     longitude: event.position.longitude,
                //   );
                //   print('Notifikasi mock location dikirim ke Command Center dari PatrolBloc.');
                // }
                // // --- AKHIR DIHAPUS ---
              } catch (e) {
                print(
                    'Error logging mock location to database or sending notification: $e');
              }
            } else {
              if (_offlineLocationBox != null) {
                final key =
                    'mock_detection_${currentState.task!.taskId}_${event.timestamp.millisecondsSinceEpoch}';
                await _offlineLocationBox!.put(key, {
                  'taskId': currentState.task!.taskId,
                  'userId': currentState.task!.userId,
                  'timestamp': event.timestamp.toIso8601String(),
                  'latitude': event.position.latitude,
                  'longitude': event.position.longitude,
                  'accuracy': event.position.accuracy,
                  'speed': event.position.speed,
                  'altitude': event.position.altitude,
                  'heading': event.position.heading,
                  'mockCount': newMockCount,
                  'deviceInfo': await getDeviceInfo(),
                });
                print('Mock location data saved to offline storage');
              }
            }

            emit(currentState.copyWith(
              mockLocationDetected: true,
              lastMockDetection: event.timestamp,
              mockLocationCount: newMockCount,
            ));

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

          Map<String, dynamic> currentDbRoutePath = {};
          if (_isConnected) {
            try {
              final taskSnapshot = await repository.getTaskById(
                  taskId: currentState.task!.taskId);
              if (taskSnapshot != null && taskSnapshot.routePath != null) {
                currentDbRoutePath =
                    Map<String, dynamic>.from(taskSnapshot.routePath as Map);
                print(
                    'Fetched existing route_path from database with ${currentDbRoutePath.length} points');
              }
            } catch (e) {
              print('Error fetching existing route_path from database: $e');
            }
          }

          Map<String, dynamic> mergedRoutePath = {
            ...currentDbRoutePath, // Data dari database
            ...?currentState
                .routePath, // Data dari state BLoC (mungkin ada yang belum disinkronkan)
            timestampKey: locationData, // Titik lokasi terbaru
          };

          bool databaseUpdateSuccess = false;
          if (_isConnected) {
            try {
              // Update ke database, sekarang mengirimkan mergedRoutePath
              await repository.updateTask(
                currentState.task!.taskId,
                {
                  'route_path': mergedRoutePath,
                  'lastLocation': locationData
                }, // Update lastLocation juga
              );
              databaseUpdateSuccess = true;
              print('Database location update successful');
            } catch (e) {
              print('Error updating database with location: $e');
            }
          }
          if (!_isConnected || !databaseUpdateSuccess) {
            if (_offlineLocationBox != null) {
              // Simpan ke offline dengan timestampKey yang unik
              await _offlineLocationBox!.put(timestampKey, {
                'latitude': event.position.latitude,
                'longitude': event.position.longitude,
                'timestamp': event.timestamp.toIso8601String(),
                'taskId': currentState.task!.taskId,
                'lastLocation':
                    locationData, // Simpan lastLocation untuk offline juga
              });

              print('Saved location to offline storage. Key: $timestampKey');
              print(
                  'Offline storage now has ${_offlineLocationBox!.length} items');
              if (_offlineLocationBox!.length % 10 == 0) {
                print(
                    'Offline storage keys: ${_offlineLocationBox!.keys.take(5).toList()}... (showing first 5)');
              }
            }
          }

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

            if (distanceInMeters > 1.0) {
              newDistance += distanceInMeters;
            }
          }

          final updatedTask = currentState.task!.copyWith(
            routePath: mergedRoutePath, // Pastikan menggunakan mergedRoutePath
            distance: newDistance,
            lastLocation: locationData,
          );

          emit(currentState.copyWith(
            currentPatrolPath: [
              ...?currentState.currentPatrolPath,
              event.position
            ],
            routePath: mergedRoutePath, // Pastikan menggunakan mergedRoutePath
            distance: newDistance,
            task: updatedTask,
            isOffline: !_isConnected,
            mockLocationDetected: false,
          ));

          print(
              'State updated with ${mergedRoutePath.length} route points'); // Gunakan mergedRoutePath
          print('Total distance: $newDistance meters');
        } catch (e, stackTrace) {
          print('Error in location update flow: $e');
          print('Stack trace: $stackTrace');
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
        print(
            'Current state route path points: ${currentState.routePath?.length ?? 0}');
        print(
            'Final route path points from event: ${event.finalRoutePath?.length ?? 0}');

        Map<String, dynamic>? existingRoutePathFromDb;
        if (_isConnected && currentState.task != null) {
          try {
            final taskSnapshot =
                await repository.getTaskById(taskId: currentState.task!.taskId);
            if (taskSnapshot != null && taskSnapshot.routePath != null) {
              existingRoutePathFromDb =
                  Map<String, dynamic>.from(taskSnapshot.routePath as Map);
              print(
                  'Found existing route_path in database with ${existingRoutePathFromDb.length} points');
            }
          } catch (e) {
            print('Error fetching existing route_path from database: $e');
          }
        }

        Map<String, dynamic> routePathToSave = {
          ...existingRoutePathFromDb ?? {}, // Data dari database
          ...?currentState.routePath, // Data dari state BLoC
          ...?event.finalRoutePath, // Data dari event (jika ada yang berbeda)
        };
        // Baris-baris ini sekarang redundan karena sudah digabungkan di atas dengan spread operator
        // if (existingRoutePathFromDb != null &&
        //     existingRoutePathFromDb.isNotEmpty) {
        //   routePathToSave.addAll(existingRoutePathFromDb);
        //   print('Added ${existingRoutePathFromDb.length} points from database');
        // }

        // if (currentState.routePath != null &&
        //     currentState.routePath!.isNotEmpty) {
        //   routePathToSave.addAll(currentState.routePath!);
        //   print(
        //       'Added ${currentState.routePath!.length} points from current state');
        // }

        // if (event.finalRoutePath != null && event.finalRoutePath!.isNotEmpty) {
        //   final newKeys = event.finalRoutePath!.keys
        //       .where((key) => !routePathToSave.containsKey(key))
        //       .toList();

        //   if (newKeys.isNotEmpty) {
        //     for (var key in newKeys) {
        //       routePathToSave[key] = event.finalRoutePath![key];
        //     }
        //     print(
        //         'Added ${newKeys.length} unique points from final route path');
        //   }
        // }

        print('Final merged route_path has ${routePathToSave.length} points');

        if (_isConnected) {
          await _onSyncOfflineData(SyncOfflineData(), emit);
          // Setelah sync, ambil lagi data task terbaru dari DB untuk memastikan routePath yang paling lengkap
          final updatedTaskFromDb =
              await repository.getTaskById(taskId: currentState.task!.taskId);
          if (updatedTaskFromDb != null &&
              updatedTaskFromDb.routePath != null) {
            routePathToSave =
                Map<String, dynamic>.from(updatedTaskFromDb.routePath as Map);
            print(
                'Refreshed route_pathToSave from DB after sync: ${routePathToSave.length} points');
          }
        }

        if (currentState.task != null && _isConnected) {
          add(CheckMissedCheckpoints(task: currentState.task!));
        }

        if (_isConnected) {
          await repository.updateTaskStatus(
              currentState.task!.taskId, 'finished');

          await repository.updateTask(
            currentState.task!.taskId,
            {
              'endTime': event.endTime.toIso8601String(),
              'distance': event.distance,
              'route_path':
                  routePathToSave, // Simpan route_path yang sudah digabungkan
              'status': 'finished', // Pastikan status final juga terkirim
            },
          );
          print('Updated task with endTime, distance, and final route_path');
        } else {
          // Logika offline untuk stop patroli
          if (_offlineLocationBox != null) {
            await _offlineLocationBox!
                .put('patrol_stop_${currentState.task!.taskId}', {
              'taskId': currentState.task!.taskId,
              'endTime': event.endTime.toIso8601String(),
              'distance': event.distance,
              'status': 'finished',
              // Perhatikan: saat offline, route_path yang lengkap mungkin belum tersedia.
              // Logika sync_offline_data harus memastikan ini digabungkan nanti.
              'route_path_length':
                  routePathToSave.length, // Simpan jumlah untuk debug
              'route_path':
                  routePathToSave, // Simpan state route_path saat ini juga untuk offline
            });

            print('Saved patrol completion data to offline storage');

            debugPrintOfflineData();

            // Emit error atau info ke user bahwa data akan disinkronkan nanti
            emit(PatrolError(
                'Patroli berhasil dihentikan dalam mode offline. Data akan disinkronkan saat koneksi tersedia.'));

            // Beri jeda singkat sebelum emit state PatrolLoaded (non-patrolling)
            await Future.delayed(const Duration(seconds: 2));
            emit(currentState.copyWith(
              isPatrolling: false,
              endTime: event.endTime,
              isOffline: true,
              routePath: routePathToSave, // Pertahankan routePath di state
            ));
          }
          return; // Penting: keluar dari fungsi jika offline
        }

        _locationSubscription?.cancel();
        _locationSubscription = null;

        List<PatrolTask> finishedTasks = [];
        if (_isConnected) {
          finishedTasks =
              await repository.getFinishedTasks(currentState.task!.userId);
        } else {
          finishedTasks = currentState.finishedTasks;
        }

        emit(currentState.copyWith(
          isPatrolling: false,
          currentPatrolPath: null,
          endTime: event.endTime,
          finishedTasks: finishedTasks,
          isOffline: !_isConnected,
        ));

        print(
            'Patrol stopped successfully with ${routePathToSave.length} route points');
      } catch (e, stackTrace) {
        print('Error stopping patrol: $e');
        print('Stack trace: $stackTrace');
        emit(PatrolError('Failed to stop patrol: $e'));
      }
    }
  }

  void _startLocationTracking() {
    print('Starting location tracking service...');

    _locationSubscription?.cancel();

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen(
      (Position position) {
        print('New position: ${position.latitude}, ${position.longitude}');

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
      },
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
        print('Timeliness changed from ${task.timeliness} to $newTimeliness');
        await repository.updateTask(task.taskId, {'timeliness': newTimeliness});

        // Update state
        if (state is PatrolLoaded) {
          final currentState = state as PatrolLoaded;
          emit(currentState.copyWith(
            task: task.copyWith(timeliness: newTimeliness),
          ));
        }
      }
    } catch (e) {
      print('Error checking timeliness: $e');
    }
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
    _timelinessTimer?.cancel();
    await _locationSubscription?.cancel();
    await _taskSubscription?.cancel();
    await _historySubscription?.cancel();
    await _connectivitySubscription?.cancel();
    await _offlineLocationBox?.close();
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
        emit(PatrolLoading());

        final updatedTask = currentState.task?.copyWith(
          initialReportPhotoUrl: event.photoUrl,
          initialReportNote: event.note,
          initialReportTime: event.reportTime,
        );

        if (updatedTask != null) {
          await repository.updateTask(
            updatedTask.taskId,
            {
              'initialReportPhotoUrl': event.photoUrl,
              'initialReportNote': event.note,
              'initialReportTime': event.reportTime.toIso8601String(),
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

  Future<void> _onCheckMissedCheckpoints(
    CheckMissedCheckpoints event,
    Emitter<PatrolState> emit,
  ) async {
    // Hanya jalankan jika online dan patroli sudah selesai (untuk validasi akhir)
    if (!_isConnected) return;

    try {
      final task = event.task;

      // Dapatkan semua titik yang dilalui petugas
      final List<LatLng> actualRoutePath =
          task.getRoutePathAsLatLng(); // Use the new method

      // Validasi jika semua titik telah dikunjungi (dalam radius 5m)
      const double requiredRadius = 10.0; // 5 meter
      final List<List<double>> missedCheckpoints = task.getMissedCheckpoints(
          actualRoutePath, requiredRadius); // Use the new method

      if (missedCheckpoints.isNotEmpty) {
        print('Patroli melewatkan ${missedCheckpoints.length} titik!');

        // Kirim notifikasi ke command center
        await sendMissedCheckpointsNotification(
          patrolTaskId: task.taskId,
          officerName: task.officerName,
          clusterName: task.clusterName,
          officerId: task.userId,
          missedCheckpoints: missedCheckpoints,
        );

        // Update task dengan flag missedCheckpoints = true
        // await repository.updateTask(
        //   task.taskId,
        //   {
        //     'missedCheckpoints': true,
        //     'missedCheckpointsCount': missedCheckpoints.length,
        //     'missedCheckpointsList': missedCheckpoints,
        //   },
        // );

        print('Notifikasi titik yang terlewat telah dikirim.');
      } else {
        print('Semua titik patroli telah dikunjungi.');
      }
    } catch (e) {
      print('Error checking missed checkpoints: $e');
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
