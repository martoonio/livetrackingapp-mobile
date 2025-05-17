import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/component/undo_button.dart';
import 'package:lottie/lottie.dart' as lottie;

class EditClusterScreen extends StatefulWidget {
  final User? existingCluster;
  final int initialTab;

  const EditClusterScreen({
    Key? key,
    this.existingCluster,
    this.initialTab = 0,
  }) : super(key: key);

  @override
  State<EditClusterScreen> createState() => _EditClusterScreenState();
}

class _EditClusterScreenState extends State<EditClusterScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;
  
  // Form controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  // Map variables
  final Set<Marker> _markers = {};
  final List<LatLng> _selectedPoints = [];
  GoogleMapController? _mapController;
  
  // Role selection
  String _selectedRole = 'patrol';
  
  // Mode editing or creating
  bool get _isEditing => widget.existingCluster != null;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    
    if (_isEditing) {
      _nameController.text = widget.existingCluster!.name;
      _emailController.text = widget.existingCluster!.email;
      _selectedRole = widget.existingCluster!.role;
      
      // Convert existing coordinates to markers and latLngs
      if (widget.existingCluster!.clusterCoordinates != null) {
        for (int i = 0; i < widget.existingCluster!.clusterCoordinates!.length; i++) {
          final coord = widget.existingCluster!.clusterCoordinates![i];
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
    } else {
      // Default values for new cluster
      _selectedRole = 'patrol';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Cluster' : 'Tambah Cluster Baru'),
        backgroundColor: kbpBlue900,
        foregroundColor: neutralWhite,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: neutralWhite,
          tabs: const [
            Tab(text: 'Info Cluster'),
            Tab(text: 'Area Cluster'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInfoTab(),
          _buildAreaTab(),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: neutralWhite,
          boxShadow: [
            BoxShadow(
              color: Color(0x29000000),
              offset: Offset(0, -1),
              blurRadius: 6,
            ),
          ],
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kbpBlue900,
            foregroundColor: neutralWhite,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _submitForm,
          child: Text(
            _isEditing ? 'Simpan Perubahan' : 'Buat Cluster',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Informasi Dasar',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: neutral900,
              ),
            ),
            16.height,
            
            // Nama Cluster
            const Text(
              'Nama Cluster',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: neutral800,
              ),
            ),
            8.height,
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Masukkan nama cluster',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Nama cluster tidak boleh kosong';
                }
                return null;
              },
            ),
            20.height,
            
            // Email
            const Text(
              'Email',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: neutral800,
              ),
            ),
            8.height,
            TextFormField(
              controller: _emailController,
              enabled: !_isEditing, // Disable if editing existing cluster
              decoration: InputDecoration(
                hintText: 'Masukkan email untuk login',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.all(16),
                suffixIcon: _isEditing ? 
                  const Tooltip(
                    message: 'Email tidak dapat diubah',
                    child: Icon(Icons.lock_outline),
                  ) : null,
              ),
              validator: (value) {
                if (!_isEditing && (value == null || value.isEmpty)) {
                  return 'Email tidak boleh kosong';
                }
                if (!_isEditing && !value!.contains('@')) {
                  return 'Masukkan email yang valid';
                }
                return null;
              },
            ),
            20.height,
            
            // Password (hanya untuk cluster baru)
            if (!_isEditing) ...[
              const Text(
                'Password',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: neutral800,
                ),
              ),
              8.height,
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'Masukkan password untuk login',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                ),
                validator: (value) {
                  if (!_isEditing && (value == null || value.isEmpty)) {
                    return 'Password tidak boleh kosong';
                  }
                  if (!_isEditing && value!.length < 6) {
                    return 'Password minimal 6 karakter';
                  }
                  return null;
                },
              ),
              20.height,
            ],
            
            // Role Selection
            const Text(
              'Tipe Akun',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: neutral800,
              ),
            ),
            8.height,
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Patroli'),
                    value: 'patrol',
                    groupValue: _selectedRole,
                    activeColor: kbpBlue900,
                    onChanged: (value) {
                      setState(() {
                        _selectedRole = value!;
                      });
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text('Command Center'),
                    value: 'commandCenter',
                    groupValue: _selectedRole,
                    activeColor: kbpBlue900,
                    onChanged: (value) {
                      setState(() {
                        _selectedRole = value!;
                      });
                    },
                  ),
                ),
              ],
            ),
            
            // Information callout
            24.height,
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: warningY50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: warningY300),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: warningY500),
                  12.width,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isEditing 
                              ? 'Penyesuaian Tipe Akun'
                              : 'Tentang Tipe Akun',
                          style: semiBoldTextStyle(color: warningY500),
                        ),
                        8.height,
                        Text(
                          _selectedRole == 'patrol'
                              ? 'Akun patroli digunakan oleh petugas untuk melakukan patroli di lapangan.'
                              : 'Akun command center dapat mengelola seluruh cluster dan melihat aktivitas patroli.',
                          style: const TextStyle(color: warningY500),
                        ),
                      ],
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

  Widget _buildAreaTab() {
    return Stack(
      children: [
        // Map
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _selectedPoints.isNotEmpty
                ? _selectedPoints.first
                : const LatLng(-6.927872391717073, 107.76910906700982),
            zoom: 14,
          ),
          markers: _markers,
          onMapCreated: (controller) {
            _mapController = controller;
            if (_selectedPoints.isNotEmpty) {
              _zoomToSelectedPoints();
            }
          },
          onTap: _handleMapTap,
          polygons: _buildClusterPolygon(),
        ),
        
        // Info panel
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: kbpBlue900),
                      8.width,
                      Text(
                        'Titik Area: ${_selectedPoints.length}',
                        style: boldTextStyle(),
                      ),
                    ],
                  ),
                  8.height,
                  const Text(
                    'Klik pada peta untuk menambahkan titik area cluster',
                    style: TextStyle(fontSize: 12, color: neutral600),
                  ),
                  16.height,
                  Row(
                    children: [
                      Expanded(
                        child: UndoButton(
                          onPressed: () {
                            if (_selectedPoints.isNotEmpty) {
                              setState(() {
                                final lastPoint = _selectedPoints.removeLast();
                                _markers.removeWhere(
                                  (marker) => marker.position == lastPoint,
                                );
                              });
                            }
                          },
                        ),
                      ),
                      8.width,
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text('Reset'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: dangerR500,
                            side: const BorderSide(color: dangerR300),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedPoints.clear();
                              _markers.clear();
                            });
                          },
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
    );
  }

  Set<Polygon> _buildClusterPolygon() {
    if (_selectedPoints.length < 3) return {}; // Need at least 3 points for a polygon
    
    return {
      Polygon(
        polygonId: const PolygonId('clusterArea'),
        points: _selectedPoints,
        fillColor: kbpBlue900.withOpacity(0.2),
        strokeColor: kbpBlue900,
        strokeWidth: 2,
      ),
    };
  }

  void _handleMapTap(LatLng position) {
    setState(() {
      _selectedPoints.add(position);
      _markers.add(
        Marker(
          markerId: MarkerId('point_${_selectedPoints.length}'),
          position: position,
          infoWindow: InfoWindow(title: 'Point ${_selectedPoints.length}'),
        ),
      );
    });
  }

  void _zoomToSelectedPoints() {
    if (_selectedPoints.isEmpty || _mapController == null) return;
    
    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;
    
    for (var point in _selectedPoints) {
      minLat = minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng > point.longitude ? maxLng : point.longitude;
    }
    
    // Add some padding
    final padding = 0.01;
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

  void _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      // Show tab with form errors
      _tabController.animateTo(0);
      return;
    }
    
    if (_selectedPoints.isEmpty) {
      showCustomSnackbar(
        context: context,
        title: 'Area belum ditentukan',
        subtitle: 'Silakan tentukan area cluster dengan minimal 3 titik',
        type: SnackbarType.warning,
      );
      _tabController.animateTo(1);
      return;
    }
    
    // Show confirmation dialog
    final confirmed = await _showConfirmationDialog();
    if (confirmed != true) return;
    
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: lottie.Lottie.asset(
          'assets/lottie/maps_loading.json',
          width: 200,
          height: 100,
        ),
      ),
    );
    
    try {
      final clusterCoordinates = _selectedPoints
          .map((point) => [point.latitude, point.longitude])
          .toList();
      
      if (_isEditing) {
        // Update existing cluster
        final updatedCluster = widget.existingCluster!.copyWith(
          name: _nameController.text,
          role: _selectedRole,
          clusterCoordinates: clusterCoordinates,
          updatedAt: DateTime.now(),
        );
        
        context.read<AdminBloc>().add(
          UpdateClusterAccount(
            cluster: updatedCluster,
          ),
        );
      } else {
        // Create new cluster
        context.read<AdminBloc>().add(
          CreateClusterAccount(
            name: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
            clusterCoordinates: clusterCoordinates,
          ),
        );
      }
      
      // Close loading dialog
      Navigator.pop(context);
      
      // Show success message
      showCustomSnackbar(
        context: context,
        title: 'Berhasil',
        subtitle: _isEditing
            ? 'Cluster berhasil diperbarui'
            : 'Cluster baru berhasil dibuat',
        type: SnackbarType.success,
      );
      
      // Navigate back
      Navigator.of(context).pop();
    } catch (e) {
      // Close loading dialog
      Navigator.pop(context);
      
      // Show error message
      showCustomSnackbar(
        context: context,
        title: 'Gagal',
        subtitle: 'Terjadi kesalahan: ${e.toString()}',
        type: SnackbarType.danger,
      );
    }
  }

  Future<bool?> _showConfirmationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _isEditing ? 'Konfirmasi Perubahan' : 'Konfirmasi Pembuatan Cluster',
          style: boldTextStyle(),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing
                  ? 'Apakah Anda yakin ingin menyimpan perubahan pada cluster ini?'
                  : 'Apakah Anda yakin ingin membuat cluster baru dengan detail berikut?',
              style: const TextStyle(color: neutral700),
            ),
            16.height,
            _infoRow('Nama', _nameController.text),
            if (!_isEditing) _infoRow('Email', _emailController.text),
            _infoRow('Tipe', _selectedRole == 'patrol' ? 'Patroli' : 'Command Center'),
            _infoRow('Jumlah Titik Area', _selectedPoints.length.toString()),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Batal'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kbpBlue900,
              foregroundColor: neutralWhite,
            ),
            child: Text(_isEditing ? 'Simpan Perubahan' : 'Buat Cluster'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: semiBoldTextStyle(color: neutral700),
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
}