import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/domain/repositories/route_repository.dart';
import '../../domain/entities/patrol_task.dart';

// Events
abstract class AdminEvent {
  const AdminEvent();
}

class LoadAllTasks extends AdminEvent {
  const LoadAllTasks();
}

class GetClusterDetail extends AdminEvent {
  final String clusterId;

  const GetClusterDetail(this.clusterId);
}

class LoadOfficersAndVehicles extends AdminEvent {
  const LoadOfficersAndVehicles();
}

class CreateTask extends AdminEvent {
  final String clusterId;
  final String vehicleId;
  final List<List<double>> assignedRoute;
  final String? assignedOfficerId;
  final DateTime? assignedStartTime;
  final DateTime? assignedEndTime;

  const CreateTask({
    required this.clusterId,
    required this.vehicleId,
    required this.assignedRoute,
    required this.assignedOfficerId,
    required this.assignedStartTime,
    required this.assignedEndTime,
  });
}

// Event untuk load seluruh clusters
class LoadClusters extends AdminEvent {
  const LoadClusters();
}

// Alias untuk LoadClusters untuk backward compatibility
class LoadAllClusters extends AdminEvent {
  const LoadAllClusters();
}

// Event untuk membuat cluster baru dengan akun
class CreateClusterAccount extends AdminEvent {
  final String name;
  final String email;
  final String password;
  final List<List<double>> clusterCoordinates;

  const CreateClusterAccount({
    required this.name,
    required this.email,
    required this.password,
    required this.clusterCoordinates,
  });
}

// Event untuk update informasi cluster
class UpdateClusterAccount extends AdminEvent {
  final User cluster;

  const UpdateClusterAccount({
    required this.cluster,
  });
}

// Event untuk update koordinat cluster
class UpdateClusterCoordinates extends AdminEvent {
  final String clusterId;
  final List<List<double>> coordinates;

  const UpdateClusterCoordinates({
    required this.clusterId,
    required this.coordinates,
  });
}

// Event untuk menambah officer ke cluster
class AddOfficerToClusterEvent extends AdminEvent {
  final String clusterId;
  final Officer officer;

  const AddOfficerToClusterEvent({
    required this.clusterId,
    required this.officer,
  });
}

// Event untuk update officer di cluster
class UpdateOfficerInClusterEvent extends AdminEvent {
  final String clusterId;
  final Officer officer;

  const UpdateOfficerInClusterEvent({
    required this.clusterId,
    required this.officer,
  });
}

// Event untuk hapus officer dari cluster
class RemoveOfficerFromClusterEvent extends AdminEvent {
  final String clusterId;
  final String officerId;

  const RemoveOfficerFromClusterEvent({
    required this.clusterId,
    required this.officerId,
  });
}

// Event untuk pencarian cluster
class SearchClustersEvent extends AdminEvent {
  final String searchTerm;

  const SearchClustersEvent(this.searchTerm);
}

// Event untuk menghapus cluster
class DeleteClusterEvent extends AdminEvent {
  final String clusterId;

  const DeleteClusterEvent(this.clusterId);
}

// Event untuk load tugas-tugas dari cluster tertentu
class LoadClusterTasksEvent extends AdminEvent {
  final String clusterId;

  const LoadClusterTasksEvent(this.clusterId);
}

// States
abstract class AdminState {}

class AdminInitial extends AdminState {}

class AdminLoading extends AdminState {}

// Loading state khusus untuk cluster
class ClustersLoading extends AdminState {}

// Perbaikan definisi AdminLoaded state
class AdminLoaded extends AdminState {
  final List<PatrolTask> activeTasks;
  final List<PatrolTask> completedTasks;
  final int totalOfficers;
  final List<String> vehicles;
  final List<User> clusters;

  AdminLoaded({
    required this.activeTasks,
    required this.completedTasks,
    required this.totalOfficers,
    required this.vehicles,
    required this.clusters,
  });
}

class AdminError extends AdminState {
  final String message;

  AdminError(this.message);
}

class LoadClusterDetails extends AdminEvent {
  final String clusterId;

  const LoadClusterDetails({required this.clusterId});
}

// State loading untuk detail cluster
class ClusterDetailsLoading extends AdminState {}

// State untuk detail cluster yang berhasil dimuat
class ClusterDetailsLoaded extends AdminState {
  final User cluster;

  ClusterDetailsLoaded({required this.cluster});
}

// State error untuk detail cluster
class ClusterDetailsError extends AdminState {
  final String message;

  ClusterDetailsError(this.message);
}

// Error state khusus untuk cluster
class ClustersError extends AdminState {
  final String message;

  ClustersError(this.message);
}

class CreateTaskLoading extends AdminState {}

class CreateTaskSuccess extends AdminState {}

class CreateTaskError extends AdminState {
  final String message;

  CreateTaskError(this.message);
}

class OfficersAndVehiclesLoaded extends AdminState {
  final List<Officer> officers;
  final List<User> clusters;
  final List<String> vehicles;

  OfficersAndVehiclesLoaded({
    required this.officers,
    required this.clusters,
    required this.vehicles,
  });
}

class OfficersAndVehiclesLoading extends AdminState {}

class OfficersAndVehiclesError extends AdminState {
  final String message;

  OfficersAndVehiclesError(this.message);
}

// Cluster Account States
class ClustersLoaded extends AdminState {
  final List<User> clusters;

  ClustersLoaded(this.clusters);
}

class ClusterDetailLoaded extends AdminState {
  final User cluster;

  ClusterDetailLoaded(this.cluster);
}

class ClusterOfficersLoaded extends AdminState {
  final String clusterId;
  final List<Officer> officers;

  ClusterOfficersLoaded({
    required this.clusterId,
    required this.officers,
  });
}

class ClusterTasksLoaded extends AdminState {
  final String clusterId;
  final List<PatrolTask> tasks;
  User? cluster;

  ClusterTasksLoaded({
    required this.clusterId,
    required this.tasks,
    this.cluster,
  });
}

// BLoC
class AdminBloc extends Bloc<AdminEvent, AdminState> {
  final RouteRepository repository;

  AdminBloc({required this.repository}) : super(AdminInitial()) {
    // Register all event handlers
    on<LoadAllTasks>(_onLoadAllTasks);
    on<CreateTask>(_onCreateTask);
    on<LoadOfficersAndVehicles>(_onLoadOfficersAndVehicles);
    on<GetClusterDetail>(_onGetClusterDetail);
    on<LoadClusterTasksEvent>(_onLoadClusterTasks);

    // Handlers for cluster-related events
    on<LoadClusters>(_onLoadClusters);
    on<LoadAllClusters>(_onLoadClusters); // Map both to same handler
    on<CreateClusterAccount>(_onCreateClusterAccount);
    on<UpdateClusterAccount>(_onUpdateClusterAccount);
    on<UpdateClusterCoordinates>(_onUpdateClusterCoordinates);
    on<AddOfficerToClusterEvent>(_onAddOfficerToCluster);
    on<UpdateOfficerInClusterEvent>(_onUpdateOfficerInCluster);
    on<RemoveOfficerFromClusterEvent>(_onRemoveOfficerFromCluster);
    on<SearchClustersEvent>(_onSearchClusters);
    on<DeleteClusterEvent>(_onDeleteCluster);
  }

  // Updated _onLoadAllTasks method
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

      // Load officers dari semua cluster
      final clusters = await repository.getAllClusters();

      // Hitung total officers dari semua cluster
      int totalOfficers = 0;
      for (var cluster in clusters) {
        if (cluster.officers != null) {
          totalOfficers += cluster.officers!.length;
        }
      }

      final vehicles = await repository.getAllVehicles();

      emit(AdminLoaded(
        activeTasks: tasks.where((t) => t.status == 'active').toList(),
        completedTasks: tasks.where((t) => t.status == 'finished').toList(),
        totalOfficers: totalOfficers,
        vehicles: vehicles,
        clusters: clusters,
      ));
    } catch (e) {
      print('Error loading all tasks: $e');
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
        clusterId: event.clusterId,
        vehicleId: event.vehicleId,
        assignedRoute: event.assignedRoute,
        assignedOfficerId: event.assignedOfficerId,
        assignedStartTime: event.assignedStartTime,
        assignedEndTime: event.assignedEndTime,
      );

      emit(CreateTaskSuccess());
      add(const LoadAllTasks());
    } catch (e) {
      emit(CreateTaskError('Failed to create task: $e'));
    }
  }

  // Updated _onLoadOfficersAndVehicles method
  Future<void> _onLoadOfficersAndVehicles(
    LoadOfficersAndVehicles event,
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(OfficersAndVehiclesLoading());

      // Load all clusters first
      final clusters = await repository.getAllClusters();

      // Collect all officers from each cluster
      List<Officer> allOfficers = [];
      for (var cluster in clusters) {
        if (cluster.officers != null) {
          // Set clusterId for each officer to ensure proper filtering later
          final officersWithClusterId = cluster.officers!.map((officer) {
            if (officer.clusterId.isEmpty) {
              return Officer(
                id: officer.id,
                name: officer.name,
                type: officer.type,
                shift: officer.shift,
                clusterId: cluster.id, // Set the cluster ID
                photoUrl: officer.photoUrl,
              );
            }
            return officer;
          }).toList();

          allOfficers.addAll(officersWithClusterId);
        }
      }

      final vehicles = await repository.getAllVehicles();

      emit(OfficersAndVehiclesLoaded(
          officers: allOfficers, vehicles: vehicles, clusters: clusters));
    } catch (e) {
      print('Error loading officers and vehicles: $e');
      emit(
          OfficersAndVehiclesError('Failed to load officers and vehicles: $e'));
    }
  }

  Future<void> _onGetClusterDetail(
      GetClusterDetail event, Emitter<AdminState> emit) async {
    try {
      emit(AdminLoading());
      final cluster = await repository.getClusterById(event.clusterId);
      // log('ini debug isi officers cluster: ${cluster.officers}');
      // Validasi tipe dan shift officer
      if (cluster.officers != null && cluster.officers!.isNotEmpty) {
        final validatedOfficers = cluster.officers!.map((officer) {
          // Pastikan officer memiliki properti type yang valid
          final officerType = officer.type;
          ShiftType officerShift = officer.shift;

          // Validasi kompatibilitas shift dengan tipe
          if (officerType == OfficerType.organik &&
              (officerShift == ShiftType.siang ||
                  officerShift == ShiftType.malamPanjang)) {
            officerShift = ShiftType.pagi;
          } else if (officerType == OfficerType.outsource &&
              (officerShift == ShiftType.pagi ||
                  officerShift == ShiftType.sore ||
                  officerShift == ShiftType.malam)) {
            officerShift = ShiftType.siang;
          }

          return Officer(
            id: officer.id,
            name: officer.name,
            type: officerType,
            shift: officerShift,
            clusterId:
                officer.clusterId.isNotEmpty ? officer.clusterId : cluster.id,
            photoUrl: officer.photoUrl,
          );
        }).toList();

        // Update cluster dengan officers tervalidasi
        final updatedCluster = User(
          id: cluster.id,
          name: cluster.name,
          email: cluster.email,
          role: cluster.role,
          officers: validatedOfficers,
          createdAt: cluster.createdAt,
          updatedAt: cluster.updatedAt,
          clusterCoordinates: cluster.clusterCoordinates,
        );

        emit(ClusterDetailLoaded(updatedCluster));
      } else {
        emit(ClusterDetailLoaded(cluster));
      }
    } catch (e) {
      emit(AdminError('Failed to get cluster details: $e'));
    }
  }

  Future<void> _onLoadClusters(
    AdminEvent event, // Accept either LoadClusters or LoadAllClusters
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(ClustersLoading());
      final clusters = await repository.getAllClusters();
      emit(ClustersLoaded(clusters));
    } catch (e) {
      emit(ClustersError('Failed to load clusters: $e'));
    }
  }

  Future<void> _onCreateClusterAccount(
    CreateClusterAccount event,
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(ClustersLoading());
      await repository.createClusterAccount(
        name: event.name,
        email: event.email,
        password: event.password,
        role: 'patrol', // Default role for clusters
        clusterCoordinates: event.clusterCoordinates,
      );
      final clusters = await repository.getAllClusters();
      emit(ClustersLoaded(clusters));
    } catch (e) {
      emit(ClustersError('Failed to create cluster account: $e'));
    }
  }

  Future<void> _onUpdateClusterAccount(
    UpdateClusterAccount event,
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(ClustersLoading());
      await repository.updateCluster(
        clusterId: event.cluster.id,
        updates: event.cluster.toMap(),
      );
      final cluster = await repository.getClusterById(event.cluster.id);
      emit(ClusterDetailLoaded(cluster));
    } catch (e) {
      emit(ClustersError('Failed to update cluster: $e'));
    }
  }

  Future<void> _onUpdateClusterCoordinates(
    UpdateClusterCoordinates event,
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(ClustersLoading());
      await repository.updateClusterCoordinates(
        clusterId: event.clusterId,
        coordinates: event.coordinates,
      );
      final cluster = await repository.getClusterById(event.clusterId);
      emit(ClusterDetailLoaded(cluster));
    } catch (e) {
      emit(ClustersError('Failed to update cluster coordinates: $e'));
    }
  }

  Future<void> _onAddOfficerToCluster(
    AddOfficerToClusterEvent event,
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(ClusterDetailsLoading()); // Ubah dari ClustersLoading

      // Tambahkan petugas ke cluster
      await repository.addOfficerToCluster(
        clusterId: event.clusterId,
        officer: event.officer,
      );

      // Load data cluster lengkap, bukan hanya officers
      final cluster = await repository.getClusterById(event.clusterId);

      // Emit state ClusterDetailLoaded yang digunakan oleh OfficerManagementScreen
      emit(ClusterDetailLoaded(cluster));
    } catch (e) {
      print('Error adding officer to cluster: $e');
      emit(ClusterDetailsError(
          'Failed to add officer to cluster: $e')); // Ubah jenis error state
    }
  }

  Future<void> _onUpdateOfficerInCluster(
    UpdateOfficerInClusterEvent event,
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(ClusterDetailsLoading()); // Ubah dari ClustersLoading

      await repository.updateOfficerInCluster(
        clusterId: event.clusterId,
        officer: event.officer,
      );

      // Load data cluster lengkap, bukan hanya officers
      final cluster = await repository.getClusterById(event.clusterId);

      // Emit state yang sesuai
      emit(ClusterDetailLoaded(cluster));
    } catch (e) {
      print('Error updating officer in cluster: $e');
      emit(ClusterDetailsError('Failed to update officer in cluster: $e'));
    }
  }

  Future<void> _onRemoveOfficerFromCluster(
    RemoveOfficerFromClusterEvent event,
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(ClusterDetailsLoading()); // Ubah dari ClustersLoading

      await repository.removeOfficerFromCluster(
        clusterId: event.clusterId,
        officerId: event.officerId,
      );

      // Load data cluster lengkap, bukan hanya officers
      final cluster = await repository.getClusterById(event.clusterId);

      // Emit state yang sesuai
      emit(ClusterDetailLoaded(cluster));
    } catch (e) {
      print('Error removing officer from cluster: $e');
      emit(ClusterDetailsError('Failed to remove officer from cluster: $e'));
    }
  }

  Future<void> _onSearchClusters(
    SearchClustersEvent event,
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(ClustersLoading());
      final clusters = await repository.searchClustersByName(event.searchTerm);
      emit(ClustersLoaded(clusters));
    } catch (e) {
      emit(ClustersError('Failed to search clusters: $e'));
    }
  }

  Future<void> _onDeleteCluster(
    DeleteClusterEvent event,
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(ClustersLoading());
      await repository.deleteCluster(event.clusterId);
      final clusters = await repository.getAllClusters();
      emit(ClustersLoaded(clusters));
    } catch (e) {
      emit(ClustersError('Failed to delete cluster: $e'));
    }
  }

  // Tambahkan event handler untuk load tugas-tugas cluster
  Future<void> _onLoadClusterTasks(
    LoadClusterTasksEvent event,
    Emitter<AdminState> emit,
  ) async {
    try {
      emit(ClustersLoading());
      final cluster = await repository.getClusterById(event.clusterId);
      final tasks = await repository.getClusterTasks(event.clusterId);
      emit(ClusterTasksLoaded(
          clusterId: event.clusterId, tasks: tasks, cluster: cluster));
    } catch (e) {
      emit(ClustersError('Failed to load cluster tasks: $e'));
    }
  }
}
