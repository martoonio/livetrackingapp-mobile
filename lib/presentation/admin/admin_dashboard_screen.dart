import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/admin/patrol_history_screen.dart';
import 'package:livetrackingapp/presentation/cluster/cluster_detail_screen.dart';
import '../routing/bloc/patrol_bloc.dart';
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

  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String _sortBy = 'assignedStartTime';
  bool _isDescending = true;
  bool _showFilterPanel = false;

  bool _isMultiSelectMode = false;
  Set<String> _selectedTaskIds = <String>{};

  // PERBAIKAN: Simplify pagination variables - HAPUS statistik

  Map<String, int> _clusterTaskPages = {};
  Map<String, bool> _clusterTaskLoading = {};
  Map<String, List<PatrolTask>> _clusterTasksData = {};
  Map<String, bool> _clusterHasMoreTasks = {};
  Map<String, String?> _clusterLastKeys = {};
  final int _tasksPerPage = 20;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  void _initializeData() {
    print('AdminDashboard: Initializing...');
    context.read<AdminBloc>().add(const LoadAllTasks());
  }

  // PERBAIKAN: Enhanced loadData TANPA cluster summary loading
  void _loadData() {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    // Clear semua data pagination - HAPUS summary counts
    _clusterTasksData.clear();
    _clusterTaskPages.clear();
    _clusterHasMoreTasks.clear();
    _clusterLastKeys.clear();
    _clusterTaskLoading.clear();
    // _clusterTaskCounts.clear(); // DIHAPUS

    // Trigger reload via bloc
    context.read<AdminBloc>().add(const LoadAllTasks());

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadClusterTasks(String clusterId,
      {bool loadMore = false}) async {
    if (_clusterTaskLoading[clusterId] == true) return;

    setState(() {
      _clusterTaskLoading[clusterId] = true;
    });

    try {
      final currentPage = _clusterTaskPages[clusterId] ?? 0;
      final newPage = loadMore ? currentPage + 1 : 0;
      final lastKey = loadMore ? _clusterLastKeys[clusterId] : null;

      print(
          'Loading cluster tasks for $clusterId, page: $newPage, loadMore: $loadMore');

      // PERBAIKAN: Single query dengan pagination yang proper
      final tasks = await context.read<PatrolBloc>().repository.getClusterTasks(
            clusterId,
            limit: _tasksPerPage,
            lastKey: lastKey,
          );

      // PERBAIKAN: Filter active dan cancelled di client side
      final filteredTasks = tasks.where((task) {
        return task.status.toLowerCase() == 'active' ||
            task.status.toLowerCase() == 'cancelled';
      }).toList();

      print(
          'Loaded ${tasks.length} tasks, filtered to ${filteredTasks.length} for cluster $clusterId');

      if (mounted) {
        setState(() {
          if (loadMore) {
            final currentTasks = _clusterTasksData[clusterId] ?? [];
            _clusterTasksData[clusterId] = [...currentTasks, ...filteredTasks];
          } else {
            _clusterTasksData[clusterId] = filteredTasks;
          }

          _clusterTaskPages[clusterId] = newPage;
          _clusterHasMoreTasks[clusterId] = tasks.length >= _tasksPerPage;

          if (tasks.isNotEmpty) {
            _clusterLastKeys[clusterId] = tasks.last.taskId;
          }

          _clusterTaskLoading[clusterId] = false;
        });
      }

      print(
          'Updated state for cluster $clusterId: hasMore=${_clusterHasMoreTasks[clusterId]}, totalLoaded=${_clusterTasksData[clusterId]?.length ?? 0}');
    } catch (e) {
      print('Error loading cluster tasks for $clusterId: $e');
      if (mounted) {
        setState(() {
          _clusterTaskLoading[clusterId] = false;
        });
      }
    }
  }

  List<PatrolTask> _filterAndSortTasks(List<PatrolTask> tasks) {
    List<PatrolTask> filteredTasks = List.from(tasks);

    // PERBAIKAN: Filter hanya task active dan cancelled
    filteredTasks = filteredTasks.where((task) {
      return task.status.toLowerCase() == 'active' ||
          task.status.toLowerCase() == 'cancelled';
    }).toList();

    // Filter berdasarkan tanggal
    if (_filterStartDate != null || _filterEndDate != null) {
      filteredTasks = filteredTasks.where((task) {
        if (task.assignedStartTime == null) return false;

        final taskDate = DateTime(
          task.assignedStartTime!.year,
          task.assignedStartTime!.month,
          task.assignedStartTime!.day,
        );

        bool matchesStartDate = _filterStartDate == null ||
            taskDate
                .isAfter(_filterStartDate!.subtract(const Duration(days: 1)));
        bool matchesEndDate = _filterEndDate == null ||
            taskDate.isBefore(_filterEndDate!.add(const Duration(days: 1)));

        return matchesStartDate && matchesEndDate;
      }).toList();
    }

    // Sort berdasarkan pilihan
    filteredTasks.sort((a, b) {
      DateTime? aDate;
      DateTime? bDate;

      if (_sortBy == 'assignedStartTime') {
        aDate = a.assignedStartTime;
        bDate = b.assignedStartTime;
      } else {
        aDate = a.createdAt;
        bDate = b.createdAt;
      }

      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return _isDescending ? 1 : -1;
      if (bDate == null) return _isDescending ? -1 : 1;

      int comparison = aDate.compareTo(bDate);
      return _isDescending ? -comparison : comparison;
    });

    return filteredTasks;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          _isMultiSelectMode
              ? '${_selectedTaskIds.length} tugas dipilih'
              : 'Command Center Dashboard',
          style: boldTextStyle(color: neutralWhite, size: 20),
        ),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        leading: _isMultiSelectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitMultiSelectMode,
              )
            : null,
        actions: _isMultiSelectMode
            ? _buildMultiSelectActions()
            : _buildNormalActions(),
      ),
      body: Column(
        children: [
          if (_isMultiSelectMode)
            Container(
              height: 60,
              child: _buildMultiSelectInfoBar(),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: _showFilterPanel ? 300 : 0,
            child: _showFilterPanel
                ? SingleChildScrollView(
                    child: _buildFilterPanel(),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: BlocConsumer<AdminBloc, AdminState>(
              listener: (context, state) {
                if (state is AdminError) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${state.message}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              builder: (context, state) {
                if (state is AdminLoading) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 200,
                          height: 100,
                          child: Lottie.asset(
                            'assets/lottie/maps_loading.json',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Memuat data dashboard...',
                          style: mediumTextStyle(color: neutral600),
                        ),
                      ],
                    ),
                  );
                }

                if (state is AdminError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'Error: ${state.message}',
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
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
                  return RefreshIndicator(
                    onRefresh: () async {
                      _loadData();
                    },
                    child: _buildContent(state),
                  );
                }

                if (state is ClustersLoaded) {
                  return RefreshIndicator(
                    onRefresh: () async {
                      _loadData();
                    },
                    child: _buildClustersOnlyContent(state),
                  );
                }

                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 200,
                        height: 100,
                        child: Lottie.asset(
                          'assets/lottie/maps_loading.json',
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Menginisialisasi dashboard...',
                        style: mediumTextStyle(color: neutral600),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _isMultiSelectMode
          ? null
          : FloatingActionButton(
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

  Widget _buildContent(AdminLoaded state) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _buildClusterList(state),
        ),
      ],
    );
  }

  Widget _buildClustersOnlyContent(ClustersLoaded state) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // HAPUS: _buildBasicStatisticsCard(state) - DIHAPUS
        if (state.clusters.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(),
          )
        else
          SliverToBoxAdapter(
            child: _buildClusterListOnly(state.clusters),
          ),
      ],
    );
  }

  List<Widget> _buildNormalActions() {
    return [
      IconButton(
        icon: Stack(
          children: [
            const Icon(Icons.filter_list),
            if (_filterStartDate != null || _filterEndDate != null)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: warningY300,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        onPressed: () {
          setState(() {
            _showFilterPanel = !_showFilterPanel;
          });
        },
      ),
      IconButton(
        icon: const Icon(Icons.refresh),
        onPressed: _loadData,
      ),
    ];
  }

  List<Widget> _buildMultiSelectActions() {
    return [
      if (_selectedTaskIds.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          onPressed: _showBulkCancelDialog,
          tooltip: 'Batalkan Terpilih',
        ),
    ];
  }

  Widget _buildMultiSelectInfoBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: kbpBlue50,
        border: Border(
          bottom: BorderSide(color: kbpBlue200, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: kbpBlue600, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedTaskIds.isEmpty
                  ? 'Pilih tugas yang ingin dibatalkan'
                  : '${_selectedTaskIds.length} tugas dipilih untuk dibatalkan',
              style: mediumTextStyle(size: 14, color: kbpBlue700),
            ),
          ),
          if (_selectedTaskIds.isNotEmpty)
            TextButton(
              onPressed: _clearSelection,
              child: Text(
                'Bersihkan',
                style: mediumTextStyle(size: 14, color: kbpBlue600),
              ),
            ),
        ],
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

  Widget _buildClusterListOnly(List<User> clusters) {
    if (clusters.isEmpty) {
      return SizedBox(
        height: 300, // Fixed height for empty state
        child: _buildEmptyState(),
      );
    }

    return ListView.builder(
      shrinkWrap: true, // PERBAIKAN: Add shrinkWrap
      physics:
          const NeverScrollableScrollPhysics(), // PERBAIKAN: Disable physics
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

    if (clusters.isEmpty) {
      return SizedBox(
        height: 300,
        child: _buildEmptyState(),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: clusters.length,
      itemBuilder: (context, index) {
        final cluster = clusters[index];

        // Data untuk filter (dari AdminBloc state)
        final clusterAllTasks = state.activeTasks
            .where((task) => task.clusterId == cluster.id)
            .toList();

        final clusterActiveCancelledTasks = clusterAllTasks.where((task) {
          return task.status.toLowerCase() == 'active' ||
              task.status.toLowerCase() == 'cancelled';
        }).toList();

        final filteredTasks = _filterAndSortTasks(clusterActiveCancelledTasks);

        return _buildEnhancedClusterCard(
          cluster: cluster,
          index: index,
          summaryActiveTasks: filteredTasks,
          totalActiveTasks: clusterActiveCancelledTasks.length,
        );
      },
    );
  }

  void _resetFilters() {
    setState(() {
      _filterStartDate = null;
      _filterEndDate = null;
      _sortBy = 'assignedStartTime';
      _isDescending = true;
    });
  }

  Widget _buildEnhancedClusterCard({
    required User cluster,
    required int index,
    required List<PatrolTask> summaryActiveTasks,
    int? totalActiveTasks,
  }) {
    final isExpanded = _expandedClusterIndex == index;
    final officers = cluster.officers ?? [];
    final isFiltered = _filterStartDate != null ||
        _filterEndDate != null ||
        _sortBy != 'assignedStartTime' ||
        !_isDescending;

    final paginatedTasks = _clusterTasksData[cluster.id] ?? [];
    final isLoadingTasks = _clusterTaskLoading[cluster.id] ?? false;
    final hasMoreTasks = _clusterHasMoreTasks[cluster.id] ?? false;
    final currentPage = _clusterTaskPages[cluster.id] ?? 0;

    // HAPUS: Semua logika statistik summary
    // final clusterSummary = _clusterTaskCounts[cluster.id]; // DIHAPUS
    // final actualActiveTasks = clusterSummary?['active'] ?? 0; // DIHAPUS
    // final actualCancelledTasks = clusterSummary?['cancelled'] ?? 0; // DIHAPUS
    // final totalTasks = actualActiveTasks + actualCancelledTasks; // DIHAPUS

    // GANTI: Gunakan data dari loaded tasks saja
    final totalTasks = summaryActiveTasks.length;

    final organikOfficers =
        officers.where((o) => o.type == OfficerType.organik).length;
    final outsourceOfficers =
        officers.where((o) => o.type == OfficerType.outsource).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isExpanded ? 4 : 2,
      shadowColor: isExpanded
          ? kbpBlue900.withOpacity(0.2)
          : Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: kbpBlue300,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (_expandedClusterIndex == index) {
                  _expandedClusterIndex = null;
                } else {
                  _expandedClusterIndex = index;
                  // HAPUS: Load cluster summary
                  // if (clusterSummary == null) {
                  //   _loadClusterSummary(cluster.id);
                  // }
                  if (_clusterTasksData[cluster.id] == null ||
                      _clusterTasksData[cluster.id]!.isEmpty) {
                    _loadClusterTasks(cluster.id);
                  }
                }
              });
            },
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(16),
              bottom: isExpanded ? Radius.zero : const Radius.circular(16),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isExpanded
                      ? [kbpBlue50, kbpBlue100.withOpacity(0.3)]
                      : [Colors.white, neutralWhite],
                ),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(16),
                  bottom: isExpanded ? Radius.zero : const Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            // PERBAIKAN: Simple cluster icon tanpa statistik
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    kbpBlue600,
                                    kbpBlue700
                                  ], // Static gradient
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: kbpBlue600.withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.location_city, // Static icon
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    cluster.name,
                                    style: boldTextStyle(
                                        size: 16, color: neutral900),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${officers.length} petugas • ${totalTasks} tugas', // Simplified subtitle
                                    style: mediumTextStyle(
                                        size: 13, color: neutral600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: isExpanded ? kbpBlue100 : neutral200,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isExpanded ? kbpBlue300 : neutral300,
                              ),
                            ),
                            child: IconButton(
                              icon: AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.keyboard_arrow_down,
                                  color: isExpanded ? kbpBlue700 : neutral600,
                                ),
                              ),
                              onPressed: () {
                                setState(() {
                                  if (_expandedClusterIndex == index) {
                                    _expandedClusterIndex = null;
                                  } else {
                                    _expandedClusterIndex = index;
                                    if (_clusterTasksData[cluster.id] == null ||
                                        _clusterTasksData[cluster.id]!
                                            .isEmpty) {
                                      _loadClusterTasks(cluster.id);
                                    }
                                  }
                                });
                              },
                              tooltip: isExpanded ? 'Tutup' : 'Buka Detail',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // PERBAIKAN: Simplified statistics tanpa loading
                  _buildSimpleClusterStatsRow(
                    officers.length,
                    organikOfficers,
                    outsourceOfficers,
                    totalTasks,
                  ),

                  if (isFiltered && summaryActiveTasks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: warningY50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: warningY200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.filter_list, color: warningY300, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Filter aktif: Menampilkan ${summaryActiveTasks.length} tugas',
                              style:
                                  mediumTextStyle(size: 12, color: warningY500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),

                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: kbpBlue50.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: kbpBlue600,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isExpanded
                              ? 'Tutup untuk menyembunyikan detail'
                              : 'Ketuk untuk melihat detail tugas',
                          style: mediumTextStyle(size: 11, color: kbpBlue600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    kbpBlue200,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Container(
              color: neutral300,
              padding: const EdgeInsets.all(16),
              child: _buildOfficersSection(officers, cluster),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tugas Aktif & Dibatalkan',
                            style: semiBoldTextStyle(size: 16),
                          ),
                          // PERBAIKAN: Info sederhana tanpa statistik detail
                          if (paginatedTasks.isNotEmpty) ...[
                            Text(
                              'Menampilkan ${paginatedTasks.length} tugas ${hasMoreTasks ? '(halaman ${currentPage + 1})' : '(semua)'}',
                              style:
                                  regularTextStyle(size: 11, color: neutral500),
                            ),
                          ],
                          if (isLoadingTasks)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Memuat tugas...',
                                style: regularTextStyle(
                                    size: 12, color: kbpBlue600),
                              ),
                            ),
                        ],
                      ),
                      Column(
                        children: [
                          TextButton.icon(
                            onPressed: () => _loadClusterTasks(cluster.id),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Refresh'),
                            style: TextButton.styleFrom(
                              foregroundColor: kbpBlue900,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CreateTaskScreen(),
                                ),
                              ).then((_) => _loadData());
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Tambah'),
                            style: TextButton.styleFrom(
                              foregroundColor: kbpBlue900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // HAPUS: Summary info box dengan statistik detail

                  if (isLoadingTasks && paginatedTasks.isEmpty)
                    Container(
                      height: 100,
                      child: const Center(
                        child: CircularProgressIndicator(color: kbpBlue900),
                      ),
                    )
                  else if (paginatedTasks.isEmpty)
                    _buildEmptyTasksState(
                        isFiltered: false, statusFilter: 'aktif dan dibatalkan')
                  else
                    Column(
                      children: [
                        ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: paginatedTasks.length,
                          itemBuilder: (context, taskIndex) {
                            final task = paginatedTasks[taskIndex];
                            final assignedOfficer =
                                _findOfficerByUserId(officers, task.userId) ??
                                    Officer(
                                      id: task.userId ?? '',
                                      name: task.officerName.isNotEmpty
                                          ? task.officerName
                                          : task.userId != null
                                              ? 'Petugas ${task.userId!.substring(0, 4)}...'
                                              : 'Tidak diketahui',
                                      type: OfficerType.organik,
                                      shift: ShiftType.pagi,
                                      clusterId: cluster.id,
                                    );

                            return _buildEnhancedTaskCard(
                                task, assignedOfficer);
                          },
                        ),
                        if (hasMoreTasks || isLoadingTasks)
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              children: [
                                Container(
                                  height: 1,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        kbpBlue200,
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                                if (isLoadingTasks)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          color: kbpBlue900,
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Memuat lebih banyak tugas...',
                                        style: mediumTextStyle(
                                            size: 12, color: kbpBlue600),
                                      ),
                                    ],
                                  )
                                else if (hasMoreTasks)
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _loadClusterTasks(
                                          cluster.id,
                                          loadMore: true),
                                      icon: const Icon(Icons.expand_more,
                                          size: 18),
                                      label: Text(
                                          'Lihat ${_tasksPerPage} Tugas Lagi'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: kbpBlue900,
                                        side: BorderSide(
                                            color: kbpBlue300, width: 1.5),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 12),
                                      ),
                                    ),
                                  ),
                                if (hasMoreTasks)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      'Halaman ${currentPage + 1} • ${paginatedTasks.length} tugas dimuat',
                                      style: regularTextStyle(
                                          size: 11, color: neutral500),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (!hasMoreTasks &&
                            paginatedTasks.isNotEmpty &&
                            !isLoadingTasks)
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              children: [
                                Container(
                                  height: 1,
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        neutral300,
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle_outline,
                                        color: successG500, size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Menampilkan semua ${paginatedTasks.length} tugas',
                                      style: mediumTextStyle(
                                          size: 12, color: successG300),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSimpleClusterStatsRow(
    int totalOfficers,
    int organikOfficers,
    int outsourceOfficers,
    int totalTasks,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Petugas',
            totalOfficers.toString(),
            '${organikOfficers}O • ${outsourceOfficers}S',
            Icons.people,
            kbpBlue600,
          ),
        ),
      ],
    );
  }

  List<Color> _getClusterGradientColors(int activeTasks, int cancelledTasks) {
    if (activeTasks > 0 && cancelledTasks == 0) {
      // All active - green gradient
      return [successG500, successG300];
    } else if (activeTasks == 0 && cancelledTasks > 0) {
      // All cancelled - red gradient
      return [dangerR500, dangerR300];
    } else if (activeTasks > 0 && cancelledTasks > 0) {
      // Mixed - blue gradient
      return [kbpBlue600, kbpBlue700];
    } else {
      // No tasks - neutral gradient
      return [neutral500, neutral600];
    }
  }

  Widget _buildStatCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(
                title,
                style: mediumTextStyle(size: 11, color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: boldTextStyle(size: 18, color: color),
          ),
          Text(
            subtitle,
            style: mediumTextStyle(size: 9, color: color.withOpacity(0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // TAMBAHAN: Widget untuk menampilkan status count

  Widget _buildFilterPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // PERBAIKAN: Add mainAxisSize
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.filter_list, color: kbpBlue900, size: 20),
              const SizedBox(width: 8),
              Text(
                'Filter & Urutkan Tugas',
                style: boldTextStyle(size: 16, color: kbpBlue900),
              ),
              const Spacer(),
              if (_filterStartDate != null ||
                  _filterEndDate != null ||
                  _sortBy != 'assignedStartTime' ||
                  !_isDescending)
                TextButton(
                  onPressed: _resetFilters,
                  child: Text(
                    'Reset',
                    style: mediumTextStyle(size: 14, color: dangerR500),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Date Range Filter
          Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min, // PERBAIKAN: Add mainAxisSize
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tanggal Mulai',
                      style: mediumTextStyle(size: 14, color: neutral700),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => _selectStartDate(context),
                      child: Container(
                        height: 40, // PERBAIKAN: Fixed height
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: neutral300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 16, color: neutral600),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _filterStartDate != null
                                    ? formatDateFromString(
                                        _filterStartDate.toString())
                                    : 'Pilih tanggal',
                                style: regularTextStyle(
                                  size: 14,
                                  color: _filterStartDate != null
                                      ? neutral800
                                      : neutral500,
                                ),
                              ),
                            ),
                            if (_filterStartDate != null)
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _filterStartDate = null),
                                child: Icon(Icons.clear,
                                    size: 16, color: neutral500),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min, // PERBAIKAN: Add mainAxisSize
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tanggal Akhir',
                      style: mediumTextStyle(size: 14, color: neutral700),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => _selectEndDate(context),
                      child: Container(
                        height: 40, // PERBAIKAN: Fixed height
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: neutral300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 16, color: neutral600),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _filterEndDate != null
                                    ? formatDateFromString(
                                        _filterEndDate.toString())
                                    : 'Pilih tanggal',
                                style: regularTextStyle(
                                  size: 14,
                                  color: _filterEndDate != null
                                      ? neutral800
                                      : neutral500,
                                ),
                              ),
                            ),
                            if (_filterEndDate != null)
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _filterEndDate = null),
                                child: Icon(Icons.clear,
                                    size: 16, color: neutral500),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Sort Options
          Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min, // PERBAIKAN: Add mainAxisSize
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Urutkan Berdasarkan',
                      style: mediumTextStyle(size: 14, color: neutral700),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 40, // PERBAIKAN: Fixed height
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: neutral300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _sortBy,
                          isExpanded: true,
                          icon: Icon(Icons.keyboard_arrow_down,
                              color: neutral600),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _sortBy = newValue;
                              });
                            }
                          },
                          items: [
                            DropdownMenuItem(
                              value: 'assignedStartTime',
                              child: Row(
                                children: [
                                  Icon(Icons.schedule,
                                      size: 16, color: kbpBlue600),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Waktu Mulai',
                                    style: regularTextStyle(size: 14),
                                  ),
                                ],
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'createdAt',
                              child: Row(
                                children: [
                                  Icon(Icons.add_circle,
                                      size: 16, color: successG300),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Waktu Dibuat',
                                    style: regularTextStyle(size: 14),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min, // PERBAIKAN: Add mainAxisSize
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Urutan',
                    style: mediumTextStyle(size: 14, color: neutral700),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildSortButton(
                        'Terlama',
                        Icons.arrow_downward,
                        _isDescending,
                        () => setState(() => _isDescending = true),
                      ),
                      const SizedBox(width: 8),
                      _buildSortButton(
                        'Terbaru',
                        Icons.arrow_upward,
                        !_isDescending,
                        () => setState(() => _isDescending = false),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Filter Summary
          if (_filterStartDate != null ||
              _filterEndDate != null ||
              _sortBy != 'assignedStartTime' ||
              !_isDescending)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kbpBlue50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kbpBlue200),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min, // PERBAIKAN: Add mainAxisSize
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filter Aktif:',
                    style: semiBoldTextStyle(size: 12, color: kbpBlue800),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (_filterStartDate != null || _filterEndDate != null)
                        _buildFilterChip(
                          'Tanggal: ${_getDateRangeText()}',
                          Icons.date_range,
                        ),
                      _buildFilterChip(
                        'Urut: ${_getSortText()}',
                        _isDescending
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // TAMBAHAN: Sort Button Widget
  Widget _buildSortButton(
      String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kbpBlue900 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? kbpBlue900 : neutral300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : neutral600,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: mediumTextStyle(
                size: 12,
                color: isSelected ? Colors.white : neutral600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // TAMBAHAN: Filter Chip Widget
  Widget _buildFilterChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kbpBlue100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: kbpBlue700),
          const SizedBox(width: 4),
          Text(
            label,
            style: mediumTextStyle(size: 11, color: kbpBlue700),
          ),
        ],
      ),
    );
  }

  // TAMBAHAN: Date Picker Methods
  Future<void> _selectStartDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _filterStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: kbpBlue900,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _filterStartDate = picked;
        // Ensure end date is not before start date
        if (_filterEndDate != null && _filterEndDate!.isBefore(picked)) {
          _filterEndDate = picked;
        }
      });
    }
  }

  Future<void> _selectEndDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _filterEndDate ??
          (_filterStartDate?.add(const Duration(days: 7)) ?? DateTime.now()),
      firstDate: _filterStartDate ?? DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: kbpBlue900,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _filterEndDate = picked;
      });
    }
  }

  String _getDateRangeText() {
    if (_filterStartDate != null && _filterEndDate != null) {
      return '${formatDateFromString(_filterStartDate.toString())} - ${formatDateFromString(_filterEndDate.toString())}';
    } else if (_filterStartDate != null) {
      return 'Dari ${formatDateFromString(_filterStartDate.toString())}';
    } else if (_filterEndDate != null) {
      return 'Sampai ${formatDateFromString(_filterEndDate.toString())}';
    }
    return '';
  }

  String _getSortText() {
    String sortByText =
        _sortBy == 'assignedStartTime' ? 'Waktu Mulai' : 'Waktu Dibuat';
    String orderText = _isDescending ? 'Terbaru' : 'Terlama';
    return '$sortByText ($orderText)';
  }

  Widget _buildClusterCard({
    required User cluster,
    required int index,
    required List<PatrolTask> activeTasks,
    int? totalActiveTasks, // TAMBAHAN: parameter opsional
  }) {
    final isExpanded = _expandedClusterIndex == index;
    final officers = cluster.officers ?? [];
    final isFiltered = _filterStartDate != null ||
        _filterEndDate != null ||
        _sortBy != 'assignedStartTime' ||
        !_isDescending;

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
                        // MODIFIKASI: Tampilkan informasi filter jika ada
                        if (isFiltered && totalActiveTasks != null)
                          Row(
                            children: [
                              Text(
                                'Petugas: ${officers.length} · Tugas: ${activeTasks.length}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: neutral600,
                                ),
                              ),
                              if (activeTasks.length != totalActiveTasks) ...[
                                Text(
                                  ' dari $totalActiveTasks',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: neutral500,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.filter_list,
                                  size: 14,
                                  color: kbpBlue600,
                                ),
                              ],
                            ],
                          )
                        else
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
                                initialTab: 0,
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
              child: _buildOfficersSection(officers, cluster),
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tugas Aktif (${activeTasks.length})',
                            style: semiBoldTextStyle(size: 16),
                          ),
                          // TAMBAHAN: Filter indicator
                          if (isFiltered &&
                              totalActiveTasks != null &&
                              activeTasks.length != totalActiveTasks)
                            Text(
                              'Menampilkan ${activeTasks.length} dari $totalActiveTasks tugas',
                              style:
                                  regularTextStyle(size: 12, color: kbpBlue600),
                            ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CreateTaskScreen(),
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
                      ? _buildEmptyTasksState(isFiltered: isFiltered)
                      : ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: activeTasks.length,
                          itemBuilder: (context, taskIndex) {
                            final task = activeTasks[taskIndex];
                            final assignedOfficer =
                                _findOfficerByUserId(officers, task.userId) ??
                                    Officer(
                                      id: task.userId ?? '',
                                      name: task.userId != null
                                          ? 'Petugas ${task.userId!.substring(0, 4)}...'
                                          : 'Tidak diketahui',
                                      type: OfficerType.organik,
                                      shift: ShiftType.pagi,
                                      clusterId: cluster.id,
                                    );

                            return _buildEnhancedTaskCard(
                                task, assignedOfficer);
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

  Widget _buildEnhancedTaskCard(PatrolTask task, Officer assignedOfficer) {
    final isSelected = _selectedTaskIds.contains(task.taskId);
    final canCancel = _canCancelTask(task);

    return GestureDetector(
      onLongPress: () {
        if (canCancel && !_isMultiSelectMode) {
          _enterMultiSelectMode(task.taskId);
        }
      },
      onTap: () {
        if (_isMultiSelectMode && canCancel) {
          _toggleTaskSelection(task.taskId);
        }
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 1,
        color: isSelected ? kbpBlue50 : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? kbpBlue300 : neutral200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // Header dengan status dan ID
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  // TAMBAHAN: Checkbox untuk multi-select
                  if (_isMultiSelectMode && canCancel) ...[
                    Checkbox(
                      value: isSelected,
                      onChanged: (bool? value) {
                        _toggleTaskSelection(task.taskId);
                      },
                      activeColor: kbpBlue900,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else if (_isMultiSelectMode && !canCancel) ...[
                    // Placeholder untuk alignment
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: neutral300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.block,
                        color: neutral400,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Status indicator dengan animasi
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _getStatusColor(task.status),
                          _getStatusColor(task.status).withOpacity(0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: _getStatusColor(task.status).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.task_alt_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Task info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Tugas #${_getSafeTaskIdPreview(task.taskId)}',
                              style: boldTextStyle(size: 12),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(task.status)
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _getStatusColor(task.status)
                                      .withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                _getStatusText(task.status),
                                style: TextStyle(
                                  color: _getStatusColor(task.status),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          assignedOfficer.name,
                          style: mediumTextStyle(size: 14, color: neutral600),
                        ),
                      ],
                    ),
                  ),

                  // Menu aksi (hanya tampil jika tidak dalam multi-select mode)
                  if (!_isMultiSelectMode)
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        size: 20,
                        color: neutral600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 8,
                      position: PopupMenuPosition.under,
                      tooltip: 'Opsi Tugas',
                      color: Colors.white,
                      onSelected: (value) {
                        if (value == 'view') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PatrolHistoryScreen(task: task),
                            ),
                          );
                        } else if (value == 'cancel') {
                          _showCancelConfirmationDialog(context, task,
                              User(id: '', email: '', name: '', role: ''));
                        } else if (value == 'multi_select') {
                          _enterMultiSelectMode(task.taskId);
                        }
                      },
                      itemBuilder: (BuildContext context) => [
                        PopupMenuItem<String>(
                          value: 'view',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.visibility_outlined,
                                color: kbpBlue600,
                                size: 18,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Lihat Detail',
                                style: mediumTextStyle(color: neutral800),
                              ),
                            ],
                          ),
                        ),
                        if (canCancel) ...[
                          PopupMenuItem<String>(
                            value: 'multi_select',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.checklist,
                                  color: kbpBlue600,
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Pilih Multiple',
                                  style: mediumTextStyle(color: neutral800),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'cancel',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.cancel_outlined,
                                  color: dangerR500,
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Batalkan Tugas',
                                  style: mediumTextStyle(color: dangerR500),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
            8.height,
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Type badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: assignedOfficer.type == OfficerType.organik
                                  ? successG50
                                  : warningY50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              assignedOfficer.type == OfficerType.organik
                                  ? 'Organik'
                                  : 'Outsource',
                              style: mediumTextStyle(
                                size: 10,
                                color:
                                    assignedOfficer.type == OfficerType.organik
                                        ? successG300
                                        : warningY300,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),

                          // Shift badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: kbpBlue50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              getShortShiftText(assignedOfficer.shift),
                              style: mediumTextStyle(
                                size: 10,
                                color: kbpBlue600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Task timing status
                _buildTimingStatus(task),
              ],
            ).paddingSymmetric(horizontal: 16),
            8.height,
            // NEW: Assigned Time Section
            if (task.assignedStartTime != null) _buildAssignedTimeSection(task),
            16.height,
          ],
        ),
      ),
    );
  }

  void _enterMultiSelectMode(String initialTaskId) {
    setState(() {
      _isMultiSelectMode = true;
      _selectedTaskIds.clear();
      _selectedTaskIds.add(initialTaskId);
    });
  }

  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedTaskIds.clear();
    });
  }

  void _toggleTaskSelection(String taskId) {
    setState(() {
      if (_selectedTaskIds.contains(taskId)) {
        _selectedTaskIds.remove(taskId);
      } else {
        _selectedTaskIds.add(taskId);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedTaskIds.clear();
    });
  }

  void _selectAllVisibleTasks() {
    setState(() {
      // Get all visible cancellable tasks from current state
      final currentState = context.read<AdminBloc>().state;
      if (currentState is AdminLoaded) {
        for (final cluster in currentState.clusters) {
          final clusterTasks = currentState.activeTasks
              .where((task) => task.clusterId == cluster.id)
              .toList();

          final filteredTasks = _filterAndSortTasks(clusterTasks);

          for (final task in filteredTasks) {
            if (_canCancelTask(task)) {
              _selectedTaskIds.add(task.taskId);
            }
          }
        }
      }
    });
  }

  // TAMBAHAN: Bulk cancel dialog
  void _showBulkCancelDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10.0,
                offset: Offset(0.0, 10.0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon warning
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: dangerR50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_sweep,
                  size: 40,
                  color: dangerR500,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'Batalkan Multiple Tugas',
                style: boldTextStyle(size: 18),
              ),
              const SizedBox(height: 8),

              // Message
              Text(
                'Apakah Anda yakin ingin membatalkan ${_selectedTaskIds.length} tugas yang dipilih? Tindakan ini tidak dapat dipulihkan.',
                textAlign: TextAlign.center,
                style: regularTextStyle(color: neutral700),
              ),
              const SizedBox(height: 16),

              // Selected tasks preview
              Container(
                height: 200,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(
                        'Tugas yang akan dibatalkan:',
                        style: mediumTextStyle(size: 12, color: neutral600),
                      ),
                      const SizedBox(height: 8),
                      ...(_selectedTaskIds.take(5).map((taskId) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: dangerR50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: dangerR200),
                            ),
                            child: Text(
                              'Tugas #${_getSafeTaskIdPreview(taskId)}',
                              style:
                                  mediumTextStyle(size: 11, color: dangerR300),
                            ),
                          ))),
                      if (_selectedTaskIds.length > 5)
                        Text(
                          '... dan ${_selectedTaskIds.length - 5} tugas lainnya',
                          style: regularTextStyle(size: 11, color: neutral500),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: neutral700,
                        side: const BorderSide(color: neutral400),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _performBulkCancel();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: dangerR500,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text('Batalkan ${_selectedTaskIds.length} Tugas'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // TAMBAHAN: Bulk cancel implementation
  Future<void> _performBulkCancel() async {
    final selectedTasks = List<String>.from(_selectedTaskIds);
    int successCount = 0;
    int failCount = 0;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Progress indicator
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    value: (successCount + failCount) / selectedTasks.length,
                    color: kbpBlue900,
                    backgroundColor: kbpBlue100,
                    strokeWidth: 4,
                  ),
                ),
                const SizedBox(height: 24),

                // Text
                Text(
                  'Membatalkan tugas...',
                  style: mediumTextStyle(size: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '${successCount + failCount} dari ${selectedTasks.length} tugas',
                  style: regularTextStyle(color: neutral600, size: 14),
                  textAlign: TextAlign.center,
                ),
                if (failCount > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '$failCount tugas gagal dibatalkan',
                    style: regularTextStyle(color: dangerR500, size: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    // Process cancellations
    for (final taskId in selectedTasks) {
      try {
        await context.read<PatrolBloc>().repository.updateTask(
          taskId,
          {
            'status': 'cancelled',
            'cancelledAt': DateTime.now().toIso8601String(),
          },
        );
        successCount++;
      } catch (e) {
        print('Error cancelling task $taskId: $e');
        failCount++;
      }

      // Update progress dialog
      // Note: In a real implementation, you might want to use a more sophisticated state management
    }

    // Close progress dialog
    if (context.mounted) Navigator.of(context).pop();

    // Exit multi-select mode
    _exitMultiSelectMode();

    // Refresh data
    _loadData();

    // Show result feedback
    if (context.mounted) {
      if (successCount == selectedTasks.length) {
        showCustomSnackbar(
          context: context,
          title: 'Berhasil',
          subtitle: '$successCount tugas berhasil dibatalkan',
          type: SnackbarType.success,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pembatalan selesai',
                  style: boldTextStyle(color: Colors.white, size: 14),
                ),
                Text(
                  'Berhasil: $successCount, Gagal: $failCount',
                  style: regularTextStyle(color: Colors.white, size: 12),
                ),
              ],
            ),
            backgroundColor: failCount == 0 ? successG500 : warningY500,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            margin: const EdgeInsets.all(8),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // NEW: Assigned time section dengan visual timeline
  Widget _buildAssignedTimeSection(PatrolTask task) {
    final now = DateTime.now();
    final assignedStart = task.assignedStartTime!;
    final assignedEnd = task.assignedEndTime;
    final actualStart = task.startTime;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kbpBlue50,
            kbpBlue50.withOpacity(0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kbpBlue200.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: kbpBlue100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  color: kbpBlue700,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Jadwal Patroli',
                style: semiBoldTextStyle(size: 14, color: kbpBlue800),
              ),
              const Spacer(),
              _buildTaskStatusBadge(task, now),
            ],
          ),

          const SizedBox(height: 12),

          // Timeline
          Row(
            children: [
              Expanded(
                child: _buildTimelineItem(
                  time: formatTimeFromString(assignedStart.toString()),
                  label: 'Mulai',
                  date: formatDateFromString(assignedStart.toString()),
                  isActive: actualStart != null,
                  isPassed: now.isAfter(assignedStart),
                  color: actualStart != null
                      ? successG500
                      : now.isAfter(assignedStart)
                          ? dangerR500
                          : kbpBlue600,
                ),
              ),

              // Connector
              Container(
                height: 2,
                width: 30,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kbpBlue300, kbpBlue500],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),

              Expanded(
                child: _buildTimelineItem(
                  time: assignedEnd != null
                      ? formatTimeFromString(assignedEnd.toString())
                      : "--/--",
                  label: 'Selesai',
                  date: assignedEnd != null
                      ? formatDateFromString(assignedEnd.toString())
                      : '--/--',
                  isActive: task.endTime != null,
                  isPassed:
                      assignedEnd != null ? now.isAfter(assignedEnd) : false,
                  color: task.endTime != null
                      ? successG500
                      : (assignedEnd != null && now.isAfter(assignedEnd))
                          ? dangerR500
                          : neutral500,
                ),
              ),
            ],
          ),

          // Progress indicator jika task sedang berjalan
          if (actualStart != null && task.endTime == null) ...[
            const SizedBox(height: 8),
            _buildProgressIndicator(
                assignedStart, assignedEnd, actualStart, now),
          ],
        ],
      ),
    );
  }

  // NEW: Timeline item untuk assigned times
  Widget _buildTimelineItem({
    required String time,
    required String label,
    required String date,
    required bool isActive,
    required bool isPassed,
    required Color color,
  }) {
    return Column(
      children: [
        // Dot indicator
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: isActive
                ? color
                : (isPassed ? color.withOpacity(0.3) : kbpBlue800),
            shape: BoxShape.circle,
            border: Border.all(
              color: color,
              width: isActive ? 2 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 4),

        // Time
        Text(
          time,
          style: boldTextStyle(
            size: 14,
            color: isActive
                ? color
                : (isPassed ? color.withOpacity(0.7) : kbpBlue800),
          ),
        ),

        // Label
        Text(
          label,
          style: mediumTextStyle(
            size: 11,
            color: isActive ? color.withOpacity(0.8) : kbpBlue800,
          ),
        ),

        // Date
        Text(
          date,
          style: regularTextStyle(
            size: 10,
            color: kbpBlue500,
          ),
        ),
      ],
    );
  }

  // NEW: Task status badge
  Widget _buildTaskStatusBadge(PatrolTask task, DateTime now) {
    String status;
    Color color;
    IconData icon;

    if (task.startTime != null && task.endTime != null) {
      status = 'Selesai';
      color = successG500;
      icon = Icons.check_circle;
    } else if (task.startTime != null) {
      status = 'Berlangsung';
      color = warningY500;
      icon = Icons.play_circle;
    } else if (task.assignedStartTime != null &&
        now.isAfter(task.assignedStartTime!)) {
      status = 'Terlambat';
      color = dangerR500;
      icon = Icons.schedule_outlined;
    } else {
      status = 'Menunggu';
      color = kbpBlue500;
      icon = Icons.pending_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            status,
            style: mediumTextStyle(size: 10, color: color),
          ),
        ],
      ),
    );
  }

  // NEW: Progress indicator untuk task yang sedang berjalan
  Widget _buildProgressIndicator(DateTime assignedStart, DateTime? assignedEnd,
      DateTime actualStart, DateTime now) {
    if (assignedEnd == null) return const SizedBox.shrink();

    final totalDuration = assignedEnd.difference(assignedStart).inMinutes;
    final elapsedDuration = now.difference(actualStart).inMinutes;
    final progress = (elapsedDuration / totalDuration).clamp(0.0, 1.0);

    return Column(
      children: [
        const Divider(height: 1, color: kbpBlue200),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.timer_outlined, color: kbpBlue600, size: 14),
            const SizedBox(width: 6),
            Text(
              'Progress: ${(progress * 100).toInt()}%',
              style: mediumTextStyle(size: 12, color: kbpBlue700),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: kbpBlue100,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress > 1.0 ? dangerR500 : kbpBlue600,
                ),
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // NEW: Timing status indicator
  Widget _buildTimingStatus(PatrolTask task) {
    final now = DateTime.now();
    final assignedStart = task.assignedStartTime;

    if (assignedStart == null) {
      return const SizedBox.shrink();
    }

    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (task.startTime != null) {
      final difference = task.startTime!.difference(assignedStart);
      if (difference.inMinutes > 5) {
        final hours = difference.inHours;
        final minutes = difference.inMinutes % 60;
        statusText = hours > 0 ? '+${hours}j ${minutes}m' : '+${minutes}m';
        statusColor = dangerR500;
        statusIcon = Icons.schedule_outlined;
      } else if (difference.inMinutes < -5) {
        final hours = difference.inHours.abs();
        final minutes = (difference.inMinutes % 60).abs();
        statusText = hours > 0 ? '-${hours}j ${minutes}m' : '-${minutes}m';
        statusColor = kbpBlue500;
        statusIcon = Icons.fast_forward;
      } else {
        statusText = 'On Time';
        statusColor = successG500;
        statusIcon = Icons.check_circle_outline;
      }
    } else if (now.isAfter(assignedStart.add(const Duration(minutes: 5)))) {
      final difference = now.difference(assignedStart);
      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;
      statusText =
          hours > 0 ? 'Late ${hours}j ${minutes}m' : 'Late ${minutes}m';
      statusColor = dangerR500;
      statusIcon = Icons.warning_outlined;
    } else {
      final difference = assignedStart.difference(now);
      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;
      statusText = hours > 0 ? '${hours}j ${minutes}m' : '${minutes}m';
      statusColor = kbpBlue500;
      statusIcon = Icons.access_time;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: statusColor.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, color: statusColor, size: 10),
              const SizedBox(width: 2),
              Text(
                statusText,
                style: mediumTextStyle(size: 9, color: statusColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyTasksState(
      {bool isFiltered = false, String statusFilter = 'aktif'}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: neutral300,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: neutral200),
      ),
      child: Column(
        children: [
          Icon(
            isFiltered ? Icons.filter_list_off : Icons.assignment_outlined,
            size: 48,
            color: neutral400,
          ),
          const SizedBox(height: 12),
          Text(
            isFiltered
                ? 'Tidak ada tugas yang sesuai filter'
                : 'Tidak ada tugas $statusFilter',
            style: mediumTextStyle(size: 14, color: neutral600),
          ),
          const SizedBox(height: 4),
          Text(
            isFiltered
                ? 'Coba ubah kriteria filter atau buat tugas baru'
                : 'Buat tugas baru untuk cluster ini',
            style: regularTextStyle(size: 12, color: neutral500),
            textAlign: TextAlign.center,
          ),
          if (isFiltered) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _resetFilters,
              child: Text(
                'Reset Filter',
                style: mediumTextStyle(size: 12, color: kbpBlue600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // NEW: Officers section (extracted for better organization)
  Widget _buildOfficersSection(List<Officer> officers, User cluster) {
    return Column(
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
                      initialTab: 1,
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
        officers.isEmpty
            ? const Text(
                'Belum ada petugas di cluster ini',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: neutral600,
                ),
              )
            : SizedBox(
                height: 70,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: officers.length,
                  itemBuilder: (context, idx) {
                    final officer = officers[idx];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Row(
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
                                        ? officer.name[0].toUpperCase()
                                        : '?',
                                    style: boldTextStyle(
                                        color: kbpBlue900, size: 14),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 70,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  officer.name.length > 10
                                      ? '${officer.name.substring(0, 10)}...'
                                      : officer.name,
                                  style: boldTextStyle(size: 12),
                                ),
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: officer.type == OfficerType.organik
                                        ? successG50
                                        : warningY50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    officer.type == OfficerType.organik
                                        ? 'Organik'
                                        : 'Outsource',
                                    style: semiBoldTextStyle(
                                      size: 10,
                                      color: officer.type == OfficerType.organik
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
    );
  }

  // Helper methods tetap sama seperti sebelumnya...
  void _showCancelConfirmationDialog(
      BuildContext context, PatrolTask task, User cluster) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10.0,
                offset: Offset(0.0, 10.0),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon warning
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: dangerR50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  size: 40,
                  color: dangerR500,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'Batalkan Tugas',
                style: boldTextStyle(size: 18),
              ),
              const SizedBox(height: 8),

              // Message
              Text(
                'Apakah Anda yakin ingin membatalkan tugas ini? Tindakan ini tidak dapat dipulihkan.',
                textAlign: TextAlign.center,
                style: regularTextStyle(color: neutral700),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: neutral700,
                        side: const BorderSide(color: neutral400),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Tidak'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        // Tutup dialog konfirmasi
                        Navigator.of(context).pop();

                        // Tampilkan dialog loading
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => Dialog(
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Loading indicator
                                  const SizedBox(
                                    width: 60,
                                    height: 60,
                                    child: CircularProgressIndicator(
                                      color: kbpBlue900,
                                      strokeWidth: 4,
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // Text
                                  Text(
                                    'Membatalkan tugas...',
                                    style: mediumTextStyle(size: 16),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Mohon tunggu sebentar',
                                    style: regularTextStyle(
                                        color: neutral600, size: 14),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );

                        // Proses pembatalan task
                        try {
                          await _cancelTask(task);

                          // Tutup dialog loading
                          if (context.mounted) Navigator.of(context).pop();

                          // Refresh data
                          _loadData();

                          // Tampilkan feedback sukses
                          if (context.mounted) {
                            showCustomSnackbar(
                              context: context,
                              title: 'Berhasil',
                              subtitle: 'Patroli berhasil dibatalkan',
                              type: SnackbarType.success,
                            );
                          }
                        } catch (error) {
                          // Tutup dialog loading
                          if (context.mounted) Navigator.of(context).pop();

                          // Tampilkan feedback error
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.error,
                                        color: Colors.white),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                          'Gagal membatalkan tugas: $error'),
                                    ),
                                  ],
                                ),
                                backgroundColor: dangerR500,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                margin: const EdgeInsets.all(8),
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: dangerR500,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Ya, Batalkan'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelTask(PatrolTask task) async {
    try {
      await context.read<PatrolBloc>().repository.updateTask(
        task.taskId,
        {
          'status': 'cancelled',
          'cancelledAt': DateTime.now().toIso8601String(),
        },
      );
    } catch (e) {
      print('Error cancelling task: $e');
      throw Exception('Gagal membatalkan tugas: $e');
    }
  }

  bool _canCancelTask(PatrolTask task) {
    // Task harus dalam status active (belum dimulai)

    final now = DateTime.now();
    final cutoffTime =
        task.assignedStartTime!.subtract(const Duration(minutes: 10));

    final result = (now.isBefore(cutoffTime) && task.status == 'active');

    // Return true jika waktu sekarang masih sebelum cutoffTime
    return result;
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

  String _getSafeTaskIdPreview(String taskId) {
    // Mengembalikan 8 karakter pertama dari taskId yang valid, atau string kosong jika tidak valid
    if (taskId.isEmpty) return '';

    return taskId.length > 8 ? taskId.substring(0, 8) : taskId;
  }
}
