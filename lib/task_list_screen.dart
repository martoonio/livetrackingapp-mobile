import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lottie/lottie.dart';
import '../../domain/entities/patrol_task.dart';
import 'presentation/auth/bloc/auth_bloc.dart';
import 'presentation/routing/bloc/patrol_bloc.dart';
import 'presentation/task/task_dialog.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  Stream<List<PatrolTask>>? _tasksStream;

  @override
  void initState() {
    super.initState();
    _initTasksStream();
  }

  void _initTasksStream() {
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      print('Initializing task stream for user: ${authState.user.id}');

      _tasksStream = FirebaseDatabase.instance
          .ref()
          .child('tasks')
          .onValue
          .asBroadcastStream()
          .map((event) {
        print('Raw database event: ${event.snapshot.value}');

        if (!event.snapshot.exists) {
          print('No snapshot exists');
          return <PatrolTask>[];
        }

        try {
          // First cast to Map<dynamic, dynamic>
          final rawMap = event.snapshot.value as Map<dynamic, dynamic>;
          print('Raw map data: $rawMap');

          final tasks = rawMap.entries.map((entry) {
            // Cast the value to Map<dynamic, dynamic> first
            final taskData = entry.value as Map<dynamic, dynamic>;

            // Convert to Map<String, dynamic> safely
            final convertedData = Map<String, dynamic>.from({
              ...taskData,
              'taskId': entry.key,
            });

            print('Converting task: $convertedData');
            return PatrolTask.fromJson(convertedData);
          }).toList();

          print('Processed ${tasks.length} tasks');
          return tasks;
        } catch (e, stackTrace) {
          print('Error processing tasks: $e');
          print('Stack trace: $stackTrace');
          return <PatrolTask>[];
        }
      });

      // Debug listener
      _tasksStream?.listen(
        (tasks) => print('Stream emitted ${tasks.length} tasks'),
        onError: (error) => print('Stream error: $error'),
      );
    } else {
      print('User not authenticated');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patrol Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: _tasksStream == null
          ? const Center(child: Text('Please login to view tasks'))
          : StreamBuilder<List<PatrolTask>>(
              stream: _tasksStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData) {
                  print('masuk sini no data');
                  return Center(
                    child: LottieBuilder.asset(
                      'assets/lottie/maps_loading.json',
                      width: 200,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  );
                }

                final tasks = snapshot.data!;
                if (tasks.isEmpty) {
                  return const Center(
                    child: Text('No tasks assigned'),
                  );
                }

                return ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: ListTile(
                        title: Text('Task ID: ${task.taskId}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Text('Vehicle: ${task.vehicleId}'),
                            Text('Status: ${task.status}'),
                            Text('Created: ${task.createdAt}'),
                          ],
                        ),
                        trailing: task.status == 'active'
                            ? ElevatedButton(
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (_) => TaskDetailDialog(
                                      task: task,
                                      onStart: () {
                                        context.read<PatrolBloc>().add(
                                              LoadRouteData(
                                                userId: task.userId,
                                              ),
                                            );
                                        Navigator.pop(context); // Close dialog
                                        Navigator.pop(context); // Return to map
                                      },
                                    ),
                                  );
                                },
                                child: const Text('View'),
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
