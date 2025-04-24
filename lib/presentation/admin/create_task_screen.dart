import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livetrackingapp/domain/entities/user.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';

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
  String _vehicleId = '';
  String? _selectedOfficerId;
  List<User> _officers = [];
  List<String> _vehicles = [];

  @override
  void initState() {
    super.initState();
    _loadOfficers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create New Task')),
      body: Column(
        children: [
          _buildMapSection(),
          _buildFormSection(),
        ],
      ),
    );
  }

  Future<void> _loadOfficers() async {
    try {
      final officers =
          await context.read<AdminBloc>().repository.getAllOfficers();
      final vehicles =
          await context.read<AdminBloc>().repository.getAllVehicles();
      setState(() {
        _officers = officers;
        _vehicles = vehicles;
      });
    } catch (e) {
      print('Error loading officers: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load officers: $e')),
      );
    }
  }

  // Widget _buildDropdown({
  //   required String label,
  //   required String? value,
  //   required List<DropdownMenuItem<String>> items,
  //   required Function(String?) onChanged,
  //   String? Function(String?)? validator,
  // }) {
  //   return DropdownButtonFormField<String>(
  //     decoration: InputDecoration(
  //       labelText: label,
  //       border: const OutlineInputBorder(),
  //     ),
  //     value: value,
  //     items: items,
  //     validator: validator,
  //     onChanged: onChanged,
  //   );
  // }

  Widget _buildOfficerDropdown() {
    return _buildDropdown(
      label: 'Select Officer',
      value: _selectedOfficerId,
      items: _officers.map((officer) {
        return DropdownMenuItem(
          value: officer.id,
          child: Text('${officer.name} (${officer.email})'),
        );
      }).toList(),
      validator: (value) => value == null ? 'Please select an officer' : null,
      onChanged: (value) {
        setState(() {
          _selectedOfficerId = value;
        });
      },
    );
  }

  Widget _buildVehicleDropdown() {
    return _buildDropdown(
      label: 'Select Vehicle',
      value: _vehicleId.isEmpty ? null : _vehicleId,
      items: _vehicles.map((vehicle) {
        return DropdownMenuItem(
          value: vehicle,
          child: Text(vehicle),
        );
      }).toList(),
      validator: (value) => value == null ? 'Please select a vehicle' : null,
      onChanged: (value) {
        setState(() {
          _vehicleId = value ?? '';
        });
      },
    );
  }

  Widget _buildMapSection() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.5,
      child: GoogleMap(
        onMapCreated: (controller) => _mapController = controller,
        initialCameraPosition: const CameraPosition(
          target: LatLng(-6.927727934898599, 107.76911107969532),
          zoom: 15,
        ),
        markers: _markers,
        onTap: _handleMapTap,
      ),
    );
  }

  Widget _buildFormSection() {
    return Expanded(
      child: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Petugas Section
              const Text(
                'Petugas :',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.teal),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _buildOfficerDropdown(),
              ),
              const SizedBox(height: 24),

              // Kendaraan Patroli Section
              const Text(
                'Kendaraan Patroli :',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.teal),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _buildVehicleDropdown(),
              ),
              const SizedBox(height: 24),

              // Points Counter
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'Jumlah Titik Patroli : ',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    '${_selectedPoints.length}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
              const Spacer(),

              // Create Task Button
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Create Task',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

// Update the dropdown builder method
  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required Function(String?) onChanged,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      value: value,
      items: items,
      validator: validator,
      onChanged: onChanged,
      icon: const Icon(Icons.arrow_drop_down, color: Colors.teal),
      dropdownColor: Colors.white,
      style: const TextStyle(
        fontSize: 16,
        color: Colors.black87,
      ),
    );
  }

  // Update _submitForm to include officer ID
  void _submitForm() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one point')),
      );
      return;
    }

    _formKey.currentState!.save();

    final assignedRoute = _selectedPoints
        .map((point) => [point.latitude, point.longitude])
        .toList();

    context.read<AdminBloc>().add(
          CreateTask(
            vehicleId: _vehicleId,
            assignedRoute: assignedRoute,
            assignedOfficerId: _selectedOfficerId!, // Add officer ID
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
