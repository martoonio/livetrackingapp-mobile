import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/map_screen.dart';
import 'package:livetrackingapp/patrol_summary_screen.dart';
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
  StreamSubscription? _historySubscription;

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
    _checkOngoingPatrol();
    _startTaskStream();
    _loadPatrolHistory();
  }

// Replace existing _buildPatrolHistory with this
  Widget _buildPatrolHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Patrol History',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        BlocBuilder<PatrolBloc, PatrolState>(
          builder: (context, state) {
            print('Building history with state: $state'); // Debug print

            if (state is PatrolLoading) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (state is PatrolLoaded) {
              if (state.finishedTasks.isEmpty) {
                return const Card(
                  child: ListTile(
                    title: Text('No patrol history'),
                    subtitle: Text('Completed patrols will appear here'),
                  ),
                );
              }

              return Container(
                height: 300,
                child: ListView.builder(
                  itemCount: state.finishedTasks.length,
                  itemBuilder: (context, index) {
                    final task = state.finishedTasks[index];
                    final duration =
                        task.endTime != null && task.startTime != null
                            ? task.endTime!.difference(task.startTime!)
                            : Duration.zero;

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 0),
                      child: ListTile(
                        title: Text('Task: ${task.taskId}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Vehicle: ${task.vehicleId}'),
                            Text('Date: ${_formatDate(task.startTime)}'),
                            Text('Duration: ${_formatDuration(duration)}'),
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
                  leading: const Icon(Icons.error, color: Colors.red),
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
  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
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
        print('Task stream error: $error');
        _showErrorSnackBar('Failed to load task: $error');
      },
    );
  }

  void _handleNewTask(PatrolTask task) {
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

  void _checkOngoingPatrol() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      print('Checking for ongoing patrol...');
      context.read<PatrolBloc>().add(
            CheckOngoingPatrol(userId: authState.user.id),
          );
    }
  }

// Add handler for ongoing patrol
  void _handleOngoingPatrol(PatrolTask task) {
    print('Resuming ongoing patrol: ${task.taskId}');
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          task: task,
          onStart: () {}, // Empty because patrol is already started
        ),
      ),
    );
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
        if (state is PatrolLoaded && state.isPatrolling && state.task != null) {
          _handleOngoingPatrol(state.task!);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Patrol Dashboard'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
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
                const SizedBox(height: 32),
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
          'Upcoming Patrols',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        BlocBuilder<PatrolBloc, PatrolState>(
          builder: (context, state) {
            if (state is PatrolLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is PatrolLoaded) {
              if (state.task != null) {
                return Card(
                  child: ListTile(
                    title: Text('Task: ${state.task!.taskId}'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vehicle: ${state.task!.vehicleId}'),
                        Text('Status: ${state.task!.status}'),
                      ],
                    ),
                    trailing: ElevatedButton(
                      onPressed: () => _showTaskDialog(state.task!),
                      child: const Text('View Details'),
                    ),
                  ),
                );
              }
            }

            return const Card(
              child: ListTile(
                title: Text('No upcoming patrols'),
                subtitle: Text('No active tasks available'),
              ),
            );
          },
        ),
      ],
    );
  }
}
