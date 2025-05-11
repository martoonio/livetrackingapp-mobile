import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:livetrackingapp/presentation/component/undo_button.dart';
import '../component/dropdown_component.dart';
import '../component/map_section.dart';

class CreateTaskScreen extends StatefulWidget {
  const CreateTaskScreen({Key? key}) : super(key: key);

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

  @override
  void initState() {
    super.initState();
    context.read<AdminBloc>().add(LoadOfficersAndVehicles());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<AdminBloc, AdminState>(
        builder: (context, state) {
          if (state is OfficersAndVehiclesLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is OfficersAndVehiclesError) {
            return Center(child: Text(state.message));
          } else if (state is OfficersAndVehiclesLoaded) {
            return Column(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: Stack(
                    children: [
                      MapSection(
                        mapController: _mapController,
                        markers: _markers,
                        onMapTap: _handleMapTap,
                      ),
                      Positioned(
                        top: 16,
                        left: 16,
                        child: leadingButton(context, "Back", () {
                          Navigator.pop(context);
                        }),
                      ),
                    ],
                  ),
                ),
                _buildFormSection(state.officers, state.vehicles),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildFormSection(List<User> officers, List<String> vehicles) {
    return Expanded(
      child: Form(
        key: _formKey,
        child: Container(
          decoration: BoxDecoration(
            color: neutralWhite,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
            border: Border.all(
              color: kbpBlue900,
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
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
                      _isOfficerInvalid = false; // Reset invalid state
                    });
                  },
                  borderColor: _isOfficerInvalid
                      ? Colors.red
                      : kbpBlue900, // Ubah warna border
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
                      _isVehicleInvalid = false; // Reset invalid state
                    });
                  },
                  borderColor: _isVehicleInvalid
                      ? Colors.red
                      : kbpBlue900, // Ubah warna border
                ),
                24.height,

                // Patrol Points Counter
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Jumlah Titik Patroli :',
                      style: const TextStyle(
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

                UndoButton(onPressed: () {
                  if (_selectedPoints.isNotEmpty) {
                    setState(() {
                      _selectedPoints.removeLast();
                      _markers.remove(_markers.last);
                    });
                  }
                }),
                // const Spacer(),

                // Create Task Button
                SizedBox(
                  height: 56,
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
    );
  }

  void _submitForm() {
    bool isValid = true;

    if (_selectedOfficerId == null) {
      setState(() {
        _isOfficerInvalid =
            true; // Tandai dropdown "Petugas" sebagai tidak valid
      });
      isValid = false;
    }

    if (_vehicleId.isEmpty) {
      setState(() {
        _isVehicleInvalid =
            true; // Tandai dropdown "Kendaraan" sebagai tidak valid
      });
      isValid = false;
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

    final assignedRoute = _selectedPoints
        .map((point) => [point.latitude, point.longitude])
        .toList();

    context.read<AdminBloc>().add(
          CreateTask(
            vehicleId: _vehicleId,
            assignedRoute: assignedRoute,
            assignedOfficerId: _selectedOfficerId!,
          ),
        );

    Navigator.pop(context);
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
