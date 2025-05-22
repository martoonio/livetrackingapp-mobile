import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/presentation/component/intExtension.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
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
      title: Text(
        'Detail Tugas Patroli',
        style: boldTextStyle(
          size: h4,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Informasi Tugas:', style: semiBoldTextStyle()),
            const SizedBox(height: 8),
            // _infoRow('ID Tugas', task.taskId),
            // _infoRow('Kendaraan', task.vehicleId),
            if (task.assignedStartTime != null)
              _infoRow('Waktu Mulai',
                  "${formatDateFromString(task.assignedStartTime.toString())} Pukul ${formatTimeFromString(task.assignedStartTime.toString())}"),
            if (task.assignedEndTime != null)
              _infoRow('Waktu Selesai',
                  "${formatDateFromString(task.assignedEndTime.toString())} Pukul ${formatTimeFromString(task.assignedEndTime.toString())}"),
            if (task.startTime != null)
              _infoRow('Dimulai Pada',
                  DateFormat('dd/MM/yyyy - HH:mm').format(task.startTime!)),
            if (task.endTime != null)
              _infoRow('Selesai Pada',
                  DateFormat('dd/MM/yyyy - HH:mm').format(task.endTime!)),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(
            backgroundColor: Colors.transparent,
          ),
          child: Text(
            'Kembali',
            style: mediumTextStyle(
              color: kbpBlue900,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kbpBlue900,
          ),
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
          child: Text(
            'Lihat Rute',
            style: mediumTextStyle(
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // Helper widget untuk menampilkan info di dialog
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
