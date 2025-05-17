import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/presentation/admin/add_cluster.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/admin/patrol_history_screen.dart';
import 'create_task_screen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<AdminBloc>().add(LoadAllTasks());
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AddClusterScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<AdminBloc, AdminState>(
        builder: (context, state) {
          if (state is AdminLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is AdminError) {
            return Center(child: Text('Error: ${state.message}'));
          }

          if (state is AdminLoaded) {
            return Column(
              children: [
                _buildStatisticsCard(state),
                _buildTasksList(state),
              ],
            );
          }

          return Center(child: Text('No data available $state'));
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CreateTaskScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildStatisticsCard(AdminLoaded state) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(
              'Active Tasks',
              state.activeTasks.length.toString(),
              kbpBlue900,
            ),
            _buildStatItem('Completed Tasks',
                state.completedTasks.length.toString(), successG300),
            _buildStatItem(
              'Total Officers',
              state.totalOfficers.toString(),
              warningY300,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label),
      ],
    );
  }

  Widget _buildTasksList(AdminLoaded state) {
    return Expanded(
      child: ListView.builder(
        itemCount: state.activeTasks.length,
        itemBuilder: (context, index) {
          final task = state.activeTasks[index];
          return ListTile(
            title: Text('Task ${task.taskId}'),
            subtitle: Text('Vehicle: ${task.vehicleId}'),
            trailing: Text(task.status),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PatrolHistoryScreen(task: task),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
