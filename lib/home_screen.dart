import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:livetrackingapp/map_screen.dart';
import 'package:livetrackingapp/patrol_summary_screen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
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
  List<PatrolTask> _upcomingTasks = [];
  List<PatrolTask> _historyTasks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Improved _loadUserData

  Future<void> _loadUserData() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    setState(() {
      _isLoading = true;
    });

    try {
      _currentUser = authState.user;
      print(
          'Loading data for user: ${_currentUser!.id}, role: ${_currentUser!.role}');

      // Load patrol history
      if (_currentUser!.role == 'patrol') {
        // For cluster users, load tasks for their officers
        await _loadClusterOfficerTasks();
      } else {
        // For individual officers
        print('Loading patrol data for officer');

        // First check if there's an ongoing patrol
        final currentTask = await context
            .read<PatrolBloc>()
            .repository
            .getCurrentTask(_currentUser!.id);
        if (currentTask != null) {
          print(
              'Found current task: ${currentTask.taskId}, status: ${currentTask.status}');

          // Add the task to the bloc
          context.read<PatrolBloc>().add(UpdateCurrentTask(task: currentTask));

          // If the task is ongoing, update the state to reflect that
          if (currentTask.status == 'ongoing' ||
              currentTask.status == 'in_progress') {
            print('Task is ongoing - restoring patrol state');
            context.read<PatrolBloc>().add(ResumePatrol(
                  task: currentTask,
                  startTime: currentTask.startTime ?? DateTime.now(),
                  currentDistance: currentTask.distance ?? 0.0,
                ));
          }
        } else {
          print('No current task found');
        }

        // Load history tasks
        context
            .read<PatrolBloc>()
            .add(LoadPatrolHistory(userId: _currentUser!.id));

        // Start task stream to listen for new tasks
        _startTaskStream();
      }
    } catch (e, stack) {
      print('Error loading user data: $e');
      print('Stack trace: $stack');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

// Improved _loadClusterOfficerTasks for better status detection
  Future<void> _loadClusterOfficerTasks() async {
    if (_currentUser == null) {
      print('Current user is null');
      return;
    }

    try {
      final clusterId = _currentUser!.id;
      print('Loading tasks for cluster: $clusterId');

      // Get all officers in this cluster
      final officerSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users/$clusterId/officers')
          .get();

      if (!officerSnapshot.exists) {
        print('No officers found in cluster $clusterId');
        setState(() {
          _upcomingTasks = [];
          _historyTasks = [];
          _isLoading = false;
        });
        return;
      }

      // Parse officer data
      final officersData = officerSnapshot.value as Map<dynamic, dynamic>;
      Map<String, String> officerNames = {};

      // Create mapping of officer IDs to names
      officersData.forEach((offId, offData) {
        if (offData is Map && offData['name'] != null) {
          officerNames[offId.toString()] = offData['name'].toString();
        }
      });

      print('Found ${officerNames.length} officers in cluster');

      // Get all tasks for this cluster
      final taskSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('tasks')
          .orderByChild('clusterId')
          .equalTo(clusterId)
          .get();

      List<PatrolTask> allHistoryTasks = [];
      List<PatrolTask> allUpcomingTasks = [];

      if (taskSnapshot.exists) {
        final tasksData = taskSnapshot.value as Map<dynamic, dynamic>;
        print('Found ${tasksData.length} tasks for cluster');

        tasksData.forEach((taskId, taskData) {
          if (taskData is Map) {
            try {
              final userId = taskData['userId']?.toString() ?? '';
              String? officerName = officerNames[userId];
              String status = taskData['status']?.toString() ?? 'unknown';

              print(
                  'Processing task $taskId: status=$status, userId=$userId, officerName=$officerName');

              // Convert task data
              final task = PatrolTask(
                taskId: taskId,
                userId: userId,
                officerName: officerName,
                vehicleId: taskData['vehicleId']?.toString() ?? '',
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
              );

              // Important: Check for active AND ongoing status
              if (status == 'finished') {
                allHistoryTasks.add(task);
              } else if (status == 'active' ||
                  status == 'ongoing' ||
                  status == 'in_progress') {
                allUpcomingTasks.add(task);
              }
            } catch (e) {
              print('Error processing task $taskId: $e');
            }
          }
        });
      } else {
        print('No tasks found for cluster $clusterId');
      }

      // Sort tasks
      allHistoryTasks.sort((a, b) =>
          (b.endTime ?? DateTime.now()).compareTo(a.endTime ?? DateTime.now()));

      allUpcomingTasks.sort((a, b) => (a.assignedStartTime ?? DateTime.now())
          .compareTo(b.assignedStartTime ?? DateTime.now()));

      // Update state
      setState(() {
        _historyTasks = allHistoryTasks;
        _upcomingTasks = allUpcomingTasks;
        _isLoading = false;
      });

      print(
          'Loaded ${_upcomingTasks.length} upcoming and ${_historyTasks.length} history tasks');
    } catch (e, stack) {
      print('Error loading cluster officer tasks: $e');
      print('Stack trace: $stack');
      setState(() {
        _isLoading = false;
      });
    }
  }

// Helper method untuk parse DateTime
  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    try {
      if (value is String) {
        // Handle string with microseconds
        if (value.contains('.')) {
          final parts = value.split('.');
          final mainPart = parts[0];
          final microPart = parts[1];

          // Limit microseconds to 6 digits
          final cleanMicroPart =
              microPart.length > 6 ? microPart.substring(0, 6) : microPart;

          return DateTime.parse('$mainPart.$cleanMicroPart');
        }
        return DateTime.parse(value);
      } else if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
    } catch (e) {
      print('Error parsing datetime: $value, error: $e');
    }
    return null;
  }

  void _startTaskStream() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      print('User not authenticated');
      return;
    }

    final userId = authState.user.id;

    // If user is a cluster account, we don't need to watch individual tasks
    if (authState.user.role == 'patrol') {
      return;
    }

    _taskSubscription =
        context.read<PatrolBloc>().repository.watchCurrentTask(userId).listen(
      (task) {
        if (task != null && mounted) {
          _handleNewTask(task);
        }
      },
      onError: (error) {
        // stop the stream if there's an error
        _taskSubscription?.cancel();
        _taskSubscription = null;
      },
    );
  }

  void _handleNewTask(PatrolTask task) {
    // Add debugging output
    print('=== New Task Received ===');
    print('Task ID: ${task.taskId}');
    print('Status: ${task.status}');
    print('Assigned Start Time: ${task.assignedStartTime}');
    print('Assigned End Time: ${task.assignedEndTime}');

    // Only show dialog for active tasks that haven't started
    if (task.status == 'active') {
      _showTaskDialog(task);
    }
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
    Navigator.pop(context); // Close dialog first
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

  void _showPatrolSummary(PatrolTask task) {
    try {
      print('=== Converting Route Path ===');
      print('Original route path: ${task.routePath}');

      List<List<double>> convertedPath = [];

      if (task.routePath != null && task.routePath is Map) {
        final map = task.routePath as Map;

        // Sort entries by timestamp
        final sortedEntries = map.entries.toList()
          ..sort((a, b) => (a.value['timestamp'] as String)
              .compareTo(b.value['timestamp'] as String));

        print('Sorted entries count: ${sortedEntries.length}');

        // Convert coordinates - KEEP SAME ORDER as MapScreen
        convertedPath = sortedEntries.map((entry) {
          final coordinates = entry.value['coordinates'] as List;
          print('Processing coordinates: $coordinates');
          return [
            (coordinates[0] as num).toDouble(), // latitude comes first
            (coordinates[1] as num).toDouble(), // longitude comes second
          ];
        }).toList();

        if (convertedPath.isNotEmpty) {
          print('First point: ${convertedPath.first}');
          print('Last point: ${convertedPath.last}');
        }
      }

      if (convertedPath.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No route data available')),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PatrolSummaryScreen(
            task: task,
            routePath: convertedPath,
            startTime: task.startTime ?? DateTime.now(),
            endTime: task.endTime ?? DateTime.now(),
            distance: task.distance ?? 0,
          ),
        ),
      );
    } catch (e, stackTrace) {
      print('Error showing patrol summary: $e');
      print('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading patrol summary: $e')),
      );
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
  void dispose() {
    _taskSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Patrol Dashboard',
          style: boldTextStyle(size: 20, color: Colors.white),
        ),
        backgroundColor: kbpBlue900,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh,
              color: neutralWhite,
            ),
            onPressed: () {
              _loadUserData();
              _startTaskStream();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadUserData();
          _startTaskStream();
        },
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
                    // For clusters (patrol role), use local state data
                    if (_currentUser?.role == 'patrol')
                      _buildUpcomingPatrolsForCluster()
                    // For officers, use the Bloc state
                    else
                      _buildUpcomingPatrolsForOfficer(),

                    16.height,

                    // For clusters (patrol role), use local state data
                    if (_currentUser?.role == 'patrol')
                      _buildPatrolHistoryForCluster()
                    // For officers, use the Bloc state
                    else
                      _buildPatrolHistoryForOfficer(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildUpcomingPatrolsForCluster() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Patroli Mendatang',
          style: boldTextStyle(size: 20),
        ),
        8.height,
        if (_upcomingTasks.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: neutral500,
                width: 3,
              ),
              color: neutral300,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SvgPicture.asset(
                  'assets/state/noTask.svg',
                  height: 60,
                  width: 60,
                ),
                4.height,
                Text(
                  'Belum ada tugas patroli\nyang dijadwalkan',
                  textAlign: TextAlign.center,
                  style: regularTextStyle(),
                ),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _upcomingTasks.length,
            itemBuilder: (context, index) {
              final task = _upcomingTasks[index];
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: kbpBlue900,
                    width: 3,
                  ),
                  color: neutralWhite,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            rowInfo(task.vehicleId, task.vehicleId),
                            rowInfo("${task.assignedRoute?.length ?? 0} Titik",
                                "pin"),
                            // Add officer name
                            rowInfo("Petugas: ${task.officerName}", "people"),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            rowInfo(
                                task.assignedStartTime != null
                                    ? formatDateFromString(
                                        task.assignedStartTime.toString())
                                    : 'Tanggal tidak tersedia',
                                null),
                            Row(
                              children: [
                                rowInfo(
                                    task.assignedStartTime != null
                                        ? formatTimeFromString(
                                            task.assignedStartTime.toString())
                                        : 'Waktu tidak tersedia',
                                    null),
                                8.width,
                                rowInfo(
                                    task.assignedStartTime != null &&
                                            task.assignedEndTime != null
                                        ? getDurasiPatroli(
                                            task.assignedStartTime!,
                                            task.assignedEndTime!)
                                        : 'Durasi tidak tersedia',
                                    null),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    8.height,
                    ElevatedButton(
                      onPressed: () => _showTaskDialog(task),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kbpBlue900,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Lihat Detail',
                              style: semiBoldTextStyle(
                                size: 14,
                                color: neutralWhite,
                              ),
                            ),
                            4.width,
                            SvgPicture.asset(
                              'assets/map.svg',
                              height: 16,
                              width: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildUpcomingPatrolsForOfficer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Patroli Mendatang',
          style: boldTextStyle(size: 20),
        ),
        8.height,
        BlocBuilder<PatrolBloc, PatrolState>(
          builder: (context, state) {
            if (state is PatrolLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is PatrolLoaded && state.task != null) {
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: kbpBlue900,
                    width: 3,
                  ),
                  color: neutralWhite,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            rowInfo(
                                state.task!.vehicleId, state.task!.vehicleId),
                            rowInfo(
                                "${state.task!.assignedRoute?.length ?? 0} Titik",
                                "pin"),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            rowInfo(
                                state.task?.assignedStartTime != null
                                    ? formatDateFromString(state
                                        .task!.assignedStartTime
                                        .toString())
                                    : 'Tanggal tidak tersedia',
                                null),
                            Row(
                              children: [
                                rowInfo(
                                    state.task?.assignedStartTime != null
                                        ? formatTimeFromString(state
                                            .task!.assignedStartTime
                                            .toString())
                                        : 'Waktu tidak tersedia',
                                    null),
                                8.width,
                                rowInfo(
                                    state.task?.assignedStartTime != null &&
                                            state.task?.assignedEndTime != null
                                        ? getDurasiPatroli(
                                            state.task!.assignedStartTime!,
                                            state.task!.assignedEndTime!)
                                        : 'Durasi tidak tersedia',
                                    null),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    8.height,
                    ElevatedButton(
                      onPressed: () => _showTaskDialog(state.task!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kbpBlue900,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Lihat Detail',
                              style: semiBoldTextStyle(
                                size: 14,
                                color: neutralWhite,
                              ),
                            ),
                            4.width,
                            SvgPicture.asset(
                              'assets/map.svg',
                              height: 16,
                              width: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: neutral500,
                  width: 3,
                ),
                color: neutral300,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SvgPicture.asset(
                    'assets/state/noTask.svg',
                    height: 60,
                    width: 60,
                  ),
                  4.height,
                  Text(
                    'Belum ada tugas patroli\nyang dijadwalkan',
                    textAlign: TextAlign.center,
                    style: regularTextStyle(),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPatrolHistoryForCluster() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Riwayat Patroli', style: boldTextStyle(size: 20)),
        8.height,
        if (_historyTasks.isEmpty)
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: neutral500, width: 3),
                color: neutral300,
              ),
              child: Column(
                children: [
                  SvgPicture.asset(
                    'assets/nodata.svg',
                    height: 150,
                    width: 150,
                  ),
                  Text(
                    'Tidak ada riwayat patroli',
                    style: boldTextStyle(
                      size: 16,
                      color: neutral900,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            height: MediaQuery.of(context).size.height * 0.6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey),
              color: Colors.white,
            ),
            padding: const EdgeInsets.all(8),
            child: ListView.separated(
              itemCount: _historyTasks.length,
              separatorBuilder: (context, index) => 4.height,
              itemBuilder: (context, index) {
                final task = _historyTasks[index];
                final duration = task.endTime != null && task.startTime != null
                    ? task.endTime!.difference(task.startTime!)
                    : Duration.zero;

                return Container(
                  margin:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                    border: Border.all(
                      color: Colors.grey,
                      width: 1,
                    ),
                  ),
                  child: ListTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(formatDateFromString(task.createdAt.toString())),
                        Text('Petugas: ${task.officerName}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: kbpBlue900,
                              fontSize: 12,
                            )),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        rowInfo(task.vehicleId, task.vehicleId),
                        Text(
                            '${formatTimeFromString(task.startTime?.toString())} - ${formatTimeFromString(task.endTime?.toString())}'),
                        Text(
                            '${_formatDuration(duration)} ${((task.distance ?? 0) / 1000).toStringAsFixed(2)} km'),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.map),
                      onPressed: () => _showPatrolSummary(task),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildPatrolHistoryForOfficer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Riwayat Patroli', style: boldTextStyle(size: 20)),
        8.height,
        BlocBuilder<PatrolBloc, PatrolState>(
          builder: (context, state) {
            print('Building history with state: $state'); // Debug print

            if (state is PatrolLoading) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: lottie.LottieBuilder.asset(
                    'assets/lottie/maps_loading.json',
                    width: 200,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
              );
            }

            if (state is PatrolLoaded) {
              if (state.finishedTasks.isEmpty) {
                return Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: neutral500, width: 3),
                      color: neutral300,
                    ),
                    child: Column(
                      children: [
                        SvgPicture.asset(
                          'assets/nodata.svg',
                          height: 150,
                          width: 150,
                        ),
                        Text(
                          'Tidak ada riwayat patroli',
                          style: boldTextStyle(
                            size: 16,
                            color: neutral900,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Container(
                height: MediaQuery.of(context).size.height * 0.6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey),
                  color: Colors.white,
                ),
                padding: const EdgeInsets.all(8),
                child: ListView.separated(
                  itemCount: state.finishedTasks.length,
                  separatorBuilder: (context, index) => 4.height,
                  itemBuilder: (context, index) {
                    final task = state.finishedTasks[index];
                    final duration =
                        task.endTime != null && task.startTime != null
                            ? task.endTime!.difference(task.startTime!)
                            : Duration.zero;

                    return Container(
                      margin: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.grey,
                          width: 1,
                        ),
                      ),
                      child: ListTile(
                        title: rowInfo(
                            formatDateFromString(task.createdAt.toString()),
                            null),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            rowInfo(task.vehicleId, task.vehicleId),
                            Text(
                                '${formatTimeFromString(task.startTime?.toString())} - ${formatTimeFromString(task.endTime?.toString())}'),
                            Text(
                                '${_formatDuration(duration)} ${((task.distance ?? 0) / 1000).toStringAsFixed(2)} km'),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.map),
                          onPressed: () => _showPatrolSummary(task),
                        ),
                      ),
                    );
                  },
                ),
              );
            }

            if (state is PatrolError) {
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.error, color: dangerR300),
                  title: const Text('Error loading history'),
                  subtitle: Text(state.message),
                ),
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}
