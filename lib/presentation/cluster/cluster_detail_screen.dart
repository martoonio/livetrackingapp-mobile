import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/cluster/edit_officer_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _loadClusterDetails();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Cluster'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Informasi'),
            Tab(text: 'Petugas'),
            Tab(text: 'Titik Patroli'),
          ],
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
                    'Informasi Cluster',
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
                  _buildActionButton(
                    icon: Icons.edit,
                    label: 'Edit Informasi Cluster',
                    onPressed: () {
                      // Navigasi ke halaman edit
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.people,
                    label: 'Kelola Petugas',
                    onPressed: () {
                      _tabController.animateTo(1); // Pindah ke tab Petugas
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.map,
                    label: 'Edit Titik Patroli',
                    onPressed: () {
                      _tabController
                          .animateTo(2); // Pindah ke tab Titik Patroli
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.task_alt,
                    label: 'Lihat Riwayat Patroli',
                    onPressed: () {
                      // Navigasi ke riwayat patroli
                    },
                  ),
                  _buildActionButton(
                    icon: Icons.delete_outline,
                    label: 'Hapus Cluster',
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

  Widget _buildOfficersTab(User cluster) {
    final officers = cluster.officers ?? [];

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
                      builder: (context) => EditOfficerScreen(
                        clusterId: widget.clusterId,
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
        ),
        Expanded(
          child: officers.isEmpty
              ? const Center(
                  child: Text(
                    'Belum ada petugas di cluster ini',
                    style: TextStyle(fontSize: 16, color: neutral600),
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
                                    errorBuilder: (context, error, _) =>
                                        const Icon(
                                      Icons.person,
                                      color: kbpBlue900,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.person, color: kbpBlue900),
                        ),
                        title: Text(
                          officer.name,
                          style: semiBoldTextStyle(),
                        ),
                        subtitle: Text('Shift: ${officer.shift}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: kbpBlue900),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EditOfficerScreen(
                                      clusterId: widget.clusterId,
                                      officer: officer,
                                    ),
                                  ),
                                ).then((_) => _loadClusterDetails());
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

  Widget _buildMapTab(User cluster) {
    return Stack(
      children: [
        // Map fullscreen
        SizedBox(
          height: MediaQuery.of(context).size.height,
          child: MapSection(
            mapController: _mapController,
            markers: _markers,
            onMapTap: _handleMapTap,
          ),
        ),

        // Edit toggle and actions bar
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
                      Switch(
                        value: _isEditingPoints,
                        onChanged: (value) {
                          setState(() {
                            _isEditingPoints = value;
                            if (!value) {
                              // Reset to original points when exiting edit mode
                              _setupMarkersFromCluster(cluster);
                            }
                          });
                        },
                        activeColor: kbpBlue900,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isEditingPoints
                        ? 'Mode Edit: Klik pada peta untuk menambah titik'
                        : 'Mode Lihat: Aktifkan switch untuk mengedit',
                    style: const TextStyle(
                      fontSize: 14,
                      color: neutral600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  if (_isEditingPoints) ...[
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
                            onPressed: _selectedPoints.isEmpty
                                ? null
                                : () {
                                    _showSavePointsConfirmation();
                                  },
                            icon: const Icon(Icons.save, color: Colors.white),
                            label: const Text('Simpan Perubahan'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kbpBlue900,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: neutral300,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
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
        title: const Text('Hapus Cluster'),
        content: const Text(
          'Anda yakin ingin menghapus cluster ini? Tindakan ini tidak dapat dibatalkan dan akan menghapus semua data terkait cluster.',
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
