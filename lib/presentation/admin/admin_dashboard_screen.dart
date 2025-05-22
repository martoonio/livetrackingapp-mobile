import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/admin/patrol_history_screen.dart';
import 'package:livetrackingapp/presentation/cluster/cluster_detail_screen.dart';
import 'create_task_screen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:lottie/lottie.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _isLoading = false;
  int? _expandedClusterIndex;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() => _isLoading = true);
    // Load clusters dan tasks
    context.read<AdminBloc>().add(const LoadAllClusters());
    context.read<AdminBloc>().add(const LoadAllTasks());
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'Command Center Dashboard',
          style: boldTextStyle(color: neutralWhite, size: 20),
        ),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: BlocBuilder<AdminBloc, AdminState>(
        builder: (context, state) {
          if (state is AdminLoading || _isLoading) {
            return Center(
              child: Lottie.asset(
                'assets/lottie/maps_loading.json',
                width: 200,
                height: 100,
              ),
            );
          }

          if (state is AdminError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${state.message}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kbpBlue900,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            );
          }

          if (state is AdminLoaded) {
            final clusters = state.clusters;
            return Column(
              children: [
                _buildStatisticsCard(state),
                Expanded(
                  child: clusters.isEmpty
                      ? _buildEmptyState()
                      : _buildClusterList(state),
                ),
              ],
            );
          } else if (state is ClustersLoaded) {
            // Jika hanya clusters yang sudah loaded, tampilkan UI khusus clusters
            return Column(
              children: [
                _buildBasicStatisticsCard(state),
                Expanded(
                  child: state.clusters.isEmpty
                      ? _buildEmptyState()
                      : _buildClusterListOnly(state.clusters),
                ),
              ],
            );
          }

          return const Center(child: Text('Memuat data...'));
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kbpBlue900,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CreateTaskScreen(),
            ),
          ).then((_) => _loadData());
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.location_city_outlined,
            size: 72,
            color: neutral400,
          ),
          const SizedBox(height: 16),
          const Text(
            'Belum ada cluster',
            style: TextStyle(
              fontSize: 18,
              color: neutral700,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tambahkan cluster untuk mulai mengelola petugas dan rute patroli',
            textAlign: TextAlign.center,
            style: TextStyle(color: neutral600),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // Navigasi ke halaman create cluster
              Navigator.pushNamed(context, '/create-cluster')
                  .then((_) => _loadData());
            },
            icon: const Icon(Icons.add),
            label: const Text('Buat Tatar Baru'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kbpBlue900,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicStatisticsCard(ClustersLoaded state) {
    int totalOfficers = 0;
    for (var cluster in state.clusters) {
      totalOfficers += (cluster.officers?.length ?? 0);
    }

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              'Tatar',
              state.clusters.length.toString(),
              kbpBlue900,
            ),
            _buildStatItem(
              'Petugas',
              totalOfficers.toString(),
              warningY300,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCard(AdminLoaded state) {
    int totalOfficers = 0;
    for (var cluster in state.clusters) {
      totalOfficers += (cluster.officers?.length ?? 0);
    }

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              'Tatar',
              state.clusters.length.toString(),
              kbpBlue900,
            ),
            _buildStatItem(
              'Task Aktif',
              state.activeTasks.length.toString(),
              kbpBlue700,
            ),
            _buildStatItem(
              'Task Selesai',
              state.completedTasks.length.toString(),
              successG300,
            ),
            _buildStatItem(
              'Petugas',
              totalOfficers.toString(),
              warningY300,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: neutral700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildClusterListOnly(List<User> clusters) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: clusters.length,
      itemBuilder: (context, index) {
        final cluster = clusters[index];
        return _buildClusterCard(
          cluster: cluster,
          index: index,
          activeTasks: [], // Tidak ada data task
        );
      },
    );
  }

  Widget _buildClusterList(AdminLoaded state) {
    final clusters = state.clusters;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: clusters.length,
      itemBuilder: (context, index) {
        final cluster = clusters[index];

        // Filter tugas berdasarkan clusterId
        final activeTasks = state.activeTasks
            .where((task) => task.clusterId == cluster.id)
            .toList();

        return _buildClusterCard(
          cluster: cluster,
          index: index,
          activeTasks: activeTasks,
        );
      },
    );
  }

  Widget _buildClusterCard({
    required User cluster,
    required int index,
    required List<PatrolTask> activeTasks,
  }) {
    final isExpanded = _expandedClusterIndex == index;
    final officers = cluster.officers ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isExpanded ? kbpBlue300 : Colors.transparent,
          width: isExpanded ? 1 : 0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - selalu terlihat
          InkWell(
            onTap: () {
              setState(() {
                if (_expandedClusterIndex == index) {
                  _expandedClusterIndex = null;
                } else {
                  _expandedClusterIndex = index;
                }
              });
            },
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cluster.name,
                          style: boldTextStyle(size: 18),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Petugas: ${officers.length} · Tugas Aktif: ${activeTasks.length}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: neutral600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility, color: kbpBlue900),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClusterDetailScreen(
                                clusterId: cluster.id,
                                initialTab: 0, // Info tab
                              ),
                            ),
                          ).then((_) => _loadData());
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          isExpanded ? Icons.expand_less : Icons.expand_more,
                          color: kbpBlue900,
                        ),
                        onPressed: () {
                          setState(() {
                            if (_expandedClusterIndex == index) {
                              _expandedClusterIndex = null;
                            } else {
                              _expandedClusterIndex = index;
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Content - hanya terlihat jika expanded
          if (isExpanded) ...[
            const Divider(height: 1),
            // Bagian officer
            Container(
              color: neutral300,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Petugas (${officers.length})',
                        style: semiBoldTextStyle(size: 16),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClusterDetailScreen(
                                clusterId: cluster.id,
                                initialTab: 1, // Officers tab
                              ),
                            ),
                          ).then((_) => _loadData());
                        },
                        icon: const Icon(Icons.people, size: 16),
                        label: const Text('Kelola Petugas'),
                        style: TextButton.styleFrom(
                          foregroundColor: kbpBlue900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Bagian officers.isEmpty ? ...
                  officers.isEmpty
                      ? const Text(
                          'Belum ada petugas di cluster ini',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: neutral600,
                          ),
                        )
                      : SizedBox(
                          height:
                              70, // Sedikit ditinggikan untuk menampung badge
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: officers.length,
                            itemBuilder: (context, idx) {
                              final officer = officers[idx];
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: kbpBlue100,
                                      backgroundImage: officer.photoUrl != null
                                          ? NetworkImage(officer.photoUrl!)
                                          : null,
                                      child: officer.photoUrl == null
                                          ? Text(
                                              officer.name.isNotEmpty
                                                  ? officer.name[0]
                                                      .toUpperCase()
                                                  : '?',
                                              style: boldTextStyle(
                                                  color: kbpBlue900, size: 14),
                                            )
                                          : null,
                                    ),
                                    8.width,
                                    SizedBox(
                                      width: 70, // Batasi lebar
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            officer.name.length > 10
                                                ? '${officer.name.substring(0, 10)}...'
                                                : officer.name,
                                            style: boldTextStyle(size: 12),
                                            textAlign: TextAlign.center,
                                          ),
                                          Container(
                                            margin:
                                                const EdgeInsets.only(top: 2),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: officer.type ==
                                                      OfficerType.organik
                                                  ? successG50
                                                  : warningY50,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              officer.type ==
                                                      OfficerType.organik
                                                  ? 'Organik'
                                                  : 'Outsource',
                                              style: semiBoldTextStyle(
                                                size: 10,
                                                color: officer.type ==
                                                        OfficerType.organik
                                                    ? successG500
                                                    : warningY500,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ],
              ),
            ),
            // Bagian task
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Tugas Aktif (${activeTasks.length})',
                        style: semiBoldTextStyle(size: 16),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CreateTaskScreen(
                                  // initialClusterId: cluster.id,
                                  ),
                            ),
                          ).then((_) => _loadData());
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Tambah Tugas'),
                        style: TextButton.styleFrom(
                          foregroundColor: kbpBlue900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  activeTasks.isEmpty
                      ? const Text(
                          'Tidak ada tugas aktif untuk cluster ini',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: neutral600,
                          ),
                        )
                      : ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: activeTasks.length,
                          itemBuilder: (context, taskIndex) {
                            final task = activeTasks[taskIndex];
// Cari officer yang mengerjakan task ini
                            final assignedOfficer =
                                _findOfficerByUserId(officers, task.userId) ??
                                    Officer(
                                      id: task.userId ?? '',
                                      name: task.userId != null
                                          ? 'Petugas ${task.userId.substring(0, 4)}...'
                                          : 'Tidak diketahui',
                                      type: OfficerType.organik,
                                      shift: ShiftType.pagi,
                                      clusterId: cluster.id,
                                    );

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 0,
                              color: neutral200,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: const BorderSide(color: neutral300),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        // Status indicator
                                        CircleAvatar(
                                          backgroundColor:
                                              _getStatusColor(task.status),
                                          radius: 16,
                                          child: const Icon(
                                            Icons.task_alt,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 12),

                                        // Task ID
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Tugas #${task.taskId.substring(0, 8)}',
                                                style: boldTextStyle(size: 16),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Status: ${_getStatusText(task.status)}',
                                                style: TextStyle(
                                                  color: _getStatusColor(
                                                      task.status),
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // View action
                                        IconButton(
                                          icon: const Icon(
                                            Icons.arrow_forward_ios,
                                            size: 16,
                                          ),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    PatrolHistoryScreen(
                                                  task: task,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),

                                    const Divider(height: 16),

                                    // Officer info section with shift and type
                                    Row(
                                      children: [
                                        // Officer avatar
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor: kbpBlue100,
                                          backgroundImage:
                                              assignedOfficer.photoUrl != null
                                                  ? NetworkImage(
                                                      assignedOfficer.photoUrl!)
                                                  : null,
                                          child:
                                              assignedOfficer.photoUrl == null
                                                  ? const Icon(Icons.person,
                                                      color: kbpBlue900,
                                                      size: 16)
                                                  : null,
                                        ),
                                        const SizedBox(width: 12),

                                        // Officer details with type and shift badges
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                assignedOfficer.name,
                                                style:
                                                    mediumTextStyle(size: 14),
                                              ),
                                              const SizedBox(height: 4),
                                              Wrap(
                                                spacing: 8,
                                                children: [
                                                  // Tipe badge
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: assignedOfficer
                                                                  .type ==
                                                              OfficerType
                                                                  .organik
                                                          ? successG50
                                                          : warningY50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      assignedOfficer
                                                          .typeDisplay,
                                                      style: mediumTextStyle(
                                                        size: 10,
                                                        color: assignedOfficer
                                                                    .type ==
                                                                OfficerType
                                                                    .organik
                                                            ? successG500
                                                            : warningY500,
                                                      ),
                                                    ),
                                                  ),

                                                  // Shift badge
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: kbpBlue50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      getShortShiftText(
                                                          assignedOfficer
                                                              .shift),
                                                      style: mediumTextStyle(
                                                          size: 10,
                                                          color: kbpBlue700),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Show task start time
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'Mulai:',
                                              style: regularTextStyle(
                                                  size: 12, color: neutral600),
                                            ),
                                            Text(
                                              formatDateFromString(
                                                  task.startTime.toString()),
                                              style: mediumTextStyle(size: 12),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Officer? _findOfficerByUserId(List<Officer> officers, String? userId) {
    if (userId == null || userId.isEmpty) {
      return null;
    }

    try {
      return officers.firstWhere(
        (officer) => officer.id == userId,
        orElse: () => Officer(
          id: userId,
          name: 'Petugas ${userId.substring(0, 4)}...',
          type: OfficerType.organik,
          shift: ShiftType.pagi,
          clusterId: '', // Atau nilai default lainnya
        ),
      );
    } catch (e) {
      print('Error finding officer by userId: $e');
      return null;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'selesai':
        return successG300;
      case 'active':
      case 'aktif':
        return kbpBlue700;
      case 'in progress':
      case 'berlangsung':
        return warningY300;
      case 'cancelled':
      case 'dibatalkan':
        return dangerR300;
      default:
        return neutral600;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'Selesai';
      case 'active':
        return 'Aktif';
      case 'in progress':
        return 'Berlangsung';
      case 'cancelled':
        return 'Dibatalkan';
      default:
        return status;
    }
  }
}
