import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/patrol_summary_screen.dart';
import 'package:livetrackingapp/presentation/auth/bloc/auth_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/routing/bloc/patrol_bloc.dart';

class PatrolHistoryListScreen extends StatefulWidget {
  final List<PatrolTask>? tasksList;
  final bool isClusterView;

  const PatrolHistoryListScreen({
    Key? key,
    this.tasksList,
    this.isClusterView = false,
  }) : super(key: key);

  @override
  State<PatrolHistoryListScreen> createState() =>
      _PatrolHistoryListScreenState();
}

class _PatrolHistoryListScreenState extends State<PatrolHistoryListScreen> {
  List<PatrolTask> _historyTasks = [];
  bool _isLoading = true;
  final dateFormatter = DateFormat('dd MMM yyyy', 'id_ID');
  final timeFormatter = DateFormat('HH:mm', 'id_ID');
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  String? _selectedVehicleId;
  TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    if (widget.tasksList != null) {
      // Jika daftar tugas diberikan dalam konstruktor
      _historyTasks = List.from(widget.tasksList!);
      _historyTasks.sort((a, b) =>
          (b.endTime ?? DateTime.now()).compareTo(a.endTime ?? DateTime.now()));
      _isLoading = false;
    } else {
      // Jika tidak, load dari bloc
      _loadHistoryTasks();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistoryTasks() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        final user = authState.user;

        if (widget.isClusterView) {
          // Load dari repositori untuk cluster
          final tasks = await context
              .read<PatrolBloc>()
              .repository
              .getClusterTasks(user.id);
          setState(() {
            _historyTasks = tasks
                .where((task) =>
                    task.status.toLowerCase() == 'finished' ||
                    task.status.toLowerCase() == 'completed')
                .toList();
            _historyTasks.sort((a, b) => (b.endTime ?? DateTime.now())
                .compareTo(a.endTime ?? DateTime.now()));
          });
        } else {
          // Untuk individual officer, ambil dari PatrolBloc
          final patrolState = context.read<PatrolBloc>().state;
          if (patrolState is PatrolLoaded) {
            setState(() {
              _historyTasks = List.from(patrolState.finishedTasks);
            });
          }
        }
      }
    } catch (e) {
      print('Error loading history tasks: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error memuat riwayat: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<PatrolTask> _getFilteredTasks() {
    List<PatrolTask> filteredTasks = List.from(_historyTasks);

    // Filter berdasarkan pencarian
    if (_searchController.text.isNotEmpty) {
      final searchTerm = _searchController.text.toLowerCase();
      filteredTasks = filteredTasks.where((task) {
        final officerNameMatch =
            task.officerName?.toLowerCase().contains(searchTerm) ?? false;
        // final vehicleIdMatch =
        //     task.vehicleId.toLowerCase().contains(searchTerm);
        return officerNameMatch;
      }).toList();
    }

    // Filter berdasarkan tanggal mulai
    if (_selectedStartDate != null) {
      filteredTasks = filteredTasks
          .where((task) =>
              task.endTime != null &&
              !task.endTime!.isBefore(_selectedStartDate!))
          .toList();
    }

    // Filter berdasarkan tanggal akhir
    if (_selectedEndDate != null) {
      final endOfDay = DateTime(_selectedEndDate!.year, _selectedEndDate!.month,
          _selectedEndDate!.day, 23, 59, 59);
      filteredTasks = filteredTasks
          .where((task) =>
              task.startTime != null && !task.startTime!.isAfter(endOfDay))
          .toList();
    }

    // Filter berdasarkan kendaraan
    // if (_selectedVehicleId != null) {
    //   filteredTasks = filteredTasks
    //       .where((task) => task.vehicleId == _selectedVehicleId)
    //       .toList();
    // }

    return filteredTasks;
  }

  void _showFilterBottomSheet() {
    // Daftar kendaraan unik
    // final vehicleIds = _historyTasks
    //     .map((task) => task.vehicleId)
    //     .where((id) => id.isNotEmpty)
    //     .toSet()
    //     .toList();
    // vehicleIds.sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
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

                    // Tanggal Mulai
                    Text(
                      'Tanggal Mulai',
                      style: semiBoldTextStyle(size: 14),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedStartDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: kbpBlue900,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (date != null) {
                          setState(() {
                            _selectedStartDate = date;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: neutral300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedStartDate == null
                                    ? 'Pilih Tanggal'
                                    : dateFormatter.format(_selectedStartDate!),
                                style: regularTextStyle(
                                  size: 14,
                                  color: _selectedStartDate == null
                                      ? neutral500
                                      : neutral900,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.calendar_today,
                              size: 18,
                              color: neutral500,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Tanggal Akhir
                    Text(
                      'Tanggal Akhir',
                      style: semiBoldTextStyle(size: 14),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedEndDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          builder: (context, child) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: kbpBlue900,
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (date != null) {
                          setState(() {
                            _selectedEndDate = date;
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: neutral300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedEndDate == null
                                    ? 'Pilih Tanggal'
                                    : dateFormatter.format(_selectedEndDate!),
                                style: regularTextStyle(
                                  size: 14,
                                  color: _selectedEndDate == null
                                      ? neutral500
                                      : neutral900,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.calendar_today,
                              size: 18,
                              color: neutral500,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // if (vehicleIds.isNotEmpty) ...[
                    //   const SizedBox(height: 16),
                    //   Text(
                    //     'Kendaraan',
                    //     style: semiBoldTextStyle(size: 14),
                    //   ),
                    //   const SizedBox(height: 8),
                    //   Container(
                    //     decoration: BoxDecoration(
                    //       border: Border.all(color: neutral300),
                    //       borderRadius: BorderRadius.circular(8),
                    //     ),
                    //     child: DropdownButtonFormField<String?>(
                    //       value: _selectedVehicleId,
                    //       decoration: const InputDecoration(
                    //         contentPadding:
                    //             EdgeInsets.symmetric(horizontal: 12),
                    //         border: InputBorder.none,
                    //         hintText: 'Semua Kendaraan',
                    //       ),
                    //       items: [
                    //         const DropdownMenuItem<String?>(
                    //           value: null,
                    //           child: Text('Semua Kendaraan'),
                    //         ),
                    //         ...vehicleIds
                    //             .map((id) => DropdownMenuItem<String>(
                    //                   value: id,
                    //                   child: Text(id),
                    //                 ))
                    //             .toList(),
                    //       ],
                    //       onChanged: (value) {
                    //         setState(() {
                    //           _selectedVehicleId = value;
                    //         });
                    //       },
                    //     ),
                    //   ),
                    // ],

                    const SizedBox(height: 24),

                    // Tombol Terapkan dan Reset
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _selectedStartDate = null;
                                _selectedEndDate = null;
                                _selectedVehicleId = null;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kbpBlue900,
                              side: const BorderSide(color: kbpBlue900),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Reset',
                              style: mediumTextStyle(color: kbpBlue900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              setState(() {}); // Refresh UI dengan filter baru
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kbpBlue900,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Terapkan',
                              style: mediumTextStyle(color: Colors.white),
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
      },
    );
  }

  void _showPatrolSummary(PatrolTask task) {
    try {
      List<List<double>> convertedPath = [];

      if (task.routePath != null && task.routePath is Map) {
        final map = task.routePath as Map;

        // Sort entries by timestamp
        final sortedEntries = map.entries.toList()
          ..sort((a, b) => (a.value['timestamp'] as String)
              .compareTo(b.value['timestamp'] as String));

        // Convert coordinates
        convertedPath = sortedEntries.map((entry) {
          final coordinates = entry.value['coordinates'] as List;
          return [
            (coordinates[0] as num).toDouble(), // latitude
            (coordinates[1] as num).toDouble(), // longitude
          ];
        }).toList();
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
            finalReportPhotoUrl: task.finalReportPhotoUrl,
            initialReportPhotoUrl: task.initialReportPhotoUrl,
          ),
        ),
      );
    } catch (e) {
      print('Error showing patrol summary: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading patrol summary: $e')),
      );
    }
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

  Widget _buildAvatarFallback(PatrolTask task) {
    return Center(
      child: Text(
        task.officerName?.substring(0, 1).toUpperCase() ?? 'P',
        style: semiBoldTextStyle(size: 16, color: kbpBlue900),
      ),
    );
  }

  Widget _buildActiveFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (_selectedStartDate != null)
          Chip(
            label: Text(
              'Dari: ${dateFormatter.format(_selectedStartDate!)}',
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: kbpBlue100,
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: () {
              setState(() {
                _selectedStartDate = null;
              });
            },
          ),
        if (_selectedEndDate != null)
          Chip(
            label: Text(
              'Sampai: ${dateFormatter.format(_selectedEndDate!)}',
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: kbpBlue100,
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: () {
              setState(() {
                _selectedEndDate = null;
              });
            },
          ),
        if (_selectedVehicleId != null)
          Chip(
            label: Text(
              'Kendaraan: $_selectedVehicleId',
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: kbpBlue100,
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: () {
              setState(() {
                _selectedVehicleId = null;
              });
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredTasks = _getFilteredTasks();

    return Scaffold(
      backgroundColor: neutral200,
      appBar: AppBar(
        title: Text(
          'Riwayat Patroli',
          style: semiBoldTextStyle(size: 18, color: Colors.white),
        ),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterBottomSheet,
            tooltip: 'Filter',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistoryTasks,
        color: kbpBlue900,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: kbpBlue900))
            : Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Cari nama petugas atau kendaraan',
                        prefixIcon: const Icon(Icons.search, color: neutral500),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {});
                      },
                    ),
                  ),

                  // Active filters
                  if (_selectedStartDate != null ||
                      _selectedEndDate != null ||
                      _selectedVehicleId != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildActiveFilters(),
                    ),

                  // Results count
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Text(
                          'Menampilkan ${filteredTasks.length} Patroli',
                          style: mediumTextStyle(color: neutral700),
                        ),
                        const Spacer(),
                        if (_selectedStartDate != null ||
                            _selectedEndDate != null ||
                            _selectedVehicleId != null ||
                            _searchController.text.isNotEmpty)
                          TextButton.icon(
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Reset'),
                            onPressed: () {
                              setState(() {
                                _selectedStartDate = null;
                                _selectedEndDate = null;
                                _selectedVehicleId = null;
                                _searchController.clear();
                              });
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: kbpBlue900,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // History list
                  Expanded(
                    child: filteredTasks.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SvgPicture.asset(
                                  'assets/nodata.svg',
                                  height: 120,
                                  width: 120,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Tidak ada riwayat patroli',
                                  style: mediumTextStyle(
                                      size: 16, color: neutral700),
                                ),
                                const SizedBox(height: 8),
                                if (_selectedStartDate != null ||
                                    _selectedEndDate != null ||
                                    _selectedVehicleId != null ||
                                    _searchController.text.isNotEmpty)
                                  Text(
                                    'Coba ubah filter pencarian',
                                    style: regularTextStyle(
                                        size: 14, color: neutral600),
                                  ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: filteredTasks.length,
                            itemBuilder: (context, index) {
                              final task = filteredTasks[index];

                              return Card(
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: InkWell(
                                  onTap: () => _showPatrolSummary(task),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Header
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            // Avatar
                                            Container(
                                              width: 40,
                                              height: 40,
                                              clipBehavior: Clip.antiAlias,
                                              decoration: BoxDecoration(
                                                color: kbpBlue100,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                    color: kbpBlue200,
                                                    width: 1),
                                              ),
                                              child: task.officerPhotoUrl !=
                                                          null &&
                                                      task.officerPhotoUrl!
                                                          .isNotEmpty
                                                  ? Image.network(
                                                      task.officerPhotoUrl!,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (context,
                                                          error, stackTrace) {
                                                        return _buildAvatarFallback(
                                                            task);
                                                      },
                                                      loadingBuilder: (context,
                                                          child,
                                                          loadingProgress) {
                                                        if (loadingProgress ==
                                                            null) return child;
                                                        return _buildAvatarFallback(
                                                            task);
                                                      },
                                                    )
                                                  : _buildAvatarFallback(task),
                                            ),
                                            const SizedBox(width: 16),

                                            // Officer & vehicle info
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    task.officerName ??
                                                        'Petugas',
                                                    style: semiBoldTextStyle(
                                                        size: 16),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  // const SizedBox(height: 4),
                                                  // Row(
                                                  //   children: [
                                                  //     const Icon(
                                                  //         Icons.directions_car,
                                                  //         size: 14,
                                                  //         color: kbpBlue700),
                                                  //     const SizedBox(width: 4),
                                                  //     Text(
                                                  //       task.vehicleId.isEmpty
                                                  //           ? 'Tanpa Kendaraan'
                                                  //           : task.vehicleId,
                                                  //       style: regularTextStyle(
                                                  //           size: 14,
                                                  //           color: kbpBlue700),
                                                  //     ),
                                                  //   ],
                                                  // ),
                                                ],
                                              ),
                                            ),

                                            // Date block
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: kbpBlue100,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(
                                                    task.endTime != null
                                                        ? dateFormatter.format(
                                                            task.endTime!)
                                                        : 'N/A',
                                                    style: mediumTextStyle(
                                                        size: 12,
                                                        color: kbpBlue900),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  task.endTime != null
                                                      ? timeFormatter
                                                          .format(task.endTime!)
                                                      : 'N/A',
                                                  style: semiBoldTextStyle(
                                                      size: 14,
                                                      color: kbpBlue900),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),

                                        const Divider(height: 24),

                                        // Details
                                        Row(
                                          children: [
                                            // Duration
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Durasi',
                                                    style: regularTextStyle(
                                                        size: 12,
                                                        color: neutral600),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.timer,
                                                          size: 16,
                                                          color: kbpBlue800),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        _formatDuration(task
                                                                        .endTime !=
                                                                    null &&
                                                                task.startTime !=
                                                                    null
                                                            ? task.endTime!
                                                                .difference(task
                                                                    .startTime!)
                                                            : Duration.zero),
                                                        style:
                                                            semiBoldTextStyle(
                                                                size: 14,
                                                                color:
                                                                    kbpBlue900),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Distance
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Jarak',
                                                    style: regularTextStyle(
                                                        size: 12,
                                                        color: neutral600),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                          Icons.straighten,
                                                          size: 16,
                                                          color: kbpBlue800),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '${((task.distance ?? 0) / 1000).toStringAsFixed(2)} km',
                                                        style:
                                                            semiBoldTextStyle(
                                                                size: 14,
                                                                color:
                                                                    kbpBlue900),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Points
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Titik',
                                                    style: regularTextStyle(
                                                        size: 12,
                                                        color: neutral600),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.place,
                                                          size: 16,
                                                          color: kbpBlue800),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '${task.assignedRoute?.length ?? 0} titik',
                                                        style:
                                                            semiBoldTextStyle(
                                                                size: 14,
                                                                color:
                                                                    kbpBlue900),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 16),

                                        // View detail button
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            icon: const Icon(Icons.map_outlined,
                                                size: 18),
                                            label: const Text('Lihat Detail'),
                                            onPressed: () =>
                                                _showPatrolSummary(task),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: kbpBlue900,
                                              side: const BorderSide(
                                                  color: kbpBlue900),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
