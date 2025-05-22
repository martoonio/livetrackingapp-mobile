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
  List<PatrolTask> _upcomingTasks = [];
  List<PatrolTask> _historyTasks = [];
  bool _isLoading = true;
  final Set<String> _expandedOfficers = {};

  late AppLifecycleListener _lifecycleListener;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) {
          _startRefreshTimer();
        } else if (state == AppLifecycleState.paused) {
          _refreshTimer?.cancel();
          _refreshTimer = null;
        }
      },
    );
    _startRefreshTimer();
    _loadUserData();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 300), (timer) {
      if (mounted) {
        _loadUserData();
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
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _toggleOfficerExpanded(String officerId) {
    setState(() {
      if (_expandedOfficers.contains(officerId)) {
        _expandedOfficers.remove(officerId);
      } else {
        _expandedOfficers.add(officerId);
      }
    });
  }

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

      if (_currentUser!.role == 'patrol') {
        await _loadClusterOfficerTasks();

        // Tambahkan pengecekan untuk task yang expired
        await _checkForExpiredTasks();
      } else {
        print('Loading patrol data for officer');

        context
            .read<PatrolBloc>()
            .add(LoadPatrolHistory(userId: _currentUser!.id));

        final currentTask = await context
            .read<PatrolBloc>()
            .repository
            .getCurrentTask(_currentUser!.id);

        if (currentTask != null) {
          print(
              'Found current task: ${currentTask.taskId}, status: ${currentTask.status}');

          // Cek apakah task sudah melewati batas waktu
          final now = DateTime.now();
          if (currentTask.status == 'active' &&
              currentTask.assignedEndTime != null &&
              now.isAfter(currentTask.assignedEndTime!)) {
            // Update status task menjadi expired
            await _markTaskAsExpired(currentTask);
          } else {
            context
                .read<PatrolBloc>()
                .add(UpdateCurrentTask(task: currentTask));

            if (currentTask.status == 'ongoing' ||
                currentTask.status == 'in_progress' ||
                currentTask.status == 'active') {
              print('Task is ongoing/active - restoring patrol state');
              context.read<PatrolBloc>().add(ResumePatrol(
                    task: currentTask,
                    startTime: currentTask.startTime ?? DateTime.now(),
                    currentDistance: currentTask.distance ?? 0.0,
                  ));
            }
          }
        } else {
          print('No current task found');
        }

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

// Metode baru untuk pengecekan expired tasks (untuk command center)
  Future<void> _checkForExpiredTasks() async {
    if (_currentUser?.role != 'patrol') return;

    final now = DateTime.now();
    List<PatrolTask> expiredTasks = [];

    // Loop semua upcoming tasks untuk mencari yang sudah expired
    for (final task in _upcomingTasks) {
      if (task.status == 'active' &&
          task.assignedEndTime != null &&
          now.isAfter(task.assignedEndTime!) &&
          task.startTime == null) {
        print(
            'Found expired task: ${task.taskId} for officer: ${task.officerName}');

        // Tambahkan ke list expired
        expiredTasks.add(task);

        // Update status di database
        try {
          await context.read<PatrolBloc>().repository.updateTask(
            task.taskId,
            {
              'status': 'expired',
              'expiredAt': now.toIso8601String(),
            },
          );

          print('Updated task ${task.taskId} status to expired');

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
    if (expiredTasks.isNotEmpty) {
      await _loadClusterOfficerTasks();
    }
  }

// Metode baru untuk menandai task sebagai expired (untuk officer)
  Future<void> _markTaskAsExpired(PatrolTask task) async {
    final now = DateTime.now();

    try {
      print('Marking task ${task.taskId} as expired');

      // Update status di database
      await context.read<PatrolBloc>().repository.updateTask(
        task.taskId,
        {
          'status': 'expired',
          'expiredAt': now.toIso8601String(),
        },
      );

      print('Task marked as expired');

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
    if (_currentUser == null) {
      print('Current user is null');
      return;
    }

    try {
      final clusterId = _currentUser!.id;
      print('Loading tasks for cluster: $clusterId');

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
        print(
            'Unexpected format for officers data: ${officerSnapshot.value.runtimeType}');
        setState(() {
          _upcomingTasks = [];
          _historyTasks = [];
          _isLoading = false;
        });
        return;
      }

      print('Officer data type: ${officerSnapshot.value.runtimeType}');
      print('Officers data after conversion: $officersData');

      Map<String, Map<String, String>> officerInfo = {};

      try {
        // Untuk kasus officers adalah array (struktur yang benar)
        if (officerSnapshot.value is List) {
          final officersList = List.from(
              (officerSnapshot.value as List).where((item) => item != null));
          print('Officers data is an array with ${officersList.length} items');

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

                print(
                    'Officer in array: $offId, Name: $name, Has Photo: ${photoUrl.isNotEmpty}');
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

              print(
                  'Officer in map: $idKey, Name: $name, Has Photo: ${photoUrl.isNotEmpty}');
            }
          });
        }
      } catch (e) {
        print('Error processing officers data: $e');
      }

      final taskSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('tasks')
          .orderByChild('clusterId')
          .equalTo(clusterId)
          .get();

      List<PatrolTask> allHistoryTasks = [];
      List<PatrolTask> allUpcomingTasks = [];

      if (taskSnapshot.exists) {
        // PERBAIKAN: Tambahkan pengecekan tipe data sebelum casting
        Map<dynamic, dynamic> tasksData;
        if (taskSnapshot.value is Map) {
          tasksData = taskSnapshot.value as Map<dynamic, dynamic>;
        } else {
          print(
              'Unexpected format for tasks data: ${taskSnapshot.value.runtimeType}');
          setState(() {
            _upcomingTasks = [];
            _historyTasks = [];
            _isLoading = false;
          });
          return;
        }

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
                // vehicleId: taskData['vehicleId']?.toString() ?? '',
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
              if (status.toLowerCase() == 'finished' ||
                  status.toLowerCase() == 'completed' ||
                  status.toLowerCase() == 'cancelled' ||
                  status.toLowerCase() == 'expired') {
                allHistoryTasks.add(task);
              } else if (status.toLowerCase() == 'active' ||
                  status.toLowerCase() == 'ongoing' ||
                  status.toLowerCase() == 'in_progress') {
                allUpcomingTasks.add(task);
              }
            } catch (e, stack) {
              print('Error processing task $taskId: $e');
              print('Stack trace: $stack');
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
        _taskSubscription?.cancel();
        _taskSubscription = null;
      },
    );
  }

  void _handleNewTask(PatrolTask task) {
    print('=== New Task Received ===');
    print('Task ID: ${task.taskId}');
    print('Status: ${task.status}');
    print('Assigned Start Time: ${task.assignedStartTime}');
    print('Assigned End Time: ${task.assignedEndTime}');

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
              initialReportPhotoUrl: updatedTask?.initialReportPhotoUrl ??
                  task.initialReportPhotoUrl,
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
                    _buildUserGreetingCard(),
                    const SizedBox(height: 24),
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

  Widget _buildUpcomingPatrolsContent() {
    if (_upcomingTasks.isEmpty) {
      return _buildEmptyStateCard(
        icon: 'assets/state/noTask.svg',
        message: 'Belum ada tugas patroli\nyang dijadwalkan',
      );
    }

    final Map<String, List<PatrolTask>> tasksByOfficer = {};

    for (final task in _upcomingTasks) {
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

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedOfficerIds.length,
      itemBuilder: (context, index) {
        final officerId = sortedOfficerIds[index];
        final officerTasks = tasksByOfficer[officerId]!;

        // Ambil nama officer dari task pertama
        final officerName = officerTasks.first.officerName;
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
                      child: officerPhotoUrl.isNotEmpty
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
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: kbpBlue900,
                      ),
                      onPressed: () {
                        _toggleOfficerExpanded(officerId);
                      },
                    ),
                  ],
                ),
              ),

              // Divider between header and tasks
              const Divider(height: 1, color: kbpBlue200),

              // Officer's tasks
              _expandedOfficers.contains(officerId)
                  ? ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: officerTasks.length,
                      itemBuilder: (context, taskIndex) {
                        return _buildOfficerTaskItem(officerTasks[taskIndex]);
                      },
                    )
                  : officerTasks.isNotEmpty
                      ? _buildOfficerTaskItem(officerTasks.first)
                      : const SizedBox.shrink(),

              // Jika ingin menambahkan indikator "lihat X tugas lainnya" saat collapsed
              if (!_expandedOfficers.contains(officerId) &&
                  officerTasks.length > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: TextButton(
                    onPressed: () => _toggleOfficerExpanded(officerId),
                    style: TextButton.styleFrom(
                      foregroundColor: kbpBlue700,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Lihat ${officerTasks.length - 1} tugas lainnya',
                          style: mediumTextStyle(size: 12, color: kbpBlue700),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down,
                            size: 16, color: kbpBlue700),
                      ],
                    ),
                  ),
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
      case 'pastDue':
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
      case 'pastDue':
        return 'Melewati Batas';
      default:
        return 'Belum Dimulai';
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
        print('BlocBuilder for upcoming tasks: state = ${state.runtimeType}');

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
          print(
              'PatrolLoaded state with task: ${state.task?.taskId}, status: ${state.task?.status}');
          print('isPatrolling: ${state.isPatrolling}');
          print('FinishedTasks count: ${state.finishedTasks.length}');

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
