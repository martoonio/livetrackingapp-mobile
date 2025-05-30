import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:livetrackingapp/map_screen.dart';
import 'package:livetrackingapp/patrol_summary_screen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:lottie/lottie.dart';
import '../../domain/entities/patrol_task.dart';
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

  // Add this method to fetch patrol history
  void _loadPatrolHistory() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    context
        .read<PatrolBloc>()
        .add(LoadPatrolHistory(userId: authState.user.id));
  }

// Update initState to load history
  @override
  void initState() {
    super.initState();
    // _checkOngoingPatrol();
    _startTaskStream();
    _loadPatrolHistory();
  }

  Widget _buildPatrolHistory() {
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
                  padding: EdgeInsets.all(16.0),
                  child: LottieBuilder.asset(
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
                    // height: MediaQuery.of(context).size.height * 0.2,
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
                            // Perbaiki cara mengakses startTime dan endTime
                            Text(
                                '${formatTimeFromString(task.startTime?.toString())} - ${formatTimeFromString(task.endTime?.toString())}'),
                            // Pastikan distance tidak null dengan menggunakan nilai default 0
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

// Add helper methods for formatting
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

// Add method to show patrol summary
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

  void _startTaskStream() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      print('User not authenticated');
      return;
    }

    final userId = authState.user.id;
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

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

//   void _checkOngoingPatrol() {
//     final authState = context.read<AuthBloc>().state;
//     if (authState is AuthAuthenticated) {
//       print('Checking for ongoing patrol...');
//       context.read<PatrolBloc>().add(
//             CheckOngoingPatrol(userId: authState.user.id),
//           );
//     }
//   }

// // Add handler for ongoing patrol
//   void _handleOngoingPatrol(PatrolTask task) {
//     print('Resuming ongoing patrol: ${task.taskId}');
//     Navigator.pushReplacement(
//       context,
//       MaterialPageRoute(
//         builder: (_) => MapScreen(
//           task: task,
//           onStart: () {},
//         ),
//       ),
//     );
//   }

  getDurasiPatroli(
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
    return BlocListener<PatrolBloc, PatrolState>(
      listener: (context, state) {
        // if (state is PatrolLoaded && state.isPatrolling) {
        //   if (state.task != null) {
        //     _handleOngoingPatrol(state.task!);
        //   } else {
        //     print('No ongoing task found');
        //   }
        // }
      },
      child: Scaffold(
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
              onPressed: _startTaskStream,
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async => _startTaskStream(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUpcomingPatrols(),
                16.height,
                _buildPatrolHistory(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingPatrols() {
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

            if (state is PatrolLoaded) {
              if (state.task != null) {
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
                                  "${state.task!.assignedRoute!.length.toString()} Titik",
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
                                              state.task?.assignedEndTime !=
                                                  null
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
}
