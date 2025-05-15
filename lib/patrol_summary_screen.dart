import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/main_nav_screen.dart';
import '../../domain/entities/patrol_task.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';

class PatrolSummaryScreen extends StatefulWidget {
  final PatrolTask task;
  final List<List<double>> routePath;
  final DateTime startTime;
  final DateTime endTime;
  final double distance;

  const PatrolSummaryScreen({
    super.key,
    required this.task,
    required this.routePath,
    required this.startTime,
    required this.endTime,
    required this.distance,
  });

  @override
  State<PatrolSummaryScreen> createState() => _PatrolSummaryScreenState();
}

class _PatrolSummaryScreenState extends State<PatrolSummaryScreen> {
  GoogleMapController? mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  static const _defaultCenter = LatLng(-6.927727934898599, 107.76911107969532);

  @override
  void initState() {
    super.initState();
    _initializeMap();
    _loadOfficerName();
    print('route path isinya apa? ${widget.routePath}');
  }

  Future<String?> _getUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return null; // Pengguna belum login
      }

      // Referensi ke path pengguna di Realtime Database
      final userRef = FirebaseDatabase.instance.ref('users/${user.uid}');
      final snapshot = await userRef.get();

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        return data['role'] as String?; // Ambil nilai role
      } else {
        print('User data not found in database');
        return null;
      }
    } catch (e) {
      print('Error fetching user role: $e');
      return null;
    }
  }

  Future<void> _loadOfficerName() async {
    final database = FirebaseDatabase.instance.ref();
    await widget.task.fetchOfficerName(database);
    if (mounted) {
      setState(() {}); // Refresh UI with officer name
    }
  }

  void _initializeMap() {
    setState(() {
    });
    _prepareRouteAndMarkers();
  }

  void _onMapCreated(GoogleMapController controller) async {
    print('Map created, initializing camera...');
    setState(() {
      mapController = controller;
    });

    // Wait for markers and polylines to be ready
    await Future.delayed(const Duration(milliseconds: 300));

    // if (widget.routePath.isNotEmpty) {
    //   print('Setting camera to first route point: ${widget.routePath.first}');
    //   await controller.animateCamera(
    //     CameraUpdate.newLatLngZoom(
    //       LatLng(widget.routePath.first[0], widget.routePath.first[1]),
    //       15.0,
    //     ),
    //   );
    // }

    // Then fit to full route
    // _fitMapToRoute();
  }

  void _prepareRouteAndMarkers() {
    try {
      print('=== Route Data Debug ===');
      print('Assigned Route: ${widget.task.assignedRoute}');
      print('Route Path: ${widget.routePath}');

      // Add assigned route markers and polyline
      if (widget.task.assignedRoute != null) {
        _addAssignedRouteMarkers();
        _addAssignedRoutePolyline();
      }

      // Add actual route path and markers
      if (widget.routePath.isNotEmpty) {
        print('Processing route path with ${widget.routePath.length} points');
        _addActualRoutePath();
        _addStartEndMarkers();
      } else {
        print('Route path is empty!');
      }

      setState(() {}); // Update UI
    } catch (e, stackTrace) {
      print('Error preparing route and markers: $e');
      print('Stack trace: $stackTrace');
    }
  }

  void _addAssignedRouteMarkers() {
    for (int i = 0; i < widget.task.assignedRoute!.length; i++) {
      final coord = widget.task.assignedRoute![i];
      _markers.add(
        Marker(
          markerId: MarkerId('checkpoint-$i'),
          position: LatLng(coord[0], coord[1]),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: 'Checkpoint ${i + 1}'),
        ),
      );
    }
  }

  void _addAssignedRoutePolyline() {
    final assignedPoints = widget.task.assignedRoute!
        .map((coord) => LatLng(coord[0], coord[1]))
        .toList();

    _polylines.add(
      Polyline(
        polylineId: const PolylineId('assigned_route'),
        points: assignedPoints,
        color: successG200,
        width: 3,
        patterns: [
          PatternItem.dash(20),
          PatternItem.gap(10),
        ],
      ),
    );
  }

  void _addActualRoutePath() {
    try {
      print('=== Adding Actual Route Path ===');
      final actualPoints = widget.routePath.map((coord) {
        print('Processing coordinate: $coord');
        return LatLng(coord[0], coord[1]);
      }).toList();

      print('Created ${actualPoints.length} LatLng points');

      _polylines.add(
        Polyline(
          polylineId: const PolylineId('actual_route'),
          points: actualPoints,
          color: kbpBlue900,
          width: 5,
          visible: true, // Explicitly set visible
        ),
      );

      print('Added polyline to set. Total polylines: ${_polylines.length}');
    } catch (e) {
      print('Error in _addActualRoutePath: $e');
    }
  }

  void _addStartEndMarkers() {
    try {
      if (widget.routePath.isEmpty) {
        print('Route path empty, skipping start/end markers');
        return;
      }

      print('=== Adding Start/End Markers ===');
      print('First point: ${widget.routePath.first}');
      print('Last point: ${widget.routePath.last}');

      // Start marker
      _markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position:
              LatLng(widget.routePath.first[0], widget.routePath.first[1]),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          infoWindow: const InfoWindow(title: 'Start Point'),
          visible: true, // Explicitly set visible
        ),
      );

      // End marker
      _markers.add(
        Marker(
          markerId: const MarkerId('end'),
          position: LatLng(widget.routePath.last[0], widget.routePath.last[1]),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'End Point'),
          visible: true, // Explicitly set visible
        ),
      );

      print('Added start and end markers. Total markers: ${_markers.length}');
    } catch (e) {
      print('Error in _addStartEndMarkers: $e');
    }
  }

  void _fitMapToRoute() {
    try {
      if (mapController == null) {
        print('Map controller not ready');
        return;
      }

      final bounds = _calculateBounds();
      print('Fitting map to bounds: $bounds');

      mapController!
          .animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 100.0),
      )
          .then((_) {
        print('Camera updated to show full route');
      }).catchError((e) {
        print('Error updating camera: $e');
      });
    } catch (e) {
      print('Error in _fitMapToRoute: $e');
    }
  }

  LatLngBounds _calculateBounds() {
    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;
    bool hasPoints = false;

    // Include assigned route points
    if (widget.task.assignedRoute != null &&
        widget.task.assignedRoute!.isNotEmpty) {
      hasPoints = true;
      for (var coord in widget.task.assignedRoute!) {
        minLat = math.min(minLat, coord[0]);
        maxLat = math.max(maxLat, coord[0]);
        minLng = math.min(minLng, coord[1]);
        maxLng = math.max(maxLng, coord[1]);
      }
    }

    // Include actual route points
    if (widget.routePath.isNotEmpty) {
      hasPoints = true;
      for (var coord in widget.routePath) {
        minLat = math.min(minLat, coord[0]);
        maxLat = math.max(maxLat, coord[0]);
        minLng = math.min(minLng, coord[1]);
        maxLng = math.max(maxLng, coord[1]);
      }
    }

    if (!hasPoints) {
      print('No points found, using default bounds');
      return LatLngBounds(
        southwest: LatLng(
            _defaultCenter.latitude - 0.02, _defaultCenter.longitude - 0.02),
        northeast: LatLng(
            _defaultCenter.latitude + 0.02, _defaultCenter.longitude + 0.02),
      );
    }

    // Add padding to bounds
    final latPadding = (maxLat - minLat) * 0.1;
    final lngPadding = (maxLng - minLng) * 0.1;

    return LatLngBounds(
      southwest: LatLng(minLat - latPadding, minLng - lngPadding),
      northeast: LatLng(maxLat + latPadding, maxLng + lngPadding),
    );
  }

  String _formatDuration(DateTime start, DateTime end) {
    final duration = end.difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Patrol Summary'),
        automaticallyImplyLeading: false,
      ),
      body: _buildMap(),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Patrol Task Summary',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            8.height,
            Text(
              'Officer: ${widget.task.officerName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            8.height,
            Text('Vehicle: ${widget.task.vehicleId}'),
            8.height,
            Text(
              'Duration: ${_formatDuration(widget.startTime, widget.endTime)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: widget.routePath.isNotEmpty
                  ? LatLng(widget.routePath[0][0], widget.routePath[0][1])
                  : _defaultCenter,
              zoom: 15.0,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            mapType: MapType.normal,
          ),
          _buildSummaryCard(),
          Positioned(
            bottom: 50,
            left: 16,
            right: 16,
            child: ElevatedButton(
                onPressed: () async {
                  final userRole = await _getUserRole();
                  Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              MainNavigationScreen(userRole: userRole ?? 'User')));
                },
                child: const Text('Continue')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    mapController?.dispose();
    super.dispose();
  }
}
