import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/admin/patrol_history_screen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:lottie/lottie.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as Math;

class ClusterPatrolHistoryScreen extends StatefulWidget {
  final String clusterId;
  final String clusterName;

  const ClusterPatrolHistoryScreen({
    super.key,
    required this.clusterId,
    required this.clusterName,
  });

  @override
  State<ClusterPatrolHistoryScreen> createState() =>
      _ClusterPatrolHistoryScreenState();
}

class _ClusterPatrolHistoryScreenState
    extends State<ClusterPatrolHistoryScreen> {
  final DateFormat dateFormatter = DateFormat('dd MMM yyyy', 'id_ID');
  final DateFormat timeFormatter = DateFormat('HH:mm', 'id_ID');

  // Filter states
  String? selectedOfficerId;
  String? selectedStatus;
  DateTime? startDate;
  DateTime? endDate;

  // TAMBAHAN: Pagination variables
  final ScrollController _scrollController = ScrollController();
  List<PatrolTask> _allTasks = [];
  List<PatrolTask> _displayedTasks = [];
  bool _isLoadingMore = false;
  bool _hasMoreData = true;
  final int _itemsPerPage = 10;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadClusterTasks();
    _loadClusterValidationRadius(widget.clusterId);

    // TAMBAHAN: Setup scroll listener untuk auto-load
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // TAMBAHAN: Scroll listener untuk auto-load
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // Trigger load more when user is 200px from bottom
      _loadMoreTasks();
    }
  }

  // PERBAIKAN: Enhanced loadClusterTasks
  void _loadClusterTasks() {
    // Reset pagination state
    _currentPage = 0;
    _allTasks.clear();
    _displayedTasks.clear();
    _hasMoreData = true;
    _isLoadingMore = false;

    context.read<AdminBloc>().add(
          LoadClusterTasksEvent(widget.clusterId),
        );
  }

  // TAMBAHAN: Load more tasks function
  void _loadMoreTasks() {
    if (_isLoadingMore || !_hasMoreData) return;

    setState(() {
      _isLoadingMore = true;
    });

    // Simulate loading delay for smooth UX
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _paginateTasks();
      }
    });
  }

  // TAMBAHAN: Paginate filtered tasks
  void _paginateTasks() {
    final startIndex = _currentPage * _itemsPerPage;
    final endIndex = startIndex + _itemsPerPage;

    List<PatrolTask> filteredTasks = _getFilteredTasks(_allTasks);

    if (startIndex < filteredTasks.length) {
      final newTasks =
          filteredTasks.skip(startIndex).take(_itemsPerPage).toList();

      setState(() {
        if (_currentPage == 0) {
          _displayedTasks = newTasks;
        } else {
          _displayedTasks.addAll(newTasks);
        }

        _currentPage++;
        _hasMoreData = endIndex < filteredTasks.length;
        _isLoadingMore = false;
      });

      print('Loaded page $_currentPage: ${newTasks.length} tasks');
      print(
          'Total displayed: ${_displayedTasks.length}, HasMore: $_hasMoreData');
    } else {
      setState(() {
        _hasMoreData = false;
        _isLoadingMore = false;
      });
    }
  }

  // TAMBAHAN: Get filtered tasks
  List<PatrolTask> _getFilteredTasks(List<PatrolTask> tasks) {
    List<PatrolTask> filteredTasks = List.from(tasks);

    // Apply filters
    if (selectedOfficerId != null) {
      filteredTasks = filteredTasks
          .where((task) =>
              task.officerId == selectedOfficerId ||
              task.userId == selectedOfficerId)
          .toList();
    }

    if (selectedStatus != null) {
      filteredTasks = filteredTasks
          .where((task) =>
              task.status.toLowerCase() == selectedStatus!.toLowerCase())
          .toList();
    }

    if (startDate != null) {
      filteredTasks = filteredTasks.where((task) {
        if (task.startTime == null && task.assignedStartTime == null)
          return false;
        final taskDate = task.startTime ?? task.assignedStartTime!;
        return taskDate.isAfter(startDate!.subtract(const Duration(days: 1)));
      }).toList();
    }

    if (endDate != null) {
      filteredTasks = filteredTasks.where((task) {
        if (task.startTime == null && task.assignedStartTime == null)
          return false;
        final taskDate = task.startTime ?? task.assignedStartTime!;
        return taskDate.isBefore(endDate!.add(const Duration(days: 1)));
      }).toList();
    }

    // Sort tasks by date (newest first)
    filteredTasks.sort((a, b) {
      final aDate = a.startTime ?? a.assignedStartTime ?? DateTime(1970);
      final bDate = b.startTime ?? b.assignedStartTime ?? DateTime(1970);
      return bDate.compareTo(aDate);
    });

    return filteredTasks;
  }

  // PERBAIKAN: Apply filters and reset pagination
  void _applyFilters() {
    // Reset pagination when filters change
    _currentPage = 0;
    _displayedTasks.clear();
    _hasMoreData = true;
    _isLoadingMore = false;

    // Load first page with new filters
    _paginateTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Riwayat Patroli ${widget.clusterName}'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
            context.read<AdminBloc>().add(
                  GetClusterDetail(widget.clusterId),
                );
          },
        ),
      ),
      body: WillPopScope(
        onWillPop: () async {
          Navigator.pop(context);
          context.read<AdminBloc>().add(
                GetClusterDetail(widget.clusterId),
              );
          return false;
        },
        child: BlocListener<AdminBloc, AdminState>(
          listener: (context, state) {
            // TAMBAHAN: Update tasks when loaded from bloc
            if (state is ClusterTasksLoaded) {
              _allTasks = List.from(state.tasks);
              print('Loaded ${_allTasks.length} total tasks from bloc');

              // Initialize first page
              _currentPage = 0;
              _displayedTasks.clear();
              _hasMoreData = true;
              _isLoadingMore = false;

              // Load first page
              _paginateTasks();
            }
          },
          child: BlocBuilder<AdminBloc, AdminState>(
            builder: (context, state) {
              if (state is ClustersLoading || state is AdminLoading) {
                return Center(
                  child: Lottie.asset(
                    'assets/lottie/maps_loading.json',
                    width: 200,
                    height: 100,
                  ),
                );
              } else if (state is ClusterTasksLoaded) {
                final cluster = state.cluster;
                final officers = cluster!.officers ?? [];

                // Show empty state if no filtered tasks
                if (_displayedTasks.isEmpty && !_isLoadingMore) {
                  return EmptyState(
                    icon: Icons.history,
                    title: 'Belum ada riwayat patroli',
                    subtitle: selectedOfficerId != null ||
                            selectedStatus != null ||
                            startDate != null ||
                            endDate != null
                        ? 'Tidak ada hasil yang cocok dengan filter yang dipilih'
                        : 'Belum ada tugas patroli yang diselesaikan di cluster ini',
                    buttonText: 'Segarkan',
                    onButtonPressed: _loadClusterTasks,
                  );
                }

                return Column(
                  children: [
                    // PERBAIKAN: Active filters strip dengan total count
                    if (selectedOfficerId != null ||
                        selectedStatus != null ||
                        startDate != null ||
                        endDate != null)
                      _buildActiveFiltersStrip(officers),

                    // TAMBAHAN: Tasks count info
                    if (_displayedTasks.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        color: kbpBlue50,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    size: 16, color: kbpBlue600),
                                const SizedBox(width: 8),
                                Text(
                                  'Menampilkan ${_displayedTasks.length} dari ${_getFilteredTasks(_allTasks).length} tugas',
                                  style: mediumTextStyle(
                                      size: 12, color: kbpBlue700),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                    // PERBAIKAN: Tasks list dengan pagination
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount:
                            _displayedTasks.length + (_hasMoreData ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Show loading indicator at the end if has more data
                          if (index == _displayedTasks.length) {
                            return _buildLoadingIndicator();
                          }

                          final task = _displayedTasks[index];

                          // Find the officer for this task
                          final officer = officers.firstWhere(
                            (o) =>
                                o.id == task.officerId || o.id == task.userId,
                            orElse: () {
                              print(
                                  'Officer not found for task ${task.taskId}');
                              print(
                                  '  - Trying to find by officerId: ${task.officerId}');
                              print(
                                  '  - Trying to find by userId: ${task.userId}');

                              if (task.officerName != 'Loading...') {
                                return Officer(
                                  id: task.officerId.isNotEmpty
                                      ? task.officerId
                                      : task.userId,
                                  name: task.officerName,
                                  type: OfficerType.organik,
                                  shift: ShiftType.pagi,
                                  clusterId: widget.clusterId,
                                  photoUrl: task.officerPhotoUrl != 'P'
                                      ? task.officerPhotoUrl
                                      : null,
                                );
                              }

                              return Officer(
                                id: task.officerId.isNotEmpty
                                    ? task.officerId
                                    : task.userId,
                                name: 'Petugas tidak ditemukan',
                                type: OfficerType.organik,
                                shift: ShiftType.pagi,
                                clusterId: widget.clusterId,
                              );
                            },
                          );

                          return _buildTaskCard(task, officer, index);
                        },
                      ),
                    ),
                  ],
                );
              } else if (state is AdminError || state is ClustersError) {
                final message = state is AdminError
                    ? (state as AdminError).message
                    : (state as ClustersError).message;

                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 64, color: dangerR300),
                      const SizedBox(height: 16),
                      Text(
                        'Error: $message',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kbpBlue900,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _loadClusterTasks,
                        child: const Text('Coba Lagi'),
                      ),
                    ],
                  ),
                );
              }

              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: kbpBlue700),
                    SizedBox(height: 16),
                    Text(
                      'Memuat riwayat patroli...',
                      style: TextStyle(color: neutral600, fontSize: 14),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // TAMBAHAN: Loading indicator untuk pagination
  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: kbpBlue600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Memuat tugas lainnya...',
            style: mediumTextStyle(size: 14, color: neutral600),
          ),
        ],
      ),
    );
  }

  // PERBAIKAN: Enhanced active filters strip
  Widget _buildActiveFiltersStrip(List<Officer> officers) {
    String officerName = '';
    if (selectedOfficerId != null) {
      final officer = officers.firstWhere(
        (o) => o.id == selectedOfficerId,
        orElse: () => Officer(
          id: '',
          name: 'Unknown',
          type: OfficerType.organik,
          shift: ShiftType.pagi,
          clusterId: '',
        ),
      );
      officerName = officer.name;
    }

    final totalFiltered = _getFilteredTasks(_allTasks).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      // color: kbpBlue50,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: kbpBlue200, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_list, size: 16, color: kbpBlue900),
              const SizedBox(width: 8),
              Text(
                'Filter Aktif:',
                style: semiBoldTextStyle(color: kbpBlue900, size: 14),
              ),
              const Spacer(),
              // TAMBAHAN: Filtered count
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kbpBlue100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$totalFiltered hasil',
                  style: boldTextStyle(size: 12, color: kbpBlue700),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    selectedOfficerId = null;
                    selectedStatus = null;
                    startDate = null;
                    endDate = null;
                  });
                  _applyFilters();
                },
                style: TextButton.styleFrom(
                  foregroundColor: dangerR500,
                  padding: const EdgeInsets.all(4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Reset'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              if (selectedOfficerId != null)
                Chip(
                  label: Text(
                    'Petugas: $officerName',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: kbpBlue100,
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      selectedOfficerId = null;
                    });
                    _applyFilters();
                  },
                ),
              if (selectedStatus != null)
                Chip(
                  label: Text(
                    'Status: ${_getStatusText(selectedStatus!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: kbpBlue100,
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      selectedStatus = null;
                    });
                    _applyFilters();
                  },
                ),
              if (startDate != null)
                Chip(
                  label: Text(
                    'Dari: ${dateFormatter.format(startDate!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: kbpBlue100,
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      startDate = null;
                    });
                    _applyFilters();
                  },
                ),
              if (endDate != null)
                Chip(
                  label: Text(
                    'Sampai: ${dateFormatter.format(endDate!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: kbpBlue100,
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      endDate = null;
                    });
                    _applyFilters();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // PERBAIKAN: Enhanced task card dengan animation
  Widget _buildTaskCard(PatrolTask task, Officer officer, int index) {
    final startDateStr =
        task.startTime != null ? dateFormatter.format(task.startTime!) : 'N/A';

    final startTimeStr =
        task.startTime != null ? timeFormatter.format(task.startTime!) : '';

    final endTimeStr =
        task.endTime != null ? timeFormatter.format(task.endTime!) : 'N/A';

    final assignedStartDateStr = task.assignedStartTime != null
        ? dateFormatter.format(task.assignedStartTime!)
        : null;

    final assignedStartTimeStr = task.assignedStartTime != null
        ? timeFormatter.format(task.assignedStartTime!)
        : null;

    final visitData = _calculateVisitedPoints(task);
    int completedPointsCount = visitData['visitedCount'] as int;
    int totalPointsCount = visitData['totalCount'] as int;

    if (totalPointsCount == 0 &&
        (task.status.toLowerCase() == 'finished' ||
            task.status.toLowerCase() == 'completed')) {
      completedPointsCount = 1;
      totalPointsCount = 1;
    } else if (totalPointsCount == 0 && task.routePath != null) {
      completedPointsCount = task.routePath!.length;
      totalPointsCount = task.routePath!.length;
    }

    final progress = totalPointsCount > 0
        ? (completedPointsCount / totalPointsCount * 100).round()
        : 0;

    return AnimatedContainer(
      duration: Duration(milliseconds: 300 + (index * 50)),
      curve: Curves.easeOutBack,
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PatrolHistoryScreen(task: task),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with task ID and status
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: _getStatusColor(task.status),
                      child: const Icon(Icons.check_circle,
                          color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tugas #${task.taskId.substring(0, 8)}',
                            style: boldTextStyle(size: 16),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _getStatusText(task.status),
                                style: TextStyle(
                                  color: _getStatusColor(task.status),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (task.timeliness != null &&
                                  task.status != 'cancelled') ...[
                                buildTimelinessIndicator(task.timeliness),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const Divider(height: 24),

                // Officer info
                Row(
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
                              style: boldTextStyle(color: kbpBlue900),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            officer.name,
                            style: semiBoldTextStyle(size: 14),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
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
                                  style: mediumTextStyle(
                                    size: 10,
                                    color: officer.type == OfficerType.organik
                                        ? successG500
                                        : warningY500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: kbpBlue50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  getShortShiftText(officer.shift),
                                  style: mediumTextStyle(
                                      size: 10, color: kbpBlue700),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Time info section
                _buildTimeInfoSection(
                  assignedStartDateStr: assignedStartDateStr,
                  assignedStartTimeStr: assignedStartTimeStr,
                  startDateStr: startDateStr,
                  startTimeStr: startTimeStr,
                  endTimeStr: endTimeStr,
                  task: task,
                ),

                const SizedBox(height: 12),

                // Progress
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Titik Dikunjungi',
                                    style: regularTextStyle(
                                        size: 12, color: neutral600),
                                  ),
                                  const SizedBox(width: 4),
                                  const Tooltip(
                                    message:
                                        'Titik dianggap dikunjungi jika petugas berada dalam radius validasi checkpoint.',
                                    child: Icon(Icons.info_outline,
                                        size: 14, color: neutral500),
                                  ),
                                ],
                              ),
                              Text(
                                '$completedPointsCount dari $totalPointsCount titik',
                                style: semiBoldTextStyle(size: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: progress / 100,
                            backgroundColor: neutral200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              task.status.toLowerCase() == 'finished' ||
                                      task.status.toLowerCase() == 'completed'
                                  ? successG500
                                  : task.status.toLowerCase() == 'ongoing' ||
                                          task.status.toLowerCase() == 'active'
                                      ? kbpBlue700
                                      : warningY500,
                            ),
                            minHeight: 8,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: kbpBlue100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$progress%',
                        style: boldTextStyle(size: 14, color: kbpBlue900),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // PERBAIKAN: Update filter sheet untuk apply filters dengan pagination
  void _showFilterSheet(BuildContext context) {
    String? tempOfficerId = selectedOfficerId;
    String? tempStatus = selectedStatus;
    DateTime? tempStartDate = startDate;
    DateTime? tempEndDate = endDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return BlocBuilder<AdminBloc, AdminState>(
          builder: (context, state) {
            if (state is ClusterTasksLoaded) {
              final officers = state.cluster!.officers ?? [];

              return StatefulBuilder(
                builder: (context, setModalState) {
                  // Date picker functions remain the same...
                  Future<void> _selectStartDate() async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: tempStartDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2101),
                      builder: (BuildContext context, Widget? child) {
                        return Theme(
                          data: ThemeData.light().copyWith(
                            primaryColor: kbpBlue900,
                            colorScheme: const ColorScheme.light(primary: kbpBlue900),
                            buttonTheme: const ButtonThemeData(
                                textTheme: ButtonTextTheme.primary),
                          ),
                          child: child!,
                        );
                      },
                    );

                    if (picked != null) {
                      setModalState(() {
                        tempStartDate = picked;
                      });
                    }
                  }

                  Future<void> _selectEndDate() async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: tempEndDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2101),
                      builder: (BuildContext context, Widget? child) {
                        return Theme(
                          data: ThemeData.light().copyWith(
                            primaryColor: kbpBlue900,
                            colorScheme: const ColorScheme.light(primary: kbpBlue900),
                            buttonTheme: const ButtonThemeData(
                                textTheme: ButtonTextTheme.primary),
                          ),
                          child: child!,
                        );
                      },
                    );

                    if (picked != null) {
                      setModalState(() {
                        tempEndDate = picked;
                      });
                    }
                  }

                  return Container(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                      left: 16,
                      right: 16,
                      top: 16,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Filter Riwayat Patroli',
                                style: boldTextStyle(size: 18),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Officer filter
                          Text(
                            'Petugas',
                            style: semiBoldTextStyle(size: 14),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: neutral300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonFormField<String?>(
                              value: tempOfficerId,
                              decoration: const InputDecoration(
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 12),
                                border: InputBorder.none,
                                hintText: 'Semua Petugas',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Semua Petugas'),
                                ),
                                ...officers.map((officer) {
                                  return DropdownMenuItem<String>(
                                    value: officer.id,
                                    child: Text(officer.name),
                                  );
                                }).toList(),
                              ],
                              onChanged: (value) {
                                setModalState(() {
                                  tempOfficerId = value;
                                });
                              },
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Status filter
                          Text(
                            'Status Patroli',
                            style: semiBoldTextStyle(size: 14),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: neutral300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonFormField<String?>(
                              value: tempStatus,
                              decoration: const InputDecoration(
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 12),
                                border: InputBorder.none,
                                hintText: 'Semua Status',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Semua Status'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'ongoing',
                                  child: Text(_getStatusText('ongoing')),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'active',
                                  child: Text(_getStatusText('active')),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'finished',
                                  child: Text(_getStatusText('finished')),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'cancelled',
                                  child: Text(_getStatusText('cancelled')),
                                ),
                              ],
                              onChanged: (value) {
                                setModalState(() {
                                  tempStatus = value;
                                });
                              },
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Date range filter
                          Text(
                            'Rentang Tanggal',
                            style: semiBoldTextStyle(size: 14),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: MaterialButton(
                                  onPressed: _selectStartDate,
                                  color: kbpBlue50,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.calendar_today,
                                          size: 16, color: kbpBlue900),
                                      const SizedBox(width: 8),
                                      Text(
                                        tempStartDate != null
                                            ? dateFormatter
                                                .format(tempStartDate!)
                                            : 'Pilih Tanggal Mulai',
                                        style:
                                            mediumTextStyle(color: kbpBlue900),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: MaterialButton(
                                  onPressed: _selectEndDate,
                                  color: kbpBlue50,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.calendar_today,
                                          size: 16, color: kbpBlue900),
                                      const SizedBox(width: 8),
                                      Text(
                                        tempEndDate != null
                                            ? dateFormatter.format(tempEndDate!)
                                            : 'Pilih Tanggal Selesai',
                                        style:
                                            mediumTextStyle(color: kbpBlue900),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Filter actions
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      selectedOfficerId = tempOfficerId;
                                      selectedStatus = tempStatus;
                                      startDate = tempStartDate;
                                      endDate = tempEndDate;
                                    });
                                    Navigator.pop(context);
                                    // PERBAIKAN: Apply filters dengan pagination
                                    _applyFilters();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kbpBlue900,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 24),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('Terapkan Filter'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextButton(
                                  onPressed: () {
                                    setModalState(() {
                                      tempOfficerId = null;
                                      tempStatus = null;
                                      tempStartDate = null;
                                      tempEndDate = null;
                                    });
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 24),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text(
                                    'Reset Filter',
                                    style: TextStyle(color: dangerR500),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  );
                },
              );
            }

            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Memuat data petugas...'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Rest of the existing methods remain the same...
  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return 'Tugas Dijadwalkan';
      case 'ongoing':
        return 'Sedang Berlangsung';
      case 'active':
        return 'Tugas Dijadwalkan';
      case 'finished':
      case 'completed':
        return 'Patroli Selesai';
      case 'cancelled':
        return 'Patroli Dibatalkan';
      case 'expired':
        return 'Patroli Tidak Dilaksanakan';
      default:
        return 'Status Tidak Diketahui';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return warningY500;
      case 'ongoing':
      case 'active':
        return kbpBlue700;
      case 'finished':
      case 'completed':
        return successG500;
      case 'cancelled':
        return dangerR500;
      case 'expired':
        return dangerR300;
      default:
        return neutral500;
    }
  }

  String getShortShiftText(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return 'Pagi (07-15)';
      case ShiftType.sore:
        return 'Sore (15-23)';
      case ShiftType.malam:
        return 'Malam (23-07)';
      case ShiftType.siang:
        return 'Siang (07-19)';
      case ShiftType.malamPanjang:
        return 'Malam (19-07)';
    }
  }

  // Existing utility methods remain the same...
  double? _clusterValidationRadius;

  Future<void> _loadClusterValidationRadius(String clusterId) async {
    try {
      if (clusterId.isEmpty) {
        print('ClusterId is empty, using default radius');
        _clusterValidationRadius = 50.0;
        return;
      }

      final snapshot = await FirebaseDatabase.instance
          .ref('users')
          .child(clusterId)
          .child('checkpoint_validation_radius')
          .get();

      if (snapshot.exists && snapshot.value != null) {
        _clusterValidationRadius = (snapshot.value as num).toDouble();
        print('Loaded cluster validation radius: ${_clusterValidationRadius}m');
      } else {
        _clusterValidationRadius = 50.0;
        print('No cluster validation radius found, using default: 50m');
      }
    } catch (e) {
      print('Error loading cluster validation radius: $e');
      _clusterValidationRadius = 50.0;
    }
  }

  Map<String, dynamic> _calculateVisitedPoints(PatrolTask task,
      {double? customRadius}) {
    try {
      final Set<int> visitedCheckpoints = <int>{};
      final List<Map<String, double>> routePositions = [];

      final double radiusInMeters =
          customRadius ?? _clusterValidationRadius ?? 50.0;

      if (task.routePath != null && task.assignedRoute != null) {
        final routePathMap = Map<String, dynamic>.from(task.routePath!);
        routePathMap.forEach((key, value) {
          try {
            if (value is Map && value.containsKey('coordinates')) {
              final coordinates = value['coordinates'] as List;
              if (coordinates.length >= 2) {
                routePositions.add({
                  'lat': coordinates[0] as double,
                  'lng': coordinates[1] as double
                });
              }
            }
          } catch (e) {
            print('Error parsing route path entry $key: $e');
          }
        });

        for (int i = 0; i < task.assignedRoute!.length; i++) {
          try {
            final checkpoint = task.assignedRoute![i];
            final checkpointLat = checkpoint[0] as double;
            final checkpointLng = checkpoint[1] as double;

            double minDistance = double.infinity;
            for (final position in routePositions) {
              final distance = Geolocator.distanceBetween(position['lat']!,
                  position['lng']!, checkpointLat, checkpointLng);

              minDistance = Math.min(minDistance, distance);
              if (distance <= radiusInMeters) {
                visitedCheckpoints.add(i);
                break;
              }
            }
          } catch (e) {
            print('Error checking distance for checkpoint $i: $e');
          }
        }
      }

      return {
        'visitedCheckpoints': visitedCheckpoints,
        'routePositions': routePositions,
        'visitedCount': visitedCheckpoints.length,
        'totalCount': task.assignedRoute?.length ?? 0,
        'radiusUsed': radiusInMeters,
      };
    } catch (e) {
      print('Error calculating visited points: $e');
      return {
        'visitedCheckpoints': <int>{},
        'routePositions': <Map<String, double>>[],
        'visitedCount': 0,
        'totalCount': task.assignedRoute?.length ?? 0,
        'radiusUsed': customRadius ?? 50.0,
      };
    }
  }

  // Existing helper methods for time info and delay info remain the same...
  Widget _buildTimeInfoSection({
    required String? assignedStartDateStr,
    required String? assignedStartTimeStr,
    required String startDateStr,
    required String startTimeStr,
    required String endTimeStr,
    required PatrolTask task,
  }) {
    return Column(
      children: [
        if (assignedStartDateStr != null && assignedStartTimeStr != null) ...[
          Row(
            children: [
              const Icon(Icons.schedule, size: 14, color: kbpBlue600),
              const SizedBox(width: 8),
              Text(
                'Jadwal: ',
                style: mediumTextStyle(size: 12, color: neutral600),
              ),
              Text(
                '$assignedStartDateStr, $assignedStartTimeStr',
                style: semiBoldTextStyle(size: 12, color: kbpBlue700),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Icon(
              task.status.toLowerCase() == 'finished' ||
                      task.status.toLowerCase() == 'completed'
                  ? Icons.check_circle
                  : task.status.toLowerCase() == 'ongoing' ||
                          task.status.toLowerCase() == 'active'
                      ? Icons.play_circle
                      : Icons.access_time,
              size: 14,
              color: task.status.toLowerCase() == 'finished' ||
                      task.status.toLowerCase() == 'completed'
                  ? successG300
                  : task.status.toLowerCase() == 'ongoing' ||
                          task.status.toLowerCase() == 'active'
                      ? kbpBlue600
                      : neutral600,
            ),
            const SizedBox(width: 8),
            Text(
              'Pelaksanaan: ',
              style: mediumTextStyle(size: 12, color: neutral600),
            ),
            Expanded(
              child: Text(
                startTimeStr.isNotEmpty && endTimeStr != 'N/A'
                    ? '$startDateStr, $startTimeStr - $endTimeStr'
                    : startTimeStr.isNotEmpty
                        ? '$startDateStr, $startTimeStr - Berlangsung'
                        : 'Belum dimulai',
                style: mediumTextStyle(size: 12, color: neutral800),
              ),
            ),
          ],
        ),
        if (assignedStartTimeStr != null &&
            startTimeStr.isNotEmpty &&
            task.assignedStartTime != null &&
            task.startTime != null) ...[
          const SizedBox(height: 6),
          _buildDelayInfo(task.assignedStartTime!, task.startTime!),
        ],
      ],
    );
  }

  Widget _buildDelayInfo(DateTime assignedTime, DateTime actualTime) {
    final difference = actualTime.difference(assignedTime);
    final isLate = difference.inMinutes > 10;
    final isEarly = difference.inMinutes < -10;

    String delayText;
    Color delayColor;
    IconData delayIcon;

    if (isLate) {
      final hours = difference.inHours;
      final minutes = (difference.inMinutes % 60) - 10;
      delayText = hours > 0
          ? 'Terlambat $hours jam ${minutes}menit'
          : 'Terlambat $minutes menit';
      delayColor = dangerR500;
      delayIcon = Icons.schedule_outlined;
    } else if (isEarly) {
      final hours = difference.inHours.abs();
      final minutes = (difference.inMinutes % 60).abs();
      delayText = hours > 0
          ? 'Lebih awal $hours jam $minutes menit'
          : 'Lebih awal $minutes menit';
      delayColor = kbpBlue600;
      delayIcon = Icons.fast_forward;
    } else {
      delayText = 'Tepat waktu';
      delayColor = successG500;
      delayIcon = Icons.check_circle_outline;
    }

    return Row(
      children: [
        Icon(delayIcon, size: 12, color: delayColor),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: delayColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: delayColor.withOpacity(0.3)),
          ),
          child: Text(
            delayText,
            style: mediumTextStyle(
              size: 10,
              color: delayColor,
            ),
          ),
        ),
      ],
    );
  }
}
