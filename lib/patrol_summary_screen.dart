import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mp;
import '../../domain/entities/patrol_task.dart';

class PatrolSummaryScreen extends StatefulWidget {
  final PatrolTask task;
  final List<List<double>> routePath;
  final DateTime startTime;
  final DateTime endTime;

  const PatrolSummaryScreen({
    Key? key,
    required this.task,
    required this.routePath,
    required this.startTime,
    required this.endTime,
  }) : super(key: key);

  @override
  State<PatrolSummaryScreen> createState() => _PatrolSummaryScreenState();
}

class _PatrolSummaryScreenState extends State<PatrolSummaryScreen> {
  mp.MapboxMap? mapboxMapController;
  bool _isMapReady = false;

  static var _defaultCenter = mp.Point(
    coordinates: mp.Position(107.76911107969532, -6.927727934898599),
  );

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  void _initializeMap() {
    setState(() {
      _isMapReady = true;
    });
  }

  void _onMapCreated(mp.MapboxMap controller) async {
    try {
      mapboxMapController = controller;
      await Future.delayed(const Duration(seconds: 1));
      await _drawRouteAndMarkers();
    } catch (e) {
      print('Error initializing map: $e');
    }
  }

  Future<void> _drawRouteAndMarkers() async {
    if (!_isMapReady || mapboxMapController == null) return;

    print(
        'Drawing route with ${widget.routePath.length} points'); // Debug print

    if (widget.routePath.isEmpty) {
      print('No route path available');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No route data available')),
      );
      return;
    }

    try {
      // Add delays between operations to prevent race conditions
      await Future.delayed(const Duration(milliseconds: 500));

      // Add route source
      final lineSource = mp.GeoJsonSource(
        id: "route-source",
        data: jsonEncode({
          "type": "Feature",
          "properties": {},
          "geometry": {
            "type": "LineString",
            "coordinates": widget.routePath
                .map((coord) => [
                      coord[1], // longitude
                      coord[0], // latitude
                    ])
                .toList(),
          }
        }),
      );

      await mapboxMapController?.style.addSource(lineSource);
      await Future.delayed(const Duration(milliseconds: 200));

      // Add route layer
      final lineLayer = mp.LineLayer(
        id: "route-layer",
        sourceId: "route-source",
      )
        ..lineColor = Colors.blue.value
        ..lineWidth = 5.0;

      await mapboxMapController?.style.addLayer(lineLayer);
      await Future.delayed(const Duration(milliseconds: 200));

      // Only add markers if we have route points
      if (widget.routePath.length >= 2) {
        await _addMarkers(widget.routePath.first, widget.routePath.last);
      }

      // Fit map to show the entire route
      final bounds = _getRouteBounds(widget.routePath);
      await mapboxMapController?.cameraForCoordinateBounds(
        bounds,
        mp.MbxEdgeInsets(top: 50, left: 50, bottom: 50, right: 50),
        null,
        null,
        0.0,
        null,
      );
    } catch (e, stackTrace) {
      print('Error drawing route and markers: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<void> _addMarkers(List<double> start, List<double> end) async {
    try {
      // Add start marker
      final startSource = mp.GeoJsonSource(
        id: "start-source",
        data: jsonEncode({
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [start[1], start[0]],
          }
        }),
      );

      await mapboxMapController?.style.addSource(startSource);
      await mapboxMapController?.style.addLayer(
        mp.SymbolLayer(
          id: "start-layer",
          sourceId: "start-source",
        )
          ..iconImage = "custom-marker" // Use a default marker image
          ..iconSize = 1.0,
      );

      // Add end marker
      final endSource = mp.GeoJsonSource(
        id: "end-source",
        data: jsonEncode({
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [end[1], end[0]],
          }
        }),
      );

      await mapboxMapController?.style.addSource(endSource);
      await mapboxMapController?.style.addLayer(
        mp.SymbolLayer(
          id: "end-layer",
          sourceId: "end-source",
        )
          ..iconImage = "custom-marker"
          ..iconSize = 1.0,
      );
    } catch (e) {
      print('Error adding markers: $e');
    }
  }

  mp.CoordinateBounds _getRouteBounds(List<List<double>> coordinates) {
    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    for (var coord in coordinates) {
      minLat = math.min(minLat, coord[0]);
      maxLat = math.max(maxLat, coord[0]);
      minLng = math.min(minLng, coord[1]);
      maxLng = math.max(maxLng, coord[1]);
    }

    return mp.CoordinateBounds(
      southwest: mp.Point(coordinates: mp.Position(minLng, minLat)),
      northeast: mp.Point(coordinates: mp.Position(maxLng, maxLat)),
      infiniteBounds: false,
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
      ),
      body: Column(
        children: [
          // Summary card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Task ID: ${widget.task.taskId}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Vehicle: ${widget.task.vehicleId}'),
                  const SizedBox(height: 8),
                  Text(
                    'Duration: ${_formatDuration(widget.startTime, widget.endTime)}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
          ),
          // Map
          Expanded(
            child: mp.MapWidget(
              onMapCreated: _onMapCreated,
              styleUri: mp.MapboxStyles.MAPBOX_STREETS,
              cameraOptions: mp.CameraOptions(
                center: widget.routePath.isNotEmpty
                    ? mp.Point(
                        coordinates: mp.Position(
                          widget.routePath[0][1],
                          widget.routePath[0][0],
                        ),
                      )
                    : _defaultCenter,
                zoom: 15.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
