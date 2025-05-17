import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/component/map_section.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:lottie/lottie.dart' as lottie;

class CreateClusterScreen extends StatefulWidget {
  const CreateClusterScreen({Key? key}) : super(key: key);

  @override
  State<CreateClusterScreen> createState() => _CreateClusterScreenState();
}

class _CreateClusterScreenState extends State<CreateClusterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final Set<Marker> _markers = {};
  final List<LatLng> _selectedPoints = [];
  bool _isCreating = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _isMapExpanded = false;
  GoogleMapController? _mapController;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  void _handleMapTap(LatLng position) {
    setState(() {
      _selectedPoints.add(position);
      _updateMarkers();
    });
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

  void _createCluster() async {
    // Close expanded map if open
    if (_isMapExpanded) {
      setState(() {
        _isMapExpanded = false;
      });
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_selectedPoints.isEmpty || _selectedPoints.length < 3) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle:
            'Anda harus menentukan setidaknya 3 titik koordinat untuk cluster',
        type: SnackbarType.danger,
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Password dan konfirmasi password tidak cocok',
        type: SnackbarType.danger,
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      // Konversi LatLng ke List<List<double>>
      final coordinates = _selectedPoints
          .map((point) => [point.latitude, point.longitude])
          .toList();

      // Kirim event create cluster ke AdminBloc
      context.read<AdminBloc>().add(
            CreateClusterAccount(
              name: _nameController.text,
              email: _emailController.text,
              password: _passwordController.text,
              clusterCoordinates: coordinates,
            ),
          );

      // Menunggu sebentar untuk memastikan event diproses
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _isCreating = false;
      });

      if (!mounted) return;

      showCustomSnackbar(
        context: context,
        title: 'Berhasil',
        subtitle: 'Cluster berhasil dibuat',
        type: SnackbarType.success,
      );

      Navigator.pop(context); // Kembali ke halaman sebelumnya
    } catch (e) {
      setState(() {
        _isCreating = false;
      });

      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Gagal membuat cluster: $e',
        type: SnackbarType.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Jika map sedang dalam mode expanded, tampilkan fullscreen map
    if (_isMapExpanded) {
      return Scaffold(
        body: Stack(
          children: [
            // Fullscreen map
            MapSection(
              mapController: _mapController,
              markers: _markers,
              onMapTap: _handleMapTap,
            ),

            // Control panel overlay
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
                            'Penentuan Area Cluster',
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
                      Text(
                        'Klik pada peta untuk menambahkan titik. Minimal 3 titik untuk membentuk area.',
                        style: const TextStyle(
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
                              onPressed: _selectedPoints.length < 3
                                  ? null
                                  : () {
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
                                disabledBackgroundColor: neutral300,
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

    // Tampilan form normal
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat Cluster Baru'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
      ),
      body: BlocListener<AdminBloc, AdminState>(
        listener: (context, state) {
          if (state is ClustersError) {
            showCustomSnackbar(
              context: context,
              title: 'Error',
              subtitle: state.message,
              type: SnackbarType.danger,
            );
            setState(() {
              _isCreating = false;
            });
          }
        },
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Informasi Cluster
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Informasi Cluster',
                        style: boldTextStyle(size: 18),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Nama Cluster',
                          hintText: 'Contoh: Cluster Barat',
                          prefixIcon:
                              const Icon(Icons.business, color: kbpBlue900),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: kbpBlue900, width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Nama cluster tidak boleh kosong';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'Contoh: cluster.barat@example.com',
                          prefixIcon:
                              const Icon(Icons.email, color: kbpBlue900),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: kbpBlue900, width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Email tidak boleh kosong';
                          }
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                              .hasMatch(value)) {
                            return 'Masukkan email yang valid';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: !_showPassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock, color: kbpBlue900),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: kbpBlue900,
                            ),
                            onPressed: () {
                              setState(() {
                                _showPassword = !_showPassword;
                              });
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: kbpBlue900, width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password tidak boleh kosong';
                          }
                          if (value.length < 6) {
                            return 'Password minimal 6 karakter';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: !_showConfirmPassword,
                        decoration: InputDecoration(
                          labelText: 'Konfirmasi Password',
                          prefixIcon:
                              const Icon(Icons.lock_outline, color: kbpBlue900),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _showConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: kbpBlue900,
                            ),
                            onPressed: () {
                              setState(() {
                                _showConfirmPassword = !_showConfirmPassword;
                              });
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: kbpBlue900, width: 2),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Konfirmasi password tidak boleh kosong';
                          }
                          if (value != _passwordController.text) {
                            return 'Password dan konfirmasi tidak cocok';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Area Koordinat Cluster
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
                            'Area Cluster',
                            style: boldTextStyle(size: 18),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _isMapExpanded = true;
                              });
                            },
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
                        'Klik pada peta untuk menentukan titik-titik area cluster. Minimal 3 titik untuk membentuk area.',
                        style: TextStyle(color: neutral600),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        height: 300,
                        decoration: BoxDecoration(
                          border: Border.all(color: kbpBlue300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            children: [
                              MapSection(
                                mapController: _mapController,
                                markers: _markers,
                                onMapTap: _handleMapTap,
                              ),
                              Positioned(
                                right: 8,
                                top: 8,
                                child: FloatingActionButton.small(
                                  heroTag: 'expand_map',
                                  backgroundColor: Colors.white,
                                  foregroundColor: kbpBlue900,
                                  onPressed: () {
                                    setState(() {
                                      _isMapExpanded = true;
                                    });
                                  },
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
                            'Titik dipilih: ${_selectedPoints.length}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              color: neutral700,
                            ),
                          ),
                          TextButton.icon(
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

                const SizedBox(height: 24),

                // Tombol Buat Cluster
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ElevatedButton(
                    onPressed: _isCreating ? null : _createCluster,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kbpBlue900,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      disabledBackgroundColor: neutral300,
                    ),
                    child: _isCreating
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
                                'Membuat Cluster...',
                                style: boldTextStyle(
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'Buat Cluster',
                            style: boldTextStyle(
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
