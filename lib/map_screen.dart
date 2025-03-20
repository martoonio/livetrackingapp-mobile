import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/patrol_summary_screen.dart';
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
  GoogleMapController? mapController;
  Position? userCurrentLocation;
  StreamSubscription<Position>? _positionStreamSubscription;
  final Set<Marker> _markers = {};
  bool _isMapReady = false;
  late final currentState;

  Timer? _patrolTimer;
  Duration _elapsedTime = Duration.zero;
  double _totalDistance = 0;
  Position? _lastPosition;

  // Add method to start timer
  void _startPatrolTimer() {
    _patrolTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedTime += const Duration(seconds: 1);
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  void _updateDistance(Position newPosition) {
    if (_lastPosition != null) {
      final distanceInMeters = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        newPosition.latitude,
        newPosition.longitude,
      );
      _totalDistance += distanceInMeters;
    }
    _lastPosition = newPosition;
  }

  @override
  void initState() {
    super.initState();
    currentState = context.read<PatrolBloc>().state;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PatrolBloc>().add(LoadRouteData(userId: widget.task.userId));
    });
    _initializeMap();
  }

  Future<void> _addRouteMarkers(List<List<double>> coordinates) async {
    if (!_isMapReady || mapController == null) return;

    try {
      setState(() {
        _markers.clear();
        for (int i = 0; i < coordinates.length; i++) {
          final coord = coordinates[i];
          _markers.add(
            Marker(
              markerId: MarkerId('route-$i'),
              position: LatLng(coord[0], coord[1]),
              infoWindow: InfoWindow(title: 'Point ${i + 1}'),
            ),
          );
        }
      });

      // Fit map to show all markers
      if (coordinates.isNotEmpty) {
        final bounds = _getRouteBounds(coordinates);
        mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 50),
        );
      }
    } catch (e) {
      print('Error adding route markers: $e');
    }
  }

  LatLngBounds _getRouteBounds(List<List<double>> coordinates) {
    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    for (var coord in coordinates) {
      minLat = minLat < coord[0] ? minLat : coord[0];
      maxLat = maxLat > coord[0] ? maxLat : coord[0];
      minLng = minLng < coord[1] ? minLng : coord[1];
      maxLng = maxLng > coord[1] ? maxLng : coord[1];
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Future<void> _initializeMap() async {
    await _getUserLocation();
    if (widget.task.assignedRoute != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addRouteMarkers(widget.task.assignedRoute!);
      });
    }
    setState(() {
      _isMapReady = true;
    });
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

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      (Position position) {
        if (mounted) {
          setState(() {
            userCurrentLocation = position;
            if (mapController != null) {
              _updateUserMarker(position);
            }
          });

          final state = context.read<PatrolBloc>().state;
          if (state is PatrolLoaded && state.isPatrolling) {
            _updateDistance(position);
          }
        }
      },
    );

    return await Geolocator.getCurrentPosition();
  }

  void _updateUserMarker(Position position) {
    setState(() {
      _markers.removeWhere(
          (marker) => marker.markerId == const MarkerId('user-location'));
      _markers.add(
        Marker(
          markerId: const MarkerId('user-location'),
          position: LatLng(position.latitude, position.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Current Location'),
        ),
      );
    });

    // Update camera to follow user if patrolling
    final state = context.read<PatrolBloc>().state;
    if (state is PatrolLoaded && state.isPatrolling) {
      mapController?.animateCamera(
        CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ),
      );
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    print('Map creation started');
    try {
      setState(() {
        mapController = controller;
        _isMapReady = true;
      });
      _debugMapStatus();

      // Add initial position check
      if (userCurrentLocation != null) {
        controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(
              userCurrentLocation!.latitude,
              userCurrentLocation!.longitude,
            ),
            15,
          ),
        );
      }
    } catch (e) {
      print('Error in map creation: $e');
    }
  }

  void _debugMapStatus() {
    print('=== Google Maps Debug Info ===');
    print('Map Controller: ${mapController != null ? 'Initialized' : 'Null'}');
    print('Is Map Ready: $_isMapReady');
    print('Markers Count: ${_markers.length}');
    print('User Location: $userCurrentLocation');
    print('Has Assigned Route: ${widget.task.assignedRoute != null}');
    print('===========================');
  }

  @override
  void dispose() {
    _patrolTimer?.cancel();
    _positionStreamSubscription?.cancel();
    mapController?.dispose();
    super.dispose();
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
            GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: const CameraPosition(
                target: LatLng(-6.927872391717073, 107.76910906700982),
                zoom: 15,
              ),
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              mapType: MapType.normal,
              compassEnabled: true,
              tiltGesturesEnabled: true,
              zoomGesturesEnabled: true,
              rotateGesturesEnabled: true,
              trafficEnabled: false,
              buildingsEnabled: true,
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
            if (context.watch<PatrolBloc>().state is PatrolLoaded &&
                (context.watch<PatrolBloc>().state as PatrolLoaded)
                    .isPatrolling)
              Positioned(
                top: 100,
                left: 16,
                right: 16,
                child: Card(
                  color: Colors.white.withOpacity(0.9),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Patrol Time: ${_formatDuration(_elapsedTime)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Distance: ${(_totalDistance / 1000).toStringAsFixed(2)} km',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
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
                              print(
                                  'Original route_path map: $map'); // Debug log

                              // Sort entries by timestamp
                              final sortedEntries = map.entries.toList()
                                ..sort((a, b) => (a.value['timestamp']
                                        as String)
                                    .compareTo(b.value['timestamp'] as String));

                              print(
                                  'Sorted entries count: ${sortedEntries.length}'); // Debug log

                              // Convert coordinates - FIXED order
                              convertedPath = sortedEntries.map((entry) {
                                final coordinates =
                                    entry.value['coordinates'] as List;
                                print(
                                    'Processing coordinates: $coordinates'); // Debug log
                                return [
                                  (coordinates[0] as num)
                                      .toDouble(), // latitude comes first
                                  (coordinates[1] as num)
                                      .toDouble(), // longitude comes second
                                ];
                              }).toList();

                              print(
                                  'First point in path: ${convertedPath.first}'); // Debug log
                              print(
                                  'Last point in path: ${convertedPath.last}'); // Debug log
                            }
                          } catch (e) {
                            print('Error converting route path: $e');
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

                          _startPatrolTimer(); // Start timer when patrol starts
                          // _startLocationTracking();
                          _elapsedTime = Duration.zero; // Reset timer
                          _totalDistance = 0; // Reset distance
                          _lastPosition = null;

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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      backgroundColor:
                          state is PatrolLoaded && state.isPatrolling
                              ? Colors.red
                              : Colors.green,
                    ),
                    child: Text(
                      state is PatrolLoaded && state.isPatrolling
                          ? 'Stop Patrol'
                          : 'Start Patrol',
                      style: const TextStyle(fontSize: 16, color: Colors.white),
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
