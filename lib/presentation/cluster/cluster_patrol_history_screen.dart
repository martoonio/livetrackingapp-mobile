import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/admin/patrol_history_screen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:lottie/lottie.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as Math;

class ClusterPatrolHistoryScreen extends StatefulWidget {
  final String clusterId;
  final String clusterName;

  const ClusterPatrolHistoryScreen({
    super.key,
    required this.clusterId,
    required this.clusterName,
  });

  @override
  State<ClusterPatrolHistoryScreen> createState() =>
      _ClusterPatrolHistoryScreenState();
}

class _ClusterPatrolHistoryScreenState
    extends State<ClusterPatrolHistoryScreen> {
  final DateFormat dateFormatter = DateFormat('dd MMM yyyy', 'id_ID');
  final DateFormat timeFormatter = DateFormat('HH:mm', 'id_ID');

  // Filter states
  String? selectedOfficerId;
  String? selectedStatus; // Ubah tipe dari PatrolStatus? menjadi String?
  DateTime? startDate;
  DateTime? endDate;

  @override
  void initState() {
    super.initState();
    _loadClusterTasks();
  }

  void _loadClusterTasks() {
    context.read<AdminBloc>().add(
          LoadClusterTasksEvent(widget.clusterId),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Riwayat Patroli ${widget.clusterName}'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
            context.read<AdminBloc>().add(
                  GetClusterDetail(widget.clusterId),
                );
          },
        ),
      ),
      body: BlocBuilder<AdminBloc, AdminState>(
        builder: (context, state) {
          if (state is ClustersLoading || state is AdminLoading) {
            return Center(
              child: Lottie.asset(
                'assets/lottie/maps_loading.json',
                width: 200,
                height: 100,
              ),
            );
          } else if (state is ClusterTasksLoaded) {
            // Get officers and tasks
            final cluster = state.cluster;
            final officers = cluster!.officers ?? [];
            List<PatrolTask> tasks = state.tasks;

            // Apply filters if set
            if (selectedOfficerId != null) {
              tasks = tasks
                  .where((task) => task.officerId == selectedOfficerId)
                  .toList();
            }

            if (selectedStatus != null) {
              tasks =
                  tasks.where((task) => task.status == selectedStatus).toList();
            }

            if (startDate != null) {
              tasks = tasks.where((task) {
                if (task.startTime == null) return false;
                return task.startTime!.isAfter(startDate!);
              }).toList();
            }

            if (endDate != null) {
              tasks = tasks.where((task) {
                if (task.endTime == null) return false;
                return task.endTime!
                    .isBefore(endDate!.add(const Duration(days: 1)));
              }).toList();
            }

            // Sort tasks by date (newest first)
            tasks.sort((a, b) {
              if (a.startTime == null) return 1;
              if (b.startTime == null) return -1;
              return b.startTime!.compareTo(a.startTime!);
            });

            if (tasks.isEmpty) {
              return EmptyState(
                icon: Icons.history,
                title: 'Belum ada riwayat patroli',
                subtitle: selectedOfficerId != null ||
                        selectedStatus != null ||
                        startDate != null ||
                        endDate != null
                    ? 'Tidak ada hasil yang cocok dengan filter yang dipilih'
                    : 'Belum ada tugas patroli yang diselesaikan di cluster ini',
                buttonText: 'Segarkan',
                onButtonPressed: _loadClusterTasks,
              );
            }

            return Column(
              children: [
                // Active filters strip
                if (selectedOfficerId != null ||
                    selectedStatus != null ||
                    startDate != null ||
                    endDate != null)
                  _buildActiveFiltersStrip(officers),

                // Tasks list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];

                      // Find the officer for this task - improved to check both officerId and userId
                      final officer = officers.firstWhere(
                        (o) => o.id == task.officerId || o.id == task.userId,
                        orElse: () {
                          // Log untuk debugging
                          print('Officer not found for task ${task.taskId}');
                          print(
                              '  - Trying to find by officerId: ${task.officerId}');
                          print('  - Trying to find by userId: ${task.userId}');
                          print(
                              '  - Available officers: ${officers.map((o) => "${o.id} (${o.name})").join(", ")}');

                          // Jika officer tidak ditemukan, coba gunakan nilai yang ada di task.officerName
                          if (task.officerName != 'Loading...') {
                            return Officer(
                              id: task.officerId.isNotEmpty
                                  ? task.officerId
                                  : task.userId,
                              name: task.officerName,
                              type: OfficerType.organik, // Default
                              shift: ShiftType.pagi, // Default
                              clusterId: widget.clusterId,
                              photoUrl: task.officerPhotoUrl != 'P'
                                  ? task.officerPhotoUrl
                                  : null,
                            );
                          }

                          // Fallback jika benar-benar tidak ada informasi
                          return Officer(
                            id: task.officerId.isNotEmpty
                                ? task.officerId
                                : task.userId,
                            name: 'Petugas tidak ditemukan',
                            type: OfficerType.organik,
                            shift: ShiftType.pagi,
                            clusterId: widget.clusterId,
                          );
                        },
                      );

                      return _buildTaskCard(task, officer);
                    },
                  ),
                ),
              ],
            );
          } else if (state is AdminError || state is ClustersError) {
            final message = state is AdminError
                ? (state as AdminError).message
                : (state as ClustersError).message;

            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: dangerR300),
                  const SizedBox(height: 16),
                  Text(
                    'Error: $message',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kbpBlue900,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _loadClusterTasks,
                    child: const Text('Coba Lagi'),
                  ),
                ],
              ),
            );
          }

          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: kbpBlue700),
                SizedBox(height: 16),
                Text(
                  'Memuat riwayat patroli...',
                  style: TextStyle(color: neutral600, fontSize: 14),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveFiltersStrip(List<Officer> officers) {
    String officerName = '';
    if (selectedOfficerId != null) {
      final officer = officers.firstWhere(
        (o) => o.id == selectedOfficerId,
        orElse: () => Officer(
          id: '',
          name: 'Unknown',
          type: OfficerType.organik,
          shift: ShiftType.pagi,
          clusterId: '',
        ),
      );
      officerName = officer.name;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: kbpBlue50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_list, size: 16, color: kbpBlue900),
              const SizedBox(width: 8),
              Text(
                'Filter Aktif:',
                style: semiBoldTextStyle(color: kbpBlue900, size: 14),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    selectedOfficerId = null;
                    selectedStatus = null;
                    startDate = null;
                    endDate = null;
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: dangerR500,
                  padding: const EdgeInsets.all(4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Reset'),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              if (selectedOfficerId != null)
                Chip(
                  label: Text(
                    'Petugas: $officerName',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: kbpBlue100,
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      selectedOfficerId = null;
                    });
                  },
                ),
              if (selectedStatus != null)
                Chip(
                  label: Text(
                    'Status: ${_getStatusText(selectedStatus!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: kbpBlue100,
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      selectedStatus = null;
                    });
                  },
                ),
              if (startDate != null)
                Chip(
                  label: Text(
                    'Dari: ${dateFormatter.format(startDate!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: kbpBlue100,
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      startDate = null;
                    });
                  },
                ),
              if (endDate != null)
                Chip(
                  label: Text(
                    'Sampai: ${dateFormatter.format(endDate!)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: kbpBlue100,
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() {
                      endDate = null;
                    });
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(PatrolTask task, Officer officer) {
    final startDateStr =
        task.startTime != null ? dateFormatter.format(task.startTime!) : 'N/A';

    final startTimeStr =
        task.startTime != null ? timeFormatter.format(task.startTime!) : '';

    final endTimeStr =
        task.endTime != null ? timeFormatter.format(task.endTime!) : 'N/A';

    // Gunakan metode baru untuk menghitung titik yang dikunjungi dengan radius 5 meter
    final visitData = _calculateVisitedPoints(task);
    int completedPointsCount = visitData['visitedCount'] as int;
    int totalPointsCount = visitData['totalCount'] as int;

    // Fallback jika data route tidak tersedia tapi status selesai
    if (totalPointsCount == 0 &&
        (task.status.toLowerCase() == 'finished' ||
            task.status.toLowerCase() == 'completed')) {
      // Jika status selesai tapi tidak ada data rute, anggap semua dikunjungi
      completedPointsCount = 1;
      totalPointsCount = 1;
    } else if (totalPointsCount == 0 && task.routePath != null) {
      // Jika tidak ada data assigned route, gunakan jumlah route path sebagai progress
      completedPointsCount = task.routePath!.length;
      totalPointsCount = task.routePath!.length;
    }

    // Hitung progress berdasarkan titik yang dikunjungi
    final progress = totalPointsCount > 0
        ? (completedPointsCount / totalPointsCount * 100).round()
        : 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PatrolHistoryScreen(task: task),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with task ID and status
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: _getStatusColor(task.status),
                    child: const Icon(Icons.check_circle,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tugas #${task.taskId.substring(0, 8)}',
                          style: boldTextStyle(size: 16),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            // Status badge
                            Text(
                              _getStatusText(task.status),
                              style: TextStyle(
                                color: _getStatusColor(task.status),
                                fontWeight: FontWeight.w500,
                              ),
                            ),

                            // Tambahkan badge timeliness jika ada
                            if (task.timeliness != null) ...[
                              const SizedBox(width: 8),
                              buildTimelinessIndicator(task.timeliness),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios,
                      size: 16, color: neutral500),
                ],
              ),

              const Divider(height: 24),

              // Officer info
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: kbpBlue100,
                    backgroundImage: officer.photoUrl != null
                        ? NetworkImage(officer.photoUrl!)
                        : null,
                    child: officer.photoUrl == null
                        ? Text(
                            officer.name.isNotEmpty
                                ? officer.name[0].toUpperCase()
                                : '?',
                            style: boldTextStyle(color: kbpBlue900),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          officer.name,
                          style: semiBoldTextStyle(size: 14),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // Tipe badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: officer.type == OfficerType.organik
                                    ? successG50
                                    : warningY50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                officer.type == OfficerType.organik
                                    ? 'Organik'
                                    : 'Outsource',
                                style: mediumTextStyle(
                                  size: 10,
                                  color: officer.type == OfficerType.organik
                                      ? successG500
                                      : warningY500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Shift badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: kbpBlue50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                getShortShiftText(officer.shift),
                                style: mediumTextStyle(
                                    size: 10, color: kbpBlue700),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Date and Time
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 14, color: neutral600),
                  const SizedBox(width: 8),
                  Text(
                    '$startDateStr, $startTimeStr - $endTimeStr',
                    style: mediumTextStyle(size: 14, color: neutral800),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Progress
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Titik Dikunjungi',
                                  style: regularTextStyle(
                                      size: 12, color: neutral600),
                                ),
                                const SizedBox(width: 4),
                                Tooltip(
                                  message:
                                      'Titik dianggap dikunjungi jika petugas berada dalam radius 5 meter.',
                                  child: Icon(Icons.info_outline,
                                      size: 14, color: neutral500),
                                ),
                              ],
                            ),
                            Text(
                              '$completedPointsCount dari $totalPointsCount titik',
                              style: semiBoldTextStyle(size: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: progress / 100,
                          backgroundColor: neutral200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            task.status.toLowerCase() == 'finished' ||
                                    task.status.toLowerCase() == 'completed'
                                ? successG500
                                : task.status.toLowerCase() == 'ongoing' ||
                                        task.status.toLowerCase() == 'active'
                                    ? kbpBlue700
                                    : warningY500,
                          ),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: kbpBlue100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$progress%',
                      style: boldTextStyle(size: 14, color: kbpBlue900),
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

  // Perbaiki fungsi _showFilterSheet - fokus pada perbaikan tanggal

  void _showFilterSheet(BuildContext context) {
    // Simpan state lokal filter yang aktif saat ini
    String? tempOfficerId = selectedOfficerId;
    String? tempStatus = selectedStatus;
    DateTime? tempStartDate = startDate;
    DateTime? tempEndDate = endDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return BlocBuilder<AdminBloc, AdminState>(
          builder: (context, state) {
            if (state is ClusterTasksLoaded) {
              final officers = state.cluster!.officers ?? [];

              return StatefulBuilder(
                builder: (context, setModalState) {
                  // Fungsi pembantu untuk memilih tanggal mulai
                  Future<void> _selectStartDate() async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: tempStartDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2101),
                      builder: (BuildContext context, Widget? child) {
                        return Theme(
                          data: ThemeData.light().copyWith(
                            primaryColor: kbpBlue900,
                            colorScheme: ColorScheme.light(primary: kbpBlue900),
                            buttonTheme: const ButtonThemeData(
                                textTheme: ButtonTextTheme.primary),
                          ),
                          child: child!,
                        );
                      },
                    );

                    if (picked != null) {
                      setModalState(() {
                        tempStartDate = picked;
                        print('Tanggal mulai dipilih: $tempStartDate');
                      });
                    }
                  }

                  // Fungsi pembantu untuk memilih tanggal akhir
                  Future<void> _selectEndDate() async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: tempEndDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2101),
                      builder: (BuildContext context, Widget? child) {
                        return Theme(
                          data: ThemeData.light().copyWith(
                            primaryColor: kbpBlue900,
                            colorScheme: ColorScheme.light(primary: kbpBlue900),
                            buttonTheme: const ButtonThemeData(
                                textTheme: ButtonTextTheme.primary),
                          ),
                          child: child!,
                        );
                      },
                    );

                    if (picked != null) {
                      setModalState(() {
                        tempEndDate = picked;
                        print('Tanggal akhir dipilih: $tempEndDate');
                      });
                    }
                  }

                  return Container(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                      left: 16,
                      right: 16,
                      top: 16,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Filter Riwayat Patroli',
                                style: boldTextStyle(size: 18),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Officer filter
                          Text(
                            'Petugas',
                            style: semiBoldTextStyle(size: 14),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: neutral300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonFormField<String?>(
                              value: tempOfficerId,
                              decoration: const InputDecoration(
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 12),
                                border: InputBorder.none,
                                hintText: 'Semua Petugas',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Semua Petugas'),
                                ),
                                ...officers.map((officer) {
                                  return DropdownMenuItem<String>(
                                    value: officer.id,
                                    child: Text(officer.name),
                                  );
                                }).toList(),
                              ],
                              onChanged: (value) {
                                setModalState(() {
                                  tempOfficerId = value;
                                });
                              },
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Status filter
                          Text(
                            'Status Patroli',
                            style: semiBoldTextStyle(size: 14),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: neutral300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonFormField<String?>(
                              value: tempStatus,
                              decoration: const InputDecoration(
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 12),
                                border: InputBorder.none,
                                hintText: 'Semua Status',
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Semua Status'),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'assigned',
                                  child: Text(_getStatusText('assigned')),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'ongoing',
                                  child: Text(_getStatusText('ongoing')),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'active',
                                  child: Text(_getStatusText('active')),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'finished',
                                  child: Text(_getStatusText('finished')),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'completed',
                                  child: Text(_getStatusText('completed')),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'canceled',
                                  child: Text(_getStatusText('canceled')),
                                ),
                              ],
                              onChanged: (value) {
                                setModalState(() {
                                  tempStatus = value;
                                });
                              },
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Date range filter dengan MaterialButton (lebih responsif)
                          Text(
                            'Rentang Tanggal',
                            style: semiBoldTextStyle(size: 14),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: MaterialButton(
                                  onPressed: _selectStartDate,
                                  color: kbpBlue50,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.calendar_today,
                                          size: 16, color: kbpBlue900),
                                      const SizedBox(width: 8),
                                      Text(
                                        tempStartDate != null
                                            ? dateFormatter
                                                .format(tempStartDate!)
                                            : 'Pilih Tanggal Mulai',
                                        style:
                                            mediumTextStyle(color: kbpBlue900),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: MaterialButton(
                                  onPressed: _selectEndDate,
                                  color: kbpBlue50,
                                  elevation: 0,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.calendar_today,
                                          size: 16, color: kbpBlue900),
                                      const SizedBox(width: 8),
                                      Text(
                                        tempEndDate != null
                                            ? dateFormatter.format(tempEndDate!)
                                            : 'Pilih Tanggal Selesai',
                                        style:
                                            mediumTextStyle(color: kbpBlue900),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // Filter actions
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      selectedOfficerId = tempOfficerId;
                                      selectedStatus = tempStatus;
                                      startDate = tempStartDate;
                                      endDate = tempEndDate;
                                    });
                                    Navigator.pop(context);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kbpBlue900,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 24),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text('Terapkan Filter'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextButton(
                                  onPressed: () {
                                    setModalState(() {
                                      tempOfficerId = null;
                                      tempStatus = null;
                                      tempStartDate = null;
                                      tempEndDate = null;
                                    });
                                  },
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12, horizontal: 24),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    'Reset Filter',
                                    style: TextStyle(color: dangerR500),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  );
                },
              );
            }

            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Memuat data petugas...'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return 'Tugas Dijadwalkan';
      case 'ongoing':
      case 'active':
        return 'Sedang Patroli';
      case 'finished':
      case 'completed':
        return 'Patroli Selesai';
      case 'canceled':
        return 'Patroli Dibatalkan';
      default:
        return 'Status Tidak Diketahui';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return warningY500;
      case 'ongoing':
      case 'active':
        return kbpBlue700;
      case 'finished':
      case 'completed':
        return successG500;
      case 'canceled':
        return dangerR500;
      default:
        return neutral500;
    }
  }

  // Helper untuk mendapatkan teks shift pendek
  String getShortShiftText(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return 'Pagi (07-15)';
      case ShiftType.sore:
        return 'Sore (15-23)';
      case ShiftType.malam:
        return 'Malam (23-07)';
      case ShiftType.siang:
        return 'Siang (07-19)';
      case ShiftType.malamPanjang:
        return 'Malam (19-07)';
    }
  }

  // Tambahkan metode baru untuk menghitung titik yang dikunjungi
  Map<String, dynamic> _calculateVisitedPoints(PatrolTask task,
      {double radiusInMeters = 5.0}) {
    try {
      final Set<int> visitedCheckpoints = <int>{};
      final List<Map<String, double>> routePositions = [];

      if (task.routePath != null && task.assignedRoute != null) {
        // Ekstrak posisi dari route path
        final routePathMap = Map<String, dynamic>.from(task.routePath!);
        routePathMap.forEach((key, value) {
          try {
            if (value is Map && value.containsKey('coordinates')) {
              final coordinates = value['coordinates'] as List;
              if (coordinates.length >= 2) {
                routePositions.add({
                  'lat': coordinates[0] as double,
                  'lng': coordinates[1] as double
                });
              }
            }
          } catch (e) {
            print('Error parsing route path entry $key: $e');
          }
        });

        // Periksa jarak terdekat untuk setiap checkpoint
        for (int i = 0; i < task.assignedRoute!.length; i++) {
          try {
            final checkpoint = task.assignedRoute![i];
            final checkpointLat = checkpoint[0] as double;
            final checkpointLng = checkpoint[1] as double;

            double minDistance = double.infinity;
            for (final position in routePositions) {
              final distance = Geolocator.distanceBetween(position['lat']!,
                  position['lng']!, checkpointLat, checkpointLng);

              minDistance = Math.min(minDistance, distance);
              if (distance <= radiusInMeters) {
                visitedCheckpoints.add(i);
                break;
              }
            }
          } catch (e) {
            print('Error checking distance for checkpoint $i: $e');
          }
        }
      }

      return {
        'visitedCheckpoints': visitedCheckpoints,
        'routePositions': routePositions,
        'visitedCount': visitedCheckpoints.length,
        'totalCount': task.assignedRoute?.length ?? 0,
      };
    } catch (e) {
      print('Error calculating visited points: $e');
      return {
        'visitedCheckpoints': <int>{},
        'routePositions': <Map<String, double>>[],
        'visitedCount': 0,
        'totalCount': task.assignedRoute?.length ?? 0,
      };
    }
  }
}
