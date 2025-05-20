import 'dart:async';
import 'dart:developer';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:livetrackingapp/map_screen.dart';
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
      Map<String, Map<String, String>> officerInfo = {};

      // Create mapping of officer IDs to info (name and photo)
      officersData.forEach((offId, offData) {
        if (offData is Map) {
          final name = offData['name']?.toString() ?? 'Unknown';
          final photoUrl = offData['photo_url']?.toString() ?? '';

          officerInfo[offId.toString()] = {
            'name': name,
            'photo_url': photoUrl,
          };

          print(
              'Officer: $offId, Name: $name, Has Photo: ${photoUrl.isNotEmpty}');
        }
      });

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
              final status = taskData['status']?.toString() ?? 'unknown';

              print('Processing task $taskId: status=$status, userId=$userId');

              // Convert task data
              final task = PatrolTask(
                taskId: taskId,
                userId: userId,
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

              // Set officer info if available from our map
              if (officerInfo.containsKey(userId)) {
                task.officerName = officerInfo[userId]!['name'].toString();
                task.officerPhotoUrl =
                    officerInfo[userId]!['photo_url'].toString();
                print(
                    'Set officer info for task $taskId: ${task.officerName}, photo: ${task.officerPhotoUrl?.isNotEmpty}');
              } else {
                print('No officer info found for userId: $userId');
              }

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

  // Perbaiki fungsi _showPatrolSummary untuk memastikan finalReportPhotoUrl diambil dengan benar
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
            ),
          ),
        );
      });
    } catch (e, stackTrace) {
      print('Error showing patrol summary: $e');
      print('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading patrol summary: $e')),
      );
    }
  }

// TAMBAHKAN: Fungsi baru untuk refresh data task langsung dari database
  Future<PatrolTask?> _refreshTaskDataForSummary(
      PatrolTask originalTask) async {
    try {
      // Ambil data task langsung dari Firebase
      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('tasks')
          .child(originalTask.taskId)
          .get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        print('Refreshed task data: $data');

        // Cek apakah ada finalReportPhotoUrl
        if (data.containsKey('finalReportPhotoUrl')) {
          print('Found finalReportPhotoUrl: ${data['finalReportPhotoUrl']}');
        } else {
          print('finalReportPhotoUrl not found in database');
        }

        // Konversi data ke PatrolTask
        final updatedTask = PatrolTask(
          taskId: originalTask.taskId,
          userId: data['userId']?.toString() ?? '',
          vehicleId: data['vehicleId']?.toString() ?? '',
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
        );

        // Set properti tambahan
        updatedTask.officerName = originalTask.officerName;
        updatedTask.officerPhotoUrl = originalTask.officerPhotoUrl;

        return updatedTask;
      }
    } catch (e) {
      print('Error refreshing task data: $e');
    }

    return null;
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

              // Show refresh feedback
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
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadUserData();
          _startTaskStream();
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
                    // User greeting card
                    _buildUserGreetingCard(),

                    const SizedBox(height: 24),

                    // Section title - Upcoming Patrols
                    _buildSectionHeader(
                      icon: Icons.access_time,
                      title: 'Patroli Mendatang',
                    ),

                    const SizedBox(height: 12),

                    // Upcoming patrols content
                    _currentUser?.role == 'patrol'
                        ? _buildUpcomingPatrolsContent()
                        : _buildUpcomingPatrolsForOfficer(),

                    const SizedBox(height: 24),

                    // Section title - History
                    _buildSectionHeader(
                      icon: Icons.history,
                      title: 'Riwayat Patroli',
                    ),

                    const SizedBox(height: 12),

                    // History content
                    _currentUser?.role == 'patrol'
                        ? _buildHistoryContent()
                        : _buildPatrolHistoryForOfficer(),

                    // Add some bottom padding
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

// Consistent section header widget
  Widget _buildSectionHeader({required IconData icon, required String title}) {
    return Row(
      children: [
        Icon(icon, color: kbpBlue900, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: semiBoldTextStyle(size: 18, color: kbpBlue900),
        ),
      ],
    );
  }

// User greeting card - consistent height and padding
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
                        ? 'Command Center'
                        : 'Petugas Patroli',
                    style: regularTextStyle(size: 14, color: kbpBlue700),
                  ),
                ],
              ),
            ),
            // Current date with fixed width for alignment
            Container(
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
    return Container(
      width: double.infinity,
      // height: 180,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: neutral400, width: 1),
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

// Wrapper for upcoming patrols content
  // Wrapper untuk menampilkan upcoming patrols content dikelompokkan berdasarkan officer
  Widget _buildUpcomingPatrolsContent() {
    if (_upcomingTasks.isEmpty) {
      return _buildEmptyStateCard(
        icon: 'assets/state/noTask.svg',
        message: 'Belum ada tugas patroli\nyang dijadwalkan',
      );
    }

    // Kelompokkan tugas berdasarkan officerId (userId)
    final Map<String, List<PatrolTask>> tasksByOfficer = {};

    // Populate map dengan task dikelompokkan berdasarkan officer
    for (final task in _upcomingTasks) {
      if (!tasksByOfficer.containsKey(task.userId)) {
        tasksByOfficer[task.userId] = [];
      }
      tasksByOfficer[task.userId]!.add(task);
    }

    // Sortir officers berdasarkan nama jika tersedia, atau userId jika tidak
    final sortedOfficerIds = tasksByOfficer.keys.toList()
      ..sort((a, b) {
        final taskA = tasksByOfficer[a]!.first;
        final taskB = tasksByOfficer[b]!.first;

        // Jika kedua officer memiliki nama, sortir berdasarkan nama
        if (taskA.officerName != null && taskB.officerName != null) {
          return taskA.officerName!.compareTo(taskB.officerName!);
        }
        // Jika hanya salah satu yang memiliki nama
        else if (taskA.officerName != null) {
          return -1; // A sebelum B
        } else if (taskB.officerName != null) {
          return 1; // B sebelum A
        }
        // Jika keduanya tidak memiliki nama, sortir berdasarkan userId
        return a.compareTo(b);
      });

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedOfficerIds.length,
      itemBuilder: (context, index) {
        final officerId = sortedOfficerIds[index];
        final officerTasks = tasksByOfficer[officerId]!;

        // Ambil nama officer dari task pertama
        final officerName = officerTasks.first.officerName ??
            'Petugas (ID: ${officerId.substring(0, 6)}...)';
        final officerPhotoUrl = officerTasks.first.officerPhotoUrl;

        // Sortir tugas untuk officer ini berdasarkan waktu mulai
        officerTasks.sort((a, b) => (a.assignedStartTime ?? DateTime.now())
            .compareTo(b.assignedStartTime ?? DateTime.now()));

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: kbpBlue300, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Officer header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    // Officer avatar
                    Container(
                      width: 48,
                      height: 48,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: kbpBlue100,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: kbpBlue300, width: 1),
                      ),
                      child: officerPhotoUrl != null &&
                              officerPhotoUrl.isNotEmpty
                          ? Image.network(
                              officerPhotoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Text(
                                    officerName.substring(0, 1).toUpperCase(),
                                    style: semiBoldTextStyle(
                                        size: 18, color: kbpBlue900),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Text(
                                officerName.substring(0, 1).toUpperCase(),
                                style: semiBoldTextStyle(
                                    size: 18, color: kbpBlue900),
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),

                    // Officer name and task count
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            officerName,
                            style:
                                semiBoldTextStyle(size: 16, color: kbpBlue900),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${officerTasks.length} tugas patroli mendatang',
                            style:
                                regularTextStyle(size: 14, color: kbpBlue700),
                          ),
                        ],
                      ),
                    ),

                    // Collapse/expand icon
                    IconButton(
                      icon: Icon(
                        Icons.keyboard_arrow_down,
                        color: kbpBlue900,
                      ),
                      onPressed: () {
                        // Implementasi expand/collapse jika dibutuhkan
                      },
                    ),
                  ],
                ),
              ),

              // Divider between header and tasks
              const Divider(height: 1, color: kbpBlue200),

              // Officer's tasks
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: officerTasks.length,
                itemBuilder: (context, taskIndex) {
                  return _buildOfficerTaskItem(officerTasks[taskIndex]);
                },
              ),
            ],
          ),
        );
      },
    );
  }

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
                      Text(
                        task.vehicleId.isEmpty
                            ? 'Tanpa Kendaraan'
                            : task.vehicleId,
                        style: mediumTextStyle(size: 14, color: kbpBlue900),
                      ),
                      const SizedBox(height: 4),
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
                          Container(
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
                              style: mediumTextStyle(
                                  size: 10, color: Colors.white),
                            ),
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

// Helper untuk menentukan warna status
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return kbpBlue700;
      case 'ongoing':
      case 'in_progress':
        return successG500;
      case 'finished':
        return neutral700;
      default:
        return kbpBlue700;
    }
  }

// Helper untuk menerjemahkan status
  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Aktif';
      case 'ongoing':
      case 'in_progress':
        return 'Sedang Berjalan';
      case 'finished':
        return 'Selesai';
      default:
        return status;
    }
  }

// Wrapper for history content
  Widget _buildHistoryContent() {
    if (_historyTasks.isEmpty) {
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
              itemCount: _historyTasks.length > 5 ? 5 : _historyTasks.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: kbpBlue200),
              itemBuilder: (context, index) {
                final task = _historyTasks[index];
                return _buildHistoryItem(task);
              },
            ),
            if (_historyTasks.length > 5)
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

// Consistent task card
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
                        Text(
                          task.vehicleId.isEmpty
                              ? 'Tanpa Kendaraan'
                              : task.vehicleId,
                          style: semiBoldTextStyle(size: 16, color: kbpBlue900),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.person,
                                size: 16, color: kbpBlue700),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                task.officerName ?? 'Petugas',
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
                      ],
                    ),
                  ),

                  // Date and time - fixed width for alignment
                  Container(
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
        task.officerName?.substring(0, 1).toUpperCase() ?? 'P',
        style: semiBoldTextStyle(size: 16, color: kbpBlue900),
      ),
    );
  }

// Consistent history item
  Widget _buildHistoryItem(PatrolTask task) {
    final duration = task.endTime != null && task.startTime != null
        ? task.endTime!.difference(task.startTime!)
        : Duration.zero;

    return Container(
      height: 70,
      child: InkWell(
        onTap: () => _showPatrolSummary(task),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: kbpBlue100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kbpBlue200, width: 1),
                ),
                child: task.officerPhotoUrl != null &&
                        task.officerPhotoUrl!.isNotEmpty
                    ? Image.network(
                        task.officerPhotoUrl!,
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
                        if (task.officerName != null) ...[
                          Expanded(
                            child: Text(
                              task.officerName!,
                              style: semiBoldTextStyle(
                                  size: 14, color: kbpBlue900),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          task.vehicleId.isEmpty
                              ? 'Tanpa Kendaraan'
                              : task.vehicleId,
                          style: mediumTextStyle(size: 12, color: kbpBlue700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Time & distance info
                    Row(
                      children: [
                        const Icon(Icons.timer, size: 14, color: kbpBlue700),
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
                  ],
                ),
              ),

              // View button - fixed size
              Container(
                width: 40,
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.navigate_next, color: kbpBlue900),
                  onPressed: () => _showPatrolSummary(task),
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

// BLoC builders with consistent sizing
  Widget _buildUpcomingPatrolsForOfficer() {
    return BlocBuilder<PatrolBloc, PatrolState>(
      builder: (context, state) {
        if (state is PatrolLoading) {
          return Container(
            height: 180,
            width: double.infinity,
            child: const Center(
              child: CircularProgressIndicator(color: kbpBlue900),
            ),
          );
        }

        if (state is PatrolLoaded && state.task != null) {
          return _buildTaskCard(state.task!);
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
          return Container(
            height: 180,
            width: double.infinity,
            child: const Center(
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
