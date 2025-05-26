import 'dart:developer';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/cluster/cluster_patrol_history_screen.dart';
import 'package:livetrackingapp/presentation/cluster/edit_map_screen.dart';
import 'package:livetrackingapp/presentation/cluster/officer_management_screen.dart';
import 'package:livetrackingapp/presentation/component/map_section.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:lottie/lottie.dart' as lottie;

class ClusterDetailScreen extends StatefulWidget {
  final String clusterId;
  final int initialTab;

  const ClusterDetailScreen({
    Key? key,
    required this.clusterId,
    this.initialTab = 0,
  }) : super(key: key);

  @override
  State<ClusterDetailScreen> createState() => _ClusterDetailScreenState();
}

class _ClusterDetailScreenState extends State<ClusterDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<Marker> _markers = {};
  final List<LatLng> _selectedPoints = [];
  bool _isEditingPoints = false;
  GoogleMapController? _mapController;
  User? _cluster;

  int _totalPatrols = 0;
  int _ongoingPatrols = 0;
  int _latePatrols = 0;
  int _expiredPatrols = 0;
  int _invalidPatrols = 0;
  int _ontimePatrols = 0;
  int _activePatrols = 0;
  int _cancelledPatrols = 0;
  bool _isHistoryLoading = true;
  String? _errorMessage;

  bool _isHistoryLoadingProcessing = false; // Tambahkan flag ini

// Pada metode initState, tambahkan:
  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _loadClusterDetails();

    // Tambahkan listener untuk mendeteksi perubahan tab
    _tabController.addListener(() {
      // Jika tab yang aktif adalah tab Riwayat (index 1) dan belum dimuat
      if (_tabController.index == 1 &&
          _isHistoryLoading &&
          !_isHistoryLoadingProcessing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadPatrolHistory();
          }
        });
      }
    });

    // Jika tab awal adalah Riwayat, muat data riwayat setelah build
    if (widget.initialTab == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isHistoryLoading && !_isHistoryLoadingProcessing) {
          _loadPatrolHistory();
        }
      });
    }
  }

// Update metode _loadPatrolHistory untuk menggunakan Realtime Database
  Future<void> _loadPatrolHistory() async {
    // PERBAIKAN: Hanya return jika tidak mounted
    if (!mounted) return;

    // Mencegah multiple calls jika sudah di proses loading
    if (_isHistoryLoadingProcessing) return;

    // Set flag processing to true
    _isHistoryLoadingProcessing = true;

    // Set loading state
    if (mounted) {
      setState(() {
        _isHistoryLoading = true;
        _errorMessage = null;
      });
    }

    try {
      // Gunakan Firebase Realtime Database untuk mendapatkan data
      final databaseReference = FirebaseDatabase.instance.ref();

      // Query tasks berdasarkan clusterId
      final tasksSnapshot = await databaseReference
          .child('tasks')
          .orderByChild('clusterId')
          .equalTo(widget.clusterId)
          .get();

      // Pastikan widget masih mounted sebelum setState
      if (!mounted) return;

      if (tasksSnapshot.exists) {
        // Reset counter
        int totalPatrols = 0;
        int ongoingPatrols = 0;
        int latePatrols = 0;
        int expiredPatrols = 0;
        int invalidPatrols = 0;
        int ontimePatrols = 0;
        int activePatrols = 0;
        int cancelledPatrols = 0;

        // Proses data dari snapshot
        final tasks = tasksSnapshot.value as Map<dynamic, dynamic>;

        tasks.forEach((key, value) {
          final data = value as Map<dynamic, dynamic>;
          totalPatrols++;

          // Hitung statistik
          final status = data['status'] as String?;
          if (status == 'active' || status == 'assigned') {
            activePatrols++;
          } else if (status == 'expired') {
            expiredPatrols++;
          } else if (status == 'ongoing') {
            ongoingPatrols++;
          } else if (status == 'cancelled') {
            cancelledPatrols++;
          }

          final mockLocationDetected = data['mockLocationDetected'] as bool?;
          if (mockLocationDetected == true) {
            invalidPatrols++;
          }

          final timeliness = data['timeliness'] as String?;
          if (timeliness == 'late') {
            latePatrols++;
          } else if (timeliness == 'ontime') {
            ontimePatrols++;
          }
        });

        // Update state jika masih mounted
        if (mounted) {
          setState(() {
            _totalPatrols = totalPatrols;
            _ongoingPatrols = ongoingPatrols;
            _latePatrols = latePatrols;
            _expiredPatrols = expiredPatrols;
            _invalidPatrols = invalidPatrols;
            _ontimePatrols = ontimePatrols;
            _activePatrols = activePatrols;
            _cancelledPatrols = cancelledPatrols;
            _isHistoryLoading = false;
          });
        }
      } else {
        // Jika tidak ada data dan masih mounted
        if (mounted) {
          setState(() {
            _totalPatrols = 0;
            _ongoingPatrols = 0;
            _latePatrols = 0;
            _expiredPatrols = 0;
            _invalidPatrols = 0;
            _ontimePatrols = 0;
            _activePatrols = 0;
            _cancelledPatrols = 0;
            _isHistoryLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading patrol history: $e');
      // Pastikan masih mounted sebelum update state
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isHistoryLoading = false;
        });
      }
    } finally {
      _isHistoryLoadingProcessing = false;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _loadClusterDetails() {
    context.read<AdminBloc>().add(
          GetClusterDetail(widget.clusterId),
        );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        context.read<AdminBloc>().add(
              LoadAllClusters(),
            );
        return true; // Allow pop
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detail Tatar'),
          backgroundColor: kbpBlue900,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'Informasi'),
              Tab(text: 'Riwayat'),
              Tab(text: 'Petugas'),
              Tab(text: 'Titik Patroli'),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
              context.read<AdminBloc>().add(
                    LoadAllClusters(),
                  );
            },
          ),
        ),
        body: BlocBuilder<AdminBloc, AdminState>(
          builder: (context, state) {
            if (state is AdminLoading) {
              return Center(
                child: lottie.LottieBuilder.asset(
                  'assets/lottie/maps_loading.json',
                  width: 200,
                  height: 100,
                  fit: BoxFit.cover,
                ),
              );
            } else if (state is ClusterDetailLoaded) {
              _cluster = state.cluster;
              _setupMarkersFromCluster(state.cluster);
      
              return TabBarView(
                controller: _tabController,
                children: [
                  _buildInfoTab(state.cluster),
                  _buildHistoryTab(state.cluster),
                  _buildOfficersTab(state.cluster),
                  _buildMapTab(state.cluster),
                ],
              );
            } else if (state is AdminError) {
              return Center(
                child: Text(
                  'Error: ${state.message}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }
            return const Center(child: Text('Loading cluster details...'));
          },
        ),
      ),
    );
  }

  void _setupMarkersFromCluster(User cluster) {
    if (_markers.isEmpty && cluster.clusterCoordinates != null) {
      _selectedPoints.clear();
      _markers.clear();

      for (var i = 0; i < cluster.clusterCoordinates!.length; i++) {
        final coord = cluster.clusterCoordinates![i];
        if (coord.length >= 2) {
          final latLng = LatLng(coord[0], coord[1]);
          _selectedPoints.add(latLng);
          _markers.add(
            Marker(
              markerId: MarkerId('point_$i'),
              position: latLng,
              infoWindow: InfoWindow(title: 'Point ${i + 1}'),
            ),
          );
        }
      }
    }
  }

  // Perbarui method _buildHistoryTab() untuk menampilkan statistik patroli

  Widget _buildHistoryTab(User cluster) {
    // Trigger loading history jika belum dimuat, tapi gunakan post-frame callback
    if (_isHistoryLoading && _errorMessage == null) {
      // Tunda hingga setelah build frame selesai
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadPatrolHistory();
        }
      });
    }

    // Handle loading state
    if (_isHistoryLoading) {
      return Center(
        child: lottie.LottieBuilder.asset(
          'assets/lottie/maps_loading.json',
          width: 200,
          height: 100,
          fit: BoxFit.cover,
        ),
      );
    }

    // Handle error state
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: dangerR500),
            const SizedBox(height: 16),
            Text(
              'Error: $_errorMessage',
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                _loadPatrolHistory();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kbpBlue900,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    // Tampilkan data statistik
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kbpBlue50,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Riwayat Patroli',
                        style: semiBoldTextStyle(size: 18),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: kbpBlue700,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.list_alt,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$_totalPatrols Patroli',
                              style:
                                  boldTextStyle(color: Colors.white, size: 14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                12.height,
                // Tombol aksi untuk riwayat lengkap
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ClusterPatrolHistoryScreen(
                            clusterId: widget.clusterId,
                            clusterName: _cluster?.name ?? '',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('Tampilkan Riwayat Lengkap'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kbpBlue900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Baris pertama statistik
                Row(
                  children: [
                    _buildStatCard(
                      icon: Icons.calendar_today,
                      title: 'Sedang Berlangsung',
                      value: _ongoingPatrols.toString(),
                      iconColor: kbpBlue900,
                      bgColor: kbpBlue50,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      icon: Icons.verified,
                      title: 'Tepat Waktu',
                      value: _ontimePatrols.toString(),
                      iconColor: successG500,
                      bgColor: successG50,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Baris kedua statistik
                Row(
                  children: [
                    _buildStatCard(
                      icon: Icons.timer,
                      title: 'Terlambat',
                      value: _latePatrols.toString(),
                      iconColor: warningY500,
                      bgColor: warningY50,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      icon: Icons.access_time_filled,
                      title: 'Lewat Tenggat',
                      value: _expiredPatrols.toString(),
                      iconColor: dangerR500,
                      bgColor: dangerR50,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Baris ketiga statistik
                Row(
                  children: [
                    _buildStatCard(
                      icon: Icons.gps_off,
                      title: 'Fake GPS',
                      value: _invalidPatrols.toString(),
                      iconColor: Colors.purple,
                      bgColor: Color(0xFFF3E5F5), // light purple
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      icon: Icons.pending_actions,
                      title: 'Belum Dimulai',
                      value: _activePatrols.toString(),
                      iconColor: kbpBlue700,
                      bgColor: kbpBlue50,
                    ),
                  ],
                ),

                12.height,

                Row(
                  children: [
                    _buildStatCard(
                      icon: Icons.cancel,
                      title: 'Dibatalkan',
                      value: _cancelledPatrols.toString(),
                      iconColor: Colors.red,
                      bgColor: Colors.red.withOpacity(0.1),
                    ),
                    const SizedBox(width: 0),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    Color iconColor = kbpBlue900,
    Color bgColor = kbpBlue50,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: boldTextStyle(size: 24, color: neutral900),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: regularTextStyle(size: 12, color: neutral600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTab(User cluster) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Informasi Tatar',
                    style: boldTextStyle(size: 18),
                  ),
                  const Divider(),
                  _infoRow('Nama', cluster.name),
                  _infoRow('Email', cluster.email),
                  _infoRow('Role', cluster.role),
                  _infoRow(
                      'Jumlah Petugas', '${cluster.officers?.length ?? 0}'),
                  _infoRow('Jumlah Titik',
                      '${cluster.clusterCoordinates?.length ?? 0}'),
                  if (cluster.createdAt != null)
                    _infoRow('Dibuat Pada',
                        formatDateFromString(cluster.createdAt!.toString())),
                  if (cluster.updatedAt != null)
                    _infoRow('Diperbarui Pada',
                        formatDateFromString(cluster.updatedAt!.toString())),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tindakan',
                    style: boldTextStyle(size: 18),
                  ),
                  const Divider(),
                  // _buildActionButton(
                  //   icon: Icons.edit,
                  //   label: 'Edit Informasi Tatar',
                  //   onPressed: () {
                  //     // Navigasi ke halaman edit
                  //   },
                  // ),
                  _buildActionButton(
                    icon: Icons.people,
                    label: 'Kelola Petugas',
                    onPressed: () {
                      _tabController.animateTo(2); // Pindah ke tab Petugas
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.map,
                    label: 'Edit Titik Patroli',
                    onPressed: () {
                      _tabController
                          .animateTo(3); // Pindah ke tab Titik Patroli
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.task_alt,
                    label: 'Lihat Riwayat Patroli',
                    onPressed: () {
                      _tabController.animateTo(1);
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.delete_outline,
                    label: 'Hapus Tatar',
                    color: Colors.red,
                    onPressed: () {
                      _showDeleteConfirmationDialog();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Perbaikan untuk bagian _buildOfficersTab

  Widget _buildOfficersTab(User cluster) {
    final officers = cluster.officers ?? [];
    log('Officers: ${officers.length}');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daftar Petugas (${officers.length})',
                style: boldTextStyle(size: 18),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => OfficerManagementScreen(
                        clusterId: widget.clusterId,
                        clusterName: cluster.name,
                      ),
                    ),
                  ).then((_) => _loadClusterDetails());
                },
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('Kelola Petugas'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kbpBlue900,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: officers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people_outline,
                          size: 64, color: neutral400),
                      const SizedBox(height: 16),
                      const Text(
                        'Belum ada petugas di cluster ini',
                        style: TextStyle(fontSize: 16, color: neutral600),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => OfficerManagementScreen(
                                clusterId: widget.clusterId,
                                clusterName: cluster.name,
                              ),
                            ),
                          ).then((_) => _loadClusterDetails());
                        },
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('Tambah Petugas'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kbpBlue900,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: officers.length,
                  itemBuilder: (context, index) {
                    final officer = officers[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: kbpBlue300, width: 1),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: kbpBlue100,
                          child: officer.photoUrl != null &&
                                  officer.photoUrl!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(50),
                                  child: Image.network(
                                    officer.photoUrl!,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, _) => Text(
                                      officer.name.isNotEmpty
                                          ? officer.name[0].toUpperCase()
                                          : '?',
                                      style: boldTextStyle(
                                          color: kbpBlue900, size: 18),
                                    ),
                                  ),
                                )
                              : Text(
                                  officer.name.isNotEmpty
                                      ? officer.name[0].toUpperCase()
                                      : '?',
                                  style: boldTextStyle(
                                      color: kbpBlue900, size: 18),
                                ),
                        ),
                        title: Text(
                          officer.name,
                          style: semiBoldTextStyle(),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                // Badge tipe
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
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
                                      size: 12,
                                      color: officer.type == OfficerType.organik
                                          ? successG500
                                          : warningY500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Badge shift
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kbpBlue50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    getShortShiftText(officer.shift),
                                    style: mediumTextStyle(
                                        size: 12, color: kbpBlue700),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: kbpBlue900),
                              onPressed: () {
                                _showEditOfficerDialog(officer);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                _showDeleteOfficerConfirmation(officer);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

// Tambahkan method untuk menampilkan dialog edit petugas
  void _showEditOfficerDialog(Officer officer) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: officer.name);
    OfficerType selectedType = officer.type;
    ShiftType selectedShift = officer.shift;

    // Map untuk menampung shift options berdasarkan tipe
    final Map<OfficerType, List<ShiftType>> typeShifts = {
      OfficerType.organik: [
        ShiftType.pagi, // 07:00-15:00
        ShiftType.sore, // 15:00-23:00
        ShiftType.malam, // 23:00-07:00
      ],
      OfficerType.outsource: [
        ShiftType.siang, // 07:00-19:00
        ShiftType.malamPanjang, // 19:00-07:00
      ],
    };

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            'Edit Petugas',
            style: boldTextStyle(),
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name field
                const Text(
                  'Nama Petugas',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: neutral800,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: 'Masukkan nama petugas',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Nama petugas wajib diisi';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Tipe Petugas selection
                const Text(
                  'Tipe Petugas',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: neutral800,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<OfficerType>(
                  value: selectedType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: OfficerType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type == OfficerType.organik
                          ? 'Organik'
                          : 'Outsource'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        selectedType = value;
                        // Reset shift ke opsi pertama untuk tipe yang dipilih
                        if (!typeShifts[value]!.contains(selectedShift)) {
                          selectedShift = typeShifts[value]!.first;
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Shift selection - dinamis berdasarkan tipe
                const Text(
                  'Shift Kerja',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: neutral800,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ShiftType>(
                  value: typeShifts[selectedType]!.contains(selectedShift)
                      ? selectedShift
                      : typeShifts[selectedType]!.first,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: typeShifts[selectedType]!.map((shift) {
                    return DropdownMenuItem(
                      value: shift,
                      child: Text(_getShiftDisplayText(shift)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        selectedShift = value;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Batal'),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kbpBlue900,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  // Update officer
                  final updatedOfficer = Officer(
                    id: officer.id,
                    name: nameController.text,
                    type: selectedType,
                    shift: selectedShift,
                    clusterId: widget.clusterId,
                    photoUrl: officer.photoUrl,
                  );

                  context.read<AdminBloc>().add(
                        UpdateOfficerInClusterEvent(
                          clusterId: widget.clusterId,
                          officer: updatedOfficer,
                        ),
                      );

                  Navigator.pop(context);

                  showCustomSnackbar(
                    context: context,
                    title: 'Berhasil',
                    subtitle: 'Informasi petugas telah diperbarui',
                    type: SnackbarType.success,
                  );

                  // Refresh data
                  _loadClusterDetails();
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

// Helper untuk mendapatkan teks shift lengkap
  String _getShiftDisplayText(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return 'Pagi (07:00 - 15:00)';
      case ShiftType.sore:
        return 'Sore (15:00 - 23:00)';
      case ShiftType.malam:
        return 'Malam (23:00 - 07:00)';
      case ShiftType.siang:
        return 'Siang (07:00 - 19:00)';
      case ShiftType.malamPanjang:
        return 'Malam (19:00 - 07:00)';
    }
  }

  Widget _buildMapTab(User cluster) {
    return Stack(
      children: [
        // Map fullscreen - Ganti MapSection dengan GoogleMap langsung
        SizedBox(
          height: MediaQuery.of(context).size.height,
          child: GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _selectedPoints.isNotEmpty
                ? CameraPosition(
                    target: _selectedPoints.first,
                    zoom: 17,
                  )
                : const CameraPosition(
                    target: LatLng(-6.8737, 107.5757), // Default: Bandung
                    zoom: 14,
                  ),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              // Zoom to points jika sudah ada titik
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _selectedPoints.isNotEmpty) {
                  _zoomToSelectedPoints();
                }
              });
            },
          ),
        ),

        // Info dan tombol edit
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Titik Patroli (${_selectedPoints.length})',
                        style: boldTextStyle(size: 16),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          // Navigasi ke halaman edit map terpisah
                          _navigateToEditMapScreen(cluster);
                        },
                        icon: const Icon(Icons.edit_location_alt,
                            color: Colors.white),
                        label: const Text('Edit Titik'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kbpBlue900,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Klik tombol Edit untuk mengedit titik patroli di halaman penuh',
                    style: regularTextStyle(
                      color: neutral600,
                      size: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

// Tambahkan method untuk navigasi ke halaman edit map
  void _navigateToEditMapScreen(User cluster) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditMapScreen(
          clusterId: widget.clusterId,
          points: List<LatLng>.from(_selectedPoints),
          clusterName: cluster.name,
        ),
      ),
    );

    if (result != null && result is List<LatLng>) {
      setState(() {
        _selectedPoints.clear();
        _selectedPoints.addAll(result);
        _updateMarkers();
      });

      // Refresh cluster data
      _loadClusterDetails();
    }
  }

  dynamic _handleMapTap(LatLng position) {
    if (!_isEditingPoints) return;

    setState(() {
      _selectedPoints.add(position);
      _updateMarkers();
    });
    return null;
  }

  void _updateMarkers() {
    _markers.clear();
    for (int i = 0; i < _selectedPoints.length; i++) {
      _markers.add(
        Marker(
          markerId: MarkerId('point_$i'),
          position: _selectedPoints[i],
          infoWindow: InfoWindow(title: 'Point ${i + 1}'),
        ),
      );
    }
  }

  void _zoomToSelectedPoints() {
    if (_selectedPoints.isEmpty || _mapController == null) return;

    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    for (var point in _selectedPoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    // Add padding
    final padding = 0.002; // About 200 meters
    minLat -= padding;
    maxLat += padding;
    minLng -= padding;
    maxLng += padding;

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50),
    );
  }

  void _showSavePointsConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Simpan Perubahan'),
        content: Text(
          'Anda yakin ingin menyimpan ${_selectedPoints.length} titik patroli untuk cluster ini?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveClusterCoordinates();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kbpBlue900,
              foregroundColor: Colors.white,
            ),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _saveClusterCoordinates() {
    final coordinates = _selectedPoints
        .map((point) => [point.latitude, point.longitude])
        .toList();

    context.read<AdminBloc>().add(
          UpdateClusterCoordinates(
            clusterId: widget.clusterId,
            coordinates: coordinates,
          ),
        );

    setState(() {
      _isEditingPoints = false;
    });

    showCustomSnackbar(
      context: context,
      title: 'Berhasil',
      subtitle: 'Titik patroli berhasil diperbarui',
      type: SnackbarType.success,
    );
  }

  void _showDeleteOfficerConfirmation(Officer officer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Petugas'),
        content: Text(
          'Anda yakin ingin menghapus petugas "${officer.name}" dari cluster ini?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AdminBloc>().add(
                    RemoveOfficerFromClusterEvent(
                      clusterId: widget.clusterId,
                      officerId: officer.id,
                    ),
                  );
              _loadClusterDetails();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus Tatar',
            style: boldTextStyle(color: dangerR300, size: 18)),
        content: const Text(
          'Anda yakin ingin menghapus cluster ini? Tindakan ini tidak dapat dibatalkan dan akan menghapus semua data terkait cluster.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Batal',
              style: boldTextStyle(
                color: dangerR300,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AdminBloc>().add(
                    DeleteClusterEvent(widget.clusterId),
                  );
              Navigator.pop(context); // Kembali ke halaman sebelumnya
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: neutral700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: neutral900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color color = kbpBlue900,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
