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
  final Map<String, dynamic>? finalRoutePath; // Tambahkan parameter ini

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

// States
abstract class PatrolState {}

class PatrolInitial extends PatrolState {}

class PatrolLoading extends PatrolState {}

class PatrolLoaded extends PatrolState {
  final PatrolTask? task;
  final bool isPatrolling;
  final List<Position>? currentPatrolPath;
  // add startTime and endTime
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? assignedStartTime;
  final DateTime? assignedEndTime;
  final double? distance;
  final Map<String, dynamic>? routePath; // Add this
  final List<PatrolTask> finishedTasks;

  PatrolLoaded({
    this.task,
    this.isPatrolling = false,
    this.currentPatrolPath,
    this.startTime,
    this.endTime,
    this.assignedStartTime,
    this.assignedEndTime,
    this.distance,
    this.routePath, // Add this
    this.finishedTasks = const [],
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
        finishedTasks
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
    Map<String, dynamic>? routePath, // Add this
    List<PatrolTask>? finishedTasks,
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
    on<ResumePatrol>(_onResumePatrol);
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
        distance: currentTask?.distance,
        isPatrolling: currentTask?.status ==
            'ongoing', // Changed from 'in_progress' to 'ongoing'
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
      print('Updating current task: ${event.task.taskId}'); // Debug print

      if (state is PatrolLoaded) {
        final currentState = state as PatrolLoaded;
        emit(currentState.copyWith(
          task: event.task,
          isPatrolling: event.task.status ==
              'ongoing', // Changed from 'in_progress' to 'ongoing'
        ));
      } else {
        emit(PatrolLoaded(
          task: event.task,
          isPatrolling: event.task.status ==
              'ongoing', // Changed from 'in_progress' to 'ongoing'
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

      // Emit loading state terlebih dahulu
      emit(PatrolLoading());

      // Update task status in database
      await repository.updateTask(
        event.task.taskId,
        {
          'status': 'ongoing',
          'startTime': event.startTime.toIso8601String(),
        },
      );

      // Initialize empty routePath if needed
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

      // Emit new state with isPatrolling = true and the updated task
      emit(PatrolLoaded(
        task: updatedTask,
        isPatrolling: true,
        startTime: event.startTime,
        routePath: routePath,
        distance: 0.0,
      ));

      // Start location tracking
      // _startLocationTracking();

      print('Patrol started successfully'); // Debug print
    } catch (e, stackTrace) {
      print('Error starting patrol: $e'); // Debug print
      print('Stack trace: $stackTrace');
      emit(PatrolError('Failed to start patrol: $e'));
    }
  }

  Future<void> _onUpdateTask(
    UpdateTask event,
    Emitter<PatrolState> emit,
  ) async {
    try {
      print('Updating task: ${event.taskId}'); // Debug print

      // await repository.updateTask(
      //   event.taskId,
      //   event.updates,
      // );

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

  // Perbaikan _onUpdatePatrolLocation untuk menyimpan route_path dengan benar
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

          // Ensure coordinates are stored as List<double>
          final List<double> coordinates = [
            event.position.latitude,
            event.position.longitude
          ];

          // Prepare timestamp key for consistent format
          final timestampKey =
              event.timestamp.millisecondsSinceEpoch.toString();

          // Create location data object
          final locationData = {
            'coordinates': coordinates,
            'timestamp': event.timestamp.toIso8601String(),
          };

          // Update route_path in the database FIRST
          try {
            // Direct write to the specific route_path entry
            await repository.updatePatrolLocation(
              currentState.task!.taskId,
              coordinates,
              event.timestamp,
            );
            print('Database location update successful');
          } catch (e) {
            print('Error updating database with location: $e');
            // Continue with local state update even if database update fails
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

          // Update total distance in database periodically
          if (updatedRoutePath.length % 5 == 0) {
            try {
              await repository.updateTask(
                currentState.task!.taskId,
                {'distance': newDistance},
              );
              print('Updated distance in database: $newDistance meters');
            } catch (e) {
              print('Error updating distance: $e');
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
          ));

          print('State updated with ${updatedRoutePath.length} route points');
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
        print('Current route path entries: ${currentState.routePath?.length}');

        // Update task status
        await repository.updateTaskStatus(
            currentState.task!.taskId, 'finished');

        // Update endTime
        await repository.updateTask(
          currentState.task!.taskId,
          {
            'endTime': event.endTime.toIso8601String(),
            'distance': event.distance,
          },
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

  List<Object> get props => [taskId, updates];
}
