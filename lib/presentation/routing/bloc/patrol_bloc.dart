import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
    Connectivity().checkConnectivity().then((result) {
      _isConnected = (result != ConnectivityResult.none);
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final result =
            results.isNotEmpty ? results.first : ConnectivityResult.none;

        final wasConnected = _isConnected;
        _isConnected = (result != ConnectivityResult.none);

        if (state is PatrolLoaded) {
          final currentState = state as PatrolLoaded;
          emit(currentState.copyWith(isOffline: !_isConnected));
        }

        if (!wasConnected && _isConnected) {
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
      if (_offlineLocationBox!.isEmpty) {
        return;
      }

      if (state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;
        emit(currentState.copyWith(isSyncing: true));

        final stopKeyPattern = 'patrol_stop_';
        final stopKeys = _offlineLocationBox!.keys
            .where((k) => k.toString().startsWith(stopKeyPattern))
            .toList();

        final locationDataByTask = <String, Map<String, dynamic>>{};

        final locationKeys = _offlineLocationBox!.keys
            .where((k) =>
                !k.toString().startsWith(stopKeyPattern) &&
                !k.toString().startsWith('task_update_') &&
                !k.toString().startsWith('patrol_start_') &&
                !k.toString().startsWith('mock_detection_'))
            .toList();

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

        for (final taskId in locationDataByTask.keys) {
          try {
            Map<String, dynamic> existingRoutePath = {};
            try {
              final taskSnapshot = await repository.getTaskById(taskId: taskId);
              if (taskSnapshot != null && taskSnapshot.routePath != null) {
                existingRoutePath =
                    Map<String, dynamic>.from(taskSnapshot.routePath as Map);
              }
            } catch (e) {}

            final mergedRoutePath = {
              ...existingRoutePath,
              ...locationDataByTask[taskId]!
            };

            await repository.updateTask(
              taskId,
              {'route_path': mergedRoutePath},
            );

            for (final key in locationDataByTask[taskId]!.keys) {
              await _offlineLocationBox!.delete(key);
            }
          } catch (e) {}
        }

        final mockDetectionKeys = _offlineLocationBox!.keys
            .where((k) => k.toString().startsWith('mock_detection_'))
            .toList();

        if (mockDetectionKeys.isNotEmpty) {
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
              }
            } catch (e) {}
          }
        }

        if (stopKeys.isNotEmpty) {
          for (final key in stopKeys) {
            final data = _offlineLocationBox!.get(key);
            if (data != null && data is Map) {
              final taskId = data['taskId'] as String;
              final endTime = DateTime.parse(data['endTime'] as String);
              final distance = data['distance'] as double;

              try {
                await repository.updateTaskStatus(taskId, 'finished');

                await repository.updateTask(
                  taskId,
                  {
                    'endTime': endTime.toIso8601String(),
                    'distance': distance,
                    'status': 'finished',
                  },
                );

                await _offlineLocationBox!.delete(key);
              } catch (e) {}
            }
          }
        }

        final updateKeyPattern = 'task_update_';
        final updateKeys = _offlineLocationBox!.keys
            .where((k) => k.toString().startsWith(updateKeyPattern))
            .toList();

        for (final key in updateKeys) {
          final data = _offlineLocationBox!.get(key);
          if (data != null && data is Map) {
            final taskId = data['taskId'] as String;
            final updates = data['updates'] as Map<dynamic, dynamic>;

            try {
              await repository.updateTask(
                taskId,
                Map<String, dynamic>.from(updates),
              );
              await _offlineLocationBox!.delete(key);
            } catch (e) {}
          }
        }

        List<PatrolTask> finishedTasks = [];
        try {
          if (currentState.task != null) {
            finishedTasks =
                await repository.getFinishedTasks(currentState.task!.userId);
          }
        } catch (e) {
          finishedTasks = currentState.finishedTasks;
        }

        emit(currentState.copyWith(
          isSyncing: false,
          finishedTasks: finishedTasks,
        ));

        if (_offlineLocationBox!.length > 0) {}
      }
    } catch (e, stack) {
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
      if (event.task.clusterId.isNotEmpty) {
        await _loadClusterValidationRadius(event.task.clusterId);
      }

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
          }
        } catch (e) {}
      }

      // Jika dari database kosong atau tidak ada koneksi, coba dari event/task object
      if (initialRoutePath.isEmpty) {
        if (event.existingRoutePath != null &&
            event.existingRoutePath!.isNotEmpty) {
          event.existingRoutePath!.forEach((key, value) {
            initialRoutePath[key.toString()] = value;
          });
        } else if (event.task.routePath != null) {
          try {
            final taskRoutePath =
                Map<String, dynamic>.from(event.task.routePath as Map);
            taskRoutePath.forEach((key, value) {
              initialRoutePath[key.toString()] = value;
            });
          } catch (e) {}
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
    } catch (e) {
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

      final routePath = <String, dynamic>{};

      // Calculate initial timeliness
      final timeliness = _calculateTimeliness(event.task.assignedStartTime,
          event.startTime, event.task.assignedEndTime, 'ongoing');

      // PERBAIKAN: Ensure all critical fields are updated atomically
      final updateData = {
        'status': 'ongoing',
        'startTime': event.startTime.toIso8601String(),
        'timeliness': timeliness,
        // TAMBAHAN: Clear any previous end data
        'endTime': null,
        'distance': 0.0,
        // TAMBAHAN: Add start metadata
        'actualStartTime': event.startTime.toIso8601String(),
        'startedFromApp': true,
      };

      if (_isConnected) {
        // PERBAIKAN: Use transaction-like update to ensure atomicity
        try {
          await repository.updateTask(event.task.taskId, updateData);

          // TAMBAHAN: Verify the update was successful
          final verifyTask =
              await repository.getTaskById(taskId: event.task.taskId);
          if (verifyTask?.startTime == null) {
            throw Exception('Failed to update startTime in database');
          }
        } catch (e) {
          print('Error updating task start: $e');
          emit(PatrolError('Failed to start patrol: database update failed'));
          return;
        }
      } else {
        if (_offlineLocationBox != null) {
          await _offlineLocationBox!.put('patrol_start_${event.task.taskId}', {
            'taskId': event.task.taskId,
            ...updateData,
          });
        }
      }

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
      );

      emit(PatrolLoaded(
        task: updatedTask,
        isPatrolling: true,
        startTime: event.startTime,
        routePath: routePath,
        distance: 0.0,
        isOffline: !_isConnected,
      ));

      _startLocationTracking();

      print(
          'Patrol started successfully for task ${event.task.taskId} at ${event.startTime}');
    } catch (e, stackTrace) {
      print('Error in _onStartPatrol: $e');
      print('Stack trace: $stackTrace');
      emit(PatrolError('Failed to start patrol: $e'));
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

  Future<void> _onUpdatePatrolLocation(
    UpdatePatrolLocation event,
    Emitter<PatrolState> emit,
  ) async {
    if (state is PatrolLoaded) {
      final currentState = state as PatrolLoaded;
      if (currentState.isPatrolling && currentState.task != null) {
        try {
          final isMocked =
              await LocationValidator.isLocationMocked(event.position);

          if (isMocked) {
            final newMockCount = currentState.mockLocationCount + 1;

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
              } catch (e) {}
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
              }
            } catch (e) {}
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
            } catch (e) {}
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

              if (_offlineLocationBox!.length % 10 == 0) {}
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

          // Gunakan mergedRoutePath
        } catch (e, stackTrace) {}
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
        // TAMBAHAN: Validate task integrity before stopping
        if (currentState.task?.startTime == null) {
          // Try to fix first
          await repository.checkAndFixTaskIntegrity(currentState.task!.taskId);

          // Re-check
          final updatedTask =
              await repository.getTaskById(taskId: currentState.task!.taskId);
          if (updatedTask?.startTime == null) {
            emit(PatrolError(
                'Cannot stop patrol: patrol was never started properly. Please start patrol first.'));
            return;
          }
        }

        final actualStartTime = currentState.task!.startTime!;

        // TAMBAHAN: Validate end time
        if (event.endTime.isBefore(actualStartTime)) {
          emit(PatrolError('Invalid end time: cannot be before start time'));
          return;
        }

        // TAMBAHAN: Check if already finished
        if (currentState.task!.status == 'finished') {
          emit(PatrolError('Patrol is already finished'));
          return;
        }

        // Rest of existing logic with additional validation...
        Map<String, dynamic>? existingRoutePathFromDb;
        if (_isConnected && currentState.task != null) {
          try {
            final taskSnapshot =
                await repository.getTaskById(taskId: currentState.task!.taskId);
            if (taskSnapshot != null && taskSnapshot.routePath != null) {
              existingRoutePathFromDb =
                  Map<String, dynamic>.from(taskSnapshot.routePath as Map);
            }
          } catch (e) {
            print('Error getting existing route path: $e');
          }
        }

        Map<String, dynamic> routePathToSave = {
          ...?existingRoutePathFromDb,
          ...?currentState.routePath,
          ...?event.finalRoutePath,
        };

        // PERBAIKAN: Ensure critical fields in stop update
        final stopUpdateData = {
          'endTime': event.endTime.toIso8601String(),
          'distance': event.distance,
          'route_path': routePathToSave,
          'status': 'finished',
          // TAMBAHAN: Preserve critical start data
          'startTime': actualStartTime.toIso8601String(),
          'actualEndTime': event.endTime.toIso8601String(),
          'finishedFromApp': true,
        };

        if (_isConnected) {
          await repository.updateTaskStatus(
              currentState.task!.taskId, 'finished');
          await repository.updateTask(
              currentState.task!.taskId, stopUpdateData);
        } else {
          if (_offlineLocationBox != null) {
            await _offlineLocationBox!
                .put('patrol_stop_${currentState.task!.taskId}', {
              'taskId': currentState.task!.taskId,
              ...stopUpdateData,
            });
          }
        }

        // Rest of existing logic...
      } catch (e, stackTrace) {
        print('Error in _onStopPatrol: $e');
        emit(PatrolError('Failed to stop patrol: $e'));
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
        accuracy: LocationAccuracy.best,
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

      if (event.task.clusterId.isNotEmpty) {
        await _loadClusterValidationRadius(event.task.clusterId);
      }
      final double requiredRadius =
          _clusterValidationRadius ?? task.validationRadius;

      // Dapatkan semua titik yang dilalui petugas
      final List<LatLng> actualRoutePath =
          task.getRoutePathAsLatLng(); // Use the new method

      // Validasi jika semua titik telah dikunjungi (dalam radius 5m)
      final List<List<double>> missedCheckpoints = task.getMissedCheckpoints(
          actualRoutePath, requiredRadius); // Use the new method

      if (missedCheckpoints.isNotEmpty) {
        // Kirim notifikasi ke command center
        await sendMissedCheckpointsNotification(
          patrolTaskId: task.taskId,
          officerName: task.officerName,
          clusterName: task.clusterName,
          officerId: task.userId,
          missedCheckpoints: missedCheckpoints,
          customRadius: requiredRadius,
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
      } else {}
    } catch (e) {}
  }

  double _getValidationRadius(PatrolTask? task) {
    // Prioritas: Cluster radius → Task radius → Default
    return _clusterValidationRadius ?? task?.validationRadius ?? 50.0;
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
