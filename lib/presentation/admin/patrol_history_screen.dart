import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';

class PatrolHistoryScreen extends StatefulWidget {
  final PatrolTask task;

  const PatrolHistoryScreen({
    Key? key,
    required this.task,
  }) : super(key: key);

  @override
  State<PatrolHistoryScreen> createState() => _PatrolHistoryScreenState();
}

class _PatrolHistoryScreenState extends State<PatrolHistoryScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _prepareRouteAndMarkers();
  }

  void _prepareRouteAndMarkers() {
    try {
      // Add assigned route markers and polyline
      if (widget.task.assignedRoute != null) {
        _addAssignedRouteMarkers();
        _addAssignedRoutePolyline();
      }

      // Add actual route path if completed
      if (widget.task.routePath != null) {
        _addActualRoutePath();
      }

      setState(() {});
    } catch (e) {
      print('Error preparing route and markers: $e');
    }
  }

  void _addAssignedRouteMarkers() {
    for (int i = 0; i < widget.task.assignedRoute!.length; i++) {
      final coord = widget.task.assignedRoute![i];
      _markers.add(
        Marker(
          markerId: MarkerId('checkpoint-$i'),
          position: LatLng(coord[0], coord[1]),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: 'Checkpoint ${i + 1}'),
        ),
      );
    }
  }

  void _addAssignedRoutePolyline() {
    final points = widget.task.assignedRoute!
        .map((coord) => LatLng(coord[0], coord[1]))
        .toList();

    _polylines.add(
      Polyline(
        polylineId: const PolylineId('assigned_route'),
        points: points,
        color: Colors.green.withOpacity(0.7),
        width: 3,
        patterns: [
          PatternItem.dash(20),
          PatternItem.gap(10),
        ],
      ),
    );
  }

  void _addActualRoutePath() {
    if (widget.task.routePath == null) return;

    final routePathMap = Map<String, dynamic>.from(widget.task.routePath!);
    final sortedEntries = routePathMap.entries.toList()
      ..sort((a, b) => (a.value['timestamp'] as String)
          .compareTo(b.value['timestamp'] as String));

    final points = sortedEntries.map((entry) {
      final coordinates = entry.value['coordinates'] as List;
      return LatLng(
        coordinates[0] as double,
        coordinates[1] as double,
      );
    }).toList();

    _polylines.add(
      Polyline(
        polylineId: const PolylineId('actual_route'),
        points: points,
        color: Colors.blue,
        width: 5,
      ),
    );
  }

  void _fitMapToRoute() {
    if (_mapController == null) return;

    double minLat = 90, maxLat = -90;
    double minLng = 180, maxLng = -180;

    // Include assigned route points
    if (widget.task.assignedRoute != null) {
      for (var coord in widget.task.assignedRoute!) {
        minLat = (minLat > coord[0]) ? coord[0] : minLat;
        maxLat = (maxLat < coord[0]) ? coord[0] : maxLat;
        minLng = (minLng > coord[1]) ? coord[1] : minLng;
        maxLng = (maxLng < coord[1]) ? coord[1] : maxLng;
      }
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.01, minLng - 0.01),
          northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
        ),
        50,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Patrol History - ${widget.task.taskId}'),
      ),
      body: Column(
        children: [
          _buildTaskDetails(),
          Expanded(
            child: GoogleMap(
              onMapCreated: (controller) {
                _mapController = controller;
                _fitMapToRoute();
              },
              initialCameraPosition: const CameraPosition(
                target: LatLng(-6.927727934898599, 107.76911107969532),
                zoom: 15,
              ),
              markers: _markers,
              polylines: _polylines,
              mapType: MapType.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskDetails() {
    final duration = widget.task.endTime != null && widget.task.startTime != null
        ? widget.task.endTime!.difference(widget.task.startTime!)
        : null;

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vehicle ID: ${widget.task.vehicleId}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Status: ${widget.task.status}'),
            if (widget.task.startTime != null) ...[
              const SizedBox(height: 8),
              Text(
                'Start: ${widget.task.startTime!.toString()}',
              ),
            ],
            if (duration != null) ...[
              const SizedBox(height: 8),
              Text(
                'Duration: ${duration.inHours}h ${duration.inMinutes % 60}m',
              ),
            ],
          ],
        ),
      ),
    );
  }
}