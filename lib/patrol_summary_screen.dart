import 'dart:math' as math;
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:livetrackingapp/domain/entities/report.dart';
import 'package:livetrackingapp/main_nav_screen.dart';
import '../../domain/entities/patrol_task.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';

class PatrolSummaryScreen extends StatefulWidget {
  final PatrolTask task;
  final List<List<double>> routePath;
  final DateTime startTime;
  final DateTime endTime;
  final double distance;
  String? finalReportPhotoUrl;
  String? initialReportPhotoUrl;

  PatrolSummaryScreen({
    super.key,
    required this.task,
    required this.routePath,
    required this.startTime,
    required this.endTime,
    required this.distance,
    this.finalReportPhotoUrl,
    this.initialReportPhotoUrl,
  });

  @override
  State<PatrolSummaryScreen> createState() => _PatrolSummaryScreenState();
}

class _PatrolSummaryScreenState extends State<PatrolSummaryScreen> {
  GoogleMapController? mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  // Tambahkan variabel untuk menyimpan data reports
  List<Report> _reports = [];
  bool _isLoadingReports = true;
  Map<String, Marker> _reportMarkers = {};

  static const _defaultCenter = LatLng(-6.927727934898599, 107.76911107969532);

  @override
  void initState() {
    super.initState();
    _initializeMap();
    _loadOfficerName();
    _loadPatrolReports();
    print('route path isinya apa? ${widget.routePath}');
    print('init final foto isinya apa? ${widget.task.finalReportPhotoUrl}');
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
    setState(() {});
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
    return '${hours}j ${minutes}m';
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _loadPatrolReports() async {
    setState(() {
      _isLoadingReports = true;
    });

    try {
      // Query Firebase untuk reports dengan taskId yang sesuai
      final snapshot = await FirebaseDatabase.instance
          .ref('reports')
          .orderByChild('taskId')
          .equalTo(widget.task.taskId)
          .get();

      if (snapshot.exists) {
        final reportsData = snapshot.value as Map<dynamic, dynamic>;
        final reports = <Report>[];

        reportsData.forEach((key, value) {
          if (value is Map) {
            reports.add(Report.fromJson(
                key.toString(), Map<String, dynamic>.from(value)));
          }
        });

        // Sort reports by timestamp
        reports.sort((a, b) => a.timestamp.compareTo(b.timestamp));

        setState(() {
          _reports = reports;

          // Create markers for each report
          _reportMarkers = {};
          for (var i = 0; i < reports.length; i++) {
            final report = reports[i];
            _reportMarkers[report.id] = Marker(
              markerId: MarkerId('report_${report.id}'),
              position: LatLng(report.latitude, report.longitude),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueBlue),
              infoWindow: InfoWindow(
                title: report.title,
                snippet: report.description,
              ),
              onTap: () {
                _showReportDetails(report);
              },
            );
          }
        });
      }
    } catch (e) {
      print('Error loading patrol reports: $e');
    } finally {
      setState(() {
        _isLoadingReports = false;
      });
    }
  }

  // Method untuk menampilkan detail report dalam bottom sheet
  void _showReportDetails(Report report) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Report Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kbpBlue100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.report_problem,
                      color: kbpBlue900,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.title,
                          style: boldTextStyle(size: 16),
                        ),
                        Text(
                          _formatDateTime(report.timestamp),
                          style: regularTextStyle(size: 12, color: neutral600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Report Photo
              if (report.photoUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    report.photoUrl,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 200,
                        color: neutral200,
                        child: const Center(
                          child: Icon(Icons.broken_image,
                              color: neutral500, size: 40),
                        ),
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        height: 200,
                        color: neutral200,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 16),

              // Report Description
              Text(
                'Deskripsi',
                style: semiBoldTextStyle(size: 14),
              ),
              const SizedBox(height: 4),
              Text(
                report.description,
                style: regularTextStyle(size: 14),
              ),

              const SizedBox(height: 16),

              // Report Location
              Text(
                'Lokasi',
                style: semiBoldTextStyle(size: 14),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: kbpBlue700),
                  const SizedBox(width: 4),
                  Text(
                    '${report.latitude.toStringAsFixed(6)}, ${report.longitude.toStringAsFixed(6)}',
                    style: regularTextStyle(size: 14),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // View on Map Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Lihat di Peta'),
                  onPressed: () {
                    Navigator.pop(context);

                    // Animasikan peta ke posisi report
                    mapController?.animateCamera(
                      CameraUpdate.newLatLngZoom(
                        LatLng(report.latitude, report.longitude),
                        18,
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kbpBlue900,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: kbpBlue900),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // Tambahkan variabel untuk controller peta
  GoogleMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neutral200,
      appBar: AppBar(
        title: Text(
          'Ringkasan Patroli',
          style: semiBoldTextStyle(size: 18, color: kbpBlue900),
        ),
        backgroundColor: neutralWhite,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  // Widget _buildBody() {
  //   return Column(
  //     children: [
  //       Expanded(
  //         child: SingleChildScrollView(
  //           physics: const BouncingScrollPhysics(),
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               // Map card
  //               _buildMapCard(),

  //               // Reports section
  //               _buildReportsSection(),

  //               // Tampilkan foto final report jika ada
  //               if (widget.finalReportPhotoUrl != null)
  //                 _buildFinalReportPhotoCard(),

  //               // Summary cards
  //               Padding(
  //                 padding: const EdgeInsets.all(16.0),
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     // Officer info card
  //                     _buildOfficerInfoCard(),

  //                     const SizedBox(height: 16),

  //                     // Time info card
  //                     _buildTimeInfoCard(),

  //                     const SizedBox(height: 16),

  //                     // Distance info card
  //                     _buildDistanceInfoCard(),
  //                   ],
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //       ),

  //       // Bottom button
  //       Container(
  //         padding: const EdgeInsets.all(16),
  //         decoration: BoxDecoration(
  //           color: Colors.white,
  //           boxShadow: [
  //             BoxShadow(
  //               color: Colors.black.withOpacity(0.1),
  //               blurRadius: 4,
  //               offset: const Offset(0, -2),
  //             ),
  //           ],
  //         ),
  //         child: SafeArea(
  //           child: SizedBox(
  //             width: double.infinity,
  //             child: ElevatedButton(
  //               onPressed: () async {
  //                 final userRole = await _getUserRole();
  //                 Navigator.pushReplacement(
  //                   context,
  //                   MaterialPageRoute(
  //                     builder: (context) => MainNavigationScreen(
  //                       userRole: userRole ?? 'User',
  //                     ),
  //                   ),
  //                 );
  //               },
  //               style: ElevatedButton.styleFrom(
  //                 backgroundColor: kbpBlue800,
  //                 foregroundColor: Colors.white,
  //                 padding: const EdgeInsets.symmetric(vertical: 14),
  //                 shape: RoundedRectangleBorder(
  //                   borderRadius: BorderRadius.circular(8),
  //                 ),
  //                 elevation: 0,
  //               ),
  //               child: Text(
  //                 'Kembali ke Beranda',
  //                 style: semiBoldTextStyle(color: Colors.white, size: 16),
  //               ),
  //             ),
  //           ),
  //         ),
  //       ),
  //     ],
  //   );
  // }

  Widget _buildMapCard() {
    final List<Marker> markers = [];

    // Tambahkan marker untuk titik pertama rute
    if (widget.routePath.isNotEmpty) {
      markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: LatLng(
            widget.routePath.first[0],
            widget.routePath.first[1],
          ),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(
            title: 'Titik Mulai',
          ),
        ),
      );

      // Tambahkan marker untuk titik terakhir rute
      markers.add(
        Marker(
          markerId: const MarkerId('end'),
          position: LatLng(
            widget.routePath.last[0],
            widget.routePath.last[1],
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(
            title: 'Titik Akhir',
          ),
        ),
      );
    }

    // Tambahkan marker untuk semua reports
    markers.addAll(_reportMarkers.values);

    // Buat polyline dari routePath
    final List<LatLng> polylineCoordinates =
        widget.routePath.map((point) => LatLng(point[0], point[1])).toList();

    final Set<Polyline> polylines = {
      Polyline(
        polylineId: const PolylineId('route'),
        points: polylineCoordinates,
        color: kbpBlue700,
        width: 5,
      ),
    };

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.map, color: kbpBlue900),
                const SizedBox(width: 8),
                Text(
                  'Rute Patroli',
                  style: semiBoldTextStyle(size: 16),
                ),
                const Spacer(),
                // Badge untuk reports
                if (_reports.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: kbpBlue100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.report_problem,
                            size: 14, color: kbpBlue900),
                        const SizedBox(width: 4),
                        Text(
                          '${_reports.length} Laporan',
                          style: mediumTextStyle(size: 12, color: kbpBlue900),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            height: 300,
            margin: const EdgeInsets.only(bottom: 16),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
              child: polylineCoordinates.isEmpty
                  ? const Center(child: Text('Tidak ada data rute'))
                  : GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: polylineCoordinates[0],
                        zoom: 15,
                      ),
                      markers: Set<Marker>.from(markers),
                      polylines: polylines,
                      myLocationEnabled: false,
                      zoomControlsEnabled: true,
                      mapType: MapType.normal,
                      onMapCreated: (controller) {
                        _mapController = controller;

                        // Atur batas peta agar semua rute terlihat
                        if (polylineCoordinates.isNotEmpty) {
                          controller.animateCamera(
                            CameraUpdate.newLatLngBounds(
                              _getBounds(polylineCoordinates),
                              50,
                            ),
                          );
                        }
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Add section for Reports
  Widget _buildReportsSection() {
    if (_isLoadingReports) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Column(
            children: [
              const CircularProgressIndicator(color: kbpBlue700),
              const SizedBox(height: 16),
              Text(
                'Memuat laporan patroli...',
                style: regularTextStyle(size: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_reports.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.report_problem, color: kbpBlue900),
                const SizedBox(width: 8),
                Text(
                  'Laporan Patroli',
                  style: semiBoldTextStyle(size: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: neutral300,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 32,
                    color: neutral500,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tidak ada laporan selama patroli ini',
                    style: regularTextStyle(color: neutral600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.report_problem, color: kbpBlue900),
                const SizedBox(width: 8),
                Text(
                  'Laporan Patroli',
                  style: semiBoldTextStyle(size: 16),
                ),
                const Spacer(),
                Text(
                  '${_reports.length} Laporan',
                  style: mediumTextStyle(size: 12, color: kbpBlue700),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _reports.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final report = _reports[index];
              return InkWell(
                onTap: () => _showReportDetails(report),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Report photo preview
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: report.photoUrl.isNotEmpty
                            ? Image.network(
                                report.photoUrl,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 80,
                                    height: 80,
                                    color: neutral200,
                                    child: const Icon(Icons.image_not_supported,
                                        color: neutral500),
                                  );
                                },
                              )
                            : Container(
                                width: 80,
                                height: 80,
                                color: neutral200,
                                child: const Icon(Icons.image_not_supported,
                                    color: neutral500),
                              ),
                      ),
                      const SizedBox(width: 12),

                      // Report details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              report.title,
                              style: semiBoldTextStyle(size: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              report.description,
                              style:
                                  regularTextStyle(size: 12, color: neutral700),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.access_time,
                                    size: 12, color: neutral500),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDateTime(report.timestamp),
                                  style: regularTextStyle(
                                      size: 12, color: neutral500),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Arrow icon
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: neutral500,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Ubah _buildBody untuk menyertakan _buildReportsSection
  Widget _buildBody() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Map card
                _buildMapCard(),

                // Reports section
                _buildReportsSection(),

                // Tampilkan foto final report jika ada
                if (widget.finalReportPhotoUrl != null)
                  _buildFinalReportPhotoCard(),
                8.height,

                if (widget.task.initialReportPhotoUrl != null)
                  _buildInitialReportSection(),

                // Summary cards
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Officer info card
                      _buildOfficerInfoCard(),

                      const SizedBox(height: 16),

                      // Time info card
                      _buildTimeInfoCard(),

                      const SizedBox(height: 16),

                      // Distance info card
                      _buildDistanceInfoCard(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bottom button
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final userRole = await _getUserRole();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MainNavigationScreen(
                        userRole: userRole ?? 'User',
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kbpBlue800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Kembali ke Beranda',
                  style: semiBoldTextStyle(color: Colors.white, size: 16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Helper untuk mendapatkan batas peta
  LatLngBounds _getBounds(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      northeast: LatLng(maxLat, maxLng),
      southwest: LatLng(minLat, minLng),
    );
  }

  Widget _buildOfficerInfoCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kbpBlue200, width: 1),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: kbpBlue900, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Informasi Petugas',
                  style: semiBoldTextStyle(size: 16, color: kbpBlue900),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    'Nama Petugas',
                    widget.task.officerName ?? 'Tidak diketahui',
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    'ID Kendaraan',
                    widget.task.vehicleId.isEmpty
                        ? 'Tidak ada'
                        : widget.task.vehicleId,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Perbaikan tampilan untuk laporan awal patroli
  Widget _buildInitialReportSection() {
    if (widget.task.initialReportPhotoUrl == null) {
      return SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.photo_camera, color: kbpBlue900, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Foto Awal Patroli',
                        style: semiBoldTextStyle(size: 16, color: kbpBlue900),
                      ),
                      if (widget.task.initialReportTime != null)
                        Text(
                          'Diambil pada ${_formatDateTime(widget.task.initialReportTime!)}',
                          style: regularTextStyle(size: 12, color: neutral600),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Foto
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            child: _buildInitialReportImage(),
          ),

          // Tampilkan catatan jika ada
          if (widget.task.initialReportNote != null &&
              widget.task.initialReportNote!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Catatan Awal:',
                    style: mediumTextStyle(size: 14, color: neutral700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.task.initialReportNote!,
                    style: regularTextStyle(size: 14, color: neutral800),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

// Helper untuk menampilkan gambar laporan awal
  Widget _buildInitialReportImage() {
    if (widget.task.initialReportPhotoUrl == null) {
      return Container(
        height: 200,
        color: neutral200,
        child: const Center(
          child: Icon(Icons.image_not_supported, color: neutral500, size: 40),
        ),
      );
    }

    // Cek apakah URL atau path file lokal
    if (widget.task.initialReportPhotoUrl!.startsWith('http')) {
      // URL gambar
      return Image.network(
        widget.task.initialReportPhotoUrl!,
        height: 300,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('Error loading image: $error');
          return Container(
            height: 200,
            color: neutral200,
            child: const Center(
              child: Icon(Icons.broken_image, color: dangerR300, size: 40),
            ),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            height: 200,
            color: neutral200,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
                color: kbpBlue700,
              ),
            ),
          );
        },
      );
    } else {
      // Path file lokal
      return Image.file(
        File(widget.task.initialReportPhotoUrl!),
        height: 300,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('Error loading local image: $error');
          return Container(
            height: 200,
            color: neutral200,
            child: const Center(
              child: Icon(Icons.broken_image, color: dangerR300, size: 40),
            ),
          );
        },
      );
    }
  }

  Widget _buildTimeInfoCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kbpBlue200, width: 1),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time, color: kbpBlue900, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Waktu Patroli',
                  style: semiBoldTextStyle(size: 16, color: kbpBlue900),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildInfoItem(
                    'Mulai',
                    _formatDateTime(widget.startTime),
                  ),
                ),
                Expanded(
                  child: _buildInfoItem(
                    'Selesai',
                    _formatDateTime(widget.endTime),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoItem(
              'Durasi',
              _formatDuration(widget.startTime, widget.endTime),
              valueColor: kbpBlue900,
              valueSize: 18,
              valueBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDistanceInfoCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kbpBlue200, width: 1),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions, color: kbpBlue900, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Jarak Tempuh',
                  style: semiBoldTextStyle(size: 16, color: kbpBlue900),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${(widget.distance / 1000).toStringAsFixed(2)} km',
                  style: semiBoldTextStyle(size: 24, color: kbpBlue900),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(
    String label,
    String value, {
    Color? valueColor,
    double valueSize = 14,
    bool valueBold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: regularTextStyle(size: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: valueBold
              ? semiBoldTextStyle(size: valueSize, color: valueColor)
              : regularTextStyle(size: valueSize, color: valueColor),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  @override
  void dispose() {
    mapController?.dispose();
    super.dispose();
  }

  // Tambahkan fungsi baru untuk menampilkan foto final report
  Widget _buildFinalReportPhotoCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.photo_camera, color: kbpBlue900, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Foto Akhir Patroli',
                        style: semiBoldTextStyle(size: 16, color: kbpBlue900),
                      ),
                      if (widget.task.finalReportTime != null)
                        Text(
                          'Diambil pada ${_formatDateTime(widget.task.finalReportTime!)}',
                          style: regularTextStyle(size: 12, color: neutral600),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Foto
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            child: _buildFinalReportImage(),
          ),

          // Tampilkan catatan jika ada
          if (widget.task.finalReportNote != null &&
              widget.task.finalReportNote!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Catatan Petugas:',
                    style: mediumTextStyle(size: 14, color: neutral700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.task.finalReportNote!,
                    style: regularTextStyle(size: 14, color: neutral800),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Helper untuk menampilkan gambar berdasarkan sumbernya (URL atau File lokal)
  Widget _buildFinalReportImage() {
    if (widget.finalReportPhotoUrl == null) {
      return Container(
        height: 200,
        color: neutral200,
        child: const Center(
          child: Icon(Icons.image_not_supported, color: neutral500, size: 40),
        ),
      );
    }

    // Cek apakah URL atau path file lokal
    if (widget.finalReportPhotoUrl!.startsWith('http')) {
      // URL gambar
      return Image.network(
        widget.finalReportPhotoUrl!,
        height: 300,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('Error loading image: $error');
          return Container(
            height: 200,
            color: neutral200,
            child: const Center(
              child: Icon(Icons.broken_image, color: dangerR300, size: 40),
            ),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            height: 200,
            color: neutral200,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
                color: kbpBlue700,
              ),
            ),
          );
        },
      );
    } else {
      // Path file lokal
      return Image.file(
        File(widget.finalReportPhotoUrl!),
        height: 300,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          print('Error loading local image: $error');
          return Container(
            height: 200,
            color: neutral200,
            child: const Center(
              child: Icon(Icons.broken_image, color: dangerR300, size: 40),
            ),
          );
        },
      );
    }
  }
}
