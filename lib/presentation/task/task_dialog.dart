import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/patrol_task.dart';
import '../../map_screen.dart';
import '../routing/bloc/patrol_bloc.dart';

class TaskDetailDialog extends StatelessWidget {
  final PatrolTask task;
  final VoidCallback onStart;

  const TaskDetailDialog({
    Key? key,
    required this.task,
    required this.onStart,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Task Details'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Task ID: ${task.taskId}'),
          const SizedBox(height: 8),
          Text('Vehicle: ${task.vehicleId}'),
          const SizedBox(height: 8),
          Text('Status: ${task.status}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context); // Close dialog first
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MapScreen(
                  task: task,
                  onStart: () {
                    // This will be called from MapScreen when starting patrol
                    context.read<PatrolBloc>().add(StartPatrol(
                          task: task,
                          startTime: DateTime.now(),
                        ));
                  },
                ),
              ),
            );
          },
          child: const Text('View Route'),
        ),
      ],
    );
  }
}
