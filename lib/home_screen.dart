import 'dart:async';
import 'dart:developer';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:livetrackingapp/map_screen.dart';
import 'package:livetrackingapp/notification_utils.dart';
import 'package:livetrackingapp/patrol_summary_screen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/patrol/patrol_history_list_screen.dart';
import 'package:lottie/lottie.dart' as lottie;
import '../../domain/entities/patrol_task.dart';
import '../../domain/entities/user.dart';
import 'presentation/auth/bloc/auth_bloc.dart';
import 'presentation/routing/bloc/patrol_bloc.dart';
import 'presentation/task/task_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  StreamSubscription? _taskSubscription;
  User? _currentUser;

  // TAMBAHAN: Pagination variables untuk upcoming tasks
  List<PatrolTask> _allUpcomingTasks = [];
  List<PatrolTask> _displayedUpcomingTasks = [];
  int _upcomingCurrentPage = 0;
  final int _upcomingItemsPerPage = 10;
  bool _hasMoreUpcomingTasks = false;
  bool _isLoadingMoreUpcoming = false;

  // TAMBAHAN: Pagination variables untuk history tasks
  List<PatrolTask> _allHistoryTasks = [];
  List<PatrolTask> _displayedHistoryTasks = [];
  int _historyCurrentPage = 0;
  final int _historyItemsPerPage = 10;
  bool _hasMoreHistoryTasks = false;
  bool _isLoadingMoreHistory = false;

  // Legacy variables - akan diupdate dengan pagination
  List<PatrolTask> _upcomingTasks = [];
  List<PatrolTask> _historyTasks = [];
  bool _isLoading = true;
  final Set<String> _expandedOfficers = {};

  List<PatrolTask> _allOngoingTasks = [];
  List<PatrolTask> _displayedOngoingTasks = [];
  int _ongoingCurrentPage = 0;
  final int _ongoingItemsPerPage = 10;
  bool _hasMoreOngoingTasks = false;
  bool _isLoadingMoreOngoing = false;

  bool _isUpcomingExpanded = false;
  final int _upcomingPreviewLimit = 5;

  // late AppLifecycleListener _lifecycleListener;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // _lifecycleListener = AppLifecycleListener(
    //   onStateChange: (state) {
    //     if (!mounted) return;

    //     if (state == AppLifecycleState.resumed) {
    //       _startRefreshTimer();
    //     } else if (state == AppLifecycleState.paused) {
    //       _refreshTimer?.cancel();
    //       _refreshTimer = null;
    //     }
    //   },
    // );
    // _startRefreshTimer();
    _loadUserData();
  }

  void _toggleUpcomingExpanded() {
    setState(() {
      _isUpcomingExpanded = !_isUpcomingExpanded;

      if (_isUpcomingExpanded) {
        // Expand: load first page of items
        _displayedUpcomingTasks =
            _allUpcomingTasks.take(_upcomingItemsPerPage).toList();
        _upcomingCurrentPage = 0;
      } else {
        // Collapse: back to preview
        _displayedUpcomingTasks =
            _allUpcomingTasks.take(_upcomingPreviewLimit).toList();
        _upcomingCurrentPage = 0;
      }

      _hasMoreUpcomingTasks =
          _displayedUpcomingTasks.length < _allUpcomingTasks.length;
      _isLoadingMoreUpcoming = false;
      _upcomingTasks = List.from(_displayedUpcomingTasks);
    });
  }

  // PERBAIKAN: Reset pagination data - update untuk upcoming state
  void _resetPaginationData() {
    _allUpcomingTasks.clear();
    _displayedUpcomingTasks.clear();
    _upcomingCurrentPage = 0;
    _hasMoreUpcomingTasks = false;
    _isLoadingMoreUpcoming = false;
    _isUpcomingExpanded = false; // TAMBAHAN: Reset expand state

    // Reset other pagination data...
    _allOngoingTasks.clear();
    _displayedOngoingTasks.clear();
    _ongoingCurrentPage = 0;
    _hasMoreOngoingTasks = false;
    _isLoadingMoreOngoing = false;

    _allHistoryTasks.clear();
    _displayedHistoryTasks.clear();
    _historyCurrentPage = 0;
    _hasMoreHistoryTasks = false;
    _isLoadingMoreHistory = false;

    // Legacy lists
    _upcomingTasks.clear();
    _historyTasks.clear();
  }

  Widget _buildUpcomingPatrolsContent() {
    if (_displayedUpcomingTasks.isEmpty && !_isLoadingMoreUpcoming) {
      return _buildEmptyStateCard(
        icon: 'assets/state/noTask.svg',
        message: 'Belum ada tugas patroli\nyang dijadwalkan',
      );
    }

    final now = DateTime.now();

    return Column(
      children: [
        // TAMBAHAN: Smart info bar
        if (_displayedUpcomingTasks.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: kbpBlue50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kbpBlue200),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 14, color: kbpBlue600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isUpcomingExpanded
                        ? 'Menampilkan ${_displayedUpcomingTasks.length} dari ${_allUpcomingTasks.length} tugas mendatang'
                        : 'Menampilkan ${_displayedUpcomingTasks.length} tugas terdekat dari ${_allUpcomingTasks.length} total',
                    style: mediumTextStyle(size: 12, color: kbpBlue700),
                  ),
                ),
                if (!_isUpcomingExpanded &&
                    _allUpcomingTasks.length > _upcomingPreviewLimit)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kbpBlue100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '+${_allUpcomingTasks.length - _upcomingPreviewLimit}',
                      style: boldTextStyle(size: 10, color: kbpBlue700),
                    ),
                  ),
              ],
            ),
          ),

        // TAMBAHAN: Priority tasks indicator (tasks yang bisa dimulai sekarang)
        if (_displayedUpcomingTasks.isNotEmpty)
          _buildPriorityTasksIndicator(now),

        // Main task list card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kbpBlue200, width: 1),
          ),
          color: Colors.white,
          child: Column(
            children: [
              // Tasks list
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _displayedUpcomingTasks.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1, color: kbpBlue100),
                itemBuilder: (context, index) {
                  final task = _displayedUpcomingTasks[index];
                  final isUrgent = _isTaskUrgent(task, now);
                  return _buildUpcomingTaskItem(task, index, isUrgent);
                },
              ),

              // TAMBAHAN: Load more section
              if (_isUpcomingExpanded &&
                  (_hasMoreUpcomingTasks || _isLoadingMoreUpcoming)) ...[
                const Divider(height: 1, color: kbpBlue200),
                if (_isLoadingMoreUpcoming)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kbpBlue600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Memuat tugas lainnya...',
                          style: mediumTextStyle(size: 14, color: kbpBlue600),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loadMoreUpcomingTasks,
                        icon: const Icon(Icons.expand_more, size: 16),
                        label: Text('Muat ${_upcomingItemsPerPage} Tugas Lagi'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kbpBlue700,
                          side: BorderSide(color: kbpBlue300, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                        ),
                      ),
                    ),
                  ),
              ],

              // TAMBAHAN: Expand/Collapse button
              if (_allUpcomingTasks.length > _upcomingPreviewLimit) ...[
                if (!_isUpcomingExpanded || !_hasMoreUpcomingTasks)
                  const Divider(height: 1, color: kbpBlue200),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _toggleUpcomingExpanded,
                      icon: AnimatedRotation(
                        turns: _isUpcomingExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down, size: 18),
                      ),
                      label: Text(
                        _isUpcomingExpanded
                            ? 'Tampilkan Lebih Sedikit'
                            : 'Lihat Semua ${_allUpcomingTasks.length} Tugas',
                        style: mediumTextStyle(size: 14, color: kbpBlue700),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: kbpBlue700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // TAMBAHAN: Priority tasks indicator
  Widget _buildPriorityTasksIndicator(DateTime now) {
    final urgentTasks = _displayedUpcomingTasks
        .where((task) => _isTaskUrgent(task, now))
        .length;

    if (urgentTasks == 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: warningY50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warningY300),
      ),
      child: Row(
        children: [
          Icon(Icons.priority_high, size: 16, color: warningY400),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$urgentTasks tugas siap dimulai (dalam 10 menit ke depan)',
              style: semiBoldTextStyle(size: 12, color: warningY500),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: warningY400,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$urgentTasks',
              style: boldTextStyle(size: 10, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // TAMBAHAN: Check if task is urgent (can be started within 10 minutes)
  bool _isTaskUrgent(PatrolTask task, DateTime now) {
    if (task.assignedStartTime == null) return false;
    final timeDifference = task.assignedStartTime!.difference(now);
    return timeDifference.inMinutes <= 10 &&
        timeDifference.inMinutes >= -5; // Allow 5 minutes late
  }

  // TAMBAHAN: Enhanced upcoming task item
  Widget _buildUpcomingTaskItem(PatrolTask task, int index, bool isUrgent) {
    final now = DateTime.now();
    final canStart = task.assignedStartTime != null &&
        task.assignedStartTime!.difference(now).inMinutes <= 10;

    return Container(
      decoration: BoxDecoration(
        color: isUrgent ? warningY50.withOpacity(0.3) : Colors.transparent,
        borderRadius: index == 0 && index == _displayedUpcomingTasks.length - 1
            ? BorderRadius.circular(12)
            : index == 0
                ? const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  )
                : index == _displayedUpcomingTasks.length - 1
                    ? const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      )
                    : BorderRadius.zero,
      ),
      child: InkWell(
        onTap: () => _showTaskDialog(task),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Priority indicator & Avatar
              Stack(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: kbpBlue100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isUrgent ? warningY400 : kbpBlue300,
                        width: isUrgent ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: task.officerPhotoUrl.isNotEmpty
                          ? Image.network(
                              task.officerPhotoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Text(
                                    task.officerName
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    style: semiBoldTextStyle(
                                        size: 16, color: kbpBlue900),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Text(
                                task.officerName.substring(0, 1).toUpperCase(),
                                style: semiBoldTextStyle(
                                    size: 16, color: kbpBlue900),
                              ),
                            ),
                    ),
                  ),
                  // Urgent indicator
                  if (isUrgent)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: warningY500,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.priority_high,
                          size: 8,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),

              // Task info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Officer name & vehicle
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            task.officerName,
                            style: semiBoldTextStyle(
                              size: 15,
                              color: isUrgent ? warningY500 : kbpBlue900,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Route info
                    Row(
                      children: [
                        Icon(
                          Icons.place,
                          size: 14,
                          color: isUrgent ? warningY400 : kbpBlue600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "${task.assignedRoute?.length ?? 0} titik patroli",
                          style: regularTextStyle(
                            size: 12,
                            color: isUrgent ? warningY500 : kbpBlue700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Status badges
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: canStart ? successG500 : kbpBlue600,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            canStart ? 'Siap Dimulai' : 'Terjadwal',
                            style: boldTextStyle(size: 10, color: Colors.white),
                          ),
                        ),
                        if (isUrgent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: warningY500,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'PRIORITAS',
                              style:
                                  boldTextStyle(size: 10, color: Colors.white),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Time & Action
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Scheduled time
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isUrgent ? warningY100 : kbpBlue50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isUrgent ? warningY300 : kbpBlue200,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          task.assignedStartTime != null
                              ? formatDateFromString(
                                  task.assignedStartTime.toString())
                              : 'N/A',
                          style: mediumTextStyle(
                            size: 10,
                            color: isUrgent ? warningY500 : kbpBlue700,
                          ),
                        ),
                        Text(
                          task.assignedStartTime != null
                              ? formatTimeFromString(
                                  task.assignedStartTime.toString())
                              : 'N/A',
                          style: boldTextStyle(
                            size: 12,
                            color: isUrgent ? warningY500 : kbpBlue900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // const SizedBox(width: 12),
                  // Icon(
                  //   Icons.access_time,
                  //   size: 14,
                  //   color: isUrgent ? warningY500 : kbpBlue600,
                  // ),
                  // const SizedBox(width: 4),
                  // Text(
                  //   _getTimeUntilStart(task, now),
                  //   style: mediumTextStyle(
                  //     size: 12,
                  //     color: isUrgent ? warningY500 : kbpBlue700,
                  //   ),
                  // ),

                  // Action button
                  SizedBox(
                    width: 80,
                    height: 32,
                    child: ElevatedButton(
                      onPressed: () => _showTaskDialog(task),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canStart ? successG500 : kbpBlue900,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        canStart ? 'Mulai' : 'Detail',
                        style: mediumTextStyle(size: 11, color: Colors.white),
                      ),
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

  // TAMBAHAN: Get time until task start
  String _getTimeUntilStart(PatrolTask task, DateTime now) {
    if (task.assignedStartTime == null) return 'Waktu tidak tersedia';

    final difference = task.assignedStartTime!.difference(now);

    if (difference.inMinutes <= 0) {
      return 'Sekarang';
    } else if (difference.inMinutes <= 60) {
      return '${difference.inMinutes} menit lagi';
    } else if (difference.inHours <= 24) {
      return '${difference.inHours} jam lagi';
    } else {
      return '${difference.inDays} hari lagi';
    }
  }

  void _loadMoreOngoingTasks() {
    if (_isLoadingMoreOngoing || !_hasMoreOngoingTasks) return;

    setState(() {
      _isLoadingMoreOngoing = true;
    });

    final startIndex = (_ongoingCurrentPage + 1) * _ongoingItemsPerPage;
    final endIndex = startIndex + _ongoingItemsPerPage;

    if (startIndex < _allOngoingTasks.length) {
      final newTasks =
          _allOngoingTasks.skip(startIndex).take(_ongoingItemsPerPage).toList();

      setState(() {
        _displayedOngoingTasks.addAll(newTasks);
        _ongoingCurrentPage++;
        _hasMoreOngoingTasks = endIndex < _allOngoingTasks.length;
        _isLoadingMoreOngoing = false;
      });

      print(
          'Loaded ongoing page $_ongoingCurrentPage: ${newTasks.length} tasks');
    } else {
      setState(() {
        _hasMoreOngoingTasks = false;
        _isLoadingMoreOngoing = false;
      });
    }
  }

  void _initializeOngoingPagination(List<PatrolTask> allTasks) {
    _allOngoingTasks = List.from(allTasks);
    _displayedOngoingTasks =
        _allOngoingTasks.take(_ongoingItemsPerPage).toList();
    _ongoingCurrentPage = 0;
    _hasMoreOngoingTasks = _allOngoingTasks.length > _ongoingItemsPerPage;
    _isLoadingMoreOngoing = false;

    print(
        'Initialized ongoing pagination: ${_displayedOngoingTasks.length}/${_allOngoingTasks.length}');
  }

  void _loadMoreUpcomingTasks() {
    if (_isLoadingMoreUpcoming || !_hasMoreUpcomingTasks) return;

    setState(() {
      _isLoadingMoreUpcoming = true;
    });

    // Simulate loading delay for smooth UX
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      final currentLength = _displayedUpcomingTasks.length;
      final nextBatch = _allUpcomingTasks
          .skip(currentLength)
          .take(_upcomingItemsPerPage)
          .toList();

      setState(() {
        _displayedUpcomingTasks.addAll(nextBatch);
        _upcomingCurrentPage++;
        _hasMoreUpcomingTasks =
            _displayedUpcomingTasks.length < _allUpcomingTasks.length;
        _isLoadingMoreUpcoming = false;
      });

      print(
          'Loaded more upcoming: +${nextBatch.length}, total: ${_displayedUpcomingTasks.length}/${_allUpcomingTasks.length}');
    });
  }

  void _loadMoreHistoryTasks() {
    if (_isLoadingMoreHistory || !_hasMoreHistoryTasks) return;

    setState(() {
      _isLoadingMoreHistory = true;
    });

    final startIndex = (_historyCurrentPage + 1) * _historyItemsPerPage;
    final endIndex = startIndex + _historyItemsPerPage;

    if (startIndex < _allHistoryTasks.length) {
      final newTasks =
          _allHistoryTasks.skip(startIndex).take(_historyItemsPerPage).toList();

      setState(() {
        _displayedHistoryTasks.addAll(newTasks);
        _historyCurrentPage++;
        _hasMoreHistoryTasks = endIndex < _allHistoryTasks.length;
        _isLoadingMoreHistory = false;
      });

      print(
          'Loaded history page $_historyCurrentPage: ${newTasks.length} tasks');
    } else {
      setState(() {
        _hasMoreHistoryTasks = false;
        _isLoadingMoreHistory = false;
      });
    }
  }

  // TAMBAHAN: Initialize pagination for upcoming tasks
  void _initializeUpcomingPagination(List<PatrolTask> allTasks) {
    // Sort berdasarkan assignedStartTime yang mendekati DateTime.now()
    final now = DateTime.now();
    allTasks.sort((a, b) {
      final aTime = a.assignedStartTime ?? DateTime(2099);
      final bTime = b.assignedStartTime ?? DateTime(2099);

      // Prioritas: tasks yang bisa dimulai sekarang (dalam 10 menit), kemudian yang terdekat
      final aCanStart = aTime.difference(now).inMinutes <= 10;
      final bCanStart = bTime.difference(now).inMinutes <= 10;

      if (aCanStart && !bCanStart) return -1;
      if (!aCanStart && bCanStart) return 1;

      return aTime.compareTo(bTime);
    });

    _allUpcomingTasks = List.from(allTasks);

    // Show only preview limit initially
    _displayedUpcomingTasks = _allUpcomingTasks
        .take(
            _isUpcomingExpanded ? _upcomingItemsPerPage : _upcomingPreviewLimit)
        .toList();

    _upcomingCurrentPage = 0;
    _hasMoreUpcomingTasks =
        _allUpcomingTasks.length > _displayedUpcomingTasks.length;
    _isLoadingMoreUpcoming = false;

    // Update legacy list untuk backward compatibility
    _upcomingTasks = List.from(_displayedUpcomingTasks);

    print(
        'Initialized upcoming pagination: ${_displayedUpcomingTasks.length}/${_allUpcomingTasks.length} (expanded: $_isUpcomingExpanded)');
  }

  // TAMBAHAN: Initialize pagination for history tasks
  void _initializeHistoryPagination(List<PatrolTask> allTasks) {
    _allHistoryTasks = List.from(allTasks);
    _displayedHistoryTasks =
        _allHistoryTasks.take(_historyItemsPerPage).toList();
    _historyCurrentPage = 0;
    _hasMoreHistoryTasks = _allHistoryTasks.length > _historyItemsPerPage;
    _isLoadingMoreHistory = false;

    // Update legacy list untuk backward compatibility
    _historyTasks = List.from(_displayedHistoryTasks);

    print(
        'Initialized history pagination: ${_displayedHistoryTasks.length}/${_allHistoryTasks.length}');
  }

  // void _startRefreshTimer() {
  //   // PERBAIKAN: Cancel timer sebelumnya dan cek mounted
  //   _refreshTimer?.cancel();
  //   if (!mounted) return;

  //   _refreshTimer = Timer.periodic(const Duration(seconds: 300), (timer) {
  //     // PERBAIKAN: Cek mounted di dalam callback timer
  //     if (!mounted) {
  //       timer.cancel();
  //       return;
  //     }

  //     _loadUserData();

  //     // PERBAIKAN: Cek mounted sebelum show snackbar
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text(
  //             'Memperbarui data...',
  //             style: mediumTextStyle(color: Colors.white),
  //           ),
  //           backgroundColor: kbpBlue800,
  //           duration: const Duration(seconds: 1),
  //           behavior: SnackBarBehavior.floating,
  //           margin: const EdgeInsets.all(16),
  //           shape: RoundedRectangleBorder(
  //             borderRadius: BorderRadius.circular(8),
  //           ),
  //         ),
  //       );
  //     }
  //   });
  // }

  @override
  void dispose() {
    // PERBAIKAN: Proper cleanup di dispose
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _taskSubscription?.cancel();
    _taskSubscription = null;
    // _lifecycleListener.dispose();
    super.dispose();
  }

  // PERBAIKAN: Safe setState wrapper
  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  void _toggleOfficerExpanded(String officerId) {
    _safeSetState(() {
      if (_expandedOfficers.contains(officerId)) {
        _expandedOfficers.remove(officerId);
      } else {
        _expandedOfficers.add(officerId);
      }
    });
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    _safeSetState(() {
      _isLoading = true;
    });

    try {
      _currentUser = authState.user;

      if (_currentUser!.role == 'patrol') {
        await _loadClusterOfficerTasks();
        if (!mounted) return;
        await _checkForExpiredTasks();
      } else {
        if (!mounted) return;

        context
            .read<PatrolBloc>()
            .add(LoadPatrolHistory(userId: _currentUser!.id));

        final currentTask = await context
            .read<PatrolBloc>()
            .repository
            .getCurrentTask(_currentUser!.id);

        if (!mounted) return;

        if (currentTask != null) {
          final now = DateTime.now();
          if (currentTask.status == 'active' &&
              currentTask.assignedEndTime != null &&
              now.isAfter(currentTask.assignedEndTime!)) {
            await _markTaskAsExpired(currentTask);
          } else {
            if (mounted) {
              context
                  .read<PatrolBloc>()
                  .add(UpdateCurrentTask(task: currentTask));

              if (currentTask.status == 'ongoing' ||
                  currentTask.status == 'in_progress' ||
                  currentTask.status == 'active') {
                context.read<PatrolBloc>().add(ResumePatrol(
                      task: currentTask,
                      startTime: currentTask.startTime ?? DateTime.now(),
                      currentDistance: currentTask.distance ?? 0.0,
                    ));
              }
            }
          }
        }

        if (mounted) {
          _startTaskStream();
        }
      }
    } catch (e, stack) {
      print('Error in _loadUserData: $e');
      print('Stack trace: $stack');
    } finally {
      _safeSetState(() {
        _isLoading = false;
      });
    }
  }

  // PERBAIKAN: Check expired tasks dengan mounted check
  Future<void> _checkForExpiredTasks() async {
    if (!mounted || _currentUser?.role != 'patrol') return;

    final now = DateTime.now();
    List<PatrolTask> expiredTasks = [];

    // Loop semua upcoming tasks untuk mencari yang sudah expired
    for (final task in _upcomingTasks) {
      if (task.status == 'active' &&
          task.assignedEndTime != null &&
          now.isAfter(task.assignedEndTime!) &&
          task.startTime == null) {
        // Tambahkan ke list expired
        expiredTasks.add(task);

        // Update status di database
        try {
          if (!mounted) return;

          await context.read<PatrolBloc>().repository.updateTask(
            task.taskId,
            {
              'status': 'expired',
              'expiredAt': now.toIso8601String(),
            },
          );

          // Kirim notifikasi ke command center
          await sendPushNotificationToCommandCenter(
            title: 'Petugas Tidak Melakukan Patroli',
            body:
                'Petugas ${task.officerName} telah melewati batas waktu tugas',
          );
        } catch (e) {
          print('Error updating expired task: $e');
        }
      }
    }

    // Refresh task list jika ada yang expired
    if (expiredTasks.isNotEmpty && mounted) {
      await _loadClusterOfficerTasks();
    }
  }

  // PERBAIKAN: Mark task as expired dengan mounted check
  Future<void> _markTaskAsExpired(PatrolTask task) async {
    if (!mounted) return;

    final now = DateTime.now();

    try {
      // Update status di database
      await context.read<PatrolBloc>().repository.updateTask(
        task.taskId,
        {
          'status': 'expired',
          'expiredAt': now.toIso8601String(),
        },
      );

      if (!mounted) return;

      // Update task di bloc
      final updatedTask = task.copyWith(status: 'expired');
      context.read<PatrolBloc>().add(UpdateCurrentTask(task: updatedTask));

      // Show notification to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tugas patroli telah melewati batas waktu dan tidak dapat dimulai',
              style: mediumTextStyle(color: Colors.white),
            ),
            backgroundColor: dangerR500,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('Error marking task as expired: $e');
    }
  }

  Future<void> _loadClusterOfficerTasks() async {
    if (!mounted || _currentUser == null) {
      return;
    }

    try {
      // TAMBAHAN: Reset pagination saat load fresh data
      _resetPaginationData();

      final clusterId = _currentUser!.id;

      final officerSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users/$clusterId/officers')
          .get();

      if (!mounted) return;

      if (!officerSnapshot.exists) {
        _safeSetState(() {
          _initializeOngoingPagination([]);
          _initializeUpcomingPagination([]);
          _initializeHistoryPagination([]);
          _isLoading = false;
        });
        return;
      }

      // ... existing officer parsing code ...
      Map<dynamic, dynamic> officersData;
      if (officerSnapshot.value is Map) {
        officersData = officerSnapshot.value as Map<dynamic, dynamic>;
      } else if (officerSnapshot.value is List) {
        final list = officerSnapshot.value as List;
        officersData = {};
        for (int i = 0; i < list.length; i++) {
          if (list[i] != null) {
            officersData[i.toString()] = list[i];
          }
        }
      } else {
        _safeSetState(() {
          _initializeOngoingPagination([]);
          _initializeUpcomingPagination([]);
          _initializeHistoryPagination([]);
          _isLoading = false;
        });
        return;
      }

      Map<String, Map<String, String>> officerInfo = {};

      try {
        if (officerSnapshot.value is List) {
          final officersList = List.from(
              (officerSnapshot.value as List).where((item) => item != null));

          for (var officer in officersList) {
            if (officer is Map) {
              final offId = officer['id']?.toString();
              if (offId != null && offId.isNotEmpty) {
                final name = officer['name']?.toString() ?? 'Unknown';
                final photoUrl = officer['photo_url']?.toString() ?? '';

                officerInfo[offId] = {
                  'name': name,
                  'photo_url': photoUrl,
                };
              }
            }
          }
        } else if (officerSnapshot.value is Map) {
          final officersData = officerSnapshot.value as Map<dynamic, dynamic>;
          officersData.forEach((offId, offData) {
            if (offData is Map) {
              final idKey = offData['id']?.toString() ?? offId.toString();
              final name = offData['name']?.toString() ?? 'Unknown';
              final photoUrl = offData['photo_url']?.toString() ?? '';

              officerInfo[idKey] = {
                'name': name,
                'photo_url': photoUrl,
              };
            }
          });
        }
      } catch (e) {
        print('Error parsing officer data: $e');
      }

      // PERBAIKAN: Limit query untuk performa yang lebih baik
      final taskSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('tasks')
          .orderByChild('clusterId')
          .equalTo(clusterId)
          .limitToLast(200) // Limit 200 tasks terbaru
          .get();

      if (!mounted) return;

      List<PatrolTask> allHistoryTasks = [];
      List<PatrolTask> allUpcomingTasks = [];
      List<PatrolTask> allOngoingTasks =
          []; // TAMBAHAN: List untuk ongoing tasks

      if (taskSnapshot.exists) {
        Map<dynamic, dynamic> tasksData;
        if (taskSnapshot.value is Map) {
          tasksData = taskSnapshot.value as Map<dynamic, dynamic>;
        } else {
          _safeSetState(() {
            _initializeOngoingPagination([]);
            _initializeUpcomingPagination([]);
            _initializeHistoryPagination([]);
            _isLoading = false;
          });
          return;
        }

        // PERBAIKAN: Process tasks dengan batching untuk menghindari blocking UI
        int processedCount = 0;
        const batchSize = 50;

        for (var entry in tasksData.entries) {
          final taskId = entry.key;
          final taskData = entry.value;

          if (taskData is Map) {
            try {
              final userId = taskData['userId']?.toString() ?? '';
              final status = taskData['status']?.toString() ?? 'unknown';

              final task = PatrolTask(
                taskId: taskId,
                userId: userId,
                status: status,
                assignedStartTime:
                    _parseDateTime(taskData['assignedStartTime']),
                assignedEndTime: _parseDateTime(taskData['assignedEndTime']),
                startTime: _parseDateTime(taskData['startTime']),
                endTime: _parseDateTime(taskData['endTime']),
                distance: taskData['distance'] != null
                    ? (taskData['distance'] as num).toDouble()
                    : null,
                createdAt:
                    _parseDateTime(taskData['createdAt']) ?? DateTime.now(),
                assignedRoute: taskData['assigned_route'] != null
                    ? (taskData['assigned_route'] as List)
                        .map((point) => (point as List)
                            .map((coord) => (coord as num).toDouble())
                            .toList())
                        .toList()
                    : null,
                routePath: taskData['route_path'] != null
                    ? Map<String, dynamic>.from(taskData['route_path'] as Map)
                    : null,
                clusterId: taskData['clusterId'].toString(),
                mockLocationDetected: taskData['mockLocationDetected'] == true,
                mockLocationCount: taskData['mockLocationCount'] is num
                    ? (taskData['mockLocationCount'] as num).toInt()
                    : 0,
              );

              // Set officer info if available
              if (officerInfo.containsKey(userId)) {
                task.officerName = officerInfo[userId]!['name'].toString();
                task.officerPhotoUrl =
                    officerInfo[userId]!['photo_url'].toString();
              }

              // PERBAIKAN: Categorize tasks dengan lebih spesifik
              if (status.toLowerCase() == 'finished' ||
                  status.toLowerCase() == 'completed' ||
                  status.toLowerCase() == 'cancelled' ||
                  status.toLowerCase() == 'expired') {
                allHistoryTasks.add(task);
              } else if (status.toLowerCase() == 'ongoing' ||
                  status.toLowerCase() == 'in_progress') {
                // TAMBAHAN: Pisahkan ongoing dari upcoming
                allOngoingTasks.add(task);
              } else if (status.toLowerCase() == 'active') {
                allUpcomingTasks.add(task);
              }

              processedCount++;

              // TAMBAHAN: Yield control setiap batch untuk tidak blocking UI
              if (processedCount % batchSize == 0) {
                await Future.delayed(Duration.zero); // Yield control
                if (!mounted) return; // Check if still mounted
              }
            } catch (e, stack) {
              print('Error parsing task $taskId: $e');
            }
          }
        }
      }

      if (!mounted) return;

      // Sort tasks
      allHistoryTasks.sort((a, b) =>
          (b.endTime ?? DateTime.now()).compareTo(a.endTime ?? DateTime.now()));

      allUpcomingTasks.sort((a, b) => (a.assignedStartTime ?? DateTime.now())
          .compareTo(b.assignedStartTime ?? DateTime.now()));

      // TAMBAHAN: Sort ongoing tasks by start time
      allOngoingTasks.sort((a, b) => (a.startTime ?? DateTime.now())
          .compareTo(b.startTime ?? DateTime.now()));

      // TAMBAHAN: Initialize pagination dengan data yang sudah diurutkan
      _safeSetState(() {
        _initializeOngoingPagination(allOngoingTasks);
        _initializeUpcomingPagination(allUpcomingTasks);
        _initializeHistoryPagination(allHistoryTasks);
        _isLoading = false;
      });

      print(
          'Loaded total: ${allOngoingTasks.length} ongoing, ${allUpcomingTasks.length} upcoming, ${allHistoryTasks.length} history');
    } catch (e, stack) {
      print('Error in _loadClusterOfficerTasks: $e');
      print('Stack trace: $stack');

      _safeSetState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildOngoingPatrolsContent() {
    if (_displayedOngoingTasks.isEmpty && !_isLoadingMoreOngoing) {
      return const SizedBox.shrink(); // Don't show anything if no ongoing tasks
    }

    final Map<String, List<PatrolTask>> tasksByOfficer = {};

    for (final task in _displayedOngoingTasks) {
      if (!tasksByOfficer.containsKey(task.userId)) {
        tasksByOfficer[task.userId] = [];
      }
      tasksByOfficer[task.userId]!.add(task);
    }

    final sortedOfficerIds = tasksByOfficer.keys.toList()
      ..sort((a, b) {
        final taskA = tasksByOfficer[a]!.first;
        final taskB = tasksByOfficer[b]!.first;
        return taskA.officerName.compareTo(taskB.officerName);
      });

    return Column(
      children: [
        // TAMBAHAN: Info pagination untuk ongoing tasks
        if (_displayedOngoingTasks.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: successG50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: successG200),
            ),
            child: Row(
              children: [
                Icon(Icons.play_circle, size: 14, color: successG400),
                const SizedBox(width: 8),
                Text(
                  'Tolong selesaikan tugas patroli ini terlebih dahulu',
                  style: mediumTextStyle(size: 12, color: successG500),
                ),
                if (_hasMoreOngoingTasks) ...[
                  const Spacer(),
                  Icon(Icons.keyboard_arrow_down, size: 14, color: successG400),
                ],
              ],
            ),
          ),

        // Task list
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sortedOfficerIds.length,
          itemBuilder: (context, index) {
            final officerId = sortedOfficerIds[index];
            final officerTasks = tasksByOfficer[officerId]!;

            final officerName = officerTasks.first.officerName;
            final officerPhotoUrl = officerTasks.first.officerPhotoUrl;

            officerTasks.sort((a, b) => (a.startTime ?? DateTime.now())
                .compareTo(b.startTime ?? DateTime.now()));

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: successG400, width: 2),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      successG50,
                      Colors.white,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Officer header dengan status ongoing
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          // Animated pulse container for ongoing indicator
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: successG100,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: successG400, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: successG300.withOpacity(0.3),
                                  blurRadius: 8,
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(22),
                                  child: officerPhotoUrl.isNotEmpty
                                      ? Image.network(
                                          officerPhotoUrl,
                                          width: 44,
                                          height: 44,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                            return Center(
                                              child: Text(
                                                officerName
                                                    .substring(0, 1)
                                                    .toUpperCase(),
                                                style: semiBoldTextStyle(
                                                    size: 18,
                                                    color: successG500),
                                              ),
                                            );
                                          },
                                        )
                                      : Center(
                                          child: Text(
                                            officerName
                                                .substring(0, 1)
                                                .toUpperCase(),
                                            style: semiBoldTextStyle(
                                                size: 18, color: successG500),
                                          ),
                                        ),
                                ),
                                // Pulse indicator
                                Positioned(
                                  bottom: -1,
                                  right: -1,
                                  child: Container(
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: successG500,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    // Animated dot indicator
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: successG500,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        officerName,
                                        style: semiBoldTextStyle(
                                            size: 16, color: successG500),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: successG500,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.play_circle,
                                              size: 12, color: Colors.white),
                                          const SizedBox(width: 4),
                                          Text(
                                            'SEDANG PATROLI',
                                            style: boldTextStyle(
                                                size: 10, color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${officerTasks.length} tugas berlangsung',
                                      style: regularTextStyle(
                                          size: 12, color: successG500),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 1, color: successG200),

                    // Always show all ongoing tasks (no expand/collapse for ongoing)
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: officerTasks.length,
                      itemBuilder: (context, taskIndex) {
                        return _buildOngoingTaskItem(officerTasks[taskIndex]);
                      },
                    ),
                    8.height,
                  ],
                ),
              ),
            );
          },
        ),

        // TAMBAHAN: Load more button untuk ongoing tasks
        if (_hasMoreOngoingTasks || _isLoadingMoreOngoing) ...[
          const SizedBox(height: 16),
          if (_isLoadingMoreOngoing)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: successG400,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Memuat patroli lainnya...',
                    style: mediumTextStyle(size: 14, color: successG400),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loadMoreOngoingTasks,
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text('Lihat ${_ongoingItemsPerPage} Patroli Lagi'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: successG500,
                  side: BorderSide(color: successG400, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildOngoingTaskItem(PatrolTask task) {
    final startTime = task.startTime ?? DateTime.now();
    final currentTime = DateTime.now();
    final elapsedDuration = currentTime.difference(startTime);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: successG200),
        boxShadow: [
          BoxShadow(
            color: successG100.withOpacity(0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Live indicator
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [successG400, successG400],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.navigation,
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: successG500,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'LIVE',
                            style: boldTextStyle(size: 10, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Patroli sedang berlangsung',
                            style:
                                semiBoldTextStyle(size: 14, color: successG500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.place, size: 14, color: successG400),
                        const SizedBox(width: 4),
                        Text(
                          "${task.assignedRoute?.length ?? 0} Titik Patroli",
                          style: regularTextStyle(size: 12, color: successG500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.timer, size: 14, color: successG400),
                        const SizedBox(width: 4),
                        Text(
                          'Berlangsung ${_formatDuration(elapsedDuration)}',
                          style: regularTextStyle(size: 12, color: successG500),
                        ),
                      ],
                    ),
                    if (task.distance != null && task.distance! > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.straighten,
                              size: 14, color: successG400),
                          const SizedBox(width: 4),
                          Text(
                            'Jarak: ${(task.distance! / 1000).toStringAsFixed(2)} km',
                            style:
                                regularTextStyle(size: 12, color: successG500),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Time info
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: successG100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      formatDateFromString(startTime.toString()),
                      style: mediumTextStyle(size: 10, color: successG500),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatTimeFromString(startTime.toString()),
                    style: semiBoldTextStyle(size: 12, color: successG500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dimulai',
                    style: regularTextStyle(size: 10, color: successG400),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MapScreen(
                          task: task,
                          onStart: () {
                            // Task already started
                          },
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map, size: 16),
                  label: Text(
                    'Lanjutkan Patroli',
                    style: mediumTextStyle(size: 12, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: successG400,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showTaskDialog(task),
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: Text(
                    'Detail',
                    style: mediumTextStyle(size: 12, color: successG500),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: successG500,
                    side: BorderSide(color: successG400, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // PERBAIKAN: Start task stream dengan proper cleanup
  void _startTaskStream() {
    // PERBAIKAN: Cancel existing subscription sebelum buat yang baru
    _taskSubscription?.cancel();

    if (!mounted) return;

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      return;
    }

    final userId = authState.user.id;

    if (authState.user.role == 'patrol') {
      return;
    }

    _taskSubscription =
        context.read<PatrolBloc>().repository.watchCurrentTask(userId).listen(
      (task) {
        // PERBAIKAN: Cek mounted di dalam callback stream
        if (task != null && mounted) {
          _handleNewTask(task);
        }
      },
      onError: (error) {
        print('Task stream error: $error');
        _taskSubscription?.cancel();
        _taskSubscription = null;
      },
      onDone: () {
        print('Task stream completed');
        _taskSubscription = null;
      },
    );
  }

  void _handleNewTask(PatrolTask task) {
    if (!mounted) return;

    if (task.status == 'active') {
      _showTaskDialog(task);
    }
  }

  // PERBAIKAN: Tambahkan mounted check di refresh functions
  Future<PatrolTask?> _refreshTaskDataForSummary(
      PatrolTask originalTask) async {
    if (!mounted) return null;

    try {
      // Ambil data task langsung dari Firebase
      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('tasks')
          .child(originalTask.taskId)
          .get();

      if (!mounted || !snapshot.exists) return null;

      final data = snapshot.value as Map<dynamic, dynamic>;

      // Cek apakah ada finalReportPhotoUrl
      if (data.containsKey('finalReportPhotoUrl')) {
      } else {}

      // Konversi data ke PatrolTask
      final updatedTask = PatrolTask(
        taskId: originalTask.taskId,
        userId: data['userId']?.toString() ?? '',
        // vehicleId: data['vehicleId']?.toString() ?? '',
        status: data['status']?.toString() ?? '',
        assignedStartTime: _parseDateTime(data['assignedStartTime']),
        assignedEndTime: _parseDateTime(data['assignedEndTime']),
        startTime: _parseDateTime(data['startTime']),
        endTime: _parseDateTime(data['endTime']),
        distance: data['distance'] != null
            ? (data['distance'] as num).toDouble()
            : null,
        createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
        assignedRoute: data['assigned_route'] != null
            ? (data['assigned_route'] as List)
                .map((point) => (point as List)
                    .map((coord) => (coord as num).toDouble())
                    .toList())
                .toList()
            : null,
        routePath: data['route_path'] != null
            ? Map<String, dynamic>.from(data['route_path'] as Map)
            : null,
        clusterId: data['clusterId']?.toString() ?? '',
        // Tambahkan field baru yang dibutuhkan
        finalReportPhotoUrl: data['finalReportPhotoUrl']?.toString(),
        finalReportNote: data['finalReportNote']?.toString(),
        finalReportTime: _parseDateTime(data['finalReportTime']),
        initialReportPhotoUrl: data['initialReportPhotoUrl']?.toString(),
        initialReportNote: data['initialReportNote']?.toString(),
        initialReportTime: _parseDateTime(data['initialReportTime']),
      );

      // Set properti tambahan
      updatedTask.officerName = originalTask.officerName;
      updatedTask.officerPhotoUrl = originalTask.officerPhotoUrl;

      return updatedTask;
    } catch (e) {
      print('Error refreshing task data: $e');
      return null;
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours == 0 && minutes == 0) {
      return '0 Menit';
    }
    if (hours == 0) {
      return '${minutes} Menit';
    }
    if (minutes == 0) {
      return '${hours} Jam';
    }
    return '${hours} Jam ${minutes} Menit';
  }

  String getDurasiPatroli(
    DateTime startTime,
    DateTime endTime,
  ) {
    final duration = endTime.difference(startTime);
    if (duration.inHours <= 0) {
      return '${duration.inMinutes} Menit';
    } else if (duration.inMinutes.remainder(60) <= 0 && duration.inHours > 0) {
      return '${duration.inHours} Jam';
    } else {
      return '${duration.inHours} Jam ${duration.inMinutes.remainder(60)} Menit';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutral200,
      appBar: AppBar(
        title: Text(
          'Patrol Dashboard',
          style: semiBoldTextStyle(size: 18, color: Colors.white),
        ),
        backgroundColor: kbpBlue900,
        automaticallyImplyLeading: false,
        centerTitle: true,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh,
              color: neutralWhite,
            ),
            onPressed: () {
              _loadUserData();
              _startTaskStream();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Memperbarui data...',
                      style: mediumTextStyle(color: Colors.white),
                    ),
                    backgroundColor: kbpBlue800,
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (mounted) {
            _loadUserData();
            _startTaskStream();
          }
        },
        color: kbpBlue900,
        child: _isLoading
            ? Center(
                child: lottie.LottieBuilder.asset(
                  'assets/lottie/maps_loading.json',
                  width: 200,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildUserGreetingCard(),
                    const SizedBox(height: 24),

                    // TAMBAHAN: Ongoing patrols section - hanya tampil jika ada ongoing tasks
                    if (_currentUser?.role == 'patrol' &&
                        _displayedOngoingTasks.isNotEmpty) ...[
                      _buildSectionHeader(
                        icon: Icons.play_circle,
                        title: 'Patroli Sedang Berlangsung',
                        color: successG500,
                      ),
                      const SizedBox(height: 12),
                      _buildOngoingPatrolsContent(),
                      const SizedBox(height: 24),
                    ],

                    _buildSectionHeader(
                      icon: Icons.access_time,
                      title: 'Patroli Mendatang',
                    ),
                    const SizedBox(height: 12),
                    _currentUser?.role == 'patrol'
                        ? _buildUpcomingPatrolsContent()
                        : _buildUpcomingPatrolsForOfficer(),
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                      icon: Icons.history,
                      title: 'Riwayat Patroli',
                    ),
                    const SizedBox(height: 12),
                    _currentUser?.role == 'patrol'
                        ? _buildHistoryContent()
                        : _buildPatrolHistoryForOfficer(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSectionHeader(
      {required IconData icon, required String title, Color? color}) {
    final iconColor = color ?? kbpBlue900;
    return Row(
      children: [
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: semiBoldTextStyle(size: 18, color: iconColor),
        ),
      ],
    );
  }

  Widget _buildUserGreetingCard() {
    final now = DateTime.now();
    String greeting;

    if (now.hour < 12) {
      greeting = 'Selamat Pagi';
    } else if (now.hour < 17) {
      greeting = 'Selamat Siang';
    } else if (now.hour < 20) {
      greeting = 'Selamat Sore';
    } else {
      greeting = 'Selamat Malam';
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: kbpBlue50,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: kbpBlue900,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _currentUser?.role == 'patrol' ? Icons.group : Icons.person,
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
                    greeting,
                    style: regularTextStyle(size: 14, color: kbpBlue800),
                  ),
                  Text(
                    _currentUser?.name ?? 'User',
                    style: semiBoldTextStyle(size: 18, color: kbpBlue900),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _currentUser?.role == 'patrol'
                        ? 'Petugas Patroli'
                        : 'Command Center',
                    style: regularTextStyle(size: 14, color: kbpBlue700),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${now.day}/${now.month}/${now.year}',
                    style: mediumTextStyle(size: 14, color: kbpBlue900),
                  ),
                  Text(
                    '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                    style: boldTextStyle(size: 16, color: kbpBlue900),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

// Consistent empty state card with fixed height
  Widget _buildEmptyStateCard({required String icon, required String message}) {
    return SizedBox(
      width: double.infinity,
      // height: 180,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: neutral400, width: 1),
        ),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                icon,
                height: 80,
                width: 80,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: mediumTextStyle(size: 14, color: neutral700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Widget _buildUpcomingPatrolsContent() {
  //   if (_displayedUpcomingTasks.isEmpty && !_isLoadingMoreUpcoming) {
  //     return _buildEmptyStateCard(
  //       icon: 'assets/state/noTask.svg',
  //       message: 'Belum ada tugas patroli\nyang dijadwalkan',
  //     );
  //   }

  //   final Map<String, List<PatrolTask>> tasksByOfficer = {};

  //   for (final task in _displayedUpcomingTasks) {
  //     if (!tasksByOfficer.containsKey(task.userId)) {
  //       tasksByOfficer[task.userId] = [];
  //     }
  //     tasksByOfficer[task.userId]!.add(task);
  //   }

  //   final sortedOfficerIds = tasksByOfficer.keys.toList()
  //     ..sort((a, b) {
  //       final taskA = tasksByOfficer[a]!.first;
  //       final taskB = tasksByOfficer[b]!.first;
  //       return taskA.officerName.compareTo(taskB.officerName);
  //     });

  //   return Column(
  //     children: [
  //       // TAMBAHAN: Info pagination untuk upcoming tasks
  //       if (_displayedUpcomingTasks.isNotEmpty)
  //         Container(
  //           width: double.infinity,
  //           padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  //           margin: const EdgeInsets.only(bottom: 12),
  //           decoration: BoxDecoration(
  //             color: kbpBlue50,
  //             borderRadius: BorderRadius.circular(8),
  //             border: Border.all(color: kbpBlue200),
  //           ),
  //           child: Row(
  //             children: [
  //               Icon(Icons.info_outline, size: 14, color: kbpBlue600),
  //               const SizedBox(width: 8),
  //               Text(
  //                 'Menampilkan ${_displayedUpcomingTasks.length} dari ${_allUpcomingTasks.length} tugas mendatang',
  //                 style: mediumTextStyle(size: 12, color: kbpBlue700),
  //               ),
  //               if (_hasMoreUpcomingTasks) ...[
  //                 const Spacer(),
  //                 Icon(Icons.keyboard_arrow_down, size: 14, color: kbpBlue600),
  //               ],
  //             ],
  //           ),
  //         ),

  //       // Task list
  //       ListView.builder(
  //         shrinkWrap: true,
  //         physics: const NeverScrollableScrollPhysics(),
  //         itemCount: sortedOfficerIds.length,
  //         itemBuilder: (context, index) {
  //           final officerId = sortedOfficerIds[index];
  //           final officerTasks = tasksByOfficer[officerId]!;

  //           final officerName = officerTasks.first.officerName;
  //           final officerPhotoUrl = officerTasks.first.officerPhotoUrl;

  //           officerTasks.sort((a, b) => (a.assignedStartTime ?? DateTime.now())
  //               .compareTo(b.assignedStartTime ?? DateTime.now()));

  //           return Card(
  //             elevation: 0,
  //             margin: const EdgeInsets.only(bottom: 16),
  //             shape: RoundedRectangleBorder(
  //               borderRadius: BorderRadius.circular(12),
  //               side: const BorderSide(color: kbpBlue300, width: 1),
  //             ),
  //             child: Column(
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //                 // Officer header
  //                 Padding(
  //                   padding: const EdgeInsets.all(16.0),
  //                   child: Row(
  //                     children: [
  //                       Container(
  //                         width: 48,
  //                         height: 48,
  //                         clipBehavior: Clip.antiAlias,
  //                         decoration: BoxDecoration(
  //                           color: kbpBlue100,
  //                           borderRadius: BorderRadius.circular(24),
  //                           border: Border.all(color: kbpBlue300, width: 1),
  //                         ),
  //                         child: officerPhotoUrl.isNotEmpty
  //                             ? Image.network(
  //                                 officerPhotoUrl,
  //                                 fit: BoxFit.cover,
  //                                 errorBuilder: (context, error, stackTrace) {
  //                                   return Center(
  //                                     child: Text(
  //                                       officerName
  //                                           .substring(0, 1)
  //                                           .toUpperCase(),
  //                                       style: semiBoldTextStyle(
  //                                           size: 18, color: kbpBlue900),
  //                                     ),
  //                                   );
  //                                 },
  //                               )
  //                             : Center(
  //                                 child: Text(
  //                                   officerName.substring(0, 1).toUpperCase(),
  //                                   style: semiBoldTextStyle(
  //                                       size: 18, color: kbpBlue900),
  //                                 ),
  //                               ),
  //                       ),
  //                       const SizedBox(width: 12),
  //                       Expanded(
  //                         child: Column(
  //                           crossAxisAlignment: CrossAxisAlignment.start,
  //                           children: [
  //                             Text(
  //                               officerName,
  //                               style: semiBoldTextStyle(
  //                                   size: 16, color: kbpBlue900),
  //                               overflow: TextOverflow.ellipsis,
  //                             ),
  //                             Text(
  //                               '${officerTasks.length} tugas patroli mendatang',
  //                               style: regularTextStyle(
  //                                   size: 14, color: kbpBlue700),
  //                             ),
  //                           ],
  //                         ),
  //                       ),
  //                       IconButton(
  //                         icon: const Icon(
  //                           Icons.keyboard_arrow_down,
  //                           color: kbpBlue900,
  //                         ),
  //                         onPressed: () {
  //                           _toggleOfficerExpanded(officerId);
  //                         },
  //                       ),
  //                     ],
  //                   ),
  //                 ),

  //                 const Divider(height: 1, color: kbpBlue200),

  //                 _expandedOfficers.contains(officerId)
  //                     ? ListView.builder(
  //                         shrinkWrap: true,
  //                         physics: const NeverScrollableScrollPhysics(),
  //                         itemCount: officerTasks.length,
  //                         itemBuilder: (context, taskIndex) {
  //                           return _buildOfficerTaskItem(
  //                               officerTasks[taskIndex]);
  //                         },
  //                       )
  //                     : officerTasks.isNotEmpty
  //                         ? _buildOfficerTaskItem(officerTasks.first)
  //                         : const SizedBox.shrink(),

  //                 if (!_expandedOfficers.contains(officerId) &&
  //                     officerTasks.length > 1)
  //                   Padding(
  //                     padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
  //                     child: TextButton(
  //                       onPressed: () => _toggleOfficerExpanded(officerId),
  //                       style: TextButton.styleFrom(
  //                         foregroundColor: kbpBlue700,
  //                         padding: const EdgeInsets.symmetric(vertical: 8),
  //                         minimumSize: Size.zero,
  //                         tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  //                       ),
  //                       child: Row(
  //                         mainAxisAlignment: MainAxisAlignment.center,
  //                         children: [
  //                           Text(
  //                             'Lihat ${officerTasks.length - 1} tugas lainnya',
  //                             style:
  //                                 mediumTextStyle(size: 12, color: kbpBlue700),
  //                           ),
  //                           const SizedBox(width: 4),
  //                           const Icon(Icons.keyboard_arrow_down,
  //                               size: 16, color: kbpBlue700),
  //                         ],
  //                       ),
  //                     ),
  //                   ),
  //               ],
  //             ),
  //           );
  //         },
  //       ),

  //       // TAMBAHAN: Load more button untuk upcoming tasks
  //       if (_hasMoreUpcomingTasks || _isLoadingMoreUpcoming) ...[
  //         const SizedBox(height: 16),
  //         if (_isLoadingMoreUpcoming)
  //           Container(
  //             padding: const EdgeInsets.symmetric(vertical: 16),
  //             child: Row(
  //               mainAxisAlignment: MainAxisAlignment.center,
  //               children: [
  //                 SizedBox(
  //                   width: 16,
  //                   height: 16,
  //                   child: CircularProgressIndicator(
  //                     strokeWidth: 2,
  //                     color: kbpBlue600,
  //                   ),
  //                 ),
  //                 const SizedBox(width: 12),
  //                 Text(
  //                   'Memuat tugas lainnya...',
  //                   style: mediumTextStyle(size: 14, color: kbpBlue600),
  //                 ),
  //               ],
  //             ),
  //           )
  //         else
  //           SizedBox(
  //             width: double.infinity,
  //             child: OutlinedButton.icon(
  //               onPressed: _loadMoreUpcomingTasks,
  //               icon: const Icon(Icons.expand_more, size: 18),
  //               label: Text('Lihat ${_upcomingItemsPerPage} Tugas Lagi'),
  //               style: OutlinedButton.styleFrom(
  //                 foregroundColor: kbpBlue900,
  //                 side: BorderSide(color: kbpBlue300, width: 1.5),
  //                 shape: RoundedRectangleBorder(
  //                   borderRadius: BorderRadius.circular(8),
  //                 ),
  //                 padding:
  //                     const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  //               ),
  //             ),
  //           ),
  //       ],
  //     ],
  //   );
  // }

// Individual task item within officer group
  Widget _buildOfficerTaskItem(PatrolTask task) {
    return InkWell(
      onTap: () => _showTaskDialog(task),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Vehicle icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kbpBlue100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.directions_car,
                    color: kbpBlue900,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),

                // Task info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Text(
                      //   task.vehicleId.isEmpty
                      //       ? 'Tanpa Kendaraan'
                      //       : task.vehicleId,
                      //   style: mediumTextStyle(size: 14, color: kbpBlue900),
                      // ),
                      // const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.place, size: 14, color: kbpBlue700),
                          const SizedBox(width: 4),
                          Text(
                            "${task.assignedRoute?.length ?? 0} Titik Patroli",
                            style:
                                regularTextStyle(size: 12, color: kbpBlue700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          // Status patroli
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(task.status,
                                  assignedStartTime: task.assignedStartTime),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getStatusText(task.status,
                                  assignedStartTime: task.assignedStartTime),
                              style: mediumTextStyle(
                                  size: 10, color: Colors.white),
                            ),
                          ),

                          // Tambahkan status timeliness disini
                          if (task.timeliness != null)
                            Row(
                              children: [
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getTimelinessColor(task.timeliness),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _getTimelinessText(task.timeliness),
                                    style: mediumTextStyle(
                                        size: 10, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Date and time
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: kbpBlue100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        task.assignedStartTime != null
                            ? formatDateFromString(
                                task.assignedStartTime.toString())
                            : 'Tidak tersedia',
                        style: mediumTextStyle(size: 10, color: kbpBlue900),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.assignedStartTime != null
                          ? formatTimeFromString(
                              task.assignedStartTime.toString())
                          : 'Tidak tersedia',
                      style: mediumTextStyle(size: 12, color: kbpBlue900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.assignedStartTime != null &&
                              task.assignedEndTime != null
                          ? getDurasiPatroli(
                              task.assignedStartTime!, task.assignedEndTime!)
                          : 'Durasi tidak tersedia',
                      style: regularTextStyle(size: 10, color: kbpBlue700),
                    ),
                  ],
                ),
              ],
            ),

            // Action button
            Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: SizedBox(
                width: double.infinity,
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: () => _showTaskDialog(task),
                  icon: const Icon(Icons.map, size: 16),
                  label: Text(
                    'Lihat Detail',
                    style: mediumTextStyle(size: 12, color: neutralWhite),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kbpBlue900,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

// Perbaiki fungsi _getStatusText() untuk menangani kondisi "Belum dimulai"
  String _getStatusText(String status, {DateTime? assignedStartTime}) {
    // Kondisi khusus untuk status "Aktif" yang belum bisa dimulai
    if (status.toLowerCase() == 'active' && assignedStartTime != null) {
      final now = DateTime.now();
      final timeDifference = assignedStartTime.difference(now);

      // Jika waktu sekarang masih lebih dari 10 menit sebelum waktu mulai
      if (timeDifference.inMinutes > 10) {
        return 'Belum dimulai';
      }
    }

    // Logic yang sudah ada
    switch (status.toLowerCase()) {
      case 'active':
        return 'Aktif';
      case 'ongoing':
      case 'in_progress':
        return 'Sedang Berjalan';
      case 'finished':
        return 'Selesai';
      case 'expired':
        return 'Tidak Dilaksanakan';
      default:
        return status;
    }
  }

// Perbaiki fungsi _getStatusColor() untuk menangani kondisi "Belum dimulai"
  Color _getStatusColor(String status, {DateTime? assignedStartTime}) {
    // Kondisi khusus untuk status "Aktif" yang belum bisa dimulai
    if (status.toLowerCase() == 'active' && assignedStartTime != null) {
      final now = DateTime.now();
      final timeDifference = assignedStartTime.difference(now);

      // Jika waktu sekarang masih lebih dari 10 menit sebelum waktu mulai
      if (timeDifference.inMinutes > 10) {
        return neutral500; // Abu-abu untuk status belum bisa dimulai
      }
    }

    // Logic yang sudah ada
    switch (status.toLowerCase()) {
      case 'active':
        return kbpBlue700;
      case 'ongoing':
      case 'in_progress':
        return successG500;
      case 'finished':
        return neutral700;
      case 'expired':
        return dangerR500;
      default:
        return kbpBlue700;
    }
  }

  Color _getTimelinessColor(String? timeliness) {
    switch (timeliness?.toLowerCase()) {
      case 'ontime':
        return successG500;
      case 'late':
        return warningY500;
      case 'pastdue':
        return dangerR500;
      default:
        return neutral500;
    }
  }

  String _getTimelinessText(String? timeliness) {
    switch (timeliness?.toLowerCase()) {
      case 'ontime':
        return 'Tepat Waktu';
      case 'late':
        return timeliness!;
      case 'pastdue':
        return 'Melewati Batas';
      default:
        return 'Belum Dimulai';
    }
  }

// Wrapper for history content
  Widget _buildHistoryContent() {
    if (_displayedHistoryTasks.isEmpty && !_isLoadingMoreHistory) {
      return _buildEmptyStateCard(
        icon: 'assets/nodata.svg',
        message: 'Belum ada riwayat patroli',
      );
    }

    return Column(
      children: [
        // TAMBAHAN: Info pagination untuk history
        if (_displayedHistoryTasks.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: successG50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: successG200),
            ),
            child: Row(
              children: [
                Icon(Icons.history, size: 14, color: successG300),
                const SizedBox(width: 8),
                Text(
                  'Menampilkan ${_displayedHistoryTasks.length} dari ${_allHistoryTasks.length} riwayat',
                  style: mediumTextStyle(size: 12, color: successG400),
                ),
                if (_hasMoreHistoryTasks) ...[
                  const Spacer(),
                  Icon(Icons.keyboard_arrow_down, size: 14, color: successG500),
                ],
              ],
            ),
          ),

        // History list
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kbpBlue200, width: 1),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _displayedHistoryTasks.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, color: kbpBlue200),
                  itemBuilder: (context, index) {
                    final task = _displayedHistoryTasks[index];
                    return _buildHistoryItem(task);
                  },
                ),

                // TAMBAHAN: Load more section untuk history
                if (_hasMoreHistoryTasks || _isLoadingMoreHistory) ...[
                  const Divider(height: 1, color: kbpBlue200),
                  if (_isLoadingMoreHistory)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: kbpBlue600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Memuat riwayat lainnya...',
                            style: mediumTextStyle(size: 14, color: kbpBlue600),
                          ),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _loadMoreHistoryTasks,
                          icon: const Icon(Icons.expand_more, size: 16),
                          label: Text(
                              'Lihat ${_historyItemsPerPage} Riwayat Lagi'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: successG500,
                            side: BorderSide(color: successG300, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                        ),
                      ),
                    ),
                ],

                // Show "Lihat Semua" button only if there are more than displayed
                if (_allHistoryTasks.length > _displayedHistoryTasks.length &&
                    !_hasMoreHistoryTasks)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PatrolHistoryListScreen(
                              tasksList:
                                  _allHistoryTasks, // Pass all history tasks
                              isClusterView: _currentUser?.role == 'patrol',
                            ),
                          ),
                        );
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Lihat Semua Riwayat',
                            style: mediumTextStyle(color: kbpBlue900),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward,
                              size: 16, color: kbpBlue900),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(PatrolTask task) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kbpBlue200, width: 1),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vehicle icon - fixed size
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kbpBlue100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.directions_car,
                      color: kbpBlue900,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Task info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Text(
                        //   task.vehicleId.isEmpty
                        //       ? 'Tanpa Kendaraan'
                        //       : task.vehicleId,
                        //   style: semiBoldTextStyle(size: 16, color: kbpBlue900),
                        //   overflow: TextOverflow.ellipsis,
                        //   maxLines: 1,
                        // ),
                        // const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.person,
                                size: 16, color: kbpBlue700),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                task.officerName,
                                style: regularTextStyle(
                                    size: 14, color: kbpBlue700),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.place,
                                size: 16, color: kbpBlue700),
                            const SizedBox(width: 4),
                            Text(
                              "${task.assignedRoute?.length ?? 0} Titik Patroli",
                              style:
                                  regularTextStyle(size: 14, color: kbpBlue700),
                            ),
                          ],
                        ),

                        // Tambahkan status badges
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Status patroli
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(task.status,
                                    assignedStartTime: task.assignedStartTime),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getStatusText(task.status,
                                    assignedStartTime: task.assignedStartTime),
                                style: mediumTextStyle(
                                    size: 12, color: Colors.white),
                              ),
                            ),

                            // Status ketepatan waktu
                            if (task.timeliness != null)
                              Row(
                                children: [
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          _getTimelinessColor(task.timeliness),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _getTimelinessText(task.timeliness),
                                      style: mediumTextStyle(
                                          size: 12, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Date and time - fixed width for alignment
                  SizedBox(
                    width: 110,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: kbpBlue100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            task.assignedStartTime != null
                                ? formatDateFromString(
                                    task.assignedStartTime.toString())
                                : 'Tidak tersedia',
                            style: mediumTextStyle(size: 12, color: kbpBlue900),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          task.assignedStartTime != null
                              ? formatTimeFromString(
                                  task.assignedStartTime.toString())
                              : 'Tidak tersedia',
                          style: semiBoldTextStyle(size: 14, color: kbpBlue900),
                        ),
                        const Spacer(),
                        Text(
                          task.assignedStartTime != null &&
                                  task.assignedEndTime != null
                              ? getDurasiPatroli(task.assignedStartTime!,
                                  task.assignedEndTime!)
                              : 'Durasi tidak tersedia',
                          style: regularTextStyle(size: 12, color: kbpBlue700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () => _showTaskDialog(task),
                icon: const Icon(Icons.map, size: 18),
                label: Text(
                  'Lihat Detail',
                  style: semiBoldTextStyle(size: 14, color: neutralWhite),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kbpBlue900,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(PatrolTask task) {
    return Center(
      child: Text(
        task.officerName.substring(0, 1).toUpperCase(),
        style: semiBoldTextStyle(size: 16, color: kbpBlue900),
      ),
    );
  }

  Widget _buildHistoryItem(PatrolTask task) {
    final duration = task.endTime != null && task.startTime != null
        ? task.endTime!.difference(task.startTime!)
        : Duration.zero;

    return SizedBox(
      height: 90, // Tinggi sedikit ditambah untuk menampung badge
      child: InkWell(
        onTap: () => task.status.toLowerCase() == 'expired'
            ? _showExpiredTaskDetails(
                task) // Tambahkan fungsi khusus untuk detail task expired
            : _showPatrolSummary(task),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar section
              Container(
                width: 40,
                height: 40,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: kbpBlue100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kbpBlue200, width: 1),
                ),
                child: task.officerPhotoUrl.isNotEmpty
                    ? Image.network(
                        task.officerPhotoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildAvatarFallback(task);
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return _buildAvatarFallback(task);
                        },
                      )
                    : _buildAvatarFallback(task),
              ),
              const SizedBox(width: 12),

              // Task info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Officer & vehicle info
                    Row(
                      children: [
                        ...[
                          Expanded(
                            child: Text(
                              task.officerName,
                              style: semiBoldTextStyle(
                                  size: 14, color: kbpBlue900),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Text(
                        //   task.vehicleId.isEmpty
                        //       ? 'Tanpa Kendaraan'
                        //       : task.vehicleId,
                        //   style: mediumTextStyle(size: 12, color: kbpBlue700),
                        // ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Time & distance info (khusus task finished)
                    // Untuk expired, tampilkan info yang berbeda
                    task.status.toLowerCase() == 'expired'
                        ? Row(
                            children: [
                              const Icon(Icons.calendar_today,
                                  size: 14, color: dangerR500),
                              const SizedBox(width: 4),
                              Text(
                                task.assignedStartTime != null
                                    ? formatDateFromString(
                                        task.assignedStartTime.toString())
                                    : 'Tanggal tidak tersedia',
                                style: regularTextStyle(
                                    size: 12, color: dangerR500),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.access_time,
                                  size: 14, color: dangerR500),
                              const SizedBox(width: 4),
                              Text(
                                task.assignedStartTime != null
                                    ? formatTimeFromString(
                                        task.assignedStartTime.toString())
                                    : 'Jam tidak tersedia',
                                style: regularTextStyle(
                                    size: 12, color: dangerR500),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              const Icon(Icons.timer,
                                  size: 14, color: kbpBlue700),
                              const SizedBox(width: 4),
                              Text(
                                _formatDuration(duration),
                                style: regularTextStyle(size: 12),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.straighten,
                                  size: 14, color: kbpBlue700),
                              const SizedBox(width: 4),
                              Text(
                                '${((task.distance ?? 0) / 1000).toStringAsFixed(2)} km',
                                style: regularTextStyle(size: 12),
                              ),
                            ],
                          ),

                    // Status badge
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _getStatusColor(task.status),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _getStatusText(task.status),
                          style: mediumTextStyle(size: 10, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // View button - fixed size
              Container(
                width: 40,
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.navigate_next, color: kbpBlue900),
                  onPressed: () => task.status.toLowerCase() == 'expired'
                      ? _showExpiredTaskDetails(task)
                      : _showPatrolSummary(task),
                  tooltip: 'Lihat Detail',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                  iconSize: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTaskDialog(PatrolTask task) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => TaskDetailDialog(
        task: task,
        onStart: () => _navigateToMap(task),
      ),
    );
  }

  void _navigateToMap(PatrolTask task) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          task: task,
          onStart: () {
            context.read<PatrolBloc>().add(StartPatrol(
                  task: task,
                  startTime: DateTime.now(),
                ));
          },
        ),
      ),
    );
  }

  // Perbaiki fungsi _showPatrolSummary untuk memastikan finalReportPhotoUrl diambil dengan benar
  void _showPatrolSummary(PatrolTask task) {
    try {
      List<List<double>> convertedPath = [];

      if (task.routePath != null && task.routePath is Map) {
        final map = task.routePath as Map;

        // Sort entries by timestamp
        final sortedEntries = map.entries.toList()
          ..sort((a, b) => (a.value['timestamp'] as String)
              .compareTo(b.value['timestamp'] as String));

        // Convert coordinates - KEEP SAME ORDER as MapScreen
        convertedPath = sortedEntries.map((entry) {
          final coordinates = entry.value['coordinates'] as List;
          return [
            (coordinates[0] as num).toDouble(), // latitude comes first
            (coordinates[1] as num).toDouble(), // longitude comes second
          ];
        }).toList();

        if (convertedPath.isNotEmpty) {}
      }

      if (convertedPath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No route data available')),
        );
        return;
      }

      // PERBAIKAN: Tampilkan debug info dan ambil data finalReportPhotoUrl dari database secara langsung jika null
      log('photo url summary: ${task.finalReportPhotoUrl}');

      // PERBAIKAN: Refresh task dari database untuk memastikan data terbaru
      _refreshTaskDataForSummary(task).then((updatedTask) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PatrolSummaryScreen(
              task:
                  updatedTask ?? task, // Gunakan data yang diperbarui jika ada
              routePath: convertedPath,
              startTime:
                  updatedTask?.startTime ?? task.startTime ?? DateTime.now(),
              endTime: updatedTask?.endTime ?? task.endTime ?? DateTime.now(),
              distance: updatedTask?.distance ?? task.distance ?? 0,
              finalReportPhotoUrl:
                  updatedTask?.finalReportPhotoUrl ?? task.finalReportPhotoUrl,
              initialReportPhotoUrl: updatedTask?.initialReportPhotoUrl ??
                  task.initialReportPhotoUrl,
            ),
          ),
        );
      });
    } catch (e, stackTrace) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading patrol summary: $e')),
      );
    }
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    try {
      if (value is String) {
        if (value.contains('.')) {
          final parts = value.split('.');
          final mainPart = parts[0];
          final microPart = parts[1];

          final cleanMicroPart =
              microPart.length > 6 ? microPart.substring(0, 6) : microPart;

          return DateTime.parse('$mainPart.$cleanMicroPart');
        }
        return DateTime.parse(value);
      } else if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
    } catch (e) {}
    return null;
  }

  void _showExpiredTaskDetails(PatrolTask task) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: kbpBlue900,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: dangerR300, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Patroli Tidak Dilaksanakan',
                      style: semiBoldTextStyle(size: 18, color: neutralWhite),
                    ),
                  ),
                ],
              ),
            ),

            // Content section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Officer info
                  _buildInfoRow(
                    'Petugas',
                    task.officerName,
                    Icons.person,
                    iconColor: kbpBlue700,
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: neutral300),
                  const SizedBox(height: 16),

                  // Vehicle info
                  // _buildInfoRow(
                  //   'Kendaraan',
                  //   task.vehicleId.isEmpty ? 'Tanpa Kendaraan' : task.vehicleId,
                  //   Icons.directions_car,
                  //   iconColor: kbpBlue700,
                  // ),
                  // const SizedBox(height: 16),
                  const Divider(height: 1, color: neutral300),
                  const SizedBox(height: 16),

                  // Schedule info
                  _buildInfoRow(
                    'Jadwal Patroli',
                    task.assignedStartTime != null
                        ? '${formatDateFromString(task.assignedStartTime.toString())} ${formatTimeFromString(task.assignedStartTime.toString())}'
                        : 'Tidak tersedia',
                    Icons.event,
                    iconColor: kbpBlue700,
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: neutral300),
                  const SizedBox(height: 16),

                  // Deadline info
                  _buildInfoRow(
                    'Batas Waktu',
                    task.assignedEndTime != null
                        ? '${formatDateFromString(task.assignedEndTime.toString())} ${formatTimeFromString(task.assignedEndTime.toString())}'
                        : 'Tidak tersedia',
                    Icons.timer_off,
                    iconColor: kbpBlue700,
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: neutral300),
                  const SizedBox(height: 16),

                  // Status info
                  _buildInfoRow(
                    'Status',
                    'Tidak Dilaksanakan',
                    Icons.highlight_off,
                    valueColor: dangerR500,
                    iconColor: dangerR500,
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: neutral300),
                  const SizedBox(height: 16),

                  // Expired time info
                  _buildInfoRow(
                    'Waktu Kedaluwarsa',
                    task.expiredAt != null
                        ? '${formatDateFromString(task.expiredAt.toString())} ${formatTimeFromString(task.expiredAt.toString())}'
                        : 'Tidak tercatat',
                    Icons.update,
                    valueColor: dangerR500,
                    iconColor: dangerR500,
                  ),
                ],
              ),
            ),

            // Footer section with buttons
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: neutral200,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kbpBlue900,
                      foregroundColor: neutralWhite,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Tutup',
                      style: mediumTextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

// Improve the info row to better match other dialogs
  Widget _buildInfoRow(String label, String value, IconData icon,
      {Color? valueColor, Color? iconColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (iconColor == dangerR500) ? dangerR100 : kbpBlue100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: iconColor ?? kbpBlue700),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: regularTextStyle(size: 13, color: neutral700),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style:
                    mediumTextStyle(size: 15, color: valueColor ?? kbpBlue900),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUpcomingPatrolsForOfficer() {
    return BlocBuilder<PatrolBloc, PatrolState>(
      builder: (context, state) {
        // Tambahkan log debug untuk state

        if (state is PatrolLoading) {
          return const SizedBox(
            height: 180,
            width: double.infinity,
            child: Center(
              child: CircularProgressIndicator(color: kbpBlue900),
            ),
          );
        }

        if (state is PatrolLoaded) {
          // Tambahkan log detail untuk memeriksa task

          if (state.task != null &&
              (state.task!.status == 'active' ||
                  state.task!.status == 'ongoing' ||
                  state.task!.status == 'in_progress')) {
            return _buildTaskCard(state.task!);
          }
        }

        return _buildEmptyStateCard(
          icon: 'assets/state/noTask.svg',
          message: 'Belum ada tugas patroli\nyang dijadwalkan',
        );
      },
    );
  }

  Widget _buildPatrolHistoryForOfficer() {
    return BlocBuilder<PatrolBloc, PatrolState>(
      builder: (context, state) {
        if (state is PatrolLoading) {
          return const SizedBox(
            height: 180,
            width: double.infinity,
            child: Center(
              child: CircularProgressIndicator(color: kbpBlue900),
            ),
          );
        }

        if (state is PatrolLoaded) {
          if (state.finishedTasks.isEmpty) {
            return _buildEmptyStateCard(
              icon: 'assets/nodata.svg',
              message: 'Belum ada riwayat patroli',
            );
          }

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: kbpBlue200, width: 1),
            ),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.finishedTasks.length > 5
                        ? 5
                        : state.finishedTasks.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1, color: kbpBlue200),
                    itemBuilder: (context, index) {
                      final task = state.finishedTasks[index];
                      return _buildHistoryItem(task);
                    },
                  ),
                  if (state.finishedTasks.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PatrolHistoryListScreen(
                                tasksList: _historyTasks,
                                isClusterView: _currentUser?.role == 'patrol',
                              ),
                            ),
                          );
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Lihat Semua Riwayat',
                              style: mediumTextStyle(color: kbpBlue900),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward,
                                size: 16, color: kbpBlue900),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        if (state is PatrolError) {
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: dangerR100,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: dangerR500),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gagal memuat riwayat',
                          style: semiBoldTextStyle(color: dangerR300),
                        ),
                        Text(
                          state.message,
                          style: regularTextStyle(size: 12, color: dangerR500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}
