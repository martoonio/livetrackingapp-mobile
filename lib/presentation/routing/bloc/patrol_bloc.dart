import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import '../../../domain/entities/patrol_task.dart';
import '../../../domain/repositories/route_repository.dart';

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

  @override
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
  StopPatrol({required this.endTime});
}

class LoadPatrolHistory extends PatrolEvent {
  final String userId;

  LoadPatrolHistory({required this.userId});

  @override
  List<Object?> get props => [userId];
}

class UpdateCurrentTask extends PatrolEvent {
  final PatrolTask task;
  UpdateCurrentTask({required this.task});
  @override
  List<Object?> get props => [task];
}

class UpdateFinishedTasks extends PatrolEvent {
  final List<PatrolTask> tasks;
  UpdateFinishedTasks({required this.tasks});
  @override
  List<Object?> get props => [tasks];
}

// States
abstract class PatrolState {}

class PatrolInitial extends PatrolState {}

class PatrolLoading extends PatrolState {}

class PatrolLoaded extends PatrolState {
  final PatrolTask? task;
  final bool isPatrolling;
  final List<Position>? currentPatrolPath;
  final Map<String, dynamic>? routePath; // Add this
  final List<PatrolTask> finishedTasks;

  PatrolLoaded({
    this.task,
    this.isPatrolling = false,
    this.currentPatrolPath,
    this.routePath, // Add this
    this.finishedTasks = const [],
  });

  @override
  List<Object?> get props =>
      [task, isPatrolling, currentPatrolPath, routePath, finishedTasks];

  PatrolLoaded copyWith({
    PatrolTask? task,
    bool? isPatrolling,
    List<Position>? currentPatrolPath,
    Map<String, dynamic>? routePath, // Add this
    List<PatrolTask>? finishedTasks,
  }) {
    return PatrolLoaded(
      task: task ?? this.task,
      isPatrolling: isPatrolling ?? this.isPatrolling,
      currentPatrolPath: currentPatrolPath ?? this.currentPatrolPath,
      routePath: routePath ?? this.routePath, // Add this
      finishedTasks: finishedTasks ?? this.finishedTasks,
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

  Future<void> _onLoadPatrolHistory(
    LoadPatrolHistory event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      print('Loading patrol history for user: ${event.userId}'); // Debug print
      emit(PatrolLoading());

      // Get current active task and finished tasks in parallel
      final currentTaskFuture = repository.getCurrentTask(event.userId);
      final finishedTasksFuture = repository.getFinishedTasks(event.userId);

      final results =
          await Future.wait([currentTaskFuture, finishedTasksFuture]);
      final currentTask = results[0] as PatrolTask?;
      final finishedTasks = results[1] as List<PatrolTask>;

      print('Loaded ${finishedTasks.length} finished tasks'); // Debug print

      // Always emit PatrolLoaded, even without current task
      emit(PatrolLoaded(
        task: currentTask,
        finishedTasks: finishedTasks,
        isPatrolling: currentTask?.status == 'in_progress',
      ));
    } catch (e) {
      print('Error in _onLoadPatrolHistory: $e'); // Debug print
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
      emit(PatrolLoaded(finishedTasks: event.tasks));
    }
  }

  void _onUpdateCurrentTask(
    UpdateCurrentTask event,
    Emitter<PatrolState> emit,
  ) {
    try {
      print('Updating current task: ${event.task?.taskId}'); // Debug print

      if (state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;
        emit(currentState.copyWith(
          task: event.task,
          isPatrolling: event.task?.status == 'in_progress',
        ));
      } else {
        emit(PatrolLoaded(
          task: event.task,
          isPatrolling: event.task?.status == 'in_progress',
          finishedTasks: const [], // Initialize empty list
        ));
      }
    } catch (e) {
      print('Error updating current task: $e'); // Debug print
      emit(PatrolError('Failed to update current task: $e'));
    }
  }

// Update _onLoadRouteData to include finished tasks
  Future<void> _onLoadRouteData(
    LoadRouteData event,
    Emitter<PatrolState> emit,
  ) async {
    emit(PatrolLoading());
    try {
      // Cancel existing subscriptions
      await _taskSubscription?.cancel();
      await _historySubscription?.cancel();

      // Start listening to current task stream
      _taskSubscription = repository.watchCurrentTask(event.userId).listen(
        (task) {
          if (task != null) {
            add(UpdateCurrentTask(task: task));
          }
        },
        onError: (error) {
          print('Task stream error: $error'); // Debug print
          emit(PatrolError('Failed to watch current task: $error'));
        },
      );

      // Start listening to finished tasks stream
      _historySubscription = repository.watchFinishedTasks(event.userId).listen(
        (tasks) {
          add(UpdateFinishedTasks(tasks: tasks));
        },
        onError: (error) {
          print('History stream error: $error'); // Debug print
          emit(PatrolError('Failed to watch finished tasks: $error'));
        },
      );
    } catch (e) {
      print('Error loading route data: $e'); // Debug print
      emit(PatrolError(e.toString()));
    }
  }

  Future<void> _onStartPatrol(
    StartPatrol event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      print('Starting patrol for task: ${event.task.taskId}'); // Debug print

      // First update task status
      await repository.updateTask(
        event.task.taskId,
        {
          'status': 'ongoing',
          'startTime': event.startTime.toIso8601String(),
        },
      );

      // Then emit new state with isPatrolling = true
      emit(PatrolLoaded(
        task: event.task,
        isPatrolling: true,
      ));

      // Start location tracking
      _startLocationTracking();

      print('Patrol started successfully'); // Debug print
    } catch (e) {
      print('Error starting patrol: $e'); // Debug print
      emit(PatrolError('Failed to start patrol: $e'));
    }
  }

  Future<void> _onUpdateTask(
    UpdateTask event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      print('Updating task: ${event.taskId}'); // Debug print

      await repository.updateTask(
        event.taskId,
        event.updates,
      );

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
          isPatrolling: isInProgress, // Set based on status update
        ));
        print(
            'Task updated successfully with isPatrolling: $isInProgress'); // Debug print
      }
    } catch (e) {
      print('Error in _onUpdateTask: $e'); // Debug print
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
          final coordinates = [
            event.position.latitude,
            event.position.longitude
          ];

          // Update repository first
          await repository.updatePatrolLocation(
            currentState.task!.taskId,
            coordinates,
            event.timestamp,
          );

          // Update local state
          final updatedRoutePath =
              Map<String, dynamic>.from(currentState.routePath ?? {});
          final timestampKey =
              event.timestamp.millisecondsSinceEpoch.toString();

          updatedRoutePath[timestampKey] = {
            'coordinates': coordinates,
            'timestamp': event.timestamp.toIso8601String(),
          };

          emit(currentState.copyWith(
            currentPatrolPath: [
              ...?currentState.currentPatrolPath,
              event.position
            ],
            routePath: updatedRoutePath,
            task: currentState.task?.copyWith(
              routePath: updatedRoutePath,
            ),
          ));

          print('Location updated successfully');
        } catch (e) {
          print('Error updating location: $e');
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
        print('Current route path entries: ${currentState.routePath?.length}');

        // Update task status
        await repository.updateTaskStatus(
            currentState.task!.taskId, 'finished');

        // Update endTime
        await repository.updateTask(
          currentState.task!.taskId,
          {'endTime': event.endTime.toIso8601String()},
        );

        // Cancel location tracking
        _locationSubscription?.cancel();
        _locationSubscription = null;

        // Get updated finished tasks
        final finishedTasks =
            await repository.getFinishedTasks(currentState.task!.userId);

        // Save route path for summary
        final routePath = currentState.routePath;
        if (routePath != null && routePath.isNotEmpty) {
          print('Converting route path with ${routePath.length} entries');

          // Sort entries by timestamp
          final sortedEntries = routePath.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));

          // Convert to list of coordinates
          final List<List<double>> convertedPath = sortedEntries.map((entry) {
            final coordinates = entry.value['coordinates'] as List<double>;
            return coordinates;
          }).toList();

          print('Converted to ${convertedPath.length} coordinate points');

          // Update task with final path
          await repository.updateTask(
            currentState.task!.taskId,
            {
              'route_path': routePath,
              'status': 'finished',
            },
          );
        }

        // Emit new state
        emit(currentState.copyWith(
          isPatrolling: false,
          currentPatrolPath: null,
          routePath: null,
          finishedTasks: finishedTasks,
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

    _locationSubscription?.cancel();
    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      (Position position) {
        print('New position: ${position.latitude}, ${position.longitude}');

        // Only update if we're in a patrolling state
        if (state is PatrolLoaded && (state as PatrolLoaded).isPatrolling) {
          add(UpdatePatrolLocation(
            position: position,
            timestamp: DateTime.now(),
          ));
        }
      },
      onError: (error) {
        print('Location tracking error: $error');
        // Don't emit error state to prevent disrupting tracking
      },
      cancelOnError: false, // Keep tracking even if errors occur
      onDone: () {
        print('Location tracking stopped');
      },
    );
  }

  // Future<void> _onUpdateTask(
  //   UpdateTask event,
  //   Emitter<PatrolState> emit,
  // ) async {
  //   try {
  //     print('Updating task: ${event.taskId}'); // Debug print

  //     // Update task in repository
  //     await repository.updateTask(
  //       event.taskId,
  //       event.updates,
  //     );

  //     if (state is PatrolLoaded) {
  //       final currentState = state as PatrolLoaded;
  //       // Emit new state with same task but updated status
  //       emit(PatrolLoaded(
  //         task: currentState.task.copyWith(
  //           status: event.updates['status'] as String?,
  //           startTime: event.updates['startTime'] != null
  //               ? DateTime.parse(event.updates['startTime'] as String)
  //               : null,
  //         ),
  //         isPatrolling: true,
  //       ));
  //       print('Task updated successfully'); // Debug print
  //     }
  //   } catch (e) {
  //     print('Error in _onUpdateTask: $e'); // Debug print
  //     emit(PatrolError('Failed to update task: $e'));
  //   }
  // }

  @override
  Future<void> close() async {
    await _locationSubscription?.cancel();
    await _taskSubscription?.cancel();
    await _historySubscription?.cancel();
    return super.close();
  }
}

// Additional Event for task updates
class UpdateTask extends PatrolEvent {
  final String taskId;
  final Map<String, dynamic> updates;

  UpdateTask({
    required this.taskId,
    required this.updates,
  });

  @override
  List<Object> get props => [taskId, updates];
}
