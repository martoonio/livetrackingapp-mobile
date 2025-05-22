import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/domain/entities/report.dart';
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

  // Tambahkan variabel-variabel baru di _FullScreenMapPageState
  bool _showTimeline = false;
  List<Map<String, dynamic>> _sortedPatrolPoints = [];
  final ScrollController _timelineScrollController = ScrollController();
  List<Map<String, dynamic>> _assignedRoutePoints = [];
  Map<String, Map<String, dynamic>> _visitedPointsMap = {};

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

    _loadPatrolTimeline();
  }

  @override
  void dispose() {
    // Kembalikan status bar ke normal saat keluar halaman
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _mapController?.dispose();
    super.dispose();
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

    // Include actual route points if available
    if (widget.task.routePath != null) {
      final routePathMap = Map<String, dynamic>.from(widget.task.routePath!);
      for (var entry in routePathMap.entries) {
        final coordinates = entry.value['coordinates'] as List;
        final lat = coordinates[0] as double;
        final lng = coordinates[1] as double;

        minLat = (minLat > lat) ? lat : minLat;
        maxLat = (maxLat < lat) ? lat : maxLat;
        minLng = (minLng > lng) ? lng : minLng;
        maxLng = (maxLng < lng) ? lng : maxLng;
      }
    }

    try {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - 0.01, minLng - 0.01),
            northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
          ),
          50,
        ),
      );

      setState(() {
        _isMapReady = true;
      });
    } catch (e) {
      print('Error fitting map to route: $e');
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          const CameraPosition(
            target: LatLng(-6.927727934898599, 107.76911107969532),
            zoom: 12,
          ),
        ),
      );
    }
  }

  Future<void> _loadPatrolTimeline() async {
    if (widget.task.assignedRoute == null) return;

    try {
      final assignedPoints = <Map<String, dynamic>>[];
      final visitedPoints = <String, Map<String, dynamic>>{};

      // Load assigned route points
      for (int i = 0; i < widget.task.assignedRoute!.length; i++) {
        final coordinates = widget.task.assignedRoute![i];
        if (coordinates.length >= 2) {
          assignedPoints.add({
            'id': 'assigned-$i',
            'coordinates': coordinates,
            'isVisited': false,
            'visitInfo': null,
          });
        }
      }

      // Check which points were visited
      if (widget.task.routePath != null) {
        final routePathMap = Map<String, dynamic>.from(widget.task.routePath!);

        routePathMap.forEach((key, value) {
          if (value is Map &&
              value.containsKey('timestamp') &&
              value.containsKey('coordinates')) {
            final timestamp = value['timestamp'] as String?;
            final coordinates = value['coordinates'] as List?;

            if (timestamp != null &&
                coordinates != null &&
                coordinates.length >= 2) {
              // Find if this coordinates match with any assigned point
              for (int i = 0; i < assignedPoints.length; i++) {
                final assignedCoord = assignedPoints[i]['coordinates'] as List;

                // Check if coordinates are close enough (within 50 meters)
                final distance = _calculateDistance(
                    (assignedCoord[0] as double),
                    (assignedCoord[1] as double),
                    (coordinates[0] as double),
                    (coordinates[1] as double));

                if (distance <= 5) {
                  // 50 meter threshold
                  assignedPoints[i]['isVisited'] = true;
                  assignedPoints[i]['visitInfo'] = {
                    'timestamp': timestamp,
                    'exactCoordinates': coordinates,
                    'reportId': value['reportId'],
                    'distance': distance,
                  };

                  // Also store in visitedPoints for quick lookup
                  final pointId = 'assigned-$i';
                  visitedPoints[pointId] = {
                    'timestamp': timestamp,
                    'coordinates': coordinates,
                    'reportId': value['reportId'],
                    'distance': value['distance'],
                  };

                  break;
                }
              }
            }
          }
        });
      }

      setState(() {
        _assignedRoutePoints = assignedPoints;
        _visitedPointsMap = visitedPoints;
      });
    } catch (e) {
      print('Error loading patrol timeline: $e');
    }
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

  // Tambahkan metode untuk menampilkan InfoWindow di titik yang dipilih
  void _showInfoWindowAt(List<dynamic> coordinates, String pointId) {
    if (_mapController == null || coordinates.length < 2) return;

    // Temukan marker yang sesuai dengan koordinat
    // Atau tambahkan marker baru dengan InfoWindow jika tidak ditemukan
    final markerId = MarkerId('selected-$pointId');
    final marker = Marker(
      markerId: markerId,
      position: LatLng(
        (coordinates[0] as num).toDouble(),
        (coordinates[1] as num).toDouble(),
      ),
      infoWindow: InfoWindow(
        title: 'Titik Patroli',
        snippet: 'Dikunjungi pada ${_formatTimestamp(pointId)}',
      ),
    );

    setState(() {
      _markers.removeWhere((m) => m.markerId.value.startsWith('selected-'));
      _markers.add(marker);
    });

    // Tampilkan InfoWindow
    Future.delayed(const Duration(milliseconds: 300), () {
      _mapController?.showMarkerInfoWindow(markerId);
    });
  }

  // Helper untuk format timestamp
  String _formatTimestamp(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      return '${dateFormatter.format(dateTime)} ${timeFormatter.format(dateTime)}';
    } catch (e) {
      return timestamp;
    }
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
          if (!_isMapReady)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

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
