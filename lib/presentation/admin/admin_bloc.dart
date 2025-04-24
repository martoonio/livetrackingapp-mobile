import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/repositories/route_repository.dart';
import '../../domain/entities/patrol_task.dart';

// Events
abstract class AdminEvent {}

class LoadAllTasks extends AdminEvent {}

class CreateTask extends AdminEvent {
  final String vehicleId;
  final List<List<double>> assignedRoute;
  final String? assignedOfficerId;

  CreateTask({
    required this.vehicleId,
    required this.assignedRoute,
    required this.assignedOfficerId,
  });
}

// States
abstract class AdminState {}

class AdminInitial extends AdminState {}

class AdminLoading extends AdminState {}

class AdminLoaded extends AdminState {
  final List<PatrolTask> activeTasks;
  final List<PatrolTask> completedTasks;
  final int totalOfficers;
  final List<String> vehicles;

  AdminLoaded({
    required this.activeTasks,
    required this.completedTasks,
    required this.totalOfficers,
    required this.vehicles,
  });
}

class AdminError extends AdminState {
  final String message;
  AdminError(this.message);
}

// BLoC
class AdminBloc extends Bloc<AdminEvent, AdminState> {
  final RouteRepository repository;

  AdminBloc({required this.repository}) : super(AdminInitial()) {
    on<LoadAllTasks>(_onLoadAllTasks);
    on<CreateTask>(_onCreateTask);
  }

  Future<void> _onLoadAllTasks(
    LoadAllTasks event,
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(AdminLoading());
      // Implement repository methods to fetch tasks
      final tasks = await repository.getAllTasks();
      final officers = await repository.getAllOfficers();
      final vehicles = await repository.getAllVehicles();

      emit(AdminLoaded(
        activeTasks: tasks.where((t) => t.status == 'active').toList(),
        completedTasks: tasks.where((t) => t.status == 'finished').toList(),
        totalOfficers: officers.length,
        vehicles: vehicles,
      ));
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }

  Future<void> _onCreateTask(
    CreateTask event,
    Emitter<AdminState> emit,
  ) async {
    try {
      await repository.createTask(
        vehicleId: event.vehicleId,
        assignedRoute: event.assignedRoute,
        assignedOfficerId: event.assignedOfficerId,
      );

      add(LoadAllTasks());
    } catch (e) {
      emit(AdminError(e.toString()));
    }
  }
}
