import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart'; // Import PatrolTask
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/notification_utils.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/component/map_section.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:lottie/lottie.dart' as lottie;

class CreateTaskScreen extends StatefulWidget {
  final String? initialClusterId;

  const CreateTaskScreen({
    super.key,
    this.initialClusterId,
  });

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen>
    with SingleTickerProviderStateMixin {
  // Single Task Form
  final _singleFormKey = GlobalKey<FormState>();
  final Set<Marker> _markers = {};
  final List<LatLng> _selectedPoints = [];
  bool _isCreatingSingle = false; // For single task submission
  bool _isMapExpanded = false;
  GoogleMapController? _mapController;

  // Form values for Single Task
  String? _selectedClusterId;
  String _vehicleId = '';
  String? _selectedOfficerId;
  Officer? _selectedOfficer;
  String? _selectedClusterName;

  String? _createdTaskId;
  String? get taskId => _createdTaskId;

  DateTime _assignedStartTime = DateTime.now();
  DateTime _assignedEndTime = DateTime.now().add(const Duration(hours: 8));

  // Multiple Task Tab
  late TabController _tabController;
  final _multipleTaskFormKey = GlobalKey<FormState>();
  final List<PatrolTask> _stagedTasks =
      []; // List to hold tasks before multiple assignment
  DateTime? _multipleStartDate;
  DateTime? _multipleEndDate;
  bool _isAssigningMultiple = false; // For multiple task submission

  // Form values for adding a task to the staged list (similar to single task)
  String? _multiSelectedClusterId;
  String _multiVehicleId = '';
  String? _multiSelectedOfficerId;
  Officer? _multiSelectedOfficer;
  String? _multiSelectedClusterName;
  final List<LatLng> _multiSelectedPoints = [];
  DateTime _multiAssignedStartTime = DateTime.now();
  DateTime _multiAssignedEndTime = DateTime.now().add(const Duration(hours: 8));

  int _totalTasksToCreate = 0;
  int _tasksCreated = 0;
  bool _showingProgressDialog = false;

  // Add a placeholder for the admin user ID.
  // In a real application, this should be retrieved from the authenticated user's session.
  final String _adminUserId = 'admin_user_id_placeholder';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Jika ada initialClusterId, set sebagai cluster terpilih
    if (widget.initialClusterId != null) {
      _selectedClusterId = widget.initialClusterId;
      _multiSelectedClusterId = widget.initialClusterId;
    }

    // Load semua data yang diperlukan dengan delay untuk mencegah race condition
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminBloc>().add(const LoadAllClusters());

      Future.delayed(const Duration(milliseconds: 300), () {
        context.read<AdminBloc>().add(const LoadOfficersAndVehicles());
      });

      if (widget.initialClusterId != null) {
        Future.delayed(const Duration(milliseconds: 600), () {
          _loadInitialClusterCoordinates();
        });
      }
    });
  }

  void _loadInitialClusterCoordinates() {
    final adminState = context.read<AdminBloc>().state;
    List<User> clusters = [];

    if (adminState is AdminLoaded) {
      clusters = adminState.clusters;
    } else if (adminState is ClustersLoaded) {
      clusters = adminState.clusters;
    } else if (adminState is OfficersAndVehiclesLoaded) {
      clusters = adminState.clusters;
    }

    if (clusters.isNotEmpty && widget.initialClusterId != null) {
      final initialCluster = clusters.firstWhere(
        (cluster) => cluster.id == widget.initialClusterId,
        orElse: () => User(id: '', email: '', name: '', role: ''),
      );

      if (initialCluster.id.isNotEmpty) {
        setState(() {
          _selectedClusterName = initialCluster.name;
          _multiSelectedClusterName = initialCluster.name;
        });

        // Load coordinates untuk single task
        if (initialCluster.clusterCoordinates != null &&
            initialCluster.clusterCoordinates!.isNotEmpty) {
          print('DEBUG _loadInitialClusterCoordinates (Single):');
          print('  - Loading initial coordinates for: ${initialCluster.name}');
          _addClusterCoordinatesToMap(initialCluster.clusterCoordinates!);
        }

        // Load coordinates untuk multi task
        if (initialCluster.clusterCoordinates != null &&
            initialCluster.clusterCoordinates!.isNotEmpty) {
          print('DEBUG _loadInitialClusterCoordinates (Multi):');
          print(
              '  - Loading initial coordinates for multi task: ${initialCluster.name}');
          _addMultiClusterCoordinatesToMap(initialCluster.clusterCoordinates!);
        }
      }
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _tabController.dispose();

    // TAMBAHAN: Hide progress dialog jika masih tampil
    if (_showingProgressDialog) {
      _hideProgressDialog();
    }

    super.dispose();
  }

  // Cek apakah waktu yang dipilih sesuai dengan range shift
  bool _isTimeInShiftRange(TimeOfDay time, ShiftType shift) {
    int hour = time.hour;

    switch (shift) {
      case ShiftType.pagi:
        return hour >= 7 && hour < 15; // 07:00-15:00
      case ShiftType.sore:
        return hour >= 15 && hour < 23; // 15:00-23:00
      case ShiftType.malam:
        return hour >= 23 || hour < 7; // 23:00-07:00
      case ShiftType.siang:
        return hour >= 7 && hour < 19; // 07:00-19:00
      case ShiftType.malamPanjang:
        return hour >= 19 || hour < 7; // 19:00-07:00
    }
  }

  // Dapatkan pesan range waktu untuk shift tertentu
  String _getShiftTimeRangeMessage(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return 'Shift Pagi hanya dapat dijadwalkan antara pukul 07:00 - 15:00';
      case ShiftType.sore:
        return 'Shift Sore hanya dapat dijadwalkan antara pukul 15:00 - 23:00';
      case ShiftType.malam:
        return 'Shift Malam hanya dapat dijadwalkan antara pukul 23:00 - 07:00';
      case ShiftType.siang:
        return 'Shift Siang hanya dapat dijadwalkan antara pukul 07:00 - 19:00';
      case ShiftType.malamPanjang:
        return 'Shift Malam hanya dapat dijadwalkan antara pukul 19:00 - 07:00';
    }
  }

  void _updateEndTimeBasedOnStartTime(
      DateTime startTime, Officer? officer, Function(DateTime) onUpdate) {
    if (officer == null) return;

    DateTime endTime = startTime.add(const Duration(hours: 1));
    DateTime maxEndTime;

    final startDate = startTime;

    switch (officer.shift) {
      case ShiftType.pagi:
        // 07:00-15:00
        maxEndTime = DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
          15,
          0,
        );
        break;

      case ShiftType.sore:
        // 15:00-23:00
        maxEndTime = DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
          23,
          0,
        );
        break;

      case ShiftType.malam:
        // 23:00-07:00 (next day)
        if (startTime.hour >= 23) {
          // Start di malam hari, max end time adalah 07:00 hari berikutnya
          maxEndTime = DateTime(
            startDate.year,
            startDate.month,
            startDate.day + 1,
            7,
            0,
          );
        } else if (startTime.hour >= 0 && startTime.hour < 7) {
          // Start di dini hari, max end time adalah 07:00 hari yang sama
          maxEndTime = DateTime(
            startDate.year,
            startDate.month,
            startDate.day,
            7,
            0,
          );
        } else {
          // Invalid start time untuk shift malam
          maxEndTime = startTime.add(const Duration(hours: 1));
        }
        break;

      case ShiftType.siang:
        // 07:00-19:00
        maxEndTime = DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
          19,
          0,
        );
        break;

      case ShiftType.malamPanjang:
        // 19:00-07:00 (next day)
        if (startTime.hour >= 19) {
          // Start di malam hari, max end time adalah 07:00 hari berikutnya
          maxEndTime = DateTime(
            startDate.year,
            startDate.month,
            startDate.day + 1,
            7,
            0,
          );
        } else if (startTime.hour >= 0 && startTime.hour < 7) {
          // Start di dini hari, max end time adalah 07:00 hari yang sama
          maxEndTime = DateTime(
            startDate.year,
            startDate.month,
            startDate.day,
            7,
            0,
          );
        } else {
          // Invalid start time untuk shift malam panjang
          maxEndTime = startTime.add(const Duration(hours: 1));
        }
        break;
    }

    // Pastikan end time tidak melewati batas maksimal
    if (endTime.isAfter(maxEndTime)) {
      endTime = maxEndTime;
    }

    // Pastikan end time minimal 1 jam setelah start time
    if (endTime.isBefore(startTime.add(const Duration(hours: 1)))) {
      endTime = startTime.add(const Duration(hours: 1));

      // Jika setelah ditambah 1 jam masih melewati batas, set ke batas maksimal
      if (endTime.isAfter(maxEndTime)) {
        endTime = maxEndTime;
      }
    }

    print('DEBUG _updateEndTimeBasedOnStartTime:');
    print('  - Officer shift: ${officer.shift}');
    print('  - Start time: $startTime');
    print('  - Calculated end time: $endTime');
    print('  - Max end time: $maxEndTime');
    print('  - Is overnight: ${_isOvernightShift(startTime, endTime)}');

    onUpdate(endTime);
  }

  void _updateMarkers() {
    _markers.clear();
    for (int i = 0; i < _selectedPoints.length; i++) {
      _markers.add(
        Marker(
          markerId: MarkerId('point_$i'),
          position: _selectedPoints[i],
          infoWindow: InfoWindow(
            title: 'Titik ${i + 1}',
            snippet: 'Klik untuk menghapus titik ini',
            onTap: () {
              _removeMarkerAtIndex(i);
            },
          ),
          onTap: () {
            if (_mapController != null) {
              _mapController!.showMarkerInfoWindow(MarkerId('point_$i'));
            }
          },
        ),
      );
    }
  }

  void _removeMarkerAtIndex(int index) {
    if (index >= 0 && index < _selectedPoints.length) {
      setState(() {
        _selectedPoints.removeAt(index);
        _updateMarkers();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Titik berhasil dihapus'),
          duration: Duration(seconds: 1),
          backgroundColor: kbpBlue700,
        ),
      );
    }
  }

  void _handleMapTap(LatLng position) {
    int indexToRemove = _findNearestPointIndex(position);

    if (indexToRemove != -1) {
      _removeMarkerAtIndex(indexToRemove);
    } else {
      setState(() {
        _selectedPoints.add(position);
        _updateMarkers();
      });
    }
  }

  int _findNearestPointIndex(LatLng tapPosition) {
    const double minDistance = 0.0001;

    for (int i = 0; i < _selectedPoints.length; i++) {
      final point = _selectedPoints[i];
      final distance = _calculateDistance(tapPosition, point);

      if (distance < minDistance) {
        return i;
      }
    }
    return -1;
  }

  double _calculateDistance(LatLng pos1, LatLng pos2) {
    final dx = pos1.latitude - pos2.latitude;
    final dy = pos1.longitude - pos2.longitude;
    return sqrt(dx * dx + dy * dy);
  }

  void _addClusterCoordinatesToMap(List<List<double>> coordinates) {
    setState(() {
      _markers.clear();
      _selectedPoints.clear();

      for (var coordinate in coordinates) {
        if (coordinate.length >= 2) {
          final point = LatLng(coordinate[0], coordinate[1]);
          _selectedPoints.add(point);
        }
      }

      _updateMarkers();

      if (_selectedPoints.isNotEmpty && _mapController != null) {
        _fitMapToBounds();
      }
    });
  }

  void _fitMapToBounds() {
    if (_selectedPoints.isEmpty || _mapController == null) return;

    double minLat = _selectedPoints.first.latitude;
    double maxLat = _selectedPoints.first.latitude;
    double minLng = _selectedPoints.first.longitude;
    double maxLng = _selectedPoints.first.longitude;

    for (var point in _selectedPoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - 0.01, minLng - 0.01),
        northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
      ),
      50, // padding
    ));
  }

  void _submitSingleTask() async {
    if (_isMapExpanded) {
      setState(() {
        _isMapExpanded = false;
      });
      return;
    }

    if (!_singleFormKey.currentState!.validate()) return;

    if (_selectedClusterId == null) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Silakan pilih cluster terlebih dahulu',
        type: SnackbarType.danger,
      );
      return;
    }

    if (_selectedOfficerId == null) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Silakan pilih petugas terlebih dahulu',
        type: SnackbarType.danger,
      );
      return;
    }

    if (_selectedPoints.isEmpty) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Silakan tentukan titik-titik patroli terlebih dahulu',
        type: SnackbarType.danger,
      );
      return;
    }

    if (_assignedEndTime.isBefore(_assignedStartTime) ||
        _assignedEndTime.isAtSameMomentAs(_assignedStartTime)) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Waktu selesai harus setelah waktu mulai',
        type: SnackbarType.danger,
      );
      return;
    }

    final result = await _showConfirmationDialog(
      isMultiple: false,
      singleTask: PatrolTask(
        taskId:
            '', // Task ID will be generated by Firebase, use empty string for now
        userId: _adminUserId, // Assign the current admin user's ID
        createdAt: DateTime.now(), // Set creation timestamp
        clusterId: _selectedClusterId!,
        assignedRoute:
            _selectedPoints.map((p) => [p.latitude, p.longitude]).toList(),
        assignedStartTime: _assignedStartTime,
        assignedEndTime: _assignedEndTime,
        officerName: _selectedOfficer?.name,
        clusterName: _selectedClusterName,
        status: 'assigned', // Default status
      ),
    );
    if (result != true) {
      return;
    }

    setState(() {
      _isCreatingSingle = true;
    });

    try {
      final coordinates = _selectedPoints
          .map((point) => [point.latitude, point.longitude])
          .toList();

      context.read<AdminBloc>().add(
            CreateTask(
              clusterId: _selectedClusterId!,
              vehicleId: _vehicleId,
              assignedRoute: coordinates,
              assignedOfficerId: _selectedOfficerId!,
              assignedStartTime: _assignedStartTime,
              assignedEndTime: _assignedEndTime,
              officerName: _selectedOfficer?.name,
              clusterName: _selectedClusterName,
            ),
          );

      await Future.delayed(const Duration(milliseconds: 500));

      await sendPushNotificationToOfficer(
        officerId:
            _selectedOfficerId!, // Use _selectedOfficerId for notification
        title: 'Tugas Patroli Baru',
        body:
            'Anda telah ditugaskan untuk patroli pada ${DateFormat('dd/MM/yyyy - HH:mm').format(_assignedStartTime)}',
        patrolTime: DateFormat('dd/MM/yyyy - HH:mm').format(_assignedStartTime),
        taskId: taskId,
      );
      setState(() {
        _isCreatingSingle = false;
      });

      if (mounted) {
        showCustomSnackbar(
          context: context,
          title: 'Berhasil',
          subtitle: 'Tugas patroli berhasil dibuat dan notifikasi terkirim',
          type: SnackbarType.success,
        );

        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isCreatingSingle = false;
      });

      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Gagal membuat tugas patroli: $e',
        type: SnackbarType.danger,
      );
    }
  }

  bool _isOvernightShift(DateTime startTime, DateTime endTime) {
    // Check if the shift crosses midnight
    return startTime.hour > endTime.hour ||
        (startTime.hour == endTime.hour && startTime.minute > endTime.minute);
  }

  Future<bool?> _showConfirmationDialog({
    required bool isMultiple,
    PatrolTask? singleTask,
    List<PatrolTask>? multipleTasks,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    String officerName =
        singleTask?.officerName ?? _selectedOfficer?.name ?? 'Tidak ditemukan';
    String clusterName =
        singleTask?.clusterName ?? _selectedClusterName ?? 'Unknown Tatar';

    String shiftText = '';
    ShiftType? currentShift;
    if (singleTask != null) {
      // Find the officer associated with this singleTask to get shift info
      final adminState = context.read<AdminBloc>().state;
      List<Officer> allOfficers = [];
      if (adminState is OfficersAndVehiclesLoaded) {
        allOfficers = adminState.officers;
      } else if (adminState is AdminLoaded) {
        allOfficers = _getOfficersFromClusters(adminState.clusters);
      }
      final officer = allOfficers.firstWhere(
        (o) => o.id == singleTask.officerId,
        orElse: () => Officer(
            id: '',
            name: '',
            type: OfficerType.organik,
            shift: ShiftType.pagi,
            clusterId: ''),
      );
      currentShift = officer.shift;
    } else if (_selectedOfficer != null) {
      currentShift = _selectedOfficer!.shift;
    }

    if (currentShift != null) {
      switch (currentShift) {
        case ShiftType.pagi:
          shiftText = 'Pagi (07-15)';
          break;
        case ShiftType.sore:
          shiftText = 'Sore (15-23)';
          break;
        case ShiftType.malam:
          shiftText = 'Malam (23-07)';
          break;
        case ShiftType.siang:
          shiftText = 'Siang (07-19)';
          break;
        case ShiftType.malamPanjang:
          shiftText = 'Malam (19-07)';
          break;
      }
    }

    String typeText =
        _selectedOfficer?.type == OfficerType.organik ? 'Organik' : 'Outsource';

    // Find cluster name from state
    final adminState = context.read<AdminBloc>().state;
    List<User> availableClusters = [];
    if (adminState is ClustersLoaded) {
      availableClusters = adminState.clusters;
    } else if (adminState is AdminLoaded) {
      availableClusters = adminState.clusters;
    } else if (adminState is OfficersAndVehiclesLoaded) {
      availableClusters = adminState.clusters;
    }

    if (_selectedClusterId != null && availableClusters.isNotEmpty) {
      for (var cluster in availableClusters) {
        if (cluster.id == _selectedClusterId) {
          clusterName = cluster.name;
          break;
        }
      }
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            isMultiple
                ? 'Konfirmasi Tugas Patroli Berulang'
                : 'Konfirmasi Tugas Patroli',
            style: boldTextStyle(size: h4),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Detail Tugas:', style: semiBoldTextStyle()),
                if (!isMultiple && singleTask != null) ...[
                  _infoRow('Tatar', clusterName),
                  _infoRow(
                      'Petugas', '$officerName ($typeText - Shift $shiftText)'),
                  _infoRow('Jumlah Titik Patroli',
                      singleTask.assignedRoute!.length.toString()),
                  _infoRow(
                      'Mulai Patroli',
                      DateFormat('dd/MM/yyyy - HH:mm')
                          .format(singleTask.assignedStartTime!)),
                  _infoRow(
                      'Selesai Patroli',
                      DateFormat('dd/MM/yyyy - HH:mm')
                          .format(singleTask.assignedEndTime!)),
                ],
                if (isMultiple &&
                    multipleTasks != null &&
                    startDate != null &&
                    endDate != null) ...[
                  _infoRow(
                      'Jumlah Jenis Tugas', multipleTasks.length.toString()),
                  _infoRow('Rentang Tanggal',
                      '${DateFormat('dd/MM/yyyy').format(startDate)} - ${DateFormat('dd/MM/yyyy').format(endDate)}'),
                  const SizedBox(height: 8),
                  Text('Preview Tugas yang akan dibuat:',
                      style: semiBoldTextStyle()),

                  // PERBAIKAN: Preview yang menampilkan tanggal yang benar
                  ...() {
                    List<Widget> previewWidgets = [];
                    DateTime currentDate = startDate;
                    int taskNumber = 1;

                    while (currentDate
                        .isBefore(endDate.add(const Duration(days: 1)))) {
                      for (var task in multipleTasks) {
                        final String officerIdToFind =
                            task.officerId ?? task.userId ?? '';

                        final officer = availableClusters
                            .expand((c) => c.officers ?? [])
                            .firstWhere(
                              (o) => o.id == officerIdToFind,
                              orElse: () => Officer(
                                id: officerIdToFind,
                                name: task.officerName ?? 'Unknown Officer',
                                type: OfficerType.organik,
                                shift: ShiftType.pagi,
                                clusterId: task.clusterId,
                              ),
                            );

                        // PERBAIKAN: Hitung waktu yang benar untuk preview
                        final startTime = DateTime(
                          currentDate.year,
                          currentDate.month,
                          currentDate.day,
                          task.assignedStartTime!.hour,
                          task.assignedStartTime!.minute,
                        );

                        DateTime endTime;
                        if (_isOvernightShift(
                            task.assignedStartTime!, task.assignedEndTime!)) {
                          endTime = DateTime(
                            currentDate.year,
                            currentDate.month,
                            currentDate.day + 1,
                            task.assignedEndTime!.hour,
                            task.assignedEndTime!.minute,
                          );
                        } else {
                          endTime = DateTime(
                            currentDate.year,
                            currentDate.month,
                            currentDate.day,
                            task.assignedEndTime!.hour,
                            task.assignedEndTime!.minute,
                          );
                        }

                        previewWidgets.add(
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                            child: Text(
                              'Task $taskNumber: ${task.clusterName ?? 'Unknown Tatar'} - ${officer.name}\n'
                              '  Mulai: ${DateFormat('dd/MM/yyyy HH:mm').format(startTime)}\n'
                              '  Selesai: ${DateFormat('dd/MM/yyyy HH:mm').format(endTime)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        );
                        taskNumber++;
                      }
                      currentDate = currentDate.add(const Duration(days: 1));
                    }

                    return previewWidgets;
                  }(),
                ]
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.transparent,
              ),
              child: Text(
                'Batal',
                style: mediumTextStyle(color: kbpBlue900),
              ),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kbpBlue900,
              ),
              child: Text(
                  isMultiple ? 'Ya, Buat Tugas Berulang' : 'Ya, Buat Tugas',
                  style: const TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );
  }

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

  void _updateSelectedOfficer(String officerId, List<Officer> officers,
      {bool isMulti = false}) {
    print('DEBUG _updateSelectedOfficer:');
    print('  - officerId: $officerId');
    print('  - isMulti: $isMulti');
    print('  - officers.length: ${officers.length}');

    final officer = officers.firstWhere(
      (o) => o.id == officerId,
      orElse: () {
        print('  - Officer not found, creating dummy');
        return Officer(
          id: officerId, // PERBAIKAN: Gunakan officerId yang dipilih
          name: 'Officer Not Found',
          type: OfficerType.organik,
          shift: ShiftType.pagi,
          clusterId: '',
        );
      },
    );

    print('  - Found officer: ${officer.name} (${officer.id})');

    setState(() {
      if (isMulti) {
        _multiSelectedOfficerId = officerId; // PERBAIKAN: Set ID yang benar
        _multiSelectedOfficer = officer;
        _setInitialTimeBasedOnShift(officer.type, officer.shift, isMulti: true);

        print('  - Set _multiSelectedOfficerId: $_multiSelectedOfficerId');
        print(
            '  - Set _multiSelectedOfficer.name: ${_multiSelectedOfficer?.name}');
      } else {
        _selectedOfficerId = officerId;
        _selectedOfficer = officer;
        _setInitialTimeBasedOnShift(officer.type, officer.shift);
      }
    });
  }

  void _setInitialTimeBasedOnShift(OfficerType type, ShiftType shift,
      {bool isMulti = false}) {
    final now = DateTime.now();

    // Tambahkan 1 hari untuk jadwal default - mulai besok
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    DateTime startDate;
    DateTime endDate;

    // Tentukan jam mulai dan selesai default berdasarkan type dan shift
    switch (shift) {
      case ShiftType.pagi:
        // Organik: 07:00-15:00
        startDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 7, 0);
        endDate = startDate.add(const Duration(hours: 1));
        break;
      case ShiftType.sore:
        // Organik: 15:00-23:00
        startDate =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15, 0);
        endDate = startDate.add(const Duration(hours: 1));
        break;
      case ShiftType.malam:
        // Organik: 23:00-07:00 (next day)
        startDate =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 23, 0);
        // PERBAIKAN: Set end time ke 7 AM hari berikutnya, bukan midnight
        endDate =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day + 1, 7, 0);
        break;
      case ShiftType.siang:
        // Outsource: 07:00-19:00
        startDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 7, 0);
        endDate = startDate.add(const Duration(hours: 1));
        break;
      case ShiftType.malamPanjang:
        // Outsource: 19:00-07:00 (next day)
        startDate =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 19, 0);
        // PERBAIKAN: Set end time ke 7 AM hari berikutnya, bukan 8 PM
        endDate =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day + 1, 7, 0);
        break;
    }

    // PERBAIKAN: Set state sesuai dengan mode (single atau multi)
    setState(() {
      if (isMulti) {
        _multiAssignedStartTime = startDate;
        _multiAssignedEndTime = endDate;

        print('DEBUG _setInitialTimeBasedOnShift (Multi):');
        print('  - Officer Type: $type');
        print('  - Shift: $shift');
        print('  - Start Time: $_multiAssignedStartTime');
        print('  - End Time: $_multiAssignedEndTime');
        print(
            '  - Is Overnight: ${_isOvernightShift(_multiAssignedStartTime, _multiAssignedEndTime)}');
      } else {
        _assignedStartTime = startDate;
        _assignedEndTime = endDate;

        print('DEBUG _setInitialTimeBasedOnShift (Single):');
        print('  - Officer Type: $type');
        print('  - Shift: $shift');
        print('  - Start Time: $_assignedStartTime');
        print('  - End Time: $_assignedEndTime');
        print(
            '  - Is Overnight: ${_isOvernightShift(_assignedStartTime, _assignedEndTime)}');
      }
    });
  }

  bool _isValidShiftTime(
      DateTime startTime, DateTime endTime, ShiftType shift) {
    final startHour = startTime.hour;
    final endHour = endTime.hour;

    switch (shift) {
      case ShiftType.pagi:
        // 07:00-15:00
        return startHour >= 7 &&
            startHour < 15 &&
            endHour >= 7 &&
            endHour <= 15 &&
            endTime.isAfter(startTime);

      case ShiftType.sore:
        // 15:00-23:00
        return startHour >= 15 &&
            startHour < 23 &&
            endHour >= 15 &&
            endHour <= 23 &&
            endTime.isAfter(startTime);

      case ShiftType.malam:
        // 23:00-07:00 (next day)
        if (startHour >= 23) {
          // Start di malam hari, end bisa di hari yang sama (after 23) atau hari berikutnya (before 7)
          return (endHour >= 23 || (endHour >= 0 && endHour <= 7)) &&
              endTime.isAfter(startTime);
        } else if (startHour >= 0 && startHour < 7) {
          // Start di dini hari, end harus masih di range dini hari
          return endHour >= 0 && endHour <= 7 && endTime.isAfter(startTime);
        }
        return false;

      case ShiftType.siang:
        // 07:00-19:00
        return startHour >= 7 &&
            startHour < 19 &&
            endHour >= 7 &&
            endHour <= 19 &&
            endTime.isAfter(startTime);

      case ShiftType.malamPanjang:
        // 19:00-07:00 (next day)
        if (startHour >= 19) {
          // Start di malam hari, end bisa di hari yang sama (after 19) atau hari berikutnya (before 7)
          return (endHour >= 19 || (endHour >= 0 && endHour <= 7)) &&
              endTime.isAfter(startTime);
        } else if (startHour >= 0 && startHour < 7) {
          // Start di dini hari, end harus masih di range dini hari
          return endHour >= 0 && endHour <= 7 && endTime.isAfter(startTime);
        }
        return false;

      default:
        return false;
    }
  }

  // Helper method to build the common task form section
  Widget _buildTaskForm({
    required GlobalKey<FormState> formKey,
    required String? selectedClusterId,
    required Function(String?) onClusterChanged,
    required String? selectedOfficerId,
    required Function(String?) onOfficerChanged,
    required DateTime assignedStartTime,
    required Function(DateTime) onStartTimeChanged,
    required DateTime assignedEndTime,
    required Function(DateTime) onEndTimeChanged,
    required List<LatLng> selectedPoints,
    required Function(LatLng) onMapTap,
    required Function() onRemoveLastPoint,
    required Function() onExpandMap,
    required GoogleMapController? mapController,
    required Set<Marker> markers,
    required List<User> clusters,
    required List<Officer> filteredOfficers,
    required Function(List<List<double>>) addClusterCoordsToMap,
    required Officer? currentSelectedOfficer,
  }) {
    return Form(
      key: formKey,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Informasi Tugas
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Informasi Tugas',
                    style: boldTextStyle(size: 18),
                  ),
                  const SizedBox(height: 16),

                  // Dropdown Tatar
                  Text(
                    'Tatar',
                    style: boldTextStyle(size: 16),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: kbpBlue900),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: selectedClusterId,
                      decoration: const InputDecoration(
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        border: InputBorder.none,
                      ),
                      hint: const Text('Pilih Tatar'),
                      isExpanded: true,
                      items: clusters.map((cluster) {
                        return DropdownMenuItem(
                          value: cluster.id,
                          child: Text(cluster.name),
                        );
                      }).toList(),
                      onChanged: onClusterChanged,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Silakan pilih cluster';
                        }
                        return null;
                      },
                    ),
                  ),
                  if (selectedClusterId != null) ...[
                    16.height,
                    Text(
                      'Petugas',
                      style: boldTextStyle(size: 16),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: kbpBlue900),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonFormField<String>(
                        value: selectedOfficerId,
                        decoration: const InputDecoration(
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          border: InputBorder.none,
                        ),
                        hint: const Text('Pilih Petugas'),
                        isExpanded: true,
                        items: filteredOfficers.map((officer) {
                          String shiftText = '';
                          switch (officer.shift) {
                            case ShiftType.pagi:
                              shiftText = 'Pagi (07-15)';
                              break;
                            case ShiftType.sore:
                              shiftText = 'Sore (15-23)';
                              break;
                            case ShiftType.malam:
                              shiftText = 'Malam (23-07)';
                              break;
                            case ShiftType.siang:
                              shiftText = 'Siang (07-19)';
                              break;
                            case ShiftType.malamPanjang:
                              shiftText = 'Malam (19-07)';
                              break;
                          }
                          String typeText = officer.type == OfficerType.organik
                              ? 'Organik'
                              : 'Outsource';
                          return DropdownMenuItem(
                            value: officer.id,
                            child: Text(
                                '${officer.name} ($typeText - $shiftText)'),
                          );
                        }).toList(),
                        onChanged: onOfficerChanged,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Silakan pilih petugas';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Jadwal Patroli',
                    style: boldTextStyle(size: 18),
                  ),
                  const SizedBox(height: 4),
                  if (currentSelectedOfficer != null) ...[
                    Text(
                      'Shift ${getShiftDisplayText(currentSelectedOfficer.shift)}',
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        color: kbpBlue700,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Text(
                    'Waktu Mulai',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: neutral900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      if (currentSelectedOfficer == null) {
                        showCustomSnackbar(
                          context: context,
                          title: 'Perhatian',
                          subtitle:
                              'Silakan pilih petugas terlebih dahulu untuk menentukan waktu patroli',
                          type: SnackbarType.warning,
                        );
                        return;
                      }
                      final selectedDate = await showDatePicker(
                        context: context,
                        initialDate: assignedStartTime,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (selectedDate != null) {
                        final selectedTime = await showTimePicker(
                          context: context,
                          initialTime:
                              TimeOfDay.fromDateTime(assignedStartTime),
                          builder: (BuildContext context, Widget? child) {
                            return MediaQuery(
                              data: MediaQuery.of(context).copyWith(
                                alwaysUse24HourFormat: true,
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (selectedTime != null) {
                          bool isValidTime = _isTimeInShiftRange(
                              selectedTime, currentSelectedOfficer.shift);
                          if (!isValidTime) {
                            if (mounted) {
                              showCustomSnackbar(
                                context: context,
                                title: 'Waktu Tidak Valid',
                                subtitle: _getShiftTimeRangeMessage(
                                    currentSelectedOfficer.shift),
                                type: SnackbarType.danger,
                              );
                            }
                            return;
                          }
                          final newStartDate = DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                            selectedTime.hour,
                            selectedTime.minute,
                          );
                          DateTime finalStartDate = newStartDate;
                          if ((currentSelectedOfficer.shift ==
                                      ShiftType.malam ||
                                  currentSelectedOfficer.shift ==
                                      ShiftType.malamPanjang) &&
                              selectedTime.hour < 7) {
                            finalStartDate = DateTime(
                              selectedDate.year,
                              selectedDate.month,
                              selectedDate.day,
                              selectedTime.hour,
                              selectedTime.minute,
                            );
                          }
                          onStartTimeChanged(finalStartDate);
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: kbpBlue900),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat('dd/MM/yyyy - HH:mm')
                                .format(assignedStartTime),
                            style: const TextStyle(fontSize: 16),
                          ),
                          const Icon(Icons.calendar_today, color: kbpBlue900),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Waktu Selesai',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: neutral900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      if (currentSelectedOfficer == null) {
                        showCustomSnackbar(
                          context: context,
                          title: 'Perhatian',
                          subtitle:
                              'Silakan pilih petugas terlebih dahulu untuk menentukan waktu patroli',
                          type: SnackbarType.warning,
                        );
                        return;
                      }
                      final selectedDate = await showDatePicker(
                        context: context,
                        initialDate: assignedEndTime,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (selectedDate != null) {
                        final selectedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(assignedEndTime),
                          builder: (BuildContext context, Widget? child) {
                            return MediaQuery(
                              data: MediaQuery.of(context).copyWith(
                                alwaysUse24HourFormat: true,
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (selectedTime != null) {
                          bool isValidTime = _isTimeInShiftRange(
                              selectedTime, currentSelectedOfficer.shift);
                          if (!isValidTime) {
                            if (mounted) {
                              showCustomSnackbar(
                                context: context,
                                title: 'Waktu Tidak Valid',
                                subtitle: _getShiftTimeRangeMessage(
                                    currentSelectedOfficer.shift),
                                type: SnackbarType.danger,
                              );
                            }
                            return;
                          }
                          DateTime newEndTime = DateTime(
                            selectedDate.year,
                            selectedDate.month,
                            selectedDate.day,
                            selectedTime.hour,
                            selectedTime.minute,
                          );
                          if ((currentSelectedOfficer.shift ==
                                      ShiftType.malam ||
                                  currentSelectedOfficer.shift ==
                                      ShiftType.malamPanjang) &&
                              selectedTime.hour < 7) {
                            newEndTime =
                                newEndTime.add(const Duration(days: 1));
                          }
                          if (newEndTime.isBefore(assignedStartTime) ||
                              newEndTime.isAtSameMomentAs(assignedStartTime)) {
                            showCustomSnackbar(
                              context: context,
                              title: 'Waktu Tidak Valid',
                              subtitle:
                                  'Waktu selesai harus setelah waktu mulai',
                              type: SnackbarType.danger,
                            );
                            return;
                          }
                          onEndTimeChanged(newEndTime);
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: kbpBlue900),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat('dd/MM/yyyy - HH:mm')
                                .format(assignedEndTime),
                            style: const TextStyle(fontSize: 16),
                          ),
                          const Icon(Icons.calendar_today, color: kbpBlue900),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Titik Patroli',
                        style: boldTextStyle(size: 18),
                      ),
                      ElevatedButton.icon(
                        onPressed: onExpandMap,
                        icon: const Icon(Icons.fullscreen,
                            color: Colors.white, size: 16),
                        label: const Text('Perbesar Peta'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kbpBlue900,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Klik pada peta untuk menentukan titik-titik patroli.',
                    style: TextStyle(color: neutral600),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: kbpBlue300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        children: [
                          MapSection(
                            mapController: mapController,
                            markers: markers,
                            onMapTap: onMapTap,
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: FloatingActionButton.small(
                              heroTag: 'expand_map_form',
                              backgroundColor: Colors.white,
                              foregroundColor: kbpBlue900,
                              onPressed: onExpandMap,
                              child: const Icon(Icons.fullscreen),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Titik dipilih: ${selectedPoints.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: neutral700,
                        ),
                      ),
                      TextButton.icon(
                        onPressed:
                            selectedPoints.isEmpty ? null : onRemoveLastPoint,
                        icon: const Icon(Icons.undo, size: 16),
                        label: const Text('Hapus Titik Terakhir'),
                        style: TextButton.styleFrom(
                          foregroundColor: kbpBlue900,
                          disabledForegroundColor: neutral400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addMultiClusterCoordinatesToMap(List<List<double>> coordinates) {
    setState(() {
      _multiSelectedPoints.clear();

      for (var coordinate in coordinates) {
        if (coordinate.length >= 2) {
          final point = LatLng(coordinate[0], coordinate[1]);
          _multiSelectedPoints.add(point);
        }
      }

      print('DEBUG _addMultiClusterCoordinatesToMap:');
      print(
          '  - Added ${_multiSelectedPoints.length} points to multi selection');
      print('  - Points: $_multiSelectedPoints');
    });
  }

  // Multiple Task Assignment Logic
  void _addStagedTask() {
    if (!_multipleTaskFormKey.currentState!.validate()) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Harap lengkapi semua bidang untuk menambahkan tugas',
        type: SnackbarType.danger,
      );
      return;
    }

    if (_multiSelectedClusterId == null) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Silakan pilih cluster terlebih dahulu',
        type: SnackbarType.danger,
      );
      return;
    }

    if (_multiSelectedOfficerId == null) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Silakan pilih petugas terlebih dahulu',
        type: SnackbarType.danger,
      );
      return;
    }

    if (_multiSelectedPoints.isEmpty) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Silakan tentukan titik-titik patroli terlebih dahulu',
        type: SnackbarType.danger,
      );
      return;
    }

    if (_multiAssignedEndTime.isBefore(_multiAssignedStartTime) ||
        _multiAssignedEndTime.isAtSameMomentAs(_multiAssignedStartTime)) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Waktu selesai harus setelah waktu mulai',
        type: SnackbarType.danger,
      );
      return;
    }

    // PERBAIKAN: Pastikan data officer ter-set dengan benar
    print('DEBUG _addStagedTask:');
    print('  - _multiSelectedOfficerId: $_multiSelectedOfficerId');
    print('  - _multiSelectedOfficer?.id: ${_multiSelectedOfficer?.id}');
    print('  - _multiSelectedOfficer?.name: ${_multiSelectedOfficer?.name}');

    final newStagedTask = PatrolTask(
      taskId: '',
      userId:
          _multiSelectedOfficerId!, // PERBAIKAN: Gunakan officerId sebagai userId
      createdAt: DateTime.now(),
      clusterId: _multiSelectedClusterId!,
      assignedRoute:
          _multiSelectedPoints.map((p) => [p.latitude, p.longitude]).toList(),
      assignedStartTime: _multiAssignedStartTime,
      assignedEndTime: _multiAssignedEndTime,
      officerName: _multiSelectedOfficer?.name ??
          'Unknown Officer', // PERBAIKAN: Pastikan officer name ada
      clusterName: _multiSelectedClusterName ?? 'Unknown Cluster',
      status: 'assigned',
      // TAMBAHAN: Set properti tambahan jika ada
      officerId:
          _multiSelectedOfficerId!, // TAMBAHAN: Jika ada property officerId terpisah
    );

    setState(() {
      _stagedTasks.add(newStagedTask);

      // PERBAIKAN: Clear form fields dengan lebih hati-hati
      _multiSelectedOfficerId = null;
      _multiSelectedOfficer = null;
      _multiSelectedPoints.clear();

      // Reset times to default for the next entry
      _multiAssignedStartTime =
          DateTime.now().add(const Duration(days: 1, hours: 7));
      _multiAssignedEndTime =
          _multiAssignedStartTime.add(const Duration(hours: 1));
    });

    showCustomSnackbar(
      context: context,
      title: 'Berhasil',
      subtitle: 'Tugas berhasil ditambahkan ke daftar',
      type: SnackbarType.success,
    );
  }

  void _removeStagedTask(int index) {
    setState(() {
      _stagedTasks.removeAt(index);
    });
    showCustomSnackbar(
      context: context,
      title: 'Dihapus',
      subtitle: 'Tugas dihapus dari daftar',
      type: SnackbarType.success,
    );
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 7)), // Max 7 days range
      initialDateRange: _multipleStartDate != null && _multipleEndDate != null
          ? DateTimeRange(start: _multipleStartDate!, end: _multipleEndDate!)
          : null,
    );

    if (picked != null) {
      if (picked.end.difference(picked.start).inDays > 6) {
        // Check for max 7 days (0-indexed difference)
        showCustomSnackbar(
          context: context,
          title: 'Rentang Tanggal Terlalu Panjang',
          subtitle: 'Maksimal rentang tanggal adalah 7 hari.',
          type: SnackbarType.warning,
        );
        return;
      }
      setState(() {
        _multipleStartDate = picked.start;
        _multipleEndDate = picked.end;
      });
    }
  }

  void _showProgressDialog() {
    if (_showingProgressDialog) return;

    _showingProgressDialog = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // Mencegah back button
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: kbpBlue100,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: const Icon(
                      Icons.task_alt_rounded,
                      size: 40,
                      color: kbpBlue900,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Title
                  Text(
                    'Membuat Tugas Patroli',
                    style: boldTextStyle(size: 20, color: neutral900),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    'Sedang memproses $_totalTasksToCreate tugas...',
                    style: regularTextStyle(size: 14, color: neutral600),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 24),

                  // Progress indicator dengan persentase
                  ValueListenableBuilder<int>(
                    valueListenable: ValueNotifier(_tasksCreated),
                    builder: (context, value, child) {
                      double progress = _totalTasksToCreate > 0
                          ? value / _totalTasksToCreate
                          : 0.0;
                      int percentage = (progress * 100).round();

                      return Column(
                        children: [
                          // Progress bar
                          Container(
                            width: double.infinity,
                            height: 8,
                            decoration: BoxDecoration(
                              color: neutral200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Stack(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  width: MediaQuery.of(context).size.width *
                                      0.6 *
                                      progress,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [kbpBlue600, kbpBlue900],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Progress text
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$value dari $_totalTasksToCreate tugas',
                                style: mediumTextStyle(
                                    size: 12, color: neutral600),
                              ),
                              Text(
                                '$percentage%',
                                style:
                                    boldTextStyle(size: 12, color: kbpBlue900),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Warning message
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: warningY50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: warningY200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: warningY500,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mohon Tunggu',
                                style: semiBoldTextStyle(
                                    size: 12, color: warningY400),
                              ),
                              Text(
                                'Jangan meninggalkan aplikasi atau menekan tombol kembali selama proses berlangsung',
                                style: regularTextStyle(
                                    size: 11, color: warningY300),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Status text
                  ValueListenableBuilder<String>(
                    valueListenable: ValueNotifier(_getCurrentStatusText()),
                    builder: (context, status, child) {
                      return Text(
                        status,
                        style: regularTextStyle(size: 12, color: neutral500),
                        textAlign: TextAlign.center,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

// TAMBAHAN: Method untuk mendapatkan status text saat ini
  String _getCurrentStatusText() {
    if (_tasksCreated == 0) {
      return 'Mempersiapkan tugas...';
    } else if (_tasksCreated < _totalTasksToCreate) {
      return 'Membuat tugas ${_tasksCreated + 1} dari $_totalTasksToCreate...';
    } else {
      return 'Menyelesaikan proses...';
    }
  }

// TAMBAHAN: Method untuk update progress
  void _updateProgress(int completed) {
    setState(() {
      _tasksCreated = completed;
    });
  }

// TAMBAHAN: Method untuk menutup progress dialog
  void _hideProgressDialog() {
    if (_showingProgressDialog) {
      _showingProgressDialog = false;
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
    }
  }

// PERBAIKAN: Update method _assignMultipleTasks dengan progress tracking
  void _assignMultipleTasks() async {
    if (_stagedTasks.isEmpty) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Tidak ada tugas dalam daftar untuk ditetapkan',
        type: SnackbarType.danger,
      );
      return;
    }
    if (_multipleStartDate == null || _multipleEndDate == null) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Silakan pilih rentang tanggal',
        type: SnackbarType.danger,
      );
      return;
    }

    final result = await _showConfirmationDialog(
      isMultiple: true,
      multipleTasks: _stagedTasks,
      startDate: _multipleStartDate,
      endDate: _multipleEndDate,
    );
    if (result != true) {
      return;
    }

    setState(() {
      _isAssigningMultiple = true;
    });

    try {
      List<PatrolTask> tasksToCreate = [];
      DateTime currentDate = _multipleStartDate!;

      print('DEBUG _assignMultipleTasks:');
      print('  - Start Date: $_multipleStartDate');
      print('  - End Date: $_multipleEndDate');
      print('  - Staged Tasks Count: ${_stagedTasks.length}');

      // TAMBAHAN: Hitung total tasks yang akan dibuat
      int totalDays =
          _multipleEndDate!.difference(_multipleStartDate!).inDays + 1;
      _totalTasksToCreate = totalDays * _stagedTasks.length;
      _tasksCreated = 0;

      print('  - Total tasks to create: $_totalTasksToCreate');

      // TAMBAHAN: Tampilkan progress dialog
      _showProgressDialog();

      // TAMBAHAN: Delay kecil untuk memastikan dialog muncul
      await Future.delayed(const Duration(milliseconds: 500));

      while (currentDate
          .isBefore(_multipleEndDate!.add(const Duration(days: 1)))) {
        print('  - Processing date: $currentDate');

        for (var stagedTask in _stagedTasks) {
          final String assignedOfficerId =
              stagedTask.officerId ?? stagedTask.userId ?? '';

          if (assignedOfficerId.isEmpty) {
            print('WARNING: No officer ID found for staged task');
            continue;
          }

          print('    - Processing task for officer: $assignedOfficerId');
          print('    - Original start time: ${stagedTask.assignedStartTime}');
          print('    - Original end time: ${stagedTask.assignedEndTime}');

          final originalStartTime = stagedTask.assignedStartTime!;
          final originalEndTime = stagedTask.assignedEndTime!;

          // Set start time dengan tanggal currentDate
          final assignedStartTime = DateTime(
            currentDate.year,
            currentDate.month,
            currentDate.day,
            originalStartTime.hour,
            originalStartTime.minute,
          );

          print('    - New start time: $assignedStartTime');

          // PERBAIKAN: Untuk end time, gunakan method _isOvernightShift
          DateTime assignedEndTime;

          if (_isOvernightShift(originalStartTime, originalEndTime)) {
            // Ini overnight shift, end time harus di hari berikutnya
            assignedEndTime = DateTime(
              currentDate.year,
              currentDate.month,
              currentDate.day + 1,
              originalEndTime.hour,
              originalEndTime.minute,
            );
            print('    - Detected overnight shift, end time moved to next day');
          } else {
            // Normal shift, same day
            assignedEndTime = DateTime(
              currentDate.year,
              currentDate.month,
              currentDate.day,
              originalEndTime.hour,
              originalEndTime.minute,
            );
            print('    - Normal shift, same day end time');
          }

          print('    - Final end time: $assignedEndTime');

          // TAMBAHAN: Double check untuk memastikan end time selalu setelah start time
          if (assignedEndTime.isBefore(assignedStartTime) ||
              assignedEndTime.isAtSameMomentAs(assignedStartTime)) {
            print('    - WARNING: End time is not after start time, fixing...');
            if (_isOvernightShift(originalStartTime, originalEndTime)) {
              // Untuk overnight shift, pastikan end time di hari berikutnya
              assignedEndTime = DateTime(
                currentDate.year,
                currentDate.month,
                currentDate.day + 1,
                originalEndTime.hour,
                originalEndTime.minute,
              );
            } else {
              // Untuk normal shift, tambah 1 jam
              assignedEndTime = assignedStartTime.add(const Duration(hours: 1));
            }
            print('    - Fixed end time: $assignedEndTime');
          }

          final taskToCreate = stagedTask.copyWith(
            assignedStartTime: assignedStartTime,
            assignedEndTime: assignedEndTime,
            userId: assignedOfficerId,
            officerId: assignedOfficerId,
          );

          tasksToCreate.add(taskToCreate);

          print('    - Task created:');
          print('      Start: ${taskToCreate.assignedStartTime}');
          print('      End: ${taskToCreate.assignedEndTime}');
          print(
              '      Is Overnight: ${_isOvernightShift(taskToCreate.assignedStartTime!, taskToCreate.assignedEndTime!)}');
        }

        currentDate = currentDate.add(const Duration(days: 1));
      }

      print('  - Total tasks to create: ${tasksToCreate.length}');

      // PERBAIKAN: Dispatch tasks dengan progress tracking
      for (int i = 0; i < tasksToCreate.length; i++) {
        final task = tasksToCreate[i];
        final String assignedOfficerId = task.officerId ?? task.userId ?? '';

        if (assignedOfficerId.isEmpty) {
          print('ERROR: Cannot create task without officer ID');
          // TAMBAHAN: Update progress bahkan jika skip
          _updateProgress(i + 1);
          continue;
        }

        print(
            'Creating task ${i + 1}/${tasksToCreate.length}: ${task.assignedStartTime} - ${task.assignedEndTime}');

        // TAMBAHAN: Update progress dialog
        _updateProgress(i + 1);

        context.read<AdminBloc>().add(
              CreateTask(
                clusterId: task.clusterId,
                vehicleId: '',
                assignedRoute: task.assignedRoute!,
                assignedOfficerId: assignedOfficerId,
                assignedStartTime: task.assignedStartTime!,
                assignedEndTime: task.assignedEndTime!,
                officerName: task.officerName,
                clusterName: task.clusterName,
              ),
            );

        // TAMBAHAN: Delay kecil untuk UI update dan mencegah overload
        await Future.delayed(const Duration(milliseconds: 300));

        // Send notification for each task
        // try {
        //   await sendPushNotificationToOfficer(
        //     officerId: assignedOfficerId,
        //     title: 'Tugas Patroli Baru',
        //     body: 'Anda telah ditugaskan untuk patroli pada ${DateFormat('dd/MM/yyyy - HH:mm').format(task.assignedStartTime!)}',
        //     patrolTime: DateFormat('dd/MM/yyyy - HH:mm').format(task.assignedStartTime!),
        //     taskId: null,
        //   );
        // } catch (e) {
        //   print('Failed to send notification to officer $assignedOfficerId: $e');
        // }

        // TAMBAHAN: Delay kecil setelah notification
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // TAMBAHAN: Delay sebelum menutup dialog
      await Future.delayed(const Duration(milliseconds: 1000));

      // TAMBAHAN: Hide progress dialog
      _hideProgressDialog();

      setState(() {
        _isAssigningMultiple = false;
        _stagedTasks.clear();
        _multipleStartDate = null;
        _multipleEndDate = null;
        _multiSelectedClusterId = null;
        _multiSelectedOfficerId = null;
        _multiSelectedOfficer = null;
        _multiSelectedClusterName = null;
        _multiSelectedPoints.clear();
      });

      if (mounted) {
        showCustomSnackbar(
          context: context,
          title: 'Berhasil',
          subtitle:
              'Semua tugas patroli berhasil dibuat dan notifikasi terkirim',
          type: SnackbarType.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      // TAMBAHAN: Hide progress dialog on error
      _hideProgressDialog();

      setState(() {
        _isAssigningMultiple = false;
      });
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Gagal membuat tugas patroli berulang: $e',
        type: SnackbarType.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isMapExpanded) {
      return Scaffold(
        body: Stack(
          children: [
            MapSection(
              mapController: _mapController,
              markers: _markers,
              onMapTap: _handleMapTap,
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.white.withOpacity(0.9),
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Penentuan Titik Patroli',
                            style: boldTextStyle(size: 16),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: kbpBlue900),
                            onPressed: () {
                              setState(() {
                                _isMapExpanded = false;
                              });
                            },
                          ),
                        ],
                      ),
                      Text(
                        'Titik dipilih: ${_selectedPoints.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          color: neutral700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Klik pada peta untuk menambahkan titik patroli.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: neutral600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _selectedPoints.isEmpty
                                  ? null
                                  : () {
                                      setState(() {
                                        if (_selectedPoints.isNotEmpty) {
                                          _selectedPoints.removeLast();
                                          _updateMarkers();
                                        }
                                      });
                                    },
                              icon: const Icon(Icons.undo, color: Colors.white),
                              label: const Text('Hapus Titik Terakhir'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kbpBlue700,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: neutral300,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isMapExpanded = false;
                                });
                              },
                              icon:
                                  const Icon(Icons.check, color: Colors.white),
                              label: const Text('Selesai'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kbpBlue900,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        // TAMBAHAN: Cegah back button jika sedang processing
        if (_isAssigningMultiple || _showingProgressDialog) {
          showCustomSnackbar(
            context: context,
            title: 'Proses Sedang Berlangsung',
            subtitle: 'Mohon tunggu hingga pembuatan tugas selesai',
            type: SnackbarType.warning,
          );
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Buat Tugas Patroli'),
          backgroundColor: kbpBlue900,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: 'Single'),
              Tab(text: 'Multiple'),
            ],
          ),
        ),
        body: BlocConsumer<AdminBloc, AdminState>(
          listener: (context, state) {
            if (state is CreateTaskSuccess) {
              _createdTaskId = state.taskId;
              // No need to show snackbar here, it's handled by _submitSingleTask or _assignMultipleTasks
            } else if (state is CreateTaskError) {
              showCustomSnackbar(
                context: context,
                title: 'Error',
                subtitle: state.message,
                type: SnackbarType.danger,
              );
              setState(() {
                _isCreatingSingle = false;
                _isAssigningMultiple = false;
              });
            }
          },
          builder: (context, state) {
            if (state is AdminLoading ||
                state is OfficersAndVehiclesLoading ||
                state is ClustersLoading) {
              return Center(
                child: lottie.LottieBuilder.asset(
                  'assets/lottie/maps_loading.json',
                  width: 200,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              );
            }

            if (state is AdminError ||
                state is OfficersAndVehiclesError ||
                state is ClustersError) {
              final errorMessage = state is AdminError
                  ? state.message
                  : state is ClustersError
                      ? state.message
                      : (state as OfficersAndVehiclesError).message;

              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Error: $errorMessage',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        context.read<AdminBloc>().add(const LoadAllClusters());
                        context
                            .read<AdminBloc>()
                            .add(const LoadOfficersAndVehicles());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kbpBlue900,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              );
            }

            List<Officer> officers = [];
            List<String> vehicles = [];
            List<User> clusters = [];
            List<List<double>>? selectedClusterCoordinates;

            if (state is OfficersAndVehiclesLoaded) {
              officers = state.officers;
              vehicles = state.vehicles;
              clusters = state.clusters;
            } else if (state is AdminLoaded) {
              officers = _getOfficersFromClusters(state.clusters);
              vehicles = state.vehicles;
              clusters = state.clusters;
            } else if (state is ClustersLoaded) {
              clusters = state.clusters;

              final adminState = context.read<AdminBloc>().state;
              if (adminState is OfficersAndVehiclesLoaded) {
                officers = adminState.officers;
                vehicles = adminState.vehicles;
              } else if (adminState is AdminLoaded) {
                officers = _getOfficersFromClusters(adminState.clusters);
                vehicles = adminState.vehicles;
              }
            }

            // Get coordinates for the selected cluster for Single Tab
            if (_selectedClusterId != null) {
              final selectedCluster = clusters.firstWhere(
                (cluster) => cluster.id == _selectedClusterId,
                orElse: () => User(id: '', email: '', name: '', role: ''),
              );
              if (selectedCluster.id.isNotEmpty &&
                  selectedCluster.clusterCoordinates != null) {
                selectedClusterCoordinates = selectedCluster.clusterCoordinates;
                if (selectedClusterCoordinates != null &&
                    _selectedPoints.isEmpty) {
                  Future.microtask(() {
                    _addClusterCoordinatesToMap(selectedClusterCoordinates!);
                  });
                }
              }
            }

            // Filter officers for Single Tab
            List<Officer> filteredOfficersSingle = officers;
            if (_selectedClusterId != null && _selectedClusterId!.isNotEmpty) {
              filteredOfficersSingle = officers
                  .where((officer) => officer.clusterId == _selectedClusterId)
                  .toList();
            }

            // Filter officers for Multiple Tab
            List<Officer> filteredOfficersMulti = officers;
            if (_multiSelectedClusterId != null &&
                _multiSelectedClusterId!.isNotEmpty) {
              filteredOfficersMulti = officers
                  .where(
                      (officer) => officer.clusterId == _multiSelectedClusterId)
                  .toList();
            }

            return TabBarView(
              controller: _tabController,
              children: [
                // Single Task Tab
                Column(
                  children: [
                    Expanded(
                      child: _buildTaskForm(
                        formKey: _singleFormKey,
                        selectedClusterId: _selectedClusterId,
                        onClusterChanged: (value) {
                          setState(() {
                            _selectedClusterId = value;
                            if (value != null) {
                              final selectedCluster = clusters.firstWhere(
                                (cluster) => cluster.id == value,
                                orElse: () =>
                                    User(id: '', email: '', name: '', role: ''),
                              );
                              if (selectedCluster.id.isNotEmpty) {
                                _selectedClusterName = selectedCluster.name;
                              }
                            }
                            _selectedOfficerId = null;
                            _selectedOfficer = null;
                            _selectedPoints.clear();
                            _markers.clear();
                          });
                        },
                        selectedOfficerId: _selectedOfficerId,
                        onOfficerChanged: (value) {
                          setState(() {
                            _selectedOfficerId = value;
                            if (value != null) {
                              _updateSelectedOfficer(
                                  value, filteredOfficersSingle);
                            }
                          });
                        },
                        assignedStartTime: _assignedStartTime,
                        onStartTimeChanged: (newTime) {
                          setState(() {
                            _assignedStartTime = newTime;
                            _updateEndTimeBasedOnStartTime(
                                _assignedStartTime, _selectedOfficer,
                                (endTime) {
                              setState(() {
                                _assignedEndTime = endTime;
                              });
                            });
                          });
                        },
                        assignedEndTime: _assignedEndTime,
                        onEndTimeChanged: (newTime) {
                          setState(() {
                            _assignedEndTime = newTime;
                          });
                        },
                        selectedPoints: _selectedPoints,
                        onMapTap: _handleMapTap,
                        onRemoveLastPoint: () {
                          setState(() {
                            if (_selectedPoints.isNotEmpty) {
                              _selectedPoints.removeLast();
                              _updateMarkers();
                            }
                          });
                        },
                        onExpandMap: () {
                          setState(() {
                            _isMapExpanded = true;
                          });
                        },
                        mapController: _mapController,
                        markers: _markers,
                        clusters: clusters,
                        filteredOfficers: filteredOfficersSingle,
                        addClusterCoordsToMap: _addClusterCoordinatesToMap,
                        currentSelectedOfficer: _selectedOfficer,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed:
                              _isCreatingSingle ? null : _submitSingleTask,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kbpBlue900,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            disabledBackgroundColor: neutral300,
                          ),
                          child: _isCreatingSingle
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 3,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Membuat Tugas...',
                                      style: boldTextStyle(
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  'Buat Tugas Patroli',
                                  style: boldTextStyle(
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Multiple Task Tab
                Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Tambahkan Tugas ke Daftar',
                                style: boldTextStyle(size: 18),
                              ),
                              const SizedBox(height: 16),
                              _buildTaskForm(
                                formKey: _multipleTaskFormKey,
                                selectedClusterId: _multiSelectedClusterId,
                                onClusterChanged: (value) {
                                  print(
                                      'DEBUG onClusterChanged (Multi) - START:');
                                  print(
                                      '  - Old cluster: $_multiSelectedClusterId');
                                  print('  - New cluster: $value');

                                  setState(() {
                                    _multiSelectedClusterId = value;

                                    // Reset officer selection ketika cluster berubah
                                    _multiSelectedOfficerId = null;
                                    _multiSelectedOfficer = null;

                                    if (value != null) {
                                      final selectedCluster =
                                          clusters.firstWhere(
                                        (cluster) => cluster.id == value,
                                        orElse: () => User(
                                            id: '',
                                            email: '',
                                            name: '',
                                            role: ''),
                                      );

                                      if (selectedCluster.id.isNotEmpty) {
                                        _multiSelectedClusterName =
                                            selectedCluster.name;

                                        print(
                                            'DEBUG onClusterChanged (Multi) - Cluster found:');
                                        print(
                                            '  - Cluster name: ${selectedCluster.name}');
                                        print(
                                            '  - Has coordinates: ${selectedCluster.clusterCoordinates != null}');
                                        print(
                                            '  - Coordinates count: ${selectedCluster.clusterCoordinates?.length ?? 0}');

                                        // PERBAIKAN: Auto-load cluster coordinates untuk multi task
                                        if (selectedCluster
                                                    .clusterCoordinates !=
                                                null &&
                                            selectedCluster.clusterCoordinates!
                                                .isNotEmpty) {
                                          print('  - Loading coordinates...');

                                          // Clear existing points first
                                          _multiSelectedPoints.clear();

                                          // Load new coordinates
                                          for (var coordinate in selectedCluster
                                              .clusterCoordinates!) {
                                            if (coordinate.length >= 2) {
                                              final point = LatLng(
                                                  coordinate[0], coordinate[1]);
                                              _multiSelectedPoints.add(point);
                                            }
                                          }

                                          print(
                                              '  - Added ${_multiSelectedPoints.length} points to multi selection');
                                        } else {
                                          print(
                                              '  - No coordinates found, clearing points');
                                          // Clear points jika cluster tidak memiliki coordinates
                                          _multiSelectedPoints.clear();
                                        }
                                      } else {
                                        print(
                                            'DEBUG onClusterChanged (Multi) - Cluster not found');
                                        _multiSelectedClusterName = null;
                                        _multiSelectedPoints.clear();
                                      }
                                    } else {
                                      print(
                                          'DEBUG onClusterChanged (Multi) - Value is null');
                                      _multiSelectedClusterName = null;
                                      _multiSelectedPoints.clear();
                                    }
                                  });

                                  print('DEBUG onClusterChanged (Multi) - END');
                                  print(
                                      '  - Final points count: ${_multiSelectedPoints.length}');
                                },
                                selectedOfficerId: _multiSelectedOfficerId,
                                onOfficerChanged: (value) {
                                  setState(() {
                                    _multiSelectedOfficerId = value;
                                    if (value != null) {
                                      _updateSelectedOfficer(
                                          value, filteredOfficersMulti,
                                          isMulti: true);
                                    }
                                  });
                                },
                                assignedStartTime: _multiAssignedStartTime,
                                onStartTimeChanged: (newTime) {
                                  setState(() {
                                    _multiAssignedStartTime = newTime;
                                    _updateEndTimeBasedOnStartTime(
                                        _multiAssignedStartTime,
                                        _multiSelectedOfficer, (endTime) {
                                      setState(() {
                                        _multiAssignedEndTime = endTime;
                                      });
                                    });
                                  });
                                },
                                assignedEndTime: _multiAssignedEndTime,
                                onEndTimeChanged: (newTime) {
                                  setState(() {
                                    _multiAssignedEndTime = newTime;
                                  });
                                },
                                selectedPoints: _multiSelectedPoints,
                                onMapTap: (position) {
                                  setState(() {
                                    _multiSelectedPoints.add(position);
                                  });
                                },
                                onRemoveLastPoint: () {
                                  setState(() {
                                    if (_multiSelectedPoints.isNotEmpty) {
                                      _multiSelectedPoints.removeLast();
                                    }
                                  });
                                },
                                onExpandMap: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) =>
                                        _buildMultiMapDialog(),
                                  );
                                },
                                mapController: null,
                                markers: {},
                                clusters: clusters,
                                filteredOfficers: filteredOfficersMulti,
                                addClusterCoordsToMap:
                                    _addMultiClusterCoordinatesToMap,
                                currentSelectedOfficer: _multiSelectedOfficer,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _addStagedTask,
                                icon:
                                    const Icon(Icons.add, color: Colors.white),
                                label: const Text('Tambahkan ke Daftar Tugas'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kbpBlue700,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Daftar Tugas yang Akan Ditetapkan',
                                style: boldTextStyle(size: 18),
                              ),
                              const SizedBox(height: 16),
                              _stagedTasks.isEmpty
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: Text(
                                          'Belum ada tugas dalam daftar.',
                                          style: TextStyle(
                                              fontStyle: FontStyle.italic,
                                              color: neutral600),
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: _stagedTasks.length,
                                      itemBuilder: (context, index) {
                                        final task = _stagedTasks[index];

                                        // PERBAIKAN: Gunakan userId atau officerId untuk mencari officer
                                        final String officerIdToFind =
                                            task.officerId ?? task.userId ?? '';

                                        print('DEBUG ListView.builder:');
                                        print(
                                            '  - task.officerId: ${task.officerId}');
                                        print(
                                            '  - task.userId: ${task.userId}');
                                        print(
                                            '  - officerIdToFind: $officerIdToFind');
                                        print(
                                            '  - task.officerName: ${task.officerName}');

                                        final officer = officers.firstWhere(
                                          (o) => o.id == officerIdToFind,
                                          orElse: () {
                                            print(
                                                '  - Officer not found in officers list');
                                            return Officer(
                                              id: officerIdToFind,
                                              name: task.officerName ??
                                                  'Unknown Officer', // PERBAIKAN: Gunakan officerName dari task
                                              type: OfficerType.organik,
                                              shift: ShiftType.pagi,
                                              clusterId: task.clusterId,
                                            );
                                          },
                                        );

                                        print(
                                            '  - Final officer.name: ${officer.name}');

                                        return Card(
                                          margin: const EdgeInsets.only(
                                              bottom: 8.0),
                                          elevation: 2,
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        '${task.clusterName ?? 'N/A'} - ${officer.name}',
                                                        style: boldTextStyle(
                                                            size: 16),
                                                      ),
                                                      Text(
                                                        'Waktu: ${DateFormat('HH:mm').format(task.assignedStartTime!)} - ${DateFormat('HH:mm').format(task.assignedEndTime!)}',
                                                        style: mediumTextStyle(
                                                            size: 14,
                                                            color: neutral700),
                                                      ),
                                                      Text(
                                                        'Titik: ${task.assignedRoute!.length}',
                                                        style: mediumTextStyle(
                                                            size: 14,
                                                            color: neutral700),
                                                      ),
                                                      // TAMBAHAN: Debug info
                                                      if (officerIdToFind
                                                          .isNotEmpty) ...[
                                                        Text(
                                                          'Officer ID: $officerIdToFind',
                                                          style: TextStyle(
                                                              fontSize: 10,
                                                              color:
                                                                  neutral500),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete,
                                                      color: Colors.red),
                                                  onPressed: () =>
                                                      _removeStagedTask(index),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                              const SizedBox(height: 24),
                              Text(
                                'Rentang Tanggal Penugasan',
                                style: boldTextStyle(size: 18),
                              ),
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: _pickDateRange,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: kbpBlue900),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        _multipleStartDate == null
                                            ? 'Pilih Rentang Tanggal (Maks 7 Hari)'
                                            : '${DateFormat('dd/MM/yyyy').format(_multipleStartDate!)} - ${DateFormat('dd/MM/yyyy').format(_multipleEndDate!)}',
                                        style: const TextStyle(fontSize: 16),
                                      ),
                                      const Icon(Icons.calendar_today,
                                          color: kbpBlue900),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: (_isAssigningMultiple ||
                                        _stagedTasks.isEmpty ||
                                        _multipleStartDate == null ||
                                        _showingProgressDialog) // TAMBAHAN: Disable jika progress dialog tampil
                                    ? null
                                    : _assignMultipleTasks,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kbpBlue900,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  disabledBackgroundColor: neutral300,
                                ),
                                child: _isAssigningMultiple ||
                                        _showingProgressDialog
                                    ? Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 3,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            _showingProgressDialog
                                                ? 'Memproses Tugas...'
                                                : 'Menetapkan Tugas...',
                                            style: boldTextStyle(
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        'Tetapkan Tugas Berulang',
                                        style: boldTextStyle(
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // TAMBAHAN: Dialog untuk expand map di multi task
  Widget _buildMultiMapDialog() {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kbpBlue900,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pilih Titik Patroli',
                    style: boldTextStyle(color: Colors.white, size: 18),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Map
            Expanded(
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(-6.200000, 106.816666), // Jakarta
                      zoom: 11.0,
                    ),
                    markers: Set<Marker>.from(
                      _multiSelectedPoints.asMap().entries.map((entry) {
                        return Marker(
                          markerId: MarkerId('multi_point_${entry.key}'),
                          position: entry.value,
                          infoWindow: InfoWindow(
                            title: 'Titik ${entry.key + 1}',
                            snippet: 'Tap untuk menghapus',
                          ),
                        );
                      }),
                    ),
                    onMapCreated: (GoogleMapController controller) {
                      // Auto fit bounds jika ada points
                      if (_multiSelectedPoints.isNotEmpty) {
                        Future.delayed(const Duration(milliseconds: 500), () {
                          _fitMultiMapToBounds(controller);
                        });
                      }
                    },
                    onTap: (LatLng position) {
                      // Check if tapping near existing point to remove it
                      int indexToRemove = _findNearestMultiPointIndex(position);
                      if (indexToRemove != -1) {
                        setState(() {
                          _multiSelectedPoints.removeAt(indexToRemove);
                        });
                      } else {
                        // Add new point
                        setState(() {
                          _multiSelectedPoints.add(position);
                        });
                      }
                    },
                  ),

                  // Info overlay
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Card(
                      color: Colors.white.withOpacity(0.9),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Titik dipilih: ${_multiSelectedPoints.length}',
                              style: boldTextStyle(size: 16),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Tap pada peta untuk menambah/menghapus titik',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _multiSelectedPoints.isEmpty
                          ? null
                          : () {
                              setState(() {
                                if (_multiSelectedPoints.isNotEmpty) {
                                  _multiSelectedPoints.removeLast();
                                }
                              });
                            },
                      icon: const Icon(Icons.undo, color: Colors.white),
                      label: const Text('Hapus Terakhir'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kbpBlue700,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text('Selesai'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kbpBlue900,
                        foregroundColor: Colors.white,
                      ),
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

// TAMBAHAN: Helper methods untuk multi map
  void _fitMultiMapToBounds(GoogleMapController controller) {
    if (_multiSelectedPoints.isEmpty) return;

    double minLat = _multiSelectedPoints.first.latitude;
    double maxLat = _multiSelectedPoints.first.latitude;
    double minLng = _multiSelectedPoints.first.longitude;
    double maxLng = _multiSelectedPoints.first.longitude;

    for (var point in _multiSelectedPoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    controller.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat - 0.01, minLng - 0.01),
        northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
      ),
      50,
    ));
  }

  int _findNearestMultiPointIndex(LatLng tapPosition) {
    const double minDistance = 0.0001;

    for (int i = 0; i < _multiSelectedPoints.length; i++) {
      final point = _multiSelectedPoints[i];
      final distance = _calculateDistance(tapPosition, point);

      if (distance < minDistance) {
        return i;
      }
    }
    return -1;
  }

// TAMBAHAN: Helper method untuk mendapatkan display text shift
  String getShiftDisplayText(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return 'Pagi (07:00-15:00)';
      case ShiftType.sore:
        return 'Sore (15:00-23:00)';
      case ShiftType.malam:
        return 'Malam (23:00-07:00)';
      case ShiftType.siang:
        return 'Siang (07:00-19:00)';
      case ShiftType.malamPanjang:
        return 'Malam Panjang (19:00-07:00)';
      default:
        return 'Unknown Shift';
    }
  }

  List<Officer> _getOfficersFromClusters(List<User> clusters) {
    List<Officer> allOfficers = [];
    for (var cluster in clusters) {
      if (cluster.officers != null && cluster.officers!.isNotEmpty) {
        for (var officer in cluster.officers!) {
          if (officer.clusterId.isEmpty) {
            final updatedOfficer = Officer(
              id: officer.id,
              name: officer.name,
              type: officer.type,
              shift: officer.shift,
              clusterId: cluster.id,
              photoUrl: officer.photoUrl,
            );
            allOfficers.add(updatedOfficer);
          } else {
            allOfficers.add(officer);
          }
        }
      }
    }
    return allOfficers;
  }
}
