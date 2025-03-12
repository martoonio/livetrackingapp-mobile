import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:livetrackingapp/patrol_summary_screen.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mp;
import '../../domain/entities/patrol_task.dart';
import 'presentation/routing/bloc/patrol_bloc.dart';

class MapScreen extends StatefulWidget {
  final PatrolTask task;
  final VoidCallback onStart;

  const MapScreen({
    super.key,
    required this.task,
    required this.onStart,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  mp.MapboxMap? mapboxMapController;
  Position? userCurrentLocation;
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _isMapReady = false;
  late final currentState;

  @override
  void initState() {
    super.initState();
    currentState = context.read<PatrolBloc>().state;
    print('Current state: $currentState');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PatrolBloc>().add(LoadRouteData(
            userId: widget.task.userId,
          ));
    });
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    await _getUserLocation();
    if (widget.task.assignedRoute != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _drawRoute(widget.task.assignedRoute!);
      });
    }
    setState(() {
      _isMapReady = true;
    });
  }

  void _onMapCreated(mp.MapboxMap controller) async {
    try {
      setState(() {
        mapboxMapController = controller;
      });

      // Wait for map style to load
      await Future.delayed(const Duration(seconds: 1));

      // Enable location tracking
      await controller.location.updateSettings(
        mp.LocationComponentSettings(
          enabled: true,
          pulsingEnabled: true,
        ),
      );

      setState(() {
        _isMapReady = true;
      });
    } catch (e) {
      print('Error initializing map: $e');
    }
  }

  Future<void> _drawRoute(List<List<double>> coordinates) async {
    if (!_isMapReady || mapboxMapController == null) {
      print('Map not ready, skipping route draw');
      return;
    }

    try {
      // Clear existing route first
      await _clearRoute();

      await Future.delayed(const Duration(milliseconds: 200));

      // Add new source
      final lineSource = mp.GeoJsonSource(
        id: "route-source",
        data: jsonEncode({
          "type": "Feature",
          "properties": {},
          "geometry": {
            "type": "LineString",
            "coordinates":
                coordinates.map((coord) => [coord[1], coord[0]]).toList(),
          }
        }),
      );

      await mapboxMapController?.style.addSource(lineSource);
      await Future.delayed(const Duration(milliseconds: 200));

      // Add new layer
      final lineLayer = mp.LineLayer(
        id: "route-layer",
        sourceId: "route-source",
      )
        ..lineColor = Colors.blue.value
        ..lineWidth = 5.0
        ..lineCap = mp.LineCap.ROUND
        ..lineJoin = mp.LineJoin.ROUND;

      await mapboxMapController?.style.addLayer(lineLayer);

      // Fit map to show the route
      final bounds = _getRouteBounds(coordinates);
      await mapboxMapController?.cameraForCoordinateBounds(
        bounds,
        mp.MbxEdgeInsets(top: 50, left: 50, bottom: 50, right: 50),
        null,
        null,
        0.0,
        null,
      );
    } catch (e) {
      print('Error drawing route: $e');
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

  Future<void> _clearRoute() async {
    if (!_isMapReady || mapboxMapController == null) return;

    try {
      await Future.delayed(const Duration(milliseconds: 100));
      await mapboxMapController?.style.removeStyleLayer("route-layer");
      await Future.delayed(const Duration(milliseconds: 50));
      await mapboxMapController?.style.removeStyleSource("route-source");
      print('Route cleared successfully');
    } catch (e) {
      print('Error clearing route: $e');
    }
  }

  Future<Position?> _getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied');
    }

    _positionStreamSubscription = Geolocator.getPositionStream().listen(
      (Position position) {
        if (mounted) {
          setState(() {
            userCurrentLocation = position;
          });
        }
      },
    );

    return await Geolocator.getCurrentPosition();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    mapboxMapController = null; // Just set to null, don't clear route
    super.dispose();
  }

  Future<void> _clearMapResources() async {
    try {
      await _clearRoute();
      await _positionStreamSubscription?.cancel();
      mapboxMapController = null;
    } catch (e) {
      print('Error clearing map resources: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PatrolBloc, PatrolState>(
      listener: (context, state) {
        // if (state is PatrolLoaded && state.isPatrolling) {
        //   ScaffoldMessenger.of(context).showSnackBar(
        //     const SnackBar(content: Text('Patrol started successfully')),
        //   );
        // }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Task: ${widget.task.taskId}'),
        ),
        body: Stack(
          children: [
            mp.MapWidget(
              onMapCreated: _onMapCreated,
              styleUri: mp.MapboxStyles.MAPBOX_STREETS,
              cameraOptions: mp.CameraOptions(
                center: mp.Point(
                  coordinates: mp.Position(
                    107.76911107969532,
                    -6.927727934898599,
                  ),
                ),
                zoom: 15.5,
                bearing: -17.6,
              ),
            ),
            // Task details card
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Vehicle: ${widget.task.vehicleId}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('Status: ${widget.task.status}'),
                    ],
                  ),
                ),
              ),
            ),
            // Start/Stop button
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: BlocConsumer<PatrolBloc, PatrolState>(
                listener: (context, state) {
                  print('Button state changed: $state'); // Debug print
                  if (state is PatrolError) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${state.message}')),
                    );
                  }
                },
                builder: (context, state) {
                  print('Building button with state: $state'); // Debug print

                  return ElevatedButton(
                    onPressed: () async {
                      print('Button pressed with state: $state'); // Debug print
                      if (state is PatrolLoaded) {
                        // Update the button's onPressed handler for stop patrol
                        if (state.isPatrolling) {
                          final endTime = DateTime.now();

                          print(
                              'Current state task: ${state.task}'); // Debug print
                          print(
                              'Current route path: ${state.task?.routePath}'); // Debug print

                          // Get route path from current state
                          List<List<double>> convertedPath = [];
                          try {
                            if (state.task?.routePath != null &&
                                state.task!.routePath is Map) {
                              final map = state.task!.routePath as Map;

                              // Get all entries and sort by timestamp
                              final sortedEntries = map.entries.toList()
                                ..sort((a, b) => (a.value['timestamp']
                                        as String)
                                    .compareTo(b.value['timestamp'] as String));

                              print(
                                  'Sorted entries length: ${sortedEntries.length}'); // Debug print

                              // Convert coordinates
                              convertedPath = sortedEntries.map((entry) {
                                final coordinates =
                                    entry.value['coordinates'] as List;
                                return [
                                  (coordinates[1] as num)
                                      .toDouble(), // latitude
                                  (coordinates[0] as num)
                                      .toDouble(), // longitude
                                ];
                              }).toList();

                              print(
                                  'Converted coordinates: $convertedPath'); // Debug print
                            }
                          } catch (e) {
                            print(
                                'Error converting route path: $e'); // Debug print
                          }

                          // First stop patrol to update state
                          context
                              .read<PatrolBloc>()
                              .add(StopPatrol(endTime: endTime));

                          // Wait briefly for state to update
                          await Future.delayed(
                              const Duration(milliseconds: 100));

                          // Then navigate to summary with the converted path
                          if (mounted) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PatrolSummaryScreen(
                                  task: widget.task,
                                  routePath: convertedPath,
                                  startTime:
                                      state.task?.startTime ?? DateTime.now(),
                                  endTime: endTime,
                                ),
                              ),
                            );
                          }
                        } else {
                          // Ensure we're updating task status before starting patrol
                          context.read<PatrolBloc>().add(UpdateTask(
                                taskId: widget.task.taskId,
                                updates: {
                                  'status': 'ongoing',
                                  'startTime': DateTime.now().toIso8601String(),
                                },
                              ));

                          context.read<PatrolBloc>().add(
                                StartPatrol(
                                  task: widget.task,
                                  startTime: DateTime.now(),
                                ),
                              );

                          // Then start patrol
                          widget.onStart();
                        }
                      } else {
                        // If state isn't loaded yet, try loading it first
                        context.read<PatrolBloc>().add(LoadRouteData(
                              userId: widget.task.userId,
                            ));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor:
                          state is PatrolLoaded && state.isPatrolling
                              ? Colors.red
                              : Colors.blue,
                    ),
                    child: Text(
                      state is PatrolLoaded && state.isPatrolling
                          ? 'Stop Patrol'
                          : 'Start Patrol',
                      style: const TextStyle(fontSize: 16),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
