import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/cluster.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/domain/repositories/route_repository.dart';
import '../../domain/entities/patrol_task.dart';

// Events
abstract class AdminEvent {}

class LoadAllTasks extends AdminEvent {}

class LoadOfficersAndVehicles extends AdminEvent {}

// Cluster events
class LoadClusters extends AdminEvent {}

class CreateCluster extends AdminEvent {
  final String name;
  final String description;
  final List<List<double>> clusterCoordinates;
  final String status;

  CreateCluster({
    required this.name,
    required this.description,
    required this.clusterCoordinates,
    required this.status,
  });
}

class UpdateCluster extends AdminEvent {
  final String clusterId;
  final String name;
  final String description;
  final List<List<double>> clusterCoordinates;
  final String status;

  UpdateCluster({
    required this.clusterId,
    required this.name,
    required this.description,
    required this.clusterCoordinates,
    required this.status,
  });
}

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
  final List<ClusterModel> clusters;

  OfficersAndVehiclesLoaded({
    required this.officers,
    required this.vehicles,
    this.clusters = const [],
  });
}

class OfficersAndVehiclesLoading extends AdminState {}

class OfficersAndVehiclesError extends AdminState {
  final String message;
  OfficersAndVehiclesError(this.message);
}

// Cluster States
class ClustersLoading extends AdminState {}

class ClustersLoaded extends AdminState {
  final List<ClusterModel> clusters;

  ClustersLoaded(this.clusters);
}

class ClustersError extends AdminState {
  final String message;

  ClustersError(this.message);
}

// BLoC
class AdminBloc extends Bloc<AdminEvent, AdminState> {
  final RouteRepository repository;

  AdminBloc({required this.repository}) : super(AdminInitial()) {
    on<LoadAllTasks>(_onLoadAllTasks);
    on<CreateTask>(_onCreateTask);
    on<LoadOfficersAndVehicles>(_onLoadOfficersAndVehicles);
    on<LoadClusters>(_onLoadClusters);
    on<CreateCluster>(_onCreateCluster);
    on<UpdateCluster>(_onUpdateCluster);
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
        clusterId: event.assignedOfficerId,
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
      final clusters = await repository.getClusters();
      emit(OfficersAndVehiclesLoaded(officers: officers, vehicles: vehicles, clusters: clusters));
    } catch (e) {
      emit(
          OfficersAndVehiclesError('Failed to load officers and vehicles: $e'));
    }
  }

  Future<void> _onLoadClusters(
      LoadClusters event, Emitter<AdminState> emit) async {
    try {
      emit(ClustersLoading());
      final clusters = await repository.getClusters();
      emit(ClustersLoaded(clusters));
    } catch (e) {
      emit(ClustersError('Failed to load clusters: $e'));
    }
  }

  Future<void> _onCreateCluster(
      CreateCluster event, Emitter<AdminState> emit) async {
    try {
      await repository.createCluster(
        name: event.name,
        description: event.description,
        clusterCoordinates: event.clusterCoordinates,
        status: event.status,
      );

      final clusters = await repository.getClusters();
      emit(ClustersLoaded(clusters));
    } catch (e) {
      emit(ClustersError('Failed to create cluster: $e'));
    }
  }

  Future<void> _onUpdateCluster(
      UpdateCluster event, Emitter<AdminState> emit) async {
    try {
      await repository.updateCluster(
        clusterId: event.clusterId,
        updates: {
          'name': event.name,
          'description': event.description,
          'clusterCoordinates': event.clusterCoordinates,
          'status': event.status,
        },
      );

      final clusters = await repository.getClusters();
      emit(ClustersLoaded(clusters));
    } catch (e) {
      emit(ClustersError('Failed to update cluster: $e'));
    }
  }
}
