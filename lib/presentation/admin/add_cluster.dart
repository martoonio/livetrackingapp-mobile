import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/cluster.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/component/undo_button.dart';
import 'package:lottie/lottie.dart' as lottie;
import '../component/dropdown_component.dart';
import '../component/map_section.dart';

class AddClusterScreen extends StatefulWidget {
  final ClusterModel? existingCluster; // Untuk fitur edit jika diperlukan

  const AddClusterScreen({super.key, this.existingCluster});

  @override
  State<AddClusterScreen> createState() => _AddClusterScreenState();
}

class _AddClusterScreenState extends State<AddClusterScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final Set<Marker> _markers = {};
  final List<LatLng> _selectedPoints = [];
  String _status = 'active'; // Default status
  GoogleMapController? _mapController;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    // Jika ada existing cluster, pra-isi form untuk edit
    if (widget.existingCluster != null) {
      _isEditing = true;
      _nameController.text = widget.existingCluster!.name;
      _descriptionController.text = widget.existingCluster!.description;
      _status = widget.existingCluster!.status;

      // Convert existing coordinates to markers
      if (widget.existingCluster!.clusterCoordinates != null) {
        for (int i = 0;
            i < widget.existingCluster!.clusterCoordinates!.length;
            i++) {
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
    }

    // Load initial data if needed
    context.read<AdminBloc>().add(LoadClusters());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<AdminBloc, AdminState>(
        builder: (context, state) {
          if (state is ClustersLoading) {
            return Center(
              child: lottie.LottieBuilder.asset(
                'assets/lottie/maps_loading.json',
                width: 200,
                height: 100,
                fit: BoxFit.cover,
              ),
            );
          } else if (state is ClustersError) {
            return Center(child: Text(state.message));
          } else {
            return Stack(
              children: [
                // Map mengisi seluruh layar
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: MapSection(
                    mapController: _mapController,
                    markers: _markers,
                    onMapTap: _handleMapTap,
                  ),
                ),

                // Back button
                Positioned(
                  top: 50,
                  left: 16,
                  child: leadingButton(context, "Back", () {
                    Navigator.pop(context);
                    context.read<AdminBloc>().add(LoadClusters());
                  }),
                ),

                // Draggable bottom sheet
                DraggableScrollableSheet(
                  initialChildSize: 0.45, // Ukuran awal (45% dari layar)
                  minChildSize: 0.2, // Ukuran minimum (20% dari layar)
                  maxChildSize: 0.85, // Ukuran maksimum (85% dari layar)
                  builder: (context, scrollController) {
                    return _buildDraggableFormSection(scrollController);
                  },
                ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildDraggableFormSection(ScrollController scrollController) {
    return Container(
      decoration: BoxDecoration(
        color: neutralWhite,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border.all(
          color: kbpBlue900,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          // Form content in scrollable area
          Expanded(
            child: SingleChildScrollView(
              controller: scrollController,
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isEditing ? 'Edit Cluster' : 'Tambah Cluster Baru',
                        style: boldTextStyle(size: 20),
                        textAlign: TextAlign.center,
                      ),
                      24.height,

                      // Cluster Name
                      const Text(
                        'Nama Cluster:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: neutral900,
                        ),
                      ),
                      8.height,
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: 'Masukkan nama cluster...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: kbpBlue900),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: kbpBlue900),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: kbpBlue900, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Nama cluster tidak boleh kosong';
                          }
                          return null;
                        },
                      ),
                      24.height,

                      // Cluster Description
                      const Text(
                        'Deskripsi:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: neutral900,
                        ),
                      ),
                      8.height,
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Masukkan deskripsi cluster...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: kbpBlue900),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: kbpBlue900),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: kbpBlue900, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Deskripsi tidak boleh kosong';
                          }
                          return null;
                        },
                      ),
                      24.height,

                      // Status Dropdown
                      const Text(
                        'Status:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: neutral900,
                        ),
                      ),
                      8.height,
                      CustomDropdown(
                        hintText: 'Pilih status...',
                        value: _status,
                        items: const [
                          DropdownMenuItem(
                              value: 'active', child: Text('Active')),
                          DropdownMenuItem(
                              value: 'inactive', child: Text('Inactive')),
                          DropdownMenuItem(
                              value: 'deleted', child: Text('Deleted')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _status = value ?? 'active';
                          });
                        },
                        borderColor: kbpBlue900,
                      ),
                      24.height,

                      // Cluster Points Counter
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Jumlah Titik Koordinat:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: neutral900,
                            ),
                          ),
                          Text(
                            '${_selectedPoints.length}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: kbpBlue900,
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        'Klik pada peta untuk menambahkan titik koordinat.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: neutral600,
                        ),
                      ),
                      8.height,
                      UndoButton(onPressed: () {
                        if (_selectedPoints.isNotEmpty) {
                          setState(() {
                            final lastPoint = _selectedPoints.removeLast();
                            _markers.removeWhere(
                                (marker) => marker.position == lastPoint);
                          });
                        }
                      }),
                      32.height,

                      // Tombol Submit
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _submitCluster,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kbpBlue900,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _isEditing ? 'Update Cluster' : 'Simpan Cluster',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: neutralWhite,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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

  void _submitCluster() async {
    if (!_formKey.currentState!.validate()) {
      showCustomSnackbar(
        context: context,
        title: 'Validasi Gagal',
        subtitle: 'Pastikan semua field sudah diisi dengan benar',
        type: SnackbarType.danger,
        entryDirection: SnackbarEntryDirection.fromTop,
      );
      return;
    }

    if (_selectedPoints.isEmpty) {
      showCustomSnackbar(
        context: context,
        title: 'Data belum lengkap',
        subtitle: 'Silakan tambahkan minimal 1 titik koordinat',
        type: SnackbarType.danger,
        entryDirection: SnackbarEntryDirection.fromTop,
      );
      return;
    }

    // Tampilkan dialog konfirmasi
    final result = await _showConfirmationDialog();
    if (result != true) {
      return; // User membatalkan operasi
    }

    // Siapkan data cluster
    final String name = _nameController.text.trim();
    final String description = _descriptionController.text.trim();
    final List<List<double>> clusterCoordinates = _selectedPoints
        .map((point) => [point.latitude, point.longitude])
        .toList();

    // Tampilkan loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Center(
          child: lottie.LottieBuilder.asset(
            'assets/lottie/maps_loading.json',
            width: 200,
            height: 100,
            fit: BoxFit.cover,
          ),
        );
      },
    );

    try {
      if (_isEditing && widget.existingCluster != null) {
        // Update existing cluster
        context.read<AdminBloc>().add(
              UpdateCluster(
                clusterId: widget.existingCluster!.id,
                name: name,
                description: description,
                clusterCoordinates: clusterCoordinates,
                status: _status,
              ),
            );
      } else {
        // Create new cluster
        context.read<AdminBloc>().add(
              CreateCluster(
                name: name,
                description: description,
                clusterCoordinates: clusterCoordinates,
                status: _status,
              ),
            );
      }

      // Close loading dialog
      Navigator.of(context).pop();

      // Show success message
      showCustomSnackbar(
        context: context,
        title: 'Berhasil',
        subtitle: _isEditing
            ? 'Cluster berhasil diperbarui'
            : 'Cluster berhasil dibuat',
        type: SnackbarType.success,
        entryDirection: SnackbarEntryDirection.fromTop,
      );

      // Reset form or navigate back
      if (!_isEditing) {
        setState(() {
          _nameController.clear();
          _descriptionController.clear();
          _selectedPoints.clear();
          _markers.clear();
          _status = 'active';
        });
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();

      // Show error message
      showCustomSnackbar(
        context: context,
        title: 'Gagal',
        subtitle: 'Terjadi kesalahan: ${e.toString()}',
        type: SnackbarType.danger,
        entryDirection: SnackbarEntryDirection.fromTop,
      );
    }
  }

  Future<bool?> _showConfirmationDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            _isEditing
                ? 'Konfirmasi Perubahan Cluster'
                : 'Konfirmasi Pembuatan Cluster',
            style: boldTextStyle(
              size: h4,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Detail Cluster:', style: semiBoldTextStyle()),
                _infoRow('Nama', _nameController.text),
                _infoRow('Deskripsi', _descriptionController.text),
                _infoRow('Status', _status),
                _infoRow('Jumlah Titik', _selectedPoints.length.toString()),
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
                style: mediumTextStyle(
                  color: kbpBlue900,
                ),
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
                  _isEditing ? 'Ya, Perbarui Cluster' : 'Ya, Buat Cluster',
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
}
