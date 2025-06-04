import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/domain/entities/report.dart';
import 'package:livetrackingapp/domain/entities/user.dart'; // ADD: Import User entity
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class FullScreenMapPage extends StatefulWidget {
  final PatrolTask task;
  final Set<Marker> initialMarkers;
  final Set<Polyline> initialPolylines;
  final List<Report> reports;

  const FullScreenMapPage({
    Key? key,
    required this.task,
    required this.initialMarkers,
    required this.initialPolylines,
    required this.reports,
  }) : super(key: key);

  @override
  State<FullScreenMapPage> createState() => _FullScreenMapPageState();
}

class _FullScreenMapPageState extends State<FullScreenMapPage> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isMapReady = false;
  MapType _currentMapType = MapType.normal;
  bool _showLegend = true;

  // Timeline variables
  bool _showTimeline = false;
  List<Map<String, dynamic>> _sortedPatrolPoints = [];
  final ScrollController _timelineScrollController = ScrollController();
  List<Map<String, dynamic>> _assignedRoutePoints = [];
  Map<String, Map<String, dynamic>> _visitedPointsMap = {};

  // PERBAIKAN 2: Tambahkan variabel untuk user dan checkpoint validation
  User? _patrolUser; // User yang melakukan patroli
  double? _customValidationRadius; // Radius custom dari user

  final dateFormatter = DateFormat('dd MMM yyyy', 'id_ID');
  final timeFormatter = DateFormat('HH:mm', 'id_ID');

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _markers = Set<Marker>.from(widget.initialMarkers);
    _polylines = Set<Polyline>.from(
      widget.initialPolylines.where((polyline) {
        final isAssignedRoute =
            polyline.color.value == Colors.green.withOpacity(0.7).value;
        return !isAssignedRoute;
      }),
    );

    // PERBAIKAN 3: Load user data dan patrol timeline
    _initializeData();
  }

  // PERBAIKAN 4: Method untuk inisialisasi data
  Future<void> _initializeData() async {
    try {
      // Load user data untuk mendapatkan radius custom
      await _loadPatrolUserData();

      // Load patrol timeline dengan radius yang tepat
      await _loadPatrolTimeline();
    } catch (e) {
      print('Error initializing data: $e');
      // Fallback ke default jika ada error
      _loadPatrolTimeline();
    }
  }

  // PERBAIKAN 5: Method untuk load user data
  Future<void> _loadPatrolUserData() async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('users')
          .child(widget.task.clusterId!)
          .get();

      if (snapshot.exists && snapshot.value != null) {
        final userData = Map<String, dynamic>.from(snapshot.value as Map);
        _patrolUser = User.fromMap(userData);
        _customValidationRadius = _patrolUser!.checkpointValidationRadius;

        print('DEBUG: User loaded: ${_patrolUser!.name}');
        print('DEBUG: Custom validation radius: ${_customValidationRadius}m');
      }
    } catch (e) {
      print('Error loading patrol user data: $e');
    }
  }

  // PERBAIKAN 6: Update _loadPatrolTimeline() dengan radius custom dan timestamp tracking
  Future<void> _loadPatrolTimeline() async {
    if (widget.task.assignedRoute == null) return;

    try {
      final assignedPoints = <Map<String, dynamic>>[];
      final visitedPoints = <String, Map<String, dynamic>>{};

      // PERBAIKAN: Gunakan radius dari user atau default 50m
      final double radiusInMeters = _customValidationRadius ?? 50.0;

      print('DEBUG TIMELINE: Using validation radius: ${radiusInMeters}m');

      // Load assigned route points dengan detail yang lebih lengkap
      for (int i = 0; i < widget.task.assignedRoute!.length; i++) {
        final coordinates = widget.task.assignedRoute![i];
        if (coordinates.length >= 2) {
          assignedPoints.add({
            'id': 'assigned-$i',
            'index': i,
            'coordinates': coordinates,
            'isVisited': false,
            'visitInfo': null,
            'visitTimestamp': null, // PERBAIKAN: Tambahkan field timestamp
            'distanceFromCheckpoint':
                null, // PERBAIKAN: Tambahkan field distance
          });
        }
      }

      // PERBAIKAN: Extract dan analisis route positions dengan timestamp
      if (widget.task.routePath != null) {
        final routePathMap = Map<String, dynamic>.from(widget.task.routePath!);
        final List<Map<String, dynamic>> routePositions = [];

        // Extract semua posisi dengan timestamp
        routePathMap.forEach((key, value) {
          try {
            if (value is Map && value.containsKey('coordinates')) {
              final coordinates = value['coordinates'] as List;
              final timestamp = value['timestamp'] as String?;

              if (coordinates.length >= 2 && timestamp != null) {
                routePositions.add({
                  'lat': coordinates[0] as double,
                  'lng': coordinates[1] as double,
                  'timestamp': timestamp,
                  'originalKey': key,
                  'originalValue': value,
                });
              }
            }
          } catch (e) {
            print('Error parsing route path entry $key: $e');
          }
        });

        // Sort route positions by timestamp
        routePositions.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));

        print('DEBUG TIMELINE: Found ${routePositions.length} route positions');

        // PERBAIKAN: Check visited checkpoints dengan algoritma yang sama seperti patrol_history_screen.dart
        for (int i = 0; i < widget.task.assignedRoute!.length; i++) {
          try {
            final checkpoint = widget.task.assignedRoute![i];
            final checkpointLat = checkpoint[0] as double;
            final checkpointLng = checkpoint[1] as double;

            double minDistance = double.infinity;
            Map<String, dynamic>? closestPosition;
            DateTime? visitTimestamp;

            // Find closest route position to this checkpoint
            for (final position in routePositions) {
              final distance = Geolocator.distanceBetween(
                position['lat'] as double,
                position['lng'] as double,
                checkpointLat,
                checkpointLng,
              );

              if (distance < minDistance) {
                minDistance = distance;
                closestPosition = position;
              }
            }

            // PERBAIKAN: Gunakan radius yang tepat dan simpan detail kunjungan
            if (minDistance <= radiusInMeters && closestPosition != null) {
              try {
                visitTimestamp = DateTime.parse(closestPosition['timestamp']);
              } catch (e) {
                print('Error parsing timestamp: $e');
              }

              // Update assigned point dengan info lengkap
              assignedPoints[i]['isVisited'] = true;
              assignedPoints[i]['visitInfo'] = {
                'timestamp': closestPosition['timestamp'],
                'exactCoordinates': [
                  closestPosition['lat'],
                  closestPosition['lng']
                ],
                'distance': minDistance,
                'reportId': closestPosition['originalValue']['reportId'],
                'originalKey': closestPosition['originalKey'],
              };
              assignedPoints[i]['visitTimestamp'] = visitTimestamp;
              assignedPoints[i]['distanceFromCheckpoint'] = minDistance;

              // Store in visitedPoints for quick lookup
              final pointId = 'assigned-$i';
              visitedPoints[pointId] = {
                'timestamp': closestPosition['timestamp'],
                'coordinates': [closestPosition['lat'], closestPosition['lng']],
                'distance': minDistance,
                'reportId': closestPosition['originalValue']['reportId'],
                'checkpointIndex': i,
                'visitDateTime': visitTimestamp,
              };

              print(
                  'DEBUG TIMELINE: Checkpoint $i visited at ${closestPosition['timestamp']}, distance: ${minDistance.toStringAsFixed(1)}m');
            }
          } catch (e) {
            print('Error checking distance for checkpoint $i: $e');
          }
        }

        // PERBAIKAN: Sort visited points by timestamp
        final sortedVisitedPoints = visitedPoints.entries.toList()
          ..sort((a, b) {
            final timestampA = a.value['timestamp'] as String?;
            final timestampB = b.value['timestamp'] as String?;
            if (timestampA == null || timestampB == null) return 0;
            return timestampA.compareTo(timestampB);
          });

        // Create sorted patrol points for timeline display
        _sortedPatrolPoints = sortedVisitedPoints
            .map((entry) => {
                  'id': entry.key,
                  'checkpointIndex': entry.value['checkpointIndex'],
                  'timestamp': entry.value['timestamp'],
                  'visitDateTime': entry.value['visitDateTime'],
                  'coordinates': entry.value['coordinates'],
                  'distance': entry.value['distance'],
                  'reportId': entry.value['reportId'],
                })
            .toList();
      }

      final visitedCount =
          assignedPoints.where((point) => point['isVisited'] == true).length;
      final totalCount = assignedPoints.length;

      print('DEBUG TIMELINE: Total checkpoints: $totalCount');
      print('DEBUG TIMELINE: Visited checkpoints: $visitedCount');
      print('DEBUG TIMELINE: Radius used: ${radiusInMeters}m');
      print(
          'DEBUG TIMELINE: Sorted patrol points: ${_sortedPatrolPoints.length}');

      setState(() {
        _assignedRoutePoints = assignedPoints;
        _visitedPointsMap = visitedPoints;
      });
    } catch (e) {
      print('Error loading patrol timeline: $e');
    }
  }

  // PERBAIKAN 7: Update _getVisitedPointsStats() untuk menggunakan radius custom
  Map<String, dynamic> _getVisitedPointsStats() {
    final visitedCount = _assignedRoutePoints
        .where((point) => point['isVisited'] == true)
        .length;
    final totalCount = _assignedRoutePoints.length;
    final radiusUsed = _customValidationRadius ?? 50.0;

    return {
      'visitedCount': visitedCount,
      'totalCount': totalCount,
      'radiusUsed': radiusUsed,
      'progress':
          totalCount > 0 ? (visitedCount / totalCount * 100).round() : 0,
      'userValidationRadius': _patrolUser?.checkpointValidationRadius ?? 50.0,
      'patrolUserName': _patrolUser?.name,
    };
  }

  // PERBAIKAN 8: Update _buildTimelinePanel() dengan informasi yang lebih detail
  Widget _buildTimelinePanel() {
    final stats = _getVisitedPointsStats();
    final visitedCount = stats['visitedCount'] as int;
    final totalCount = stats['totalCount'] as int;
    final progress = stats['progress'] as int;
    final radiusUsed = stats['radiusUsed'] as double;

    return Container(
      height: 320, // Increase height untuk more content
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PERBAIKAN: Header dengan informasi lengkap
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Timeline Rute Patroli',
                      style: boldTextStyle(size: 16),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: successG100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Dikunjungi: $visitedCount/$totalCount',
                            style:
                                mediumTextStyle(size: 12, color: successG300),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: infoB100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.gps_fixed,
                                  size: 12, color: kbpBlue500),
                              const SizedBox(width: 4),
                              Text(
                                'Radius: ${radiusUsed.toStringAsFixed(0)}m',
                                style: mediumTextStyle(
                                    size: 12, color: kbpBlue500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // PERBAIKAN: Show patrol user info if available
                    if (_patrolUser != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Petugas: ${_patrolUser!.name}',
                        style: regularTextStyle(size: 11, color: neutral600),
                      ),
                    ],
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _showTimeline = false;
                    });
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // PERBAIKAN: Progress bar dengan info radius
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Progress Kunjungan',
                      style: mediumTextStyle(size: 12, color: neutral600),
                    ),
                    Row(
                      children: [
                        Text(
                          '$progress%',
                          style:
                              semiBoldTextStyle(size: 12, color: successG300),
                        ),
                        const SizedBox(width: 8),
                        if (_patrolUser?.checkpointValidationRadius != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: warningY100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Custom',
                              style:
                                  mediumTextStyle(size: 10, color: warningY300),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: totalCount > 0 ? visitedCount / totalCount : 0,
                  backgroundColor: neutral200,
                  valueColor: AlwaysStoppedAnimation<Color>(successG500),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
          ),

          // PERBAIKAN: Timeline items dengan timestamp chronological order
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tabs untuk switch view
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: kbpBlue700),
                      const SizedBox(width: 8),
                      Text(
                        'Urutan Kunjungan (${_sortedPatrolPoints.length} dikunjungi)',
                        style: semiBoldTextStyle(size: 13, color: kbpBlue700),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: _sortedPatrolPoints.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.timeline, size: 48, color: neutral400),
                              SizedBox(height: 8),
                              Text(
                                'Belum ada checkpoint yang dikunjungi',
                                style: TextStyle(color: neutral600),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _timelineScrollController,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          itemCount: _sortedPatrolPoints.length,
                          itemBuilder: (context, index) {
                            final visitData = _sortedPatrolPoints[index];
                            final checkpointIndex =
                                visitData['checkpointIndex'] as int;
                            final timestamp = visitData['timestamp'] as String;
                            final distance = visitData['distance'] as double;
                            final coordinates =
                                visitData['coordinates'] as List;
                            final visitDateTime =
                                visitData['visitDateTime'] as DateTime?;

                            String timeString = 'Unknown';
                            String dateString = 'Unknown';

                            if (visitDateTime != null) {
                              timeString = timeFormatter.format(visitDateTime);
                              dateString = dateFormatter.format(visitDateTime);
                            }

                            return Container(
                              width: 160, // Increase width for more content
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    successG50,
                                    successG100.withOpacity(0.3),
                                  ],
                                ),
                                border:
                                    Border.all(color: successG400, width: 1.5),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: successG200.withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: InkWell(
                                onTap: () {
                                  _focusOnPatrolPoint(coordinates);
                                  _showInfoWindowAt(coordinates, timestamp);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // PERBAIKAN: Header dengan urutan visit dan checkpoint index
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: kbpBlue600,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '#${index + 1}', // Visit order
                                              style: boldTextStyle(
                                                  size: 11,
                                                  color: Colors.white),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: successG200,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'CP${checkpointIndex + 1}', // Checkpoint number
                                              style: mediumTextStyle(
                                                  size: 10, color: successG500),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // Status
                                      Row(
                                        children: [
                                          Icon(Icons.check_circle,
                                              size: 16, color: successG500),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Dikunjungi',
                                            style: semiBoldTextStyle(
                                                size: 12, color: successG300),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // PERBAIKAN: Time info
                                      Row(
                                        children: [
                                          const Icon(Icons.access_time,
                                              size: 12, color: neutral600),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              timeString,
                                              style: mediumTextStyle(size: 11),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),

                                      // Date info
                                      Row(
                                        children: [
                                          const Icon(Icons.calendar_today,
                                              size: 12, color: neutral600),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              dateString,
                                              style: regularTextStyle(
                                                  size: 10, color: neutral700),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),

                                      // PERBAIKAN: Distance with validation status
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: distance <= radiusUsed
                                              ? successG200
                                              : warningY200,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              distance <= radiusUsed
                                                  ? Icons.gps_fixed
                                                  : Icons.gps_not_fixed,
                                              size: 12,
                                              color: distance <= radiusUsed
                                                  ? successG300
                                                  : warningY500,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${distance.toStringAsFixed(0)}m',
                                              style: mediumTextStyle(
                                                size: 10,
                                                color: distance <= radiusUsed
                                                    ? successG300
                                                    : warningY500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const Spacer(),

                                      // Action button
                                      SizedBox(
                                        width: double.infinity,
                                        height: 32,
                                        child: ElevatedButton(
                                          onPressed: () {
                                            _focusOnPatrolPoint(coordinates);
                                            _showInfoWindowAt(
                                                coordinates, timestamp);
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: kbpBlue700,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 4),
                                            textStyle:
                                                mediumTextStyle(size: 10),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.map, size: 14),
                                              const SizedBox(width: 4),
                                              const Text('Lihat'),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // PERBAIKAN 9: Update _showInfoWindowAt() untuk show detailed info
  void _showInfoWindowAt(List<dynamic> coordinates, String timestamp) {
    if (_mapController == null || coordinates.length < 2) return;

    try {
      final visitDateTime = DateTime.parse(timestamp);
      final timeString = timeFormatter.format(visitDateTime);
      final dateString = dateFormatter.format(visitDateTime);

      final markerId = MarkerId('selected-timeline-$timestamp');
      final marker = Marker(
        markerId: markerId,
        position: LatLng(
          (coordinates[0] as num).toDouble(),
          (coordinates[1] as num).toDouble(),
        ),
        infoWindow: InfoWindow(
          title: 'Checkpoint Dikunjungi',
          snippet:
              '$timeString - $dateString (Radius: ${(_customValidationRadius ?? 50).toStringAsFixed(0)}m)',
        ),
      );

      setState(() {
        _markers.removeWhere(
            (m) => m.markerId.value.startsWith('selected-timeline'));
        _markers.add(marker);
      });

      // Show InfoWindow
      Future.delayed(const Duration(milliseconds: 300), () {
        _mapController?.showMarkerInfoWindow(markerId);
      });
    } catch (e) {
      print('Error showing info window: $e');
    }
  }

  void _fitMapToRoute() {
    if (_mapController == null) return;

    try {
      final bounds = _calculateBounds();
      if (bounds != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 100.0),
        );
      }
    } catch (e) {
      print('Error fitting map to route: $e');
      // Fallback ke koordinat default jika ada error
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          const LatLng(-6.927727934898599, 107.76911107969532),
          15,
        ),
      );
    }
  }

// PERBAIKAN: Tambahkan method _calculateBounds() untuk menghitung batas peta
  LatLngBounds? _calculateBounds() {
    final List<LatLng> allPoints = [];

    // Tambahkan semua marker positions
    for (final marker in _markers) {
      allPoints.add(marker.position);
    }

    // Tambahkan semua polyline points
    for (final polyline in _polylines) {
      allPoints.addAll(polyline.points);
    }

    // Tambahkan assigned route points jika ada
    if (widget.task.assignedRoute != null) {
      for (final route in widget.task.assignedRoute!) {
        if (route.length >= 2) {
          allPoints.add(LatLng(route[0], route[1]));
        }
      }
    }

    if (allPoints.isEmpty) return null;

    // Hitung bounds
    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (final point in allPoints) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // Tambahkan metode untuk menghitung jarak antara dua koordinat
  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    // Radius bumi dalam meter
    const double earthRadius = 6371000;

    // Konversi derajat ke radian
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lng2 - lng1);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  // Tambahkan metode untuk fokus ke titik tertentu
  void _focusOnPatrolPoint(List<dynamic> coordinates) {
    if (_mapController == null || coordinates.length < 2) return;

    _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(
          (coordinates[0] as num).toDouble(),
          (coordinates[1] as num).toDouble(),
        ),
        18,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Maps sebagai background penuh
          GoogleMap(
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
            mapType: _currentMapType,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            scrollGesturesEnabled: true,
            rotateGesturesEnabled: true,
            tiltGesturesEnabled: true,
            zoomGesturesEnabled: true,
          ),

          // Loading indicator
          // if (!_isMapReady)
          //   const Center(
          //     child: CircularProgressIndicator(color: Colors.white),
          //   ),

          // Header dengan title dan tombol kembali
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                bottom: 8,
                left: 8,
                right: 8,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  // Tombol kembali
                  Material(
                    color: Colors.transparent,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Kembali',
                    ),
                  ),

                  // Title
                  Expanded(
                    child: Text(
                      'Peta Patroli Detail',
                      style: boldTextStyle(size: 18, color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // Toggle map type
                  Material(
                    color: Colors.transparent,
                    child: IconButton(
                      icon: Icon(
                        _currentMapType == MapType.normal
                            ? Icons.map
                            : Icons.satellite,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          _currentMapType = _currentMapType == MapType.normal
                              ? MapType.satellite
                              : MapType.normal;
                        });
                      },
                      tooltip: 'Ubah tipe peta',
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Legenda yang bisa disembunyikan
          if (_showLegend)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                color: Colors.white.withOpacity(0.9),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Legenda',
                            style: semiBoldTextStyle(size: 14),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _showLegend = false;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 40,
                        runSpacing: 8,
                        children: [
                          _buildLegendItem(kbpBlue700, 'Rute aktual'),
                          _buildLegendItem(Colors.green, 'Titik dikunjungi',
                              isMarker: true),
                          _buildLegendItem(Colors.red, 'Titik belum dikunjungi',
                              isMarker: true),
                          if (widget.reports.isNotEmpty)
                            _buildLegendItem(Colors.blue,
                                'Laporan (${widget.reports.length})',
                                isMarker: true),
                          if (widget.task.mockLocationDetected == true)
                            _buildLegendItem(Colors.purple, 'Fake GPS',
                                isMarker: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Tombol kanan bawah
          Positioned(
            bottom: 24,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tombol Fit to Route
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.white,
                  foregroundColor: kbpBlue900,
                  onPressed: _fitMapToRoute,
                  heroTag: 'fitRoute',
                  child: const Icon(Icons.route),
                  tooltip: 'Lihat seluruh rute',
                ),
                const SizedBox(height: 12),

                // Tombol lokasi saya
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.white,
                  foregroundColor: kbpBlue900,
                  onPressed: () async {
                    try {
                      // Mendapatkan lokasi saat ini
                      final position = await Geolocator.getCurrentPosition();
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngZoom(
                          LatLng(position.latitude, position.longitude),
                          17,
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Gagal mendapatkan lokasi saat ini'),
                          backgroundColor: dangerR500,
                        ),
                      );
                    }
                  },
                  heroTag: 'myLocation',
                  child: const Icon(Icons.my_location),
                  tooltip: 'Lokasi saya',
                ),
                const SizedBox(height: 12),

                // Tombol zoom in
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.white,
                  foregroundColor: kbpBlue900,
                  onPressed: () {
                    _mapController?.animateCamera(CameraUpdate.zoomIn());
                  },
                  heroTag: 'zoomIn',
                  child: const Icon(Icons.add),
                  tooltip: 'Perbesar',
                ),
                const SizedBox(height: 12),

                // Tombol zoom out
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.white,
                  foregroundColor: kbpBlue900,
                  onPressed: () {
                    _mapController?.animateCamera(CameraUpdate.zoomOut());
                  },
                  heroTag: 'zoomOut',
                  child: const Icon(Icons.remove),
                  tooltip: 'Perkecil',
                ),
              ],
            ),
          ),

          // Tombol kiri bawah
          Positioned(
            bottom: 24,
            left: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tombol untuk tampilkan legenda
                if (!_showLegend)
                  FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.white,
                    foregroundColor: kbpBlue900,
                    onPressed: () {
                      setState(() {
                        _showLegend = true;
                      });
                    },
                    heroTag: 'showLegend',
                    child: const Icon(Icons.info_outline),
                    tooltip: 'Tampilkan legenda',
                  ),
              ],
            ),
          ),

          // Tombol timeline
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.extended(
                backgroundColor: Colors.white,
                foregroundColor: kbpBlue900,
                onPressed: () {
                  setState(() {
                    _showTimeline = !_showTimeline;
                  });
                },
                heroTag: 'showTimeline',
                icon: Icon(
                    _showTimeline ? Icons.timeline_outlined : Icons.timeline),
                label: Text(
                  _showTimeline ? 'Sembunyikan Timeline' : 'Lihat Timeline',
                  style: mediumTextStyle(color: kbpBlue900),
                ),
              ),
            ),
          ),

          // Panel timeline
          if (_showTimeline)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Timeline Rute Patroli',
                            style: boldTextStyle(size: 16),
                          ),
                          Row(
                            children: [
                              Text(
                                'Dikunjungi: ${_visitedPointsMap.length}/${_assignedRoutePoints.length}',
                                style: mediumTextStyle(size: 12),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.close),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  setState(() {
                                    _showTimeline = false;
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _assignedRoutePoints.isEmpty
                          ? const Center(
                              child:
                                  Text('Tidak ada titik rute yang ditugaskan'),
                            )
                          : ListView.builder(
                              controller: _timelineScrollController,
                              scrollDirection: Axis.horizontal,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              itemCount: _assignedRoutePoints.length,
                              itemBuilder: (context, index) {
                                final point = _assignedRoutePoints[index];
                                final isVisited = point['isVisited'] as bool;
                                final visitInfo =
                                    point['visitInfo'] as Map<String, dynamic>?;
                                final coordinates =
                                    point['coordinates'] as List;

                                // Informasi kunjungan
                                String? timeString;
                                String? dateString;
                                DateTime? visitDateTime;

                                if (isVisited &&
                                    visitInfo != null &&
                                    visitInfo.containsKey('timestamp')) {
                                  try {
                                    visitDateTime =
                                        DateTime.parse(visitInfo['timestamp']);
                                    timeString =
                                        timeFormatter.format(visitDateTime);
                                    dateString =
                                        dateFormatter.format(visitDateTime);
                                  } catch (_) {}
                                }

                                final bool hasReport = isVisited &&
                                    visitInfo != null &&
                                    visitInfo['reportId'] != null;

                                return Container(
                                  width: 120,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isVisited ? successG50 : neutral200,
                                    border: Border.all(
                                      color: isVisited
                                          ? hasReport
                                              ? kbpBlue300
                                              : successG300
                                          : dangerR300,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: InkWell(
                                    onTap: () {
                                      _focusOnPatrolPoint(coordinates);
                                      if (isVisited && visitInfo != null) {
                                        _showInfoWindowAt(
                                          coordinates,
                                          visitInfo['timestamp'] ?? 'unknown',
                                        );
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isVisited
                                                      ? successG100
                                                      : dangerR100,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'Titik ${index + 1}',
                                                  style: mediumTextStyle(
                                                    size: 10,
                                                    color: isVisited
                                                        ? successG300
                                                        : dangerR300,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                isVisited
                                                    ? hasReport
                                                        ? Icons.description
                                                        : Icons.check_circle
                                                    : Icons.cancel,
                                                size: 14,
                                                color: isVisited
                                                    ? hasReport
                                                        ? kbpBlue700
                                                        : successG300
                                                    : dangerR300,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),

                                          // Status kunjungan
                                          Text(
                                            isVisited
                                                ? 'Dikunjungi'
                                                : 'Tidak dikunjungi',
                                            style: mediumTextStyle(
                                              size: 12,
                                              color: isVisited
                                                  ? successG300
                                                  : dangerR300,
                                            ),
                                          ),

                                          // Jika dikunjungi, tampilkan waktu
                                          if (isVisited &&
                                              timeString != null) ...[
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(Icons.access_time,
                                                    size: 12,
                                                    color: neutral600),
                                                const SizedBox(width: 4),
                                                Text(
                                                  timeString,
                                                  style: regularTextStyle(
                                                      size: 12),
                                                ),
                                              ],
                                            ),
                                          ],

                                          // Jika dikunjungi, tampilkan tanggal
                                          if (isVisited &&
                                              dateString != null) ...[
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(Icons.calendar_today,
                                                    size: 12,
                                                    color: neutral600),
                                                const SizedBox(width: 4),
                                                Text(
                                                  dateString,
                                                  style: regularTextStyle(
                                                      size: 10),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ],

                                          const SizedBox(height: 8),
                                          ElevatedButton(
                                            onPressed: () {
                                              _focusOnPatrolPoint(coordinates);
                                              if (isVisited &&
                                                  visitInfo != null) {
                                                _showInfoWindowAt(
                                                  coordinates,
                                                  visitInfo['timestamp'] ??
                                                      'unknown',
                                                );
                                              }
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: isVisited
                                                  ? hasReport
                                                      ? kbpBlue700
                                                      : successG500
                                                  : neutral500,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4),
                                              minimumSize: const Size(
                                                  double.infinity, 24),
                                              textStyle:
                                                  mediumTextStyle(size: 10),
                                            ),
                                            child: Text(
                                              isVisited
                                                  ? hasReport
                                                      ? 'Lihat Laporan'
                                                      : 'Lihat di Peta'
                                                  : 'Belum Dikunjungi',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text,
      {bool isDashed = false, bool isMarker = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMarker)
            Icon(Icons.location_on, color: color, size: 18)
          else
            Container(
              width: 20,
              height: 3,
              decoration: BoxDecoration(
                color: isDashed ? Colors.transparent : color,
              ),
              child: isDashed
                  ? CustomPaint(
                      painter: DashedLinePainter(color: color),
                    )
                  : null,
            ),
          const SizedBox(width: 6),
          Text(
            text,
            style: regularTextStyle(size: 12, color: neutral800),
          ),
        ],
      ),
    );
  }
}

// Custom painter for dashed lines
class DashedLinePainter extends CustomPainter {
  final Color color;

  DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashWidth = 5;
    const dashSpace = 3;
    double currentX = 0;

    while (currentX < size.width) {
      canvas.drawLine(
        Offset(currentX, size.height / 2),
        Offset(currentX + dashWidth, size.height / 2),
        paint,
      );
      currentX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
