import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

class MapSection extends StatefulWidget {
  final GoogleMapController? mapController;
  final Set<Marker> markers;
  final Function(LatLng) onMapTap;

  const MapSection({
    Key? key,
    required this.mapController,
    required this.markers,
    required this.onMapTap,
  }) : super(key: key);

  @override
  State<MapSection> createState() => _MapSectionState();
}

class _MapSectionState extends State<MapSection> {
  LatLng? _currentPosition;

  @override
  void initState() {
    super.initState();
    _getUserCurrentLocation();
  }

  Future<void> _getUserCurrentLocation() async {
    try {
      print('Requesting location permission...');
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }

      print('Fetching current position...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });

      print('Current position updated: $_currentPosition');

      if (widget.mapController != null) {
        widget.mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _currentPosition!,
              zoom: 15,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error getting user location: $e');
      setState(() {
        _currentPosition = const LatLng(
          -6.927727934898599,
          107.76911107969532,
        );
      });

      print('Fallback position used: $_currentPosition');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('Building MapSection with _currentPosition: $_currentPosition');

    if (_currentPosition == null) {
      return const Center(
          child: CircularProgressIndicator()); // Tampilkan loading
    }

    return GoogleMap(
      onMapCreated: (controller) {
        if (widget.mapController != null) {
          widget.mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: _currentPosition!,
                zoom: 15,
              ),
            ),
          );
        }
      },
      initialCameraPosition: CameraPosition(
        target: _currentPosition!,
        zoom: 15,
      ),
      markers: widget.markers,
      onTap: widget.onMapTap,
    );
  }
}
