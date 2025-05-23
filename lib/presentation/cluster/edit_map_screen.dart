import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/presentation/admin/admin_bloc.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';

class EditMapScreen extends StatefulWidget {
  final String clusterId;
  final List<LatLng> points;
  final String clusterName;

  const EditMapScreen({
    Key? key,
    required this.clusterId,
    required this.points,
    required this.clusterName,
  }) : super(key: key);

  @override
  State<EditMapScreen> createState() => _EditMapScreenState();
}

class _EditMapScreenState extends State<EditMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  List<LatLng> _selectedPoints = [];
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _selectedPoints = List<LatLng>.from(widget.points);
    _updateMarkers();
  }

  void _updateMarkers() {
    _markers.clear();
    for (int i = 0; i < _selectedPoints.length; i++) {
      _markers.add(
        Marker(
          markerId: MarkerId('point_$i'),
          position: _selectedPoints[i],
          infoWindow: InfoWindow(title: 'Titik ${i + 1}'),
        ),
      );
    }
  }

  void _handleMapTap(LatLng position) {
    setState(() {
      _selectedPoints.add(position);
      _updateMarkers();
      _hasChanges = true;
    });
  }

  void _zoomToPoints() {
    if (_selectedPoints.isEmpty || _mapController == null) return;

    try {
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
    } catch (e) {
      print('Error zooming to points: $e');
    }
  }

  void _saveChanges() {
    final coordinates = _selectedPoints
        .map((point) => [point.latitude, point.longitude])
        .toList();

    context.read<AdminBloc>().add(
          UpdateClusterCoordinates(
            clusterId: widget.clusterId,
            coordinates: coordinates,
          ),
        );

    Navigator.pop(context, _selectedPoints);
  }

  void _showDiscardChangesDialog() {
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          'Batalkan Perubahan',
          style: boldTextStyle(size: 18, color: kbpBlue900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: warningY500,
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(
              'Anda memiliki perubahan yang belum disimpan. Apakah Anda yakin ingin membatalkan perubahan?',
              style: regularTextStyle(color: neutral700),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        actionsPadding: const EdgeInsets.all(16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: kbpBlue900,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Lanjutkan Mengedit',
              style: mediumTextStyle(color: kbpBlue900),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: dangerR500,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Buang Perubahan',
              style: mediumTextStyle(color: Colors.white),
            ),
          ),
        ],
        actionsAlignment: MainAxisAlignment.end,
        elevation: 4,
        backgroundColor: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_hasChanges) {
          _showDiscardChangesDialog();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Edit Titik Patroli - ${widget.clusterName}'),
          backgroundColor: kbpBlue900,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: _zoomToPoints,
            ),
          ],
        ),
        body: Stack(
          children: [
            GoogleMap(
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
              onTap: _handleMapTap,
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
                if (_selectedPoints.isNotEmpty) {
                  _zoomToPoints();
                }
              },
            ),

            // Bottom action panel
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Titik Patroli (${_selectedPoints.length})',
                      style: boldTextStyle(size: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Klik pada peta untuk menambah titik. Titik akan muncul secara berurutan berdasarkan waktu penambahan.',
                      style: regularTextStyle(color: neutral600),
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
                                        _hasChanges = true;
                                      }
                                    });
                                  },
                            icon: const Icon(Icons.undo, color: Colors.white),
                            label: const Text('Undo'),
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
                            onPressed:
                                _selectedPoints.isEmpty ? null : _saveChanges,
                            icon: const Icon(Icons.save, color: Colors.white),
                            label: const Text('Simpan'),
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
          ],
        ),
      ),
    );
  }
}
