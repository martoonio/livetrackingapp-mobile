import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/notification_utils.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/component/undo_button.dart';
import 'package:lottie/lottie.dart' as lottie;
import '../component/dropdown_component.dart';
import '../component/map_section.dart';

class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final Set<Marker> _markers = {};
  final List<LatLng> _selectedPoints = [];
  GoogleMapController? _mapController;
// Store the user's current location
  String _vehicleId = '';
  String? _selectedOfficerId;

  bool _isOfficerInvalid = true;
  bool _isVehicleInvalid = true;

  DateTime _assignedStartTime = DateTime.now();
  DateTime _assignedEndTime = DateTime.now().add(const Duration(hours: 1));

  @override
  void initState() {
    super.initState();
    context.read<AdminBloc>().add(LoadOfficersAndVehicles());
  }

  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<AdminBloc, AdminState>(
        builder: (context, state) {
          if (state is OfficersAndVehiclesLoading) {
            return Center(
              child: lottie.LottieBuilder.asset(
                'assets/lottie/maps_loading.json',
                width: 200,
                height: 100,
                fit: BoxFit.cover,
              ),
            );
          } else if (state is OfficersAndVehiclesError) {
            return Center(child: Text(state.message));
          } else if (state is OfficersAndVehiclesLoaded) {
            return Stack(
              children: [
                // Map mengisi seluruh layar
                SizedBox(
                  height: MediaQuery.of(context).size.height,
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
                    context.read<AdminBloc>().add(LoadAllTasks());
                  }),
                ),

                // Draggable bottom sheet
                DraggableScrollableSheet(
                  initialChildSize: 0.45, // Ukuran awal (45% dari layar)
                  minChildSize: 0.2, // Ukuran minimum (20% dari layar)
                  maxChildSize: 0.85, // Ukuran maksimum (85% dari layar)
                  builder: (context, scrollController) {
                    return _buildDraggableFormSection(
                        state.officers, state.vehicles, scrollController);
                  },
                ),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildDraggableFormSection(List<User> officers, List<String> vehicles,
      ScrollController scrollController) {
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
                      // Officer Dropdown
                      const Text(
                        'Petugas :',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: neutral900,
                        ),
                      ),
                      8.height,
                      CustomDropdown(
                        hintText: 'Silakan pilih petugas...',
                        value: _selectedOfficerId,
                        items: officers.map((officer) {
                          return DropdownMenuItem(
                            value: officer.id,
                            child: Text('${officer.name} (${officer.email})'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedOfficerId = value;
                            _isOfficerInvalid = false;
                          });
                        },
                        borderColor:
                            _isOfficerInvalid ? Colors.red : kbpBlue900,
                      ),
                      24.height,

                      // Vehicle Dropdown
                      const Text(
                        'Kendaraan Patroli :',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: neutral900,
                        ),
                      ),
                      8.height,
                      CustomDropdown(
                        hintText: 'Silakan pilih kendaraan...',
                        value: _vehicleId.isEmpty ? null : _vehicleId,
                        items: vehicles.map((vehicle) {
                          return DropdownMenuItem(
                            value: vehicle,
                            child: Text(vehicle),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _vehicleId = value ?? '';
                            _isVehicleInvalid = false;
                          });
                        },
                        borderColor:
                            _isVehicleInvalid ? Colors.red : kbpBlue900,
                      ),
                      24.height,

                      // Patrol Points Counter
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Jumlah Titik Patroli :',
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
                      8.height,
                      UndoButton(onPressed: () {
                        if (_selectedPoints.isNotEmpty) {
                          setState(() {
                            _selectedPoints.removeLast();
                            _markers.remove(_markers.last);
                          });
                        }
                      }),
                      16.height,

                      // Assigned Start Time and Date
                      const Text(
                        'Waktu Mulai Patroli :',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: neutral900,
                        ),
                      ),
                      8.height,
                      GestureDetector(
                        onTap: () async {
                          // Pilih tanggal terlebih dahulu
                          final selectedDate = await showDatePicker(
                            context: context,
                            initialDate: _assignedStartTime,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );

                          if (selectedDate != null) {
                            // Setelah tanggal dipilih, tampilkan pemilih waktu
                            final selectedTime = await showTimePicker(
                              context: context,
                              initialTime:
                                  TimeOfDay.fromDateTime(_assignedStartTime),
                            );

                            if (selectedTime != null) {
                              setState(() {
                                // Gabungkan tanggal dan waktu yang dipilih
                                _assignedStartTime = DateTime(
                                  selectedDate.year,
                                  selectedDate.month,
                                  selectedDate.day,
                                  selectedTime.hour,
                                  selectedTime.minute,
                                );

                                // Jika waktu mulai lebih besar dari waktu akhir,
                                // update waktu akhir secara otomatis (tambah 1 jam)
                                if (_assignedStartTime
                                    .isAfter(_assignedEndTime)) {
                                  _assignedEndTime = _assignedStartTime
                                      .add(const Duration(hours: 1));
                                }
                              });
                            }
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            border: Border.all(color: kbpBlue900),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Format tanggal dan waktu untuk tampilan yang lebih user-friendly
                              Text(
                                "${formatDateFromString(_assignedStartTime.toString())} - ${DateFormat('HH:mm').format(_assignedStartTime)}",
                                style: const TextStyle(fontSize: 16),
                              ),
                              const Icon(Icons.calendar_today,
                                  color: kbpBlue900),
                            ],
                          ),
                        ),
                      ),
                      24.height,

// Assigned End Time and Date
                      const Text(
                        'Waktu Selesai Patroli :',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: neutral900,
                        ),
                      ),
                      8.height,
                      GestureDetector(
                        onTap: () async {
                          // Pilih tanggal terlebih dahulu
                          final selectedDate = await showDatePicker(
                            context: context,
                            initialDate: _assignedEndTime,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );

                          if (selectedDate != null) {
                            // Setelah tanggal dipilih, tampilkan pemilih waktu
                            final selectedTime = await showTimePicker(
                              context: context,
                              initialTime:
                                  TimeOfDay.fromDateTime(_assignedEndTime),
                            );

                            if (selectedTime != null) {
                              setState(() {
                                // Gabungkan tanggal dan waktu yang dipilih
                                _assignedEndTime = DateTime(
                                  selectedDate.year,
                                  selectedDate.month,
                                  selectedDate.day,
                                  selectedTime.hour,
                                  selectedTime.minute,
                                );
                              });
                            }
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            border: Border.all(color: kbpBlue900),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Format tanggal dan waktu untuk tampilan yang lebih user-friendly
                              Text(
                                "${formatDateFromString(_assignedEndTime.toString())} - ${DateFormat('HH:mm').format(_assignedEndTime)}",
                                style: const TextStyle(fontSize: 16),
                              ),
                              const Icon(Icons.calendar_today,
                                  color: kbpBlue900),
                            ],
                          ),
                        ),
                      ),
                      32.height,

                      // Create Task Button
                      SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _submitForm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kbpBlue900,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Create Task',
                            style: TextStyle(
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

  void _submitForm() async {
    bool isValid = true;

    if (_selectedOfficerId == null) {
      setState(() {
        _isOfficerInvalid = true;
      });
      isValid = false;
    }

    if (_vehicleId.isEmpty) {
      setState(() {
        _isVehicleInvalid = true;
      });
      isValid = false;
    }

    if (_assignedEndTime.isBefore(_assignedStartTime) ||
        _assignedEndTime.isAtSameMomentAs(_assignedStartTime)) {
      showCustomSnackbar(
        context: context,
        title: 'Data tidak valid',
        subtitle: 'Waktu selesai harus lebih besar dari waktu mulai',
        type: SnackbarType.danger,
        entryDirection: SnackbarEntryDirection.fromTop,
      );
      return;
    }

    if (!isValid) {
      showCustomSnackbar(
        context: context,
        title: 'Data belum lengkap',
        subtitle: 'Pastikan semua data sudah diisi',
        type: SnackbarType.danger,
        entryDirection: SnackbarEntryDirection.fromTop,
      );
      return;
    }

    if (_selectedPoints.isEmpty) {
      showCustomSnackbar(
        context: context,
        title: 'Data belum lengkap',
        subtitle: 'Silakan pilih titik patroli',
        type: SnackbarType.danger,
        entryDirection: SnackbarEntryDirection.fromTop,
      );
      return;
    }

    // 1. Menampilkan dialog konfirmasi
    final result = await _showConfirmationDialog();
    if (result != true) {
      return; // User membatalkan operasi
    }

    // 2. Menyimpan variabel yang akan digunakan
    final String officerId = _selectedOfficerId!;
    final String vehicleId = _vehicleId;
    final DateTime startTime = _assignedStartTime;
    final DateTime endTime = _assignedEndTime;
    final List<List<double>> assignedRoute = _selectedPoints
        .map((point) => [point.latitude, point.longitude])
        .toList();

    // 3. Mengirim event CreateTask ke AdminBloc
    context.read<AdminBloc>().add(
          CreateTask(
            vehicleId: vehicleId,
            assignedRoute: assignedRoute,
            assignedOfficerId: officerId,
            assignedStartTime: startTime,
            assignedEndTime: endTime,
          ),
        );

    // 4. Reset form fields
    setState(() {
      _selectedPoints.clear();
      _markers.clear();
      _vehicleId = '';
      _selectedOfficerId = null;
      _isOfficerInvalid = true;
      _isVehicleInvalid = true;
    });

    // 5. Menampilkan loading dialog di tengah layar
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

    print('ini debug sebelum send notification');

    try {
      // 6. Mengirim notifikasi ke petugas
      await sendPushNotificationToOfficer(
        officerId: officerId,
        title: 'Tugas Patroli Baru',
        body:
            'Anda telah ditugaskan untuk patroli pada ${DateFormat('dd/MM/yyyy - HH:mm').format(startTime)}',
        patrolTime: DateFormat('dd/MM/yyyy - HH:mm').format(startTime),
      );

      print('ini debug setelah send notification');

      // 7. Menutup dialog loading
      Navigator.of(context).pop();

      // 8. Menampilkan pesan sukses
      showCustomSnackbar(
        context: context,
        title: 'Berhasil',
        subtitle: 'Tugas berhasil dibuat dan notifikasi terkirim',
        type: SnackbarType.success,
        entryDirection: SnackbarEntryDirection.fromTop,
      );

      // 9. Kembali ke halaman sebelumnya
      Navigator.pop(context);
    } catch (e) {
      // 10. Jika gagal, tutup dialog loading dan tampilkan pesan error
      Navigator.of(context).pop();

      showCustomSnackbar(
        context: context,
        title: 'Peringatan',
        subtitle: 'Tugas berhasil dibuat tetapi gagal mengirim notifikasi',
        type: SnackbarType.warning,
        entryDirection: SnackbarEntryDirection.fromTop,
      );

      print('Error sending notification: $e');
      Navigator.pop(context);
    }
  }

// Menambahkan dialog konfirmasi
  Future<bool?> _showConfirmationDialog() async {
    // Cari nama officer berdasarkan ID
    String officerName = 'Unknown Officer';
    final state = context.read<AdminBloc>().state;
    if (state is OfficersAndVehiclesLoaded) {
      final officer = state.officers.firstWhere(
        (o) => o.id == _selectedOfficerId,
        orElse: () =>
            User(id: '', email: '', name: 'Tidak ditemukan', role: ''),
      );
      officerName = officer.name;
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Konfirmasi Tugas Patroli',
            style: boldTextStyle(
              size: h4,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Detail Tugas:', style: semiBoldTextStyle()),
                _infoRow('Petugas', officerName),
                _infoRow('Kendaraan', _vehicleId),
                _infoRow(
                    'Jumlah Titik Patroli', _selectedPoints.length.toString()),
                _infoRow('Mulai Patroli',
                    "${formatDateFromString(_assignedStartTime.toString())} Pukul ${formatTimeFromString(_assignedStartTime.toString())}"),
                _infoRow('Selesai Patroli',
                    "${formatDateFromString(_assignedEndTime.toString())} Pukul ${formatTimeFromString(_assignedEndTime.toString())}"),
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
}
