import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:lottie/lottie.dart' as lottie;
import 'package:flutter_svg/flutter_svg.dart';
import 'presentation/auth/bloc/auth_bloc.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'dart:math' as Math;

class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({super.key});

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final Map<String, PatrolTask> _activeTasks = {};
  final Map<String, List<LatLng>> _taskRoutes = {};

  // Custom marker icons
  BitmapDescriptor? _carIcon;
  BitmapDescriptor? _motorcycleIcon;
  BitmapDescriptor? _bicycleIcon;
  BitmapDescriptor? _defaultIcon;

  bool _isLoading = true;
  bool _showLegend = true;
  String? _selectedTaskId;
  bool _isFirstLoad = true;
  Timer? _refreshTimer;
  DateTime _lastRefresh = DateTime.now();

  // Filter options
  final Map<String, bool> _clusterFilters = {};
  bool _showAllClusters = true;
  final Map<String, String> _clusterNames = {};

  @override
  void initState() {
    super.initState();
    _loadMarkerIcons();
    _loadActiveTasks();
    _loadClusters();

    // Set timer to refresh tasks every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadActiveTasks();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Tambahkan di _AdminMapScreenState

  Future<void> _loadClusters() async {
    try {
      final snapshot =
          await FirebaseDatabase.instance.ref().child('users').get();

      if (!snapshot.exists) return;

      final users = snapshot.value as Map<dynamic, dynamic>;
      Map<String, String> newClusterNames = {};

      users.forEach((userId, userData) {
        if (userData is Map &&
            (userData['role']?.toString() == 'patrol' ||
                userData.containsKey('officers')) &&
            userData['name'] != null) {
          newClusterNames[userId.toString()] = userData['name'].toString();
        }
      });

      // Update state dengan semua cluster di-check secara default
      setState(() {
        _clusterNames.clear();
        _clusterNames.addAll(newClusterNames);

        // Init filter map untuk semua cluster
        _clusterFilters.clear();
        for (var clusterId in _clusterNames.keys) {
          _clusterFilters[clusterId] = true;
        }
      });

      print('Loaded ${_clusterNames.length} clusters');
    } catch (e) {
      print('Error loading clusters: $e');
    }
  }

  Future<void> _loadMarkerIcons() async {
    try {
      _carIcon = await _getBitmapDescriptorFromAssetBytes(
          'assets/markers/car_marker.png', 120);

      _motorcycleIcon = await _getBitmapDescriptorFromAssetBytes(
          'assets/markers/motorcycle_marker.png', 120);

      _bicycleIcon = await _getBitmapDescriptorFromAssetBytes(
          'assets/markers/bicycle_marker.png', 120);

      _defaultIcon = await _getBitmapDescriptorFromAssetBytes(
          'assets/markers/default_marker.png', 120);
    } catch (e) {
      print('Error loading marker icons: $e');
    }
  }

  Future<BitmapDescriptor> _getBitmapDescriptorFromAssetBytes(
      String path, int width) async {
    try {
      final ByteData data = await rootBundle.load(path);
      final Uint8List bytes = data.buffer.asUint8List();

      // Resize the image to the desired size
      final ui.Codec codec =
          await ui.instantiateImageCodec(bytes, targetWidth: width);
      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? resizedData =
          await fi.image.toByteData(format: ui.ImageByteFormat.png);

      if (resizedData != null) {
        final Uint8List resizedBytes = resizedData.buffer.asUint8List();
        return BitmapDescriptor.fromBytes(resizedBytes);
      } else {
        return BitmapDescriptor.defaultMarker;
      }
    } catch (e) {
      print('Error creating custom marker: $e');
      return BitmapDescriptor.defaultMarker;
    }
  }

  // Perbaiki bagian query ke Firebase, lebih spesifik untuk status "ongoing"

  Future<void> _loadActiveTasks() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      print('User not authenticated');
      return;
    }

    try {
      _lastRefresh = DateTime.now();

      // Query hanya tasks dengan status "ongoing"
      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('tasks')
          .orderByChild('status')
          .equalTo('ongoing') // Fokus hanya pada status "ongoing"
          .get();

      // Jika tidak ada task ongoing, coba cek status lain yang mungkin setara
      if (!snapshot.exists ||
          (snapshot.value as Map<dynamic, dynamic>).isEmpty) {
        print('No tasks with status "ongoing", trying alternative statuses');

        // Coba cek task dengan status "in_progress"
        final inProgressSnapshot = await FirebaseDatabase.instance
            .ref()
            .child('tasks')
            .orderByChild('status')
            .equalTo('in_progress')
            .get();

        // Process inProgressSnapshot jika ada
        if (inProgressSnapshot.exists && inProgressSnapshot.value != null) {
          await _processTaskSnapshot(inProgressSnapshot);
          return;
        }

        // Jika semua query tidak menghasilkan data
        setState(() {
          _isLoading = false;
          _activeTasks.clear();
          _markers.clear();
          _polylines.clear();
        });
        return;
      }

      // Jika ada data, proses snapshot
      await _processTaskSnapshot(snapshot);
    } catch (e) {
      print('Error loading active tasks: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

// Metode helper untuk memproses task snapshot
  Future<void> _processTaskSnapshot(DataSnapshot snapshot) async {
    if (!snapshot.exists) {
      print('No tasks found');
      setState(() {
        _isLoading = false;
        _activeTasks.clear();
        _markers.clear();
        _polylines.clear();
      });
      return;
    }

    // Process tasks
    final Map<dynamic, dynamic> allTasks =
        snapshot.value as Map<dynamic, dynamic>;
    final Map<String, PatrolTask> newActiveTasks = {};

    // Extract all active tasks
    await Future.forEach(allTasks.entries,
        (MapEntry<dynamic, dynamic> entry) async {
      final taskId = entry.key.toString();
      final taskData = entry.value as Map<dynamic, dynamic>;

      try {
        final task = _createPatrolTaskFromMap(taskId, taskData);

        // Store the task
        newActiveTasks[taskId] = task;

        // Fetch officer details if needed
        if (task.officerName!.startsWith('Officer #')) {
          await _fetchOfficerInfo(task);
        }

        // Extract route path if available
        if (taskData['route_path'] != null && taskData['route_path'] is Map) {
          final routePath = _extractRoutePath(
              taskData['route_path'] as Map<dynamic, dynamic>);
          if (routePath.isNotEmpty) {
            _taskRoutes[taskId] = routePath;
          }
        }
      } catch (e) {
        print('Error processing task $taskId: $e');
      }
    });

    if (mounted) {
      setState(() {
        _activeTasks.clear();
        _activeTasks.addAll(newActiveTasks);
        _isLoading = false;
      });

      _updateMapMarkers();

      if (_isFirstLoad && _markers.isNotEmpty) {
        _centerMapOnAllMarkers();
        _isFirstLoad = false;
      }
    }
  }

  PatrolTask _createPatrolTaskFromMap(
      String taskId, Map<dynamic, dynamic> data) {
    return PatrolTask(
      taskId: taskId,
      userId: data['userId']?.toString() ?? '',
      vehicleId: data['vehicleId']?.toString() ?? '',
      status: data['status']?.toString() ?? 'unknown',
      assignedStartTime: _parseDateTime(data['assignedStartTime']),
      assignedEndTime: _parseDateTime(data['assignedEndTime']),
      startTime: _parseDateTime(data['startTime']),
      endTime: _parseDateTime(data['endTime']),
      distance: data['distance'] != null
          ? (data['distance'] as num).toDouble()
          : null,
      createdAt: _parseDateTime(data['createdAt']) ?? DateTime.now(),
      assignedRoute: data['assigned_route'] != null
          ? (data['assigned_route'] as List)
              .map((point) => (point as List)
                  .map((coord) => (coord as num).toDouble())
                  .toList())
              .toList()
          : null,
      routePath: data['route_path'] != null
          ? Map<String, dynamic>.from(data['route_path'] as Map)
          : null,
      clusterId: data['clusterId']?.toString() ?? '',
      timeliness: data['timeliness']?.toString(),
      mockLocationDetected: data['mockLocationDetected'] == true,
      mockLocationCount: data['mockLocationCount'] is num
          ? (data['mockLocationCount'] as num).toInt()
          : 0,
    );
  }

  List<LatLng> _extractRoutePath(Map<dynamic, dynamic> routePathData) {
    try {
      final List<MapEntry<dynamic, dynamic>> sortedEntries =
          routePathData.entries.toList()
            ..sort((a, b) => (a.value['timestamp'] as String)
                .compareTo(b.value['timestamp'] as String));

      return sortedEntries.map((entry) {
        final coordinates = entry.value['coordinates'] as List;
        // Note that Firebase stores as [latitude, longitude]
        final lat = (coordinates[0] as num).toDouble();
        final lng = (coordinates[1] as num).toDouble();
        return LatLng(lat, lng);
      }).toList();
    } catch (e) {
      print('Error extracting route path: $e');
      return [];
    }
  }

  Future<void> _fetchOfficerInfo(PatrolTask task) async {
    try {
      if (task.clusterId.isEmpty || task.userId.isEmpty) return;

      final snapshot = await FirebaseDatabase.instance
          .ref()
          .child('users/${task.clusterId}/officers')
          .get();

      if (!snapshot.exists) return;

      if (snapshot.value is List) {
        final officersList =
            List.from((snapshot.value as List).where((item) => item != null));

        for (var officer in officersList) {
          if (officer is Map && officer['id'] == task.userId) {
            task.officerName = officer['name']?.toString() ?? 'Unknown Officer';
            task.officerPhotoUrl = officer['photo_url']!.toString();
            return;
          }
        }
      }
    } catch (e) {
      print('Error fetching officer info: $e');
    }
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    try {
      if (value is String) {
        if (value.contains('.')) {
          final parts = value.split('.');
          final mainPart = parts[0];
          final microPart = parts[1];
          final cleanMicroPart =
              microPart.length > 6 ? microPart.substring(0, 6) : microPart;

          return DateTime.parse('$mainPart.$cleanMicroPart');
        }
        return DateTime.parse(value);
      } else if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
    } catch (e) {
      print('Error parsing datetime: $value, error: $e');
    }
    return null;
  }

  void _updateMapMarkers() {
    if (!mounted) return;

    setState(() {
      _markers.clear();
      _polylines.clear();

      _activeTasks.forEach((taskId, task) {
        final List<LatLng>? routePath = _taskRoutes[taskId];
        if (routePath != null && routePath.isNotEmpty) {
          final lastPosition = routePath.last;

          if (!_showAllClusters && !(_clusterFilters[task.clusterId] ?? true)) {
            return;
          }

          final marker = Marker(
            markerId: MarkerId(taskId),
            position: lastPosition,
            infoWindow: InfoWindow(
              title:
                  '${task.officerName}${task.timeliness != null ? " (${getTimelinessText(task.timeliness)})" : ""}',
              snippet:
                  'Cluster: ${_clusterNames[task.clusterId] ?? task.clusterId.substring(0, Math.min(8, task.clusterId.length))}, Jarak: ${((task.distance ?? 0) / 1000).toStringAsFixed(2)} km',
            ),
            icon: _getMarkerIconForCluster(task.clusterId),
            onTap: () {
              setState(() {
                _selectedTaskId = taskId;
              });
              _showTaskDetailsBottomSheet(task);
            },
          );

          _markers.add(marker);

          final polyline = Polyline(
            polylineId: PolylineId('path_$taskId'),
            points: routePath,
            color: _selectedTaskId == taskId
                ? Colors.red
                : _getColorForCluster(task.clusterId),
            width: _selectedTaskId == taskId ? 5 : 3,
          );

          _polylines.add(polyline);
        }
      });
    });
  }

  Color _getColorForCluster(String clusterId) {
    final hashCode = clusterId.hashCode;
    return Color.fromARGB(
      255,
      (hashCode & 0xFF0000) >> 16,
      (hashCode & 0x00FF00) >> 8,
      hashCode & 0x0000FF,
    );
  }

  BitmapDescriptor _getMarkerIconForCluster(String clusterId) {
    return _defaultIcon ?? BitmapDescriptor.defaultMarker;
  }

  void _centerMapOnAllMarkers() async {
    if (_markers.isEmpty || !_mapController.isCompleted) return;

    final GoogleMapController controller = await _mapController.future;

    // If there's only one marker, center on it with closer zoom
    if (_markers.length == 1) {
      final position = _markers.first.position;
      controller.animateCamera(CameraUpdate.newLatLngZoom(
        position,
        17.0, // Closer zoom for single marker
      ));
      return;
    }

    // For multiple markers, fit bounds
    final double minLat = _markers
        .map((m) => m.position.latitude)
        .reduce((a, b) => a < b ? a : b);
    final double maxLat = _markers
        .map((m) => m.position.latitude)
        .reduce((a, b) => a > b ? a : b);
    final double minLng = _markers
        .map((m) => m.position.longitude)
        .reduce((a, b) => a < b ? a : b);
    final double maxLng = _markers
        .map((m) => m.position.longitude)
        .reduce((a, b) => a > b ? a : b);

    final LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat - 0.01, minLng - 0.01),
      northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
    );

    final CameraUpdate update = CameraUpdate.newLatLngBounds(bounds, 50.0);
    controller.animateCamera(update);
  }

  void _showTaskDetailsBottomSheet(PatrolTask task) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final duration = task.startTime != null
            ? DateTime.now().difference(task.startTime!)
            : Duration.zero;

        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: kbpBlue100,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: task.officerPhotoUrl!.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.network(
                              task.officerPhotoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Center(
                                child: Text(
                                  task.officerName
                                          ?.substring(0, 1)
                                          .toUpperCase() ??
                                      'P',
                                  style: boldTextStyle(
                                      size: 18, color: kbpBlue900),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              task.officerName?.substring(0, 1).toUpperCase() ??
                                  'P',
                              style: boldTextStyle(size: 18, color: kbpBlue900),
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.officerName ?? 'Petugas Patroli',
                          style: boldTextStyle(size: 16, color: kbpBlue900),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          task.vehicleId.isEmpty
                              ? 'Tanpa Kendaraan'
                              : task.vehicleId,
                          style: regularTextStyle(size: 14, color: kbpBlue700),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: successG500,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Aktif',
                      style: boldTextStyle(size: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
              if (task.timeliness != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    buildTimelinessIndicator(task.timeliness),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        getTimelinessDescription(task.timeliness),
                        style: regularTextStyle(
                          size: 12,
                          color: getTimelinessColor(task.timeliness),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _infoItem(
                      Icons.timer,
                      'Durasi',
                      '${duration.inHours}j ${duration.inMinutes.remainder(60)}m',
                    ),
                  ),
                  Expanded(
                    child: _infoItem(
                      Icons.straighten,
                      'Jarak',
                      '${((task.distance ?? 0) / 1000).toStringAsFixed(2)} km',
                    ),
                  ),
                  Expanded(
                    child: _infoItem(
                      Icons.place,
                      'Titik Patroli',
                      '${task.assignedRoute?.length ?? 0} Titik',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _infoItem(
                      Icons.access_time,
                      'Mulai',
                      task.startTime != null
                          ? '${task.startTime!.hour.toString().padLeft(2, '0')}:${task.startTime!.minute.toString().padLeft(2, '0')}'
                          : 'N/A',
                    ),
                  ),
                  Expanded(
                    child: _infoItem(
                      Icons.calendar_today,
                      'Tanggal',
                      task.startTime != null
                          ? '${task.startTime!.day}/${task.startTime!.month}/${task.startTime!.year}'
                          : 'N/A',
                    ),
                  ),
                  Expanded(
                    child: _infoItem(
                      Icons.speed,
                      'Cluster',
                      task.clusterId
                          .substring(0, Math.min(8, task.clusterId.length)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _centerMapOnTask(task.taskId);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kbpBlue900,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Lihat Rute di Peta',
                    style: semiBoldTextStyle(size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: kbpBlue900, size: 22),
        const SizedBox(height: 4),
        Text(
          label,
          style: regularTextStyle(size: 12, color: kbpBlue700),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: semiBoldTextStyle(size: 14, color: kbpBlue900),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _centerMapOnTask(String taskId) async {
    if (!_mapController.isCompleted) return;

    final routePath = _taskRoutes[taskId];
    if (routePath == null || routePath.isEmpty) return;

    setState(() {
      _selectedTaskId = taskId;
    });

    _updateMapMarkers();

    final controller = await _mapController.future;

    if (routePath.length == 1) {
      controller.animateCamera(CameraUpdate.newLatLngZoom(
        routePath.first,
        17.0,
      ));
      return;
    }

    final double minLat =
        routePath.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final double maxLat =
        routePath.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final double minLng =
        routePath.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final double maxLng =
        routePath.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

    final LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat - 0.005, minLng - 0.005),
      northeast: LatLng(maxLat + 0.005, maxLng + 0.005),
    );

    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50.0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Live Tracking Dashboard',
          style: semiBoldTextStyle(size: 18, color: Colors.white),
        ),
        backgroundColor: kbpBlue900,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadActiveTasks,
            tooltip: 'Refresh Data',
          ),
          IconButton(
            icon: Icon(
              _showLegend ? Icons.visibility_off : Icons.visibility,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                _showLegend = !_showLegend;
              });
            },
            tooltip: _showLegend ? 'Hide Legend' : 'Show Legend',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(-6.8859, 107.6158),
              zoom: 12.0,
            ),
            mapType: MapType.normal,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              _mapController.complete(controller);
            },
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: Center(
                child: lottie.LottieBuilder.asset(
                  'assets/lottie/maps_loading.json',
                  width: 150,
                  height: 150,
                ),
              ),
            ),
          if (_showLegend)
            Positioned(
              top: 16,
              right: 16,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  width: 200,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Filter Cluster',
                            style:
                                semiBoldTextStyle(size: 14, color: kbpBlue900),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _showAllClusters = !_showAllClusters;

                                for (var key in _clusterFilters.keys) {
                                  _clusterFilters[key] = _showAllClusters;
                                }
                                _updateMapMarkers();
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: kbpBlue100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _showAllClusters ? 'Reset' : 'Pilih Semua',
                                style: regularTextStyle(
                                    size: 10, color: kbpBlue900),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: _clusterNames.isEmpty
                            ? Center(
                                child: Text(
                                  'Tidak ada cluster yang tersedia',
                                  style: regularTextStyle(
                                      size: 12, color: kbpBlue700),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: _clusterNames.length,
                                itemBuilder: (context, index) {
                                  final clusterId =
                                      _clusterNames.keys.elementAt(index);
                                  final clusterName =
                                      _clusterNames[clusterId] ??
                                          'Cluster #$index';

                                  return CheckboxListTile(
                                    value: _clusterFilters[clusterId] ?? true,
                                    onChanged: (value) {
                                      setState(() {
                                        _clusterFilters[clusterId] =
                                            value ?? true;

                                        _showAllClusters = _clusterFilters
                                            .values
                                            .every((v) => v);
                                      });
                                      _updateMapMarkers();
                                    },
                                    title: Text(
                                      clusterName,
                                      style: regularTextStyle(size: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  );
                                },
                              ),
                      ),
                      const Divider(),
                      Row(
                        children: [
                          Icon(Icons.people, size: 14, color: kbpBlue900),
                          const SizedBox(width: 8),
                          Text(
                            'Petugas Ongoing: ${_activeTasks.length}',
                            style: mediumTextStyle(size: 12, color: kbpBlue900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.refresh, size: 14, color: kbpBlue900),
                          const SizedBox(width: 8),
                          Text(
                            'Update: ${_lastRefresh.hour.toString().padLeft(2, '0')}:${_lastRefresh.minute.toString().padLeft(2, '0')}',
                            style:
                                regularTextStyle(size: 12, color: kbpBlue900),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!_isLoading && _activeTasks.isEmpty)
            Container(
              color: Colors.black.withOpacity(0.7),
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    width: MediaQuery.of(context).size.width * 0.8,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          'assets/state/noTask.svg',
                          height: 120,
                          width: 120,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Tidak Ada Petugas Berpatroli',
                          style: semiBoldTextStyle(size: 18, color: kbpBlue900),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Saat ini tidak ada petugas yang sedang melakukan patroli',
                          style: regularTextStyle(size: 14, color: kbpBlue700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadActiveTasks,
                          icon: const Icon(
                            Icons.refresh,
                            size: 16,
                            color: neutralWhite,
                          ),
                          label: Text(
                            'Refresh Data',
                            style:
                                mediumTextStyle(size: 14, color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kbpBlue900,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
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
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Fit bounds button
          FloatingActionButton(
            onPressed: _centerMapOnAllMarkers,
            backgroundColor: kbpBlue900,
            heroTag: 'fitBounds',
            mini: true,
            child: const Icon(Icons.fit_screen),
            tooltip: 'Tampilkan Semua Petugas',
          ),
          const SizedBox(height: 12),
          // My location button
          FloatingActionButton(
            onPressed: () async {
              if (!_mapController.isCompleted) return;
              final controller = await _mapController.future;
              controller.animateCamera(CameraUpdate.newCameraPosition(
                const CameraPosition(
                  target: LatLng(-6.856876, 107.489486),
                  zoom: 12.0,
                ),
              ));
            },
            backgroundColor: kbpBlue900,
            heroTag: 'myLocation',
            child: const Icon(Icons.my_location),
            tooltip: 'Lokasi Saya',
          ),
        ],
      ),
    );
  }
}
