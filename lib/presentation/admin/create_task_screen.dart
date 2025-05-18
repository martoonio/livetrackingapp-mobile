import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
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

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final Set<Marker> _markers = {};
  final List<LatLng> _selectedPoints = [];
  bool _isCreating = false;
  bool _isMapExpanded = false;
  GoogleMapController? _mapController;

  // Form values
  String? _selectedClusterId;
  String _vehicleId = '';
  String? _selectedOfficerId;
  Officer? _selectedOfficer;
  String? _selectedClusterName;

  // Shift-based time presets

  DateTime _assignedStartTime = DateTime.now();
  DateTime _assignedEndTime = DateTime.now().add(const Duration(hours: 8));

  @override
  void initState() {
    super.initState();
    print('CreateTaskScreen initialized');

    // Jika ada initialClusterId, set sebagai cluster terpilih
    if (widget.initialClusterId != null) {
      _selectedClusterId = widget.initialClusterId;
    }

    // Load semua data yang diperlukan dengan delay untuk mencegah race condition
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('Dispatching LoadAllClusters event');
      context.read<AdminBloc>().add(const LoadAllClusters());

      Future.delayed(const Duration(milliseconds: 300), () {
        print('Dispatching LoadOfficersAndVehicles event');
        context.read<AdminBloc>().add(const LoadOfficersAndVehicles());
      });
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  // Tambahkan metode-metode ini di dalam class _CreateTaskScreenState

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

// Perbaikan pada metode _updateEndTimeBasedOnStartTime

  void _updateEndTimeBasedOnStartTime() {
    if (_selectedOfficer == null) return;

    // Default: waktu selesai adalah 1 jam setelah waktu mulai
    DateTime endTime = _assignedStartTime.add(const Duration(hours: 1));

    // Tentukan batas maksimum waktu selesai berdasarkan shift
    DateTime maxEndTime;

    switch (_selectedOfficer!.shift) {
      case ShiftType.pagi:
        // Batas waktu maksimum untuk shift pagi: jam 15:00 di hari yang sama
        maxEndTime = DateTime(
          _assignedStartTime.year,
          _assignedStartTime.month,
          _assignedStartTime.day,
          15,
          0,
        );
        break;
      case ShiftType.sore:
        // Batas waktu maksimum untuk shift sore: jam 23:00 di hari yang sama
        maxEndTime = DateTime(
          _assignedStartTime.year,
          _assignedStartTime.month,
          _assignedStartTime.day,
          23,
          0,
        );
        break;
      case ShiftType.malam:
        // Batas waktu maksimum untuk shift malam: jam 7:00 di hari berikutnya
        maxEndTime = DateTime(
          _assignedStartTime.year,
          _assignedStartTime.month,
          _assignedStartTime.day,
          7,
          0,
        ).add(const Duration(days: 1));
        break;
      case ShiftType.siang:
        // Batas waktu maksimum untuk shift siang outsource: jam 19:00 di hari yang sama
        maxEndTime = DateTime(
          _assignedStartTime.year,
          _assignedStartTime.month,
          _assignedStartTime.day,
          19,
          0,
        );
        break;
      case ShiftType.malamPanjang:
        // Batas waktu maksimum untuk shift malam outsource: jam 7:00 di hari berikutnya
        maxEndTime = DateTime(
          _assignedStartTime.year,
          _assignedStartTime.month,
          _assignedStartTime.day,
          7,
          0,
        ).add(const Duration(days: 1));
        break;
    }

    // Gunakan waktu yang lebih awal antara endTime (waktu mulai + 1 jam) atau maxEndTime (batas shift)
    if (endTime.isAfter(maxEndTime)) {
      endTime = maxEndTime;
    }

    setState(() {
      _assignedEndTime = endTime;
    });

    print(
        'Updated end time: ${DateFormat('dd/MM/yyyy HH:mm').format(_assignedEndTime)}');
  }

  // Perbarui fungsi _updateMarkers untuk membuat marker yang dapat diklik untuk dihapus

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
              // Ketika infoWindow diklik, hapus marker ini
              _removeMarkerAtIndex(i);
            },
          ),
          onTap: () {
            // Ketika marker diklik, tampilkan infoWindow
            if (_mapController != null) {
              // Perbarui tampilan camera untuk fokus ke marker yang diklik
              _mapController!.showMarkerInfoWindow(MarkerId('point_$i'));
            }
          },
        ),
      );
    }
  }

// Tambahkan fungsi baru untuk menghapus titik berdasarkan index
  void _removeMarkerAtIndex(int index) {
    if (index >= 0 && index < _selectedPoints.length) {
      setState(() {
        // Hapus titik dari list
        _selectedPoints.removeAt(index);
        // Update semua marker dengan index yang terbarui
        _updateMarkers();
      });

      // Tampilkan snackbar konfirmasi
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Titik berhasil dihapus'),
          duration: Duration(seconds: 1),
          backgroundColor: kbpBlue700,
        ),
      );
    }
  }

// Modifikasi juga _handleMapTap untuk mendukung penghapusan titik dengan tap langsung
  void _handleMapTap(LatLng position) {
    // Periksa apakah tap berada di dekat titik yang sudah ada (untuk menghapus)
    int indexToRemove = _findNearestPointIndex(position);

    if (indexToRemove != -1) {
      // Jika dekat dengan titik yang sudah ada, hapus titik tersebut
      _removeMarkerAtIndex(indexToRemove);
    } else {
      // Jika tidak dekat dengan titik yang sudah ada, tambahkan titik baru
      setState(() {
        _selectedPoints.add(position);
        _updateMarkers();
      });
    }
  }

// Fungsi tambahan untuk mencari titik terdekat dari posisi tap
  int _findNearestPointIndex(LatLng tapPosition) {
    // Jarak minimum dalam derajat untuk mendeteksi "klik pada titik" (~5-10 meter)
    const double minDistance = 0.0001;

    for (int i = 0; i < _selectedPoints.length; i++) {
      final point = _selectedPoints[i];
      final distance = _calculateDistance(tapPosition, point);

      if (distance < minDistance) {
        return i; // Kembalikan index titik yang cukup dekat
      }
    }

    return -1; // Tidak ada titik yang cukup dekat
  }

// Fungsi untuk menghitung jarak antara dua titik koordinat
  double _calculateDistance(LatLng pos1, LatLng pos2) {
    // Menggunakan formula sederhana Euclidean distance untuk keperluan deteksi tap
    // Ini hanya perkiraan, tidak akurat untuk jarak sebenarnya di bumi
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

      // Zoom to bounds if we have points
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

  void _submitTask() async {
    if (_isMapExpanded) {
      setState(() {
        _isMapExpanded = false;
      });
      return;
    }

    if (!_formKey.currentState!.validate()) return;

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

    if (_vehicleId.isEmpty) {
      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Silakan pilih kendaraan terlebih dahulu',
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

    // Konfirmasi waktu patroli
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

    // 1. Menampilkan dialog konfirmasi
    final result = await _showConfirmationDialog();
    if (result != true) {
      return; // User membatalkan operasi
    }

    setState(() {
      _isCreating = true;
    });

    try {
      // Konversi LatLng ke List<List<double>>
      final coordinates = _selectedPoints
          .map((point) => [point.latitude, point.longitude])
          .toList();

      // Kirim event create task ke AdminBloc
      context.read<AdminBloc>().add(
            CreateTask(
              clusterId: _selectedClusterId!,
              vehicleId: _vehicleId,
              assignedRoute: coordinates,
              assignedOfficerId: _selectedOfficerId,
              assignedStartTime: _assignedStartTime,
              assignedEndTime: _assignedEndTime,
            ),
          );

      // Menunggu sebentar untuk memastikan event diproses
      await Future.delayed(const Duration(milliseconds: 500));

      // Kirim notifikasi ke petugas
      await sendPushNotificationToOfficer(
        officerId: _selectedClusterId!,
        title: 'Tugas Patroli Baru',
        body:
            'Anda telah ditugaskan untuk patroli pada ${DateFormat('dd/MM/yyyy - HH:mm').format(_assignedStartTime)}',
        patrolTime: DateFormat('dd/MM/yyyy - HH:mm').format(_assignedStartTime),
      );

      setState(() {
        _isCreating = false;
      });

      if (mounted) {
        showCustomSnackbar(
          context: context,
          title: 'Berhasil',
          subtitle: 'Tugas patroli berhasil dibuat dan notifikasi terkirim',
          type: SnackbarType.success,
        );

        Navigator.pop(context); // Kembali ke halaman sebelumnya
      }
    } catch (e) {
      setState(() {
        _isCreating = false;
      });

      showCustomSnackbar(
        context: context,
        title: 'Error',
        subtitle: 'Gagal membuat tugas patroli: $e',
        type: SnackbarType.danger,
      );
    }
  }

  // Menampilkan dialog konfirmasi
  // Memperbaiki dialog konfirmasi untuk menampilkan nama cluster yang benar

  Future<bool?> _showConfirmationDialog() async {
    String officerName = _selectedOfficer?.name ?? 'Tidak ditemukan';
    String clusterName = 'Unknown Cluster';

    // Get readable shift display text
    String shiftText = '';
    if (_selectedOfficer != null) {
      switch (_selectedOfficer!.shift) {
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

    // Get readable type display text
    String typeText =
        _selectedOfficer?.type == OfficerType.organik ? 'Organik' : 'Outsource';

    // Cari info cluster dari state
    final adminState = context.read<AdminBloc>().state;

    // Pendekatan lebih sederhana untuk menemukan cluster yang dipilih
    List<User> availableClusters = [];

    if (adminState is ClustersLoaded) {
      availableClusters = adminState.clusters;
    } else if (adminState is AdminLoaded) {
      availableClusters = adminState.clusters;
    } else if (adminState is OfficersAndVehiclesLoaded) {
      availableClusters = adminState.clusters;
    }

    // Coba temukan cluster berdasarkan ID
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
            'Konfirmasi Tugas Patroli',
            style: boldTextStyle(size: h4),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Detail Tugas:', style: semiBoldTextStyle()),
                _infoRow('Cluster', clusterName),
                _infoRow(
                    'Petugas', '$officerName ($typeText - Shift $shiftText)'),
                _infoRow('Kendaraan', _vehicleId),
                _infoRow(
                    'Jumlah Titik Patroli', _selectedPoints.length.toString()),
                _infoRow('Mulai Patroli',
                    "${DateFormat('dd/MM/yyyy - HH:mm').format(_assignedStartTime)}"),
                _infoRow('Selesai Patroli',
                    "${DateFormat('dd/MM/yyyy - HH:mm').format(_assignedEndTime)}"),
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
              child: const Text('Ya, Buat Tugas',
                  style: TextStyle(color: Colors.white)),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );
  }

  // Helper widget untuk menampilkan info di dialog konfirmasi
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

  // Mencari officer data berdasarkan ID
  // Perbarui metode _updateSelectedOfficer

  void _updateSelectedOfficer(String officerId, List<Officer> officers) {
    final officer = officers.firstWhere(
      (o) => o.id == officerId,
      orElse: () => Officer(
        id: '',
        name: '',
        type: OfficerType.organik, // Default ke organik
        shift: ShiftType.pagi, // Default ke pagi
        clusterId: '',
      ),
    );

    setState(() {
      _selectedOfficer = officer;
    });

    // Atur waktu berdasarkan shift petugas
    _setInitialTimeBasedOnShift(officer.type, officer.shift);
  }

// 3. Tambah metode baru untuk set awal waktu berdasarkan type dan shift

  void _setInitialTimeBasedOnShift(OfficerType type, ShiftType shift) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    DateTime startDate;
    DateTime endDate;

    // Tentukan jam mulai dan selesai default berdasarkan type dan shift
    switch (shift) {
      case ShiftType.pagi:
        // Organik: 07:00-15:00
        startDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 7, 0);
        endDate = startDate.add(const Duration(hours: 1)); // Default 1 jam
        break;
      case ShiftType.sore:
        // Organik: 15:00-23:00
        startDate =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15, 0);
        endDate = startDate.add(const Duration(hours: 1));
        break;
      case ShiftType.malam:
        // Organik: 23:00-07:00
        startDate =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 23, 0);
        endDate = startDate.add(const Duration(hours: 1));
        break;
      case ShiftType.siang:
        // Outsource: 07:00-19:00
        startDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 7, 0);
        endDate = startDate.add(const Duration(hours: 1));
        break;
      case ShiftType.malamPanjang:
        // Outsource: 19:00-07:00
        startDate =
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 19, 0);
        endDate = startDate.add(const Duration(hours: 1));
        break;
    }

    setState(() {
      _assignedStartTime = startDate;
      _assignedEndTime = endDate;
    });

    print(
        'Initial times set based on type ${type.toString()} and shift ${shift.toString()}: Start=${DateFormat('dd/MM/yyyy HH:mm').format(startDate)}, End=${DateFormat('dd/MM/yyyy HH:mm').format(endDate)}');
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

    // Tampilan form normal
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat Tugas Patroli'),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
      ),
      body: BlocConsumer<AdminBloc, AdminState>(
        listener: (context, state) {
          if (state is CreateTaskSuccess) {
            // Berhasil membuat tugas, akan dihandle di _submitTask
          } else if (state is CreateTaskError) {
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
        builder: (context, state) {
          // Tampilkan loading jika data belum siap
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

          // Tampilkan error jika gagal memuat data
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
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
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

          // Extract data from state
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

            // Cari officers dan vehicles dari state lain
            final adminState = context.read<AdminBloc>().state;
            if (adminState is OfficersAndVehiclesLoaded) {
              officers = adminState.officers;
              vehicles = adminState.vehicles;
            } else if (adminState is AdminLoaded) {
              officers = _getOfficersFromClusters(adminState.clusters);
              vehicles = adminState.vehicles;
            }
          }

          // Get coordinates for the selected cluster
          if (_selectedClusterId != null) {
            final selectedCluster = clusters.firstWhere(
              (cluster) => cluster.id == _selectedClusterId,
              orElse: () => User(id: '', email: '', name: '', role: ''),
            );

            if (selectedCluster.id.isNotEmpty &&
                selectedCluster.clusterCoordinates != null) {
              selectedClusterCoordinates = selectedCluster.clusterCoordinates;

              // Add cluster coordinates to map if we just got them
              if (selectedClusterCoordinates != null &&
                  _selectedPoints.isEmpty) {
                Future.microtask(() {
                  _addClusterCoordinatesToMap(selectedClusterCoordinates!);
                });
              }
            }
          }

          // Filter officers jika cluster telah dipilih
          List<Officer> filteredOfficers = officers;
          if (_selectedClusterId != null && _selectedClusterId!.isNotEmpty) {
            filteredOfficers = officers
                .where((officer) => officer.clusterId == _selectedClusterId)
                .toList();
          }

          return Form(
            key: _formKey,
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

                        // Dropdown Cluster
                        const Text(
                          'Cluster',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: neutral900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: kbpBlue900),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonFormField<String>(
                            value: _selectedClusterId,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              border: InputBorder.none,
                            ),
                            hint: const Text('Pilih Cluster'),
                            isExpanded: true,
                            items: clusters.map((cluster) {
                              return DropdownMenuItem(
                                value: cluster.id,
                                child: Text(cluster.name),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedClusterId = value;

                                // Simpan nama cluster saat pilihan dibuat
                                if (value != null) {
                                  final selectedCluster = clusters.firstWhere(
                                    (cluster) => cluster.id == value,
                                    orElse: () => User(
                                        id: '', email: '', name: '', role: ''),
                                  );
                                  if (selectedCluster.id.isNotEmpty) {
                                    _selectedClusterName = selectedCluster
                                        .name; // Tambahkan field ini di class
                                  }
                                }

                                _selectedOfficerId = null;
                                _selectedOfficer = null;
                                _selectedPoints.clear();
                                _markers.clear();
                              });
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Silakan pilih cluster';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Dropdown Petugas - hanya tampilkan jika cluster telah dipilih
                        if (_selectedClusterId != null) ...[
                          const Text(
                            'Petugas',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: neutral900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: kbpBlue900),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonFormField<String>(
                              value: _selectedOfficerId,
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                border: InputBorder.none,
                              ),
                              hint: const Text('Pilih Petugas'),
                              isExpanded: true,
                              items: filteredOfficers.map((officer) {
                                // Get readable shift display text
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

                                // Get readable type display text
                                String typeText =
                                    officer.type == OfficerType.organik
                                        ? 'Organik'
                                        : 'Outsource';

                                return DropdownMenuItem(
                                  value: officer.id,
                                  child: Text(
                                      '${officer.name} ($typeText - $shiftText)'),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedOfficerId = value;
                                  if (value != null) {
                                    _updateSelectedOfficer(
                                        value, filteredOfficers);
                                  }
                                });
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Silakan pilih petugas';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Dropdown Kendaraan
                        const Text(
                          'Kendaraan',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: neutral900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: kbpBlue900),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonFormField<String>(
                            value: _vehicleId.isEmpty ? null : _vehicleId,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              border: InputBorder.none,
                            ),
                            hint: const Text('Pilih Kendaraan'),
                            isExpanded: true,
                            items: vehicles.map((vehicle) {
                              return DropdownMenuItem(
                                value: vehicle,
                                child: Text(vehicle),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _vehicleId = value ?? '';
                              });
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Silakan pilih kendaraan';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Jadwal Patroli
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
                        const SizedBox(height: 16),

                        // Waktu Mulai dan Selesai (disesuaikan dengan shift officer)
                        if (_selectedOfficer != null) ...[
                          Text(
                            'Jadwal otomatis berdasarkan Shift ${_selectedOfficer!.shift}',
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              color: kbpBlue700,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],

                        // Waktu Mulai
                        const Text(
                          'Waktu Mulai',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: neutral900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Modifikasi GestureDetector pada "Waktu Mulai" dan "Waktu Selesai"

// Waktu Mulai
                        GestureDetector(
                          onTap: () async {
                            _showStartTimePicker();
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
                                      .format(_assignedStartTime),
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const Icon(Icons.calendar_today,
                                    color: kbpBlue900),
                              ],
                            ),
                          ),
                        ),

// Waktu Selesai

                        const SizedBox(height: 16),

                        // Waktu Selesai
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
                            if (_selectedOfficer == null) {
                              showCustomSnackbar(
                                context: context,
                                title: 'Perhatian',
                                subtitle:
                                    'Silakan pilih petugas terlebih dahulu untuk menentukan waktu patroli',
                                type: SnackbarType.warning,
                              );
                              return;
                            }

                            // Pilih tanggal terlebih dahulu
                            final selectedDate = await showDatePicker(
                              context: context,
                              initialDate: _assignedEndTime,
                              firstDate: DateTime.now(),
                              lastDate:
                                  DateTime.now().add(const Duration(days: 365)),
                            );

                            if (selectedDate != null) {
                              // Tampilkan time picker
                              final selectedTime = await showTimePicker(
                                context: context,
                                initialTime:
                                    TimeOfDay.fromDateTime(_assignedEndTime),
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
                                // Validasi jam yang dipilih sesuai shift
                                bool isValidTime = _isTimeInShiftRange(
                                    selectedTime, _selectedOfficer!.shift);

                                if (!isValidTime) {
                                  if (mounted) {
                                    showCustomSnackbar(
                                      context: context,
                                      title: 'Waktu Tidak Valid',
                                      subtitle: _getShiftTimeRangeMessage(
                                          _selectedOfficer!.shift),
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

                                // Untuk shift malam, jika jam lebih kecil dari 7, artinya ini adalah dini hari (pagi berikutnya)
                                if (_selectedOfficer!.shift == 'Malam' &&
                                    selectedTime.hour < 7) {
                                  newEndTime =
                                      newEndTime.add(const Duration(days: 1));
                                }

                                // Pastikan waktu selesai setelah waktu mulai
                                if (newEndTime.isBefore(_assignedStartTime) ||
                                    newEndTime
                                        .isAtSameMomentAs(_assignedStartTime)) {
                                  showCustomSnackbar(
                                    context: context,
                                    title: 'Waktu Tidak Valid',
                                    subtitle:
                                        'Waktu selesai harus setelah waktu mulai',
                                    type: SnackbarType.danger,
                                  );
                                  return;
                                }

                                setState(() {
                                  _assignedEndTime = newEndTime;
                                });
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
                                      .format(_assignedEndTime),
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const Icon(Icons.calendar_today,
                                    color: kbpBlue900),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Titik Patroli
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

                  // Tombol Buat Tugas
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: ElevatedButton(
                      onPressed: _isCreating ? null : _submitTask,
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

                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Ekstrak semua officers dari list cluster
  List<Officer> _getOfficersFromClusters(List<User> clusters) {
    List<Officer> allOfficers = [];

    for (var cluster in clusters) {
      if (cluster.officers != null && cluster.officers!.isNotEmpty) {
        // Pastikan setiap officer mendapatkan clusterId jika belum ada
        for (var officer in cluster.officers!) {
          if (officer.clusterId.isEmpty) {
            final updatedOfficer = Officer(
              id: officer.id,
              name: officer.name,
              type: officer.type, // Use the officer type
              shift: officer.shift, // Use the officer shift
              clusterId: cluster.id, // Set clusterId dari parent cluster
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

  // Di dalam GestureDetector untuk memilih waktu mulai
  void _showStartTimePicker() async {
    if (_selectedOfficer == null) {
      showCustomSnackbar(
        context: context,
        title: 'Perhatian',
        subtitle:
            'Silakan pilih petugas terlebih dahulu untuk menentukan waktu patroli',
        type: SnackbarType.warning,
      );
      return;
    }

    // Pilih tanggal terlebih dahulu
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _assignedStartTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selectedDate != null) {
      // Tentukan range waktu yang valid berdasarkan shift
      TimeOfDay initialTime = TimeOfDay.fromDateTime(_assignedStartTime);

      // Tampilkan time picker
      final selectedTime = await showTimePicker(
        context: context,
        initialTime: initialTime,
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
        // Validasi jam yang dipilih sesuai shift
        bool isValidTime =
            _isTimeInShiftRange(selectedTime, _selectedOfficer!.shift);

        if (!isValidTime) {
          if (mounted) {
            showCustomSnackbar(
              context: context,
              title: 'Waktu Tidak Valid',
              subtitle: _getShiftTimeRangeMessage(_selectedOfficer!.shift),
              type: SnackbarType.danger,
            );
          }
          return;
        }

        setState(() {
          // Gabungkan tanggal dan waktu yang dipilih
          _assignedStartTime = DateTime(
            selectedDate.year,
            selectedDate.month,
            selectedDate.day,
            selectedTime.hour,
            selectedTime.minute,
          );

          // Untuk shift malam, jika jam lebih kecil dari 7, artinya ini adalah dini hari (pagi berikutnya)
          if ((_selectedOfficer!.shift == ShiftType.malam ||
                  _selectedOfficer!.shift == ShiftType.malamPanjang) &&
              selectedTime.hour < 7) {
            _assignedStartTime =
                _assignedStartTime.add(const Duration(days: 1));
          }

          // Update juga waktu selesai
          _updateEndTimeBasedOnStartTime();
        });
      }
    }
  }
}
