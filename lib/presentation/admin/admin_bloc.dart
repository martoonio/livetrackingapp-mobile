import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/domain/repositories/route_repository.dart';
import '../../domain/entities/patrol_task.dart';

// Events
abstract class AdminEvent {}

class LoadAllTasks extends AdminEvent {}

class LoadOfficersAndVehicles extends AdminEvent {}

class CreateTask extends AdminEvent {
  final String vehicleId;
  final List<List<double>> assignedRoute;
  final String? assignedOfficerId;
  final DateTime? assignedStartTime;
  final DateTime? assignedEndTime;

  CreateTask({
    required this.vehicleId,
    required this.assignedRoute,
    required this.assignedOfficerId,
    required this.assignedStartTime,
    required this.assignedEndTime,
  });
}

class CreateTaskLoading extends AdminState {}

class CreateTaskSuccess extends AdminState {}

class CreateTaskError extends AdminState {
  final String message;
  CreateTaskError(this.message);
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

class OfficersAndVehiclesLoaded extends AdminState {
  final List<User> officers;
  final List<String> vehicles;

  OfficersAndVehiclesLoaded({
    required this.officers,
    required this.vehicles,
  });
}

class OfficersAndVehiclesLoading extends AdminState {}

class OfficersAndVehiclesError extends AdminState {
  final String message;
  OfficersAndVehiclesError(this.message);
}

// BLoC
class AdminBloc extends Bloc<AdminEvent, AdminState> {
  final RouteRepository repository;

  AdminBloc({required this.repository}) : super(AdminInitial()) {
    on<LoadAllTasks>(_onLoadAllTasks);
    on<CreateTask>(_onCreateTask);
    on<LoadOfficersAndVehicles>(_onLoadOfficersAndVehicles);
  }

  Future<void> _onLoadAllTasks(
    LoadAllTasks event,
    Emitter<AdminState> emit,
  ) async {
    try {
      // Pertahankan state sebelumnya jika ada
      final currentState = state;
      if (currentState is AdminLoaded) {
        emit(currentState); // Emit state sebelumnya
      } else {
        emit(AdminLoading());
      }

      // Muat data baru
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
      emit(CreateTaskLoading());

      await repository.createTask(
        vehicleId: event.vehicleId,
        assignedRoute: event.assignedRoute,
        assignedOfficerId: event.assignedOfficerId,
        assignedStartTime: event.assignedStartTime,
        assignedEndTime: event.assignedEndTime,
      );

      emit(CreateTaskSuccess());
      add(LoadAllTasks());
    } catch (e) {
      emit(CreateTaskError('Failed to create task: $e'));
    }
  }

  Future<void> _onLoadOfficersAndVehicles(
    LoadOfficersAndVehicles event,
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(OfficersAndVehiclesLoading());
      final officers = await repository.getAllOfficers();
      final vehicles = await repository.getAllVehicles();
      emit(OfficersAndVehiclesLoaded(officers: officers, vehicles: vehicles));
    } catch (e) {
      emit(
          OfficersAndVehiclesError('Failed to load officers and vehicles: $e'));
    }
  }
}
