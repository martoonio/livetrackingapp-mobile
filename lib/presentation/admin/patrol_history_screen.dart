import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:livetrackingapp/domain/entities/patrol_task.dart';
import 'package:livetrackingapp/domain/entities/report.dart';
import 'package:livetrackingapp/presentation/admin/full_screen_map.dart';
import 'package:livetrackingapp/presentation/component/photo_gallery_fullscreen.dart';
import 'package:livetrackingapp/presentation/component/utils.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as Math;
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:dots_indicator/dots_indicator.dart';

class PatrolHistoryScreen extends StatefulWidget {
  final PatrolTask task;

  const PatrolHistoryScreen({
    super.key,
    required this.task,
  });

  @override
  State<PatrolHistoryScreen> createState() => _PatrolHistoryScreenState();
}

class _PatrolHistoryScreenState extends State<PatrolHistoryScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final dateFormatter = DateFormat('dd MMM yyyy', 'id_ID');
  final timeFormatter = DateFormat('HH:mm', 'id_ID');

  TabController? _tabController;
  bool _isMapReady = false;

  // Tambahkan variabel reports
  List<Report> _reports = [];
  bool _isLoadingReports = true;

  // Di dalam _PatrolHistoryScreenState
  String? _finalReportPhotoUrl;
  String? _initialReportPhotoUrl;

  bool _isLoadingMockData = false;

  bool _isMapExpanded = false;

  // TAMBAHAN BARU: Variabel untuk menyimpan validation radius cluster
  double? _clusterValidationRadius;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Setel finalReportPhotoUrl awal jika ada
    _finalReportPhotoUrl = widget.task.finalReportPhotoUrl;
    _initialReportPhotoUrl = widget.task.initialReportPhotoUrl;

    // Load data secara berurutan
    _initializeData();
  }

  // PERBAIKAN: Method baru untuk inisialisasi data secara berurutan
  Future<void> _initializeData() async {
    try {
      // 1. Load cluster validation radius terlebih dahulu
      await _loadClusterValidationRadius();

      // 2. Load reports terlebih dahulu
      await _loadReports();

      // 3. Load photo URLs jika diperlukan
      if (_finalReportPhotoUrl == null || _finalReportPhotoUrl!.isEmpty) {
        await _loadFinalReportPhoto();
      }

      if (_initialReportPhotoUrl == null || _initialReportPhotoUrl!.isEmpty) {
        await _loadInitialReportPhoto();
      }

      // 4. Prepare route dan markers dengan data yang sudah lengkap
      _prepareRouteAndMarkers();

      print('DEBUG: Data initialization completed');
      print('DEBUG: Reports loaded: ${_reports.length}');
      print('DEBUG: Cluster validation radius: ${_clusterValidationRadius}m');

      final visitData = _calculateVisitedPoints();
      print(
          'DEBUG: Visited checkpoints: ${visitData['visitedCount']}/${visitData['totalCount']}');
    } catch (e) {
      print('Error initializing data: $e');
    }
  }

  // TAMBAHAN BARU: Method untuk load validation radius dari cluster
  Future<void> _loadClusterValidationRadius() async {
    try {
      if (widget.task.clusterId.isEmpty) {
        print('ClusterId is empty, using default radius');
        _clusterValidationRadius = 50.0;
        return;
      }

      final snapshot = await FirebaseDatabase.instance
          .ref('users')
          .child(widget.task.clusterId)
          .child('checkpoint_validation_radius')
          .get();

      if (snapshot.exists && snapshot.value != null) {
        _clusterValidationRadius = (snapshot.value as num).toDouble();
        print('Loaded cluster validation radius: ${_clusterValidationRadius}m');
      } else {
        _clusterValidationRadius = 50.0; // Default fallback
        print('No cluster validation radius found, using default: 50m');
      }
    } catch (e) {
      print('Error loading cluster validation radius: $e');
      _clusterValidationRadius = 50.0; // Default fallback
    }
  }

  Future<void> _loadInitialReportPhoto() async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('tasks')
          .child(widget.task.taskId)
          .child('initialReportPhotoUrl')
          .get();

      if (snapshot.exists && snapshot.value != null) {
        setState(() {
          _initialReportPhotoUrl = snapshot.value as String;
          // Update juga di objek task
          widget.task.initialReportPhotoUrl = _initialReportPhotoUrl;
        });
      }
    } catch (e) {
      print('Error loading initial report photo URL: $e');
    }
  }

  Future<void> _loadFinalReportPhoto() async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('tasks')
          .child(widget.task.taskId)
          .child('finalReportPhotoUrl')
          .get();

      if (snapshot.exists && snapshot.value != null) {
        setState(() {
          _finalReportPhotoUrl = snapshot.value as String;
          // Update juga di objek task
          widget.task.finalReportPhotoUrl = _finalReportPhotoUrl;
        });
      }
    } catch (e) {
      print('Error loading final report photo URL: $e');
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // PERBAIKAN: Update method _addAssignedRouteMarkers() agar sinkron dengan _calculateVisitedPoints()
  void _addAssignedRouteMarkers() {
    if (widget.task.assignedRoute == null) return;

    // PERBAIKAN: Gunakan method _calculateVisitedPoints() yang sudah diperbaiki
    final visitData = _calculateVisitedPoints();
    final Set<int> visitedCheckpoints =
        visitData['visitedCheckpoints'] as Set<int>;
    final double radiusUsed = visitData['radiusUsed'] as double;

    // Tambahkan marker untuk setiap checkpoint dengan warna yang sesuai
    for (int i = 0; i < widget.task.assignedRoute!.length; i++) {
      final coord = widget.task.assignedRoute![i];
      final bool isVisited = visitedCheckpoints.contains(i);

      _markers.add(
        Marker(
          markerId: MarkerId('checkpoint-$i'),
          position: LatLng(coord[0], coord[1]),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              isVisited ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'Checkpoint ${i + 1}',
            snippet: isVisited
                ? 'Dikunjungi (dalam radius ${radiusUsed.toStringAsFixed(0)}m)'
                : 'Belum dikunjungi',
          ),
        ),
      );
    }

    // Log untuk debugging
    print('DEBUG: Total checkpoints: ${widget.task.assignedRoute!.length}');
    print('DEBUG: Visited checkpoints: ${visitedCheckpoints.length}');
    print('DEBUG: Visited checkpoint indices: $visitedCheckpoints');
    print('DEBUG: Radius used: ${radiusUsed}m');
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
        color: kbpBlue700,
        width: 5,
      ),
    );

    // Tambahkan marker untuk start dan end point jika ada
    if (points.isNotEmpty) {
      _markers.add(
        Marker(
          markerId: const MarkerId('start_point'),
          position: points.first,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(
            title: 'Titik Mulai',
            snippet: 'Petugas memulai patroli di sini',
          ),
        ),
      );

      // _markers.add(
      //   Marker(
      //     markerId: const MarkerId('end_point'),
      //     position: points.last,
      //     icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      //     infoWindow: const InfoWindow(
      //       title: 'Titik Akhir',
      //       snippet: 'Petugas mengakhiri patroli di sini',
      //     ),
      //   ),
      // );
    }
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

    // Ensure bounds are valid and add padding
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
      // Fallback to default view if bounds calculation fails
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

  // Fungsi untuk memuat laporan
  Future<void> _loadReports() async {
    try {
      setState(() {
        _isLoadingReports = true;
      });

      final snapshot = await FirebaseDatabase.instance
          .ref('reports')
          .orderByChild('taskId')
          .equalTo(widget.task.taskId)
          .get();

      final List<Report> reports = [];

      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        data.forEach((key, value) {
          if (value is Map) {
            reports.add(Report.fromJson(
              key.toString(),
              Map<String, dynamic>.from(value),
            ));
          }
        });

        // Sort reports by timestamp
        reports.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }

      setState(() {
        _reports = reports;
        _isLoadingReports = false;
      });

      // PERBAIKAN: Refresh markers setelah reports loaded
      _refreshMapMarkers();
    } catch (e) {
      print('Error loading reports: $e');
      setState(() {
        _isLoadingReports = false;
      });
    }
  }

  // Tambahkan method untuk menambahkan marker laporan
  void _addReportMarkers() {
    // Clear existing report markers
    _markers
        .removeWhere((marker) => marker.markerId.value.startsWith('report-'));

    for (var i = 0; i < _reports.length; i++) {
      final report = _reports[i];

      _markers.add(
        Marker(
          markerId: MarkerId('report-${report.id}'),
          position: LatLng(report.latitude, report.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: 'Laporan: ${report.title}',
            snippet: 'Klik untuk melihat detail',
            onTap: () {
              _showReportDetail(report);
            },
          ),
        ),
      );
    }

    setState(() {});
  }

  void _prepareRouteAndMarkers() {
    try {
      // Clear existing markers dan polylines
      _markers.clear();
      _polylines.clear();

      // Add assigned route markers and polyline
      if (widget.task.assignedRoute != null) {
        _addAssignedRouteMarkers();
        _addAssignedRoutePolyline();
      }

      // Add actual route path if completed
      if (widget.task.routePath != null) {
        _addActualRoutePath();
      }

      // Add mock location markers
      if (widget.task.mockLocationDetected == true) {
        _addMockLocationMarkers();
      }

      // Add report markers (jika sudah loaded)
      if (_reports.isNotEmpty) {
        _addReportMarkers();
      }

      setState(() {});
    } catch (e) {
      print('Error preparing route and markers: $e');
    }
  }

  // PERBAIKAN: Method baru untuk refresh semua markers
  void _refreshMapMarkers() {
    // Clear existing markers kecuali yang diperlukan
    _markers.removeWhere((marker) =>
        marker.markerId.value.startsWith('checkpoint-') ||
        marker.markerId.value.startsWith('report-'));

    // Re-add checkpoint markers dengan status terbaru
    if (widget.task.assignedRoute != null) {
      _addAssignedRouteMarkers();
    }

    // Re-add report markers
    if (_reports.isNotEmpty) {
      _addReportMarkers();
    }

    setState(() {});
  }

  // Tambahkan method untuk menambahkan marker laporan

  void _showReportDetail(Report report) {
    // Parse multiple photo URLs
    final List<String> photoUrls =
        report.photoUrl.isNotEmpty ? report.photoUrl.split(',') : [];

    // Current photo index untuk carousel
    int currentPhotoIndex = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(16),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Detail Laporan',
                        style: boldTextStyle(size: 18),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Judul laporan
                          Text(
                            report.title,
                            style: boldTextStyle(size: 16),
                          ),
                          const SizedBox(height: 8),

                          // Waktu laporan
                          Row(
                            children: [
                              const Icon(Icons.access_time,
                                  size: 16, color: neutral500),
                              const SizedBox(width: 4),
                              Text(
                                '${dateFormatter.format(report.timestamp)} ${timeFormatter.format(report.timestamp)}',
                                style: regularTextStyle(
                                    size: 14, color: neutral600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Foto laporan dengan carousel jika ada multiple photos
                          if (photoUrls.isNotEmpty)
                            Column(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    // Navigate to full screen gallery view
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PhotoGalleryScreen(
                                          title: 'Foto Laporan',
                                          photoUrls: photoUrls,
                                          initialIndex: currentPhotoIndex,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: neutral300, width: 1),
                                    ),
                                    child: Column(
                                      children: [
                                        // Photo carousel
                                        CarouselSlider(
                                          options: CarouselOptions(
                                            height: 240.0,
                                            viewportFraction: 1.0,
                                            enlargeCenterPage: false,
                                            enableInfiniteScroll:
                                                photoUrls.length > 1,
                                            onPageChanged: (index, reason) {
                                              setState(() {
                                                currentPhotoIndex = index;
                                              });
                                            },
                                          ),
                                          items: photoUrls.map((url) {
                                            return Builder(
                                              builder: (BuildContext context) {
                                                return ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  child: Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      Image.network(
                                                        url.trim(),
                                                        fit: BoxFit.cover,
                                                        loadingBuilder: (context,
                                                            child,
                                                            loadingProgress) {
                                                          if (loadingProgress ==
                                                              null)
                                                            return child;
                                                          return Container(
                                                            color: neutral200,
                                                            child: Center(
                                                              child:
                                                                  CircularProgressIndicator(
                                                                value: loadingProgress
                                                                            .expectedTotalBytes !=
                                                                        null
                                                                    ? loadingProgress
                                                                            .cumulativeBytesLoaded /
                                                                        loadingProgress
                                                                            .expectedTotalBytes!
                                                                    : null,
                                                                color:
                                                                    kbpBlue700,
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                        errorBuilder: (context,
                                                            error, stackTrace) {
                                                          return Container(
                                                            color: neutral200,
                                                            child: Center(
                                                              child: Column(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Icon(
                                                                      Icons
                                                                          .broken_image,
                                                                      size: 48,
                                                                      color:
                                                                          neutral500),
                                                                  const SizedBox(
                                                                      height:
                                                                          8),
                                                                  Text(
                                                                    'Gagal memuat gambar',
                                                                    style: mediumTextStyle(
                                                                        color:
                                                                            neutral600),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      ),

                                                      // Overlay untuk menampilkan ikon zoom
                                                      Positioned(
                                                        right: 12,
                                                        bottom: 12,
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(8),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: Colors.black
                                                                .withOpacity(
                                                                    0.6),
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                          child: const Icon(
                                                            Icons.zoom_in,
                                                            color: Colors.white,
                                                            size: 24,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            );
                                          }).toList(),
                                        ),

                                        // Indicator dots untuk multiple photos
                                        if (photoUrls.length > 1)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8),
                                            child: DotsIndicator(
                                              dotsCount: photoUrls.length,
                                              position:
                                                  currentPhotoIndex.toDouble(),
                                              decorator: DotsDecorator(
                                                activeColor: kbpBlue900,
                                                color: neutral300,
                                                size: const Size(8, 8),
                                                activeSize: const Size(10, 10),
                                                spacing:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4),
                                              ),
                                            ),
                                          ),

                                        // Counter text + lihat semua
                                        if (photoUrls.length > 1)
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                12, 0, 12, 8),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  'Foto ${currentPhotoIndex + 1} dari ${photoUrls.length}',
                                                  style: regularTextStyle(
                                                      size: 13,
                                                      color: neutral600),
                                                ),
                                                Text(
                                                  'Lihat semua foto',
                                                  style: semiBoldTextStyle(
                                                    size: 13,
                                                    color: kbpBlue900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Container(
                              height: 200,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: neutral200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.image_not_supported,
                                        size: 48, color: neutral500),
                                    SizedBox(height: 8),
                                    Text('Tidak ada foto'),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),

                          // Deskripsi
                          Text(
                            'Deskripsi',
                            style: semiBoldTextStyle(size: 16),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            report.description,
                            style: regularTextStyle(size: 14),
                          ),
                          const SizedBox(height: 16),

                          // Lokasi
                          Text(
                            'Lokasi',
                            style: semiBoldTextStyle(size: 16),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.location_on,
                                  size: 16, color: kbpBlue700),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${report.latitude.toStringAsFixed(6)}, ${report.longitude.toStringAsFixed(6)}',
                                  style: regularTextStyle(size: 14),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.map_outlined,
                                    color: kbpBlue700),
                                onPressed: () async {
                                  // Tutup dialog detail laporan dulu
                                  Navigator.pop(context);

                                  // Pindah ke tab peta (tab index 0)
                                  _tabController!.animateTo(0);

                                  // Tunggu sebentar agar UI terupdate
                                  await Future.delayed(
                                      const Duration(milliseconds: 300));

                                  // Zoom ke lokasi laporan
                                  _mapController?.animateCamera(
                                    CameraUpdate.newLatLngZoom(
                                      LatLng(report.latitude, report.longitude),
                                      18, // Zoom level yang cukup detail
                                    ),
                                  );

                                  // Opsional: tampilkan snackbar sebagai feedback
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Menampilkan lokasi laporan di peta',
                                        style: mediumTextStyle(
                                            color: Colors.white),
                                      ),
                                      backgroundColor: kbpBlue900,
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                tooltip: 'Lihat di Peta Patroli',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Button to view on map
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.map),
                      label: const Text('Tampilkan di Peta'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kbpBlue900,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);

                        // Pindah ke tab peta dan zoom ke posisi laporan
                        _tabController!.animateTo(0); // Tab peta adalah index 0

                        // Zoom ke lokasi laporan
                        _mapController
                            ?.animateCamera(CameraUpdate.newLatLngZoom(
                          LatLng(report.latitude, report.longitude),
                          18,
                        ));
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Tambahkan widget untuk menampilkan laporan
  Widget _buildReportsView() {
    if (_isLoadingReports) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: kbpBlue700),
            SizedBox(height: 16),
            Text('Memuat data laporan...'),
          ],
        ),
      );
    }

    if (_reports.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.report_off, size: 64, color: neutral400),
            const SizedBox(height: 16),
            Text(
              'Tidak ada laporan untuk patroli ini',
              style: mediumTextStyle(size: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Petugas tidak mengirimkan laporan selama patroli berlangsung',
              style: regularTextStyle(size: 14, color: neutral600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _reports.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final report = _reports[index];

        // Parse multiple photo URLs
        final List<String> photoUrls =
            report.photoUrl.isNotEmpty ? report.photoUrl.split(',') : [];

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          child: InkWell(
            onTap: () => _showReportDetail(report),
            borderRadius: BorderRadius.circular(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header dengan judul dan timestamp
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kbpBlue100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.report_problem,
                          color: kbpBlue900,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              report.title,
                              style: semiBoldTextStyle(size: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${dateFormatter.format(report.timestamp)} ${timeFormatter.format(report.timestamp)}',
                              style:
                                  regularTextStyle(size: 12, color: neutral600),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios,
                          size: 16, color: neutral500),
                    ],
                  ),
                ),

                // Gambar laporan
                if (photoUrls.isNotEmpty)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                        child: Image.network(
                          photoUrls.first.trim(), // Show first image in list
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 180,
                              color: neutral200,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes !=
                                          null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 180,
                              color: neutral200,
                              child: const Center(
                                child: Icon(Icons.broken_image,
                                    size: 48, color: neutral500),
                              ),
                            );
                          },
                        ),
                      ),

                      // Photo count badge if multiple photos
                      if (photoUrls.length > 1)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.photo_library,
                                    color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  '${photoUrls.length}',
                                  style: mediumTextStyle(
                                      size: 12, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),

                // Deskripsi jika tidak ada foto
                if (photoUrls.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          report.description,
                          style: regularTextStyle(size: 14),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Detail Patroli',
          style: semiBoldTextStyle(color: Colors.white),
        ),
        backgroundColor: kbpBlue900,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: kbpBlue900,
            child: TabBar(
              controller: _tabController,
              indicatorColor: neutralWhite,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: semiBoldTextStyle(size: 14, color: neutralWhite),
              unselectedLabelStyle:
                  mediumTextStyle(size: 14, color: neutral200),
              tabs: [
                const Tab(text: 'Rute Patroli'),
                const Tab(text: 'Informasi'),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Laporan'),
                      const SizedBox(width: 4),
                      if (_reports.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: neutralWhite,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_reports.length}',
                            style:
                                semiBoldTextStyle(size: 12, color: kbpBlue900),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Map view
          _buildMapView(),

          // Tab 2: Task details
          _buildTaskDetailsView(),

          // Tab 3: Reports
          _buildReportsView(),
        ],
      ),
    );
  }

  // Tambahkan tombol fullscreen di _buildMapView() di PatrolHistoryScreen
  Widget _buildMapView() {
    return Column(
      children: [
        // Header dengan legenda dan tombol fullscreen + refresh
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    _legendItem(kbpBlue700, 'Rute aktual'),
                    _legendItem(successG500, 'Titik dikunjungi',
                        isDashed: false),
                    _legendItem(dangerR500, 'Titik belum dikunjungi',
                        isDashed: false),
                  ],
                ),
              ),
              // Tombol refresh untuk debugging

              const SizedBox(width: 8),
              // Tombol fullscreen
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => FullScreenMapPage(
                        task: widget.task,
                        initialMarkers: _markers,
                        initialPolylines: _polylines,
                        reports: _reports,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: kbpBlue900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fullscreen,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        'Fullscreen',
                        style: mediumTextStyle(size: 12, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Info panel dengan statistik visited checkpoints
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: kbpBlue50,
          child: () {
            final visitData = _calculateVisitedPoints();
            final visitedCount = visitData['visitedCount'] as int;
            final totalCount = visitData['totalCount'] as int;
            final radiusUsed = visitData['radiusUsed'] as double;

            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, size: 16, color: kbpBlue700),
                const SizedBox(width: 8),
                Text(
                  'Checkpoint: $visitedCount/$totalCount dikunjungi (radius: ${radiusUsed.toStringAsFixed(0)}m)',
                  style: mediumTextStyle(size: 13, color: kbpBlue700),
                ),
              ],
            );
          }(),
        ),

        // Legenda yang bisa di-scroll
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Titik dikunjungi',
                    style: regularTextStyle(size: 12, color: neutral700),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_on, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Titik belum dikunjungi',
                    style: regularTextStyle(size: 12, color: neutral700),
                  ),
                ],
              ),
              if (_reports.isNotEmpty) const SizedBox(width: 16),
              if (_reports.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Laporan (${_reports.length})',
                      style: regularTextStyle(size: 12, color: neutral700),
                    ),
                  ],
                ),
              if (widget.task.mockLocationDetected == true)
                const SizedBox(width: 16),
              if (widget.task.mockLocationDetected == true)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on,
                        color: Colors.purple, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Fake GPS',
                      style: regularTextStyle(size: 12, color: neutral700),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // Peta
        Expanded(
          child: Stack(
            children: [
              GoogleMap(
                onMapCreated: (controller) {
                  _mapController = controller;
                  _fitMapToRoute();

                  // Refresh markers setelah map ready
                  Future.delayed(const Duration(milliseconds: 500), () {
                    _refreshMapMarkers();
                  });
                },
                initialCameraPosition: const CameraPosition(
                  target: LatLng(-6.927727934898599, 107.76911107969532),
                  zoom: 15,
                ),
                markers: _markers,
                polylines: _polylines,
                mapType: MapType.normal,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
                zoomControlsEnabled: true,
                compassEnabled: true,
                scrollGesturesEnabled: true,
                rotateGesturesEnabled: true,
              ),
              if (!_isMapReady)
                const Center(
                  child: CircularProgressIndicator(color: kbpBlue700),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _calculateTimeliness() {
    try {
      if (widget.task.assignedStartTime == null ||
          widget.task.startTime == null) {
        return {
          'status': 'unknown',
          'minutesLate': 0,
          'description': 'Data waktu tidak lengkap',
        };
      }

      final scheduledStart =
          DateTime.parse(widget.task.assignedStartTime!.toString());
      final actualStart = widget.task.startTime!;

      final difference = actualStart.difference(scheduledStart);
      final minutesLate = difference.inMinutes;

      if (minutesLate <= 10) {
        return {
          'status': 'ontime',
          'minutesLate': minutesLate,
          'description': 'Tepat Waktu',
        };
      } else if (minutesLate <= 15) {
        return {
          'status': 'slightly_late',
          'minutesLate': minutesLate,
          'description': 'Terlambat $minutesLate menit',
        };
      } else {
        return {
          'status': 'very_late',
          'minutesLate': minutesLate,
          'description': 'Sangat terlambat',
        };
      }
    } catch (e) {
      print('Error calculating timeliness: $e');
      return {
        'status': 'error',
        'minutesLate': 0,
        'description': 'Error menghitung ketepatan waktu',
      };
    }
  }

  Color getTimelinessColor(String? timeliness) {
    if (timeliness == null) return neutral500;

    // Gunakan data real time jika tersedia
    final timelinessData = _calculateTimeliness();
    final status = timelinessData['status'] as String;

    switch (status.toLowerCase()) {
      case 'ontime':
        return successG500;
      case 'slightly_late':
        return warningY500;
      case 'very_late':
        return dangerR500;
      case 'unknown':
      case 'error':
        return neutral500;
      default:
        // Fallback ke timeliness dari task
        switch (timeliness.toLowerCase()) {
          case 'ontime':
            return successG500;
          case 'late':
            return dangerR500;
          default:
            return neutral500;
        }
    }
  }

  String getTimelinessText(String? timeliness) {
    if (timeliness == null) return 'Tidak ada data';

    // Gunakan perhitungan real time jika tersedia
    final timelinessData = _calculateTimeliness();
    final status = timelinessData['status'] as String;
    final description = timelinessData['description'] as String;

    if (status != 'unknown' && status != 'error') {
      return description;
    }

    // Fallback ke timeliness dari task
    switch (timeliness.toLowerCase()) {
      case 'ontime':
        return 'Tepat Waktu';
      case 'late':
        return 'Terlambat';
      default:
        return 'Status Tidak Diketahui';
    }
  }

  // Tambahkan method untuk menambahkan marker mock location di peta
  Future<void> _addMockLocationMarkers() async {
    try {
      final snapshot = await FirebaseDatabase.instance
          .ref('tasks')
          .child(widget.task.taskId)
          .child('mock_detections')
          .get();

      if (!snapshot.exists) return;

      final mockDetections = <Map<String, dynamic>>[];
      final data = snapshot.value as Map<dynamic, dynamic>;

      data.forEach((key, value) {
        if (value is Map) {
          mockDetections.add(Map<String, dynamic>.from(value as Map));
        }
      });

      for (int i = 0; i < mockDetections.length; i++) {
        final detection = mockDetections[i];
        final coordinates = detection['coordinates'] as List?;
        final isUnrealisticMovement = detection['unrealistic_movement'] == true;

        if (coordinates != null && coordinates.length >= 2) {
          // Buat custom marker icon
          final BitmapDescriptor icon = isUnrealisticMovement
              ? BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange)
              : BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueViolet);

          final position = LatLng(
            (coordinates[0] as num).toDouble(),
            (coordinates[1] as num).toDouble(),
          );

          _markers.add(
            Marker(
              markerId: MarkerId('mock-$i'),
              position: position,
              icon: icon,
              infoWindow: InfoWindow(
                title: isUnrealisticMovement
                    ? 'Gerakan Tidak Realistis'
                    : 'Fake GPS Terdeteksi',
                snippet: 'Klik untuk detail',
                onTap: () => _showMockLocationDetails(),
              ),
            ),
          );
        }
      }

      setState(() {});
    } catch (e) {
      print('Error adding mock location markers: $e');
    }
  }

  // Tambahkan fungsi _legendItem di dalam class _PatrolHistoryScreenState
  Widget _legendItem(Color color, String text, {bool isDashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 4,
          decoration: BoxDecoration(
            color: isDashed ? Colors.transparent : color,
          ),
          child: isDashed
              ? CustomPaint(
                  painter: DashedLinePainter(color: color),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: regularTextStyle(size: 12, color: neutral700),
        ),
      ],
    );
  }

  // Tambahkan di _PatrolHistoryScreenState class
  Future<void> _showMockLocationDetails() async {
    try {
      setState(() {
        _isLoadingMockData = true;
      });

      final snapshot = await FirebaseDatabase.instance
          .ref('tasks')
          .child(widget.task.taskId)
          .child('mock_detections')
          .get();

      setState(() {
        _isLoadingMockData = false;
      });

      if (!snapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data deteksi Fake GPS tidak ditemukan'),
            backgroundColor: warningY500,
          ),
        );
        return;
      }

      final mockDetections = <Map<String, dynamic>>[];

      final data = snapshot.value as Map<dynamic, dynamic>;
      data.forEach((key, value) {
        if (value is Map) {
          mockDetections.add({
            'id': key,
            ...Map<String, dynamic>.from(value as Map),
          });
        }
      });

      // Urutkan berdasarkan waktu, terbaru di atas
      mockDetections.sort((a, b) {
        final aTimestamp = a['timestamp'] as String?;
        final bTimestamp = b['timestamp'] as String?;
        if (aTimestamp == null || bTimestamp == null) return 0;
        return bTimestamp.compareTo(aTimestamp);
      });

      if (mockDetections.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak ada data detail mock location'),
            backgroundColor: warningY500,
          ),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Detail Deteksi Fake GPS',
                      style: boldTextStyle(size: 18),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                Text(
                  'Terdeteksi ${mockDetections.length} kali upaya penggunaan Fake GPS',
                  style: mediumTextStyle(size: 14, color: neutral700),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.separated(
                    itemCount: mockDetections.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final detection = mockDetections[index];
                      final timestamp = parseDateTime(detection['timestamp']);
                      final coordinates = detection['coordinates'] as List?;
                      final unrealisticMovement =
                          detection['unrealistic_movement'] == true;
                      final deviceInfo = detection['deviceInfo'] as Map?;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: unrealisticMovement
                                      ? warningY100
                                      : dangerR100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  unrealisticMovement
                                      ? Icons.speed
                                      : Icons.gps_off,
                                  color: unrealisticMovement
                                      ? warningY300
                                      : dangerR300,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      unrealisticMovement
                                          ? 'Gerakan Tidak Realistis'
                                          : 'Mock Location API',
                                      style: semiBoldTextStyle(size: 14),
                                    ),
                                    if (timestamp != null)
                                      Text(
                                        '${dateFormatter.format(timestamp)} ${timeFormatter.format(timestamp)}',
                                        style: regularTextStyle(
                                            size: 12, color: neutral500),
                                      ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.map_outlined,
                                    color: kbpBlue700, size: 20),
                                onPressed: () {
                                  Navigator.pop(context);
                                  if (coordinates != null &&
                                      coordinates.length >= 2) {
                                    _tabController!.animateTo(0);
                                    Future.delayed(
                                        const Duration(milliseconds: 300), () {
                                      _mapController?.animateCamera(
                                        CameraUpdate.newLatLngZoom(
                                          LatLng(
                                            (coordinates[0] as num).toDouble(),
                                            (coordinates[1] as num).toDouble(),
                                          ),
                                          18,
                                        ),
                                      );
                                    });
                                  }
                                },
                                tooltip: 'Lihat di peta',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (coordinates != null && coordinates.length >= 2)
                            Text(
                              'Lokasi: ${(coordinates[0] as num).toStringAsFixed(6)}, ${(coordinates[1] as num).toStringAsFixed(6)}',
                              style: regularTextStyle(size: 12),
                            ),

                          // Tampilkan detail gerakan tidak realistis jika ada
                          if (unrealisticMovement) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: warningY50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: warningY200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (detection['movement_speed'] != null)
                                    Text(
                                      'Kecepatan: ${(detection['movement_speed'] as num).toStringAsFixed(2)} m/s',
                                      style: regularTextStyle(size: 12),
                                    ),
                                  if (detection['movement_distance'] != null)
                                    Text(
                                      'Jarak: ${(detection['movement_distance'] as num).toStringAsFixed(2)} m',
                                      style: regularTextStyle(size: 12),
                                    ),
                                  if (detection['movement_time'] != null)
                                    Text(
                                      'Waktu: ${(detection['movement_time'] as num).toStringAsFixed(2)} detik',
                                      style: regularTextStyle(size: 12),
                                    ),
                                ],
                              ),
                            ),
                          ],

                          // Tampilkan info device jika ada
                          if (deviceInfo != null && deviceInfo.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Informasi Perangkat:',
                              style: mediumTextStyle(size: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Model: ${deviceInfo['model'] ?? 'Unknown'}',
                              style: regularTextStyle(size: 12),
                            ),
                            Text(
                              'OS: ${deviceInfo['os'] ?? 'Android'} ${deviceInfo['osVersion'] ?? ''}',
                              style: regularTextStyle(size: 12),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      setState(() {
        _isLoadingMockData = false;
      });
      print('Error showing mock location details: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memuat data: $e'),
          backgroundColor: dangerR500,
        ),
      );
    }
  }

  // Add this method to format time display
  String _formatAssignedTime(String? timeString) {
    if (timeString == null || timeString.isEmpty) return 'Tidak ditentukan';

    try {
      final DateTime dateTime = DateTime.parse(timeString);
      final DateFormat timeFormat = DateFormat('HH:mm', 'id_ID');
      final DateFormat dateFormat = DateFormat('dd MMM yyyy', 'id_ID');

      return '${timeFormat.format(dateTime)}\n${dateFormat.format(dateTime)}';
    } catch (e) {
      return 'Format tidak valid';
    }
  }

  // Add this to your _buildTaskDetailsView() method
  Widget _buildAssignedTimeSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kbpBlue50,
            kbpBlue100.withOpacity(0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kbpBlue200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kbpBlue600,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.schedule,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Jadwal Patroli',
                style: boldTextStyle(size: 16, color: kbpBlue900),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              // Start Time
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kbpGreen300, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: kbpGreen500,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Mulai',
                            style: semiBoldTextStyle(
                              size: 12,
                              color: kbpGreen700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatAssignedTime(
                            widget.task.assignedStartTime.toString()),
                        style: boldTextStyle(
                          size: 14,
                          color: neutral800,
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Duration indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kbpBlue100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.arrow_forward,
                  color: kbpBlue700,
                  size: 16,
                ),
              ),

              const SizedBox(width: 12),

              // End Time
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: dangerR300, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: dangerR400,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Selesai',
                            style: semiBoldTextStyle(
                              size: 12,
                              color: dangerR400,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatAssignedTime(
                            widget.task.assignedEndTime.toString()),
                        style: boldTextStyle(
                          size: 14,
                          color: neutral800,
                        ),
                        textAlign: TextAlign.start,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Duration calculation
          if (widget.task.assignedStartTime != null &&
              widget.task.assignedEndTime != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: infoB50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: infoB200, width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.timer,
                      color: infoB400,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Durasi: ${_calculateDuration()}',
                      style: mediumTextStyle(
                        size: 12,
                        color: infoB500,
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

  // Helper method to calculate duration
  String _calculateDuration() {
    try {
      if (widget.task.assignedStartTime == null ||
          widget.task.assignedEndTime == null) {
        return 'Tidak dapat dihitung';
      }

      final startTime =
          DateTime.parse(widget.task.assignedStartTime!.toString());
      final endTime = DateTime.parse(widget.task.assignedEndTime!.toString());
      final duration = endTime.difference(startTime);

      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;

      if (hours > 0) {
        return '${hours}h ${minutes}m';
      } else {
        return '${minutes}m';
      }
    } catch (e) {
      return 'Format tidak valid';
    }
  }

  Widget _buildTaskDetailsView() {
    final visitData = _calculateVisitedPoints();
    final visitedCount = visitData['visitedCount'] as int;
    final totalCount = visitData['totalCount'] as int;
    final progress =
        totalCount > 0 ? (visitedCount / totalCount * 100).round() : 0;

    final duration =
        widget.task.endTime != null && widget.task.startTime != null
            ? widget.task.endTime!.difference(widget.task.startTime!)
            : null;

    // Hitung keterlambatan
    final timelinessData = _calculateTimeliness();
    final minutesLate = timelinessData['minutesLate'] as int;
    final timelinessStatus = timelinessData['status'] as String;

    return Container(
      color: neutral300,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // HERO SECTION dengan status dan progress
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _getStatusColor(widget.task.status),
                    _getStatusColor(widget.task.status).withOpacity(0.8),
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // Status Badge dan Task ID
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Task #${widget.task.taskId.substring(0, 8)}',
                              style: mediumTextStyle(
                                  size: 12, color: Colors.white),
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _getStatusText(widget.task.status),
                                  style: semiBoldTextStyle(
                                      size: 12,
                                      color:
                                          _getStatusColor(widget.task.status)),
                                ),
                              ),
                              // Badge keterlambatan jika ada
                              if (minutesLate > 0 &&
                                  timelinessStatus != 'unknown') ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: getTimelinessColor(
                                            widget.task.timeliness)
                                        .withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.access_time,
                                          color: Colors.white, size: 12),
                                      const SizedBox(width: 4),
                                      Text(
                                        '+${minutesLate}m',
                                        style: boldTextStyle(
                                            size: 11, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Progress Circle dengan info utama
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            // Progress Circle
                            SizedBox(
                              width: 80,
                              height: 80,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: progress / 100,
                                    strokeWidth: 6,
                                    backgroundColor:
                                        Colors.white.withOpacity(0.3),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                  ),
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '$progress%',
                                        style: boldTextStyle(
                                            size: 8, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 20),

                            // Info summary
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Checkpoint Progress',
                                    style: mediumTextStyle(
                                        size: 14, color: Colors.white70),
                                  ),
                                  Text(
                                    '$visitedCount dari $totalCount titik',
                                    style: boldTextStyle(
                                        size: 20, color: Colors.white),
                                  ),
                                  const SizedBox(height: 8),
                                  if (duration != null) ...[
                                    Text(
                                      'Durasi Patroli',
                                      style: mediumTextStyle(
                                          size: 12, color: Colors.white70),
                                    ),
                                    Text(
                                      '${duration.inHours}h ${duration.inMinutes % 60}m',
                                      style: semiBoldTextStyle(
                                          size: 16, color: Colors.white),
                                    ),
                                  ],
                                  // Tampilkan info keterlambatan di hero section jika signifikan
                                  if (minutesLate > 5 &&
                                      timelinessStatus != 'unknown') ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.schedule,
                                              color: Colors.white, size: 14),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Terlambat $minutesLate menit',
                                            style: mediumTextStyle(
                                                size: 11, color: Colors.white),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Warning untuk Fake GPS jika ada
                      if (widget.task.mockLocationDetected == true) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: dangerR500.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning,
                                  color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Terdeteksi Fake GPS ${widget.task.mockLocationCount ?? 0}x',
                                  style: mediumTextStyle(
                                      size: 13, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Duration Card
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.timer,
                      title: 'Durasi',
                      value: duration != null
                          ? '${duration.inHours}h ${duration.inMinutes % 60}m'
                          : 'N/A',
                      subtitle: 'Total waktu patroli',
                      color: infoB500,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Timeliness Card - NEW
                  Expanded(
                    child: _buildStatCard(
                      icon: _getTimelinessIcon(timelinessStatus),
                      title: 'Ketepatan',
                      value: minutesLate > 0 ? '+${minutesLate}m' : 'Tepat',
                      subtitle: timelinessStatus == 'ontime'
                          ? 'Sesuai jadwal'
                          : 'Terlambat',
                      color: getTimelinessColor(widget.task.timeliness),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Reports Card
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.report,
                      title: 'Laporan',
                      value: '${_reports.length}',
                      subtitle: 'Total laporan',
                      color: successG500,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // SCHEDULE SECTION - Simplified
            _buildSimpleScheduleSection(),

            const SizedBox(height: 16),

            // TIMELINE SECTION - Simplified
            _buildSimpleTimelineSection(),

            const SizedBox(height: 16),

            // PERFORMANCE INSIGHTS
            _buildPerformanceInsights(),

            const SizedBox(height: 16),

            // REPORTS PHOTOS (if available)
            if (widget.task.initialReportPhotoUrl != null ||
                widget.task.finalReportPhotoUrl != null)
              _buildReportsGallery(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

// Helper widget untuk stat cards
  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: boldTextStyle(size: 18, color: neutral800),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: mediumTextStyle(size: 12, color: neutral600),
          ),
          Text(
            subtitle,
            style: regularTextStyle(size: 10, color: neutral500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

// Simplified Schedule Section
  Widget _buildSimpleScheduleSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kbpBlue600, kbpBlue700],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Jadwal Patroli',
                  style: boldTextStyle(size: 16, color: Colors.white),
                ),
              ],
            ),
          ),

          // Content - Simplified
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Start time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: successG500,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Mulai',
                            style: mediumTextStyle(size: 12, color: neutral600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatAssignedTime(
                                widget.task.assignedStartTime.toString())
                            .split('\n')
                            .first,
                        style: boldTextStyle(size: 16, color: neutral800),
                      ),
                      Text(
                        _formatAssignedTime(
                                widget.task.assignedStartTime.toString())
                            .split('\n')
                            .last,
                        style: regularTextStyle(size: 12, color: neutral500),
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: kbpBlue100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(Icons.arrow_forward, color: kbpBlue600, size: 16),
                ),

                // End time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'Selesai',
                            style: mediumTextStyle(size: 12, color: neutral600),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: dangerR400,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatAssignedTime(
                                widget.task.assignedEndTime.toString())
                            .split('\n')
                            .first,
                        style: boldTextStyle(size: 16, color: neutral800),
                      ),
                      Text(
                        _formatAssignedTime(
                                widget.task.assignedEndTime.toString())
                            .split('\n')
                            .last,
                        style: regularTextStyle(size: 12, color: neutral500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

// Simplified Timeline Section
  Widget _buildSimpleTimelineSection() {
    final events = <Map<String, dynamic>>[];

    // Build events list
    events.add({
      'title': 'Tugas Dijadwalkan',
      'time': widget.task.createdAt ?? DateTime.now(),
      'icon': Icons.assignment,
      'color': kbpBlue500,
    });

    if (widget.task.startTime != null) {
      events.add({
        'title': 'Patroli Dimulai',
        'time': widget.task.startTime!,
        'icon': Icons.play_arrow,
        'color': warningY500,
      });
    }

    if (widget.task.cancelledAt != null) {
      events.add({
        'title': 'Patroli Dibatalkan',
        'time': widget.task.cancelledAt!,
        'icon': Icons.cancel,
        'color': dangerR500,
      });
    }

    if (widget.task.endTime != null) {
      events.add({
        'title': 'Patroli Selesai',
        'time': widget.task.endTime!,
        'icon': Icons.check_circle,
        'color': successG500,
      });
    }

    events.sort(
        (a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [successG300, successG500],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.timeline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Timeline Aktivitas',
                  style: boldTextStyle(size: 16, color: Colors.white),
                ),
              ],
            ),
          ),

          // Timeline items - Horizontal scroll
          Container(
            height: 160,
            padding: const EdgeInsets.all(20),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: events.length,
              separatorBuilder: (context, index) => const SizedBox(width: 20),
              itemBuilder: (context, index) {
                final event = events[index];
                return Container(
                  width: 140,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (event['color'] as Color).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (event['color'] as Color).withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: event['color'] as Color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          event['icon'] as IconData,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        event['title'] as String,
                        style: semiBoldTextStyle(size: 12, color: neutral800),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Text(
                        timeFormatter.format(event['time'] as DateTime),
                        style: mediumTextStyle(size: 11, color: neutral600),
                      ),
                      Text(
                        dateFormatter.format(event['time'] as DateTime),
                        style: regularTextStyle(size: 10, color: neutral500),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

// Performance Insights Section
  Widget _buildPerformanceInsights() {
    final visitData = _calculateVisitedPoints();
    final progress = visitData['totalCount'] > 0
        ? (visitData['visitedCount'] / visitData['totalCount'] * 100).round()
        : 0;

    // Hitung ketepatan waktu dengan detail
    final timelinessData = _calculateTimeliness();
    final minutesLate = timelinessData['minutesLate'] as int;
    final timelinessStatus = timelinessData['status'] as String;
    final timelinessDescription = timelinessData['description'] as String;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [warningY500, warningY300],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.insights, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Insight Kinerja',
                  style: boldTextStyle(size: 16, color: Colors.white),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Progress bar dengan label
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Checkpoint Coverage',
                      style: mediumTextStyle(size: 14, color: neutral700),
                    ),
                    Text(
                      '$progress%',
                      style: boldTextStyle(
                          size: 14, color: _getProgressColor(progress)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress / 100,
                  backgroundColor: neutral200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      _getProgressColor(progress)),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 16),

                // Insight text
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _getProgressColor(progress).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getPerformanceTitle(progress),
                        style: semiBoldTextStyle(size: 14, color: neutral800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getPerformanceDescription(progress,
                            visitData['visitedCount'], visitData['totalCount']),
                        style: regularTextStyle(size: 12, color: neutral600),
                      ),
                    ],
                  ),
                ),

                // PERBAIKAN: Enhanced timeliness info dengan detail menit
                if (timelinessStatus != 'unknown' &&
                    timelinessStatus != 'error') ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: getTimelinessColor(widget.task.timeliness)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: getTimelinessColor(widget.task.timeliness)
                            .withOpacity(0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                    getTimelinessColor(widget.task.timeliness)
                                        .withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getTimelinessIcon(timelinessStatus),
                                color:
                                    getTimelinessColor(widget.task.timeliness),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Ketepatan Waktu',
                                    style: mediumTextStyle(
                                        size: 12, color: neutral600),
                                  ),
                                  Text(
                                    _getTimelinessStatusText(timelinessStatus),
                                    style: semiBoldTextStyle(
                                      size: 14,
                                      color: getTimelinessColor(
                                          widget.task.timeliness),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Badge dengan menit keterlambatan
                            if (minutesLate > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: getTimelinessColor(
                                      widget.task.timeliness),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '+${minutesLate}m',
                                  style: boldTextStyle(
                                      size: 12, color: Colors.white),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Detail waktu
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Jadwal Mulai',
                                        style: regularTextStyle(
                                            size: 11, color: neutral500),
                                      ),
                                      if (widget.task.assignedStartTime != null)
                                        Text(
                                          TimeOfDay.fromDateTime(DateTime.parse(
                                                  widget.task.assignedStartTime!
                                                      .toString()))
                                              .format(context),
                                          style: semiBoldTextStyle(
                                              size: 13, color: neutral700),
                                        ),
                                    ],
                                  ),
                                  Icon(Icons.arrow_forward,
                                      size: 16, color: neutral400),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Mulai Aktual',
                                        style: regularTextStyle(
                                            size: 11, color: neutral500),
                                      ),
                                      if (widget.task.startTime != null)
                                        Text(
                                          TimeOfDay.fromDateTime(
                                                  widget.task.startTime!)
                                              .format(context),
                                          style: semiBoldTextStyle(
                                              size: 13, color: neutral700),
                                        ),
                                    ],
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),

                              // Summary text
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      getTimelinessColor(widget.task.timeliness)
                                          .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  timelinessDescription,
                                  style: mediumTextStyle(
                                      size: 12,
                                      color: getTimelinessColor(
                                          widget.task.timeliness)),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

// Reports Gallery Section
  Widget _buildReportsGallery() {
    final List<Widget> photoWidgets = [];

    if (widget.task.initialReportPhotoUrl != null &&
        widget.task.initialReportPhotoUrl!.isNotEmpty) {
      photoWidgets.add(_buildPhotoCard(
          'Foto Awal', widget.task.initialReportPhotoUrl!, successG500));
    }

    if (widget.task.finalReportPhotoUrl != null &&
        widget.task.finalReportPhotoUrl!.isNotEmpty) {
      photoWidgets.add(_buildPhotoCard(
          'Foto Akhir', widget.task.finalReportPhotoUrl!, infoB500));
    }

    if (photoWidgets.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [infoB500, infoB300],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.photo_camera, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Dokumentasi Patroli',
                  style: boldTextStyle(size: 16, color: Colors.white),
                ),
              ],
            ),
          ),

          // Photos
          Padding(
            padding: const EdgeInsets.all(20),
            child: photoWidgets.length == 1
                ? photoWidgets.first
                : Row(
                    children: [
                      Expanded(child: photoWidgets[0]),
                      if (photoWidgets.length > 1) ...[
                        const SizedBox(width: 12),
                        Expanded(child: photoWidgets[1]),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  IconData _getTimelinessIcon(String status) {
    switch (status.toLowerCase()) {
      case 'ontime':
        return Icons.check_circle;
      case 'slightly_late':
        return Icons.access_time;
      case 'very_late':
        return Icons.warning;
      default:
        return Icons.help;
    }
  }

  String _getTimelinessStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'ontime':
        return 'Tepat Waktu';
      case 'slightly_late':
        return 'Sedikit Terlambat';
      case 'very_late':
        return 'Sangat Terlambat';
      default:
        return 'Status Tidak Diketahui';
    }
  }

  Widget _buildPhotoCard(String title, String imageUrl, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: semiBoldTextStyle(size: 14, color: neutral700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _showFullScreenImage(imageUrl),
          child: Container(
            height: 120,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withOpacity(0.3)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                          color: kbpBlue700,
                          strokeWidth: 2,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Center(
                        child: Icon(Icons.broken_image,
                            size: 32, color: neutral500),
                      );
                    },
                  ),
                  // Overlay
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.zoom_in,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Helper methods
  Color _getProgressColor(int progress) {
    if (progress >= 80) return successG500;
    if (progress >= 50) return warningY500;
    return dangerR500;
  }

  String _getPerformanceTitle(int progress) {
    if (progress >= 80) return 'Kinerja Excellent';
    if (progress >= 50) return 'Kinerja Good';
    return 'Kinerja Needs Improvement';
  }

  String _getPerformanceDescription(int progress, int visited, int total) {
    if (progress >= 80) {
      return 'Patroli dilakukan dengan sangat baik. $visited dari $total checkpoint berhasil dikunjungi.';
    } else if (progress >= 50) {
      return 'Patroli dilakukan dengan cukup baik. Masih ada ${total - visited} checkpoint yang belum dikunjungi.';
    } else {
      return 'Patroli perlu ditingkatkan. Hanya $visited dari $total checkpoint yang berhasil dikunjungi.';
    }
  }

  Widget _buildReportPhoto(String type, String imageUrl) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_camera, color: kbpBlue900),
                const SizedBox(width: 8),
                Text(
                  type == 'initial'
                      ? 'Foto Laporan Awal'
                      : 'Foto Laporan Akhir',
                  style: semiBoldTextStyle(size: 16),
                ),
                const Spacer(),
                if (type == 'initial' && widget.task.initialReportTime != null)
                  Text(
                    timeFormatter.format(widget.task.initialReportTime!),
                    style: regularTextStyle(size: 12, color: neutral600),
                  )
                else if (type == 'final' && widget.task.finalReportTime != null)
                  Text(
                    timeFormatter.format(widget.task.finalReportTime!),
                    style: regularTextStyle(size: 12, color: neutral600),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showFullScreenImage(type == 'initial'
                  ? widget.task.initialReportPhotoUrl!
                  : widget.task.finalReportPhotoUrl!),
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: neutral200,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                  ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                  : null,
                              color: kbpBlue700,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.broken_image,
                                  size: 64,
                                  color: Colors.white70,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Gagal memuat gambar',
                                  style: mediumTextStyle(color: Colors.white70),
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Coba Lagi'),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _showFullScreenImage(imageUrl);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kbpBlue700,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      // Overlay dengan ikon zoom
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.zoom_in,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.task.finalReportNote != null &&
                widget.task.finalReportNote!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Catatan:',
                style: mediumTextStyle(size: 14),
              ),
              const SizedBox(height: 4),
              Text(
                widget.task.finalReportNote!,
                style: regularTextStyle(size: 14, color: neutral700),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: neutral500),
        const SizedBox(width: 8),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: regularTextStyle(size: 14, color: neutral600),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: mediumTextStyle(size: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline() {
    final events = <Map<String, dynamic>>[];

    // Assigned event
    events.add({
      'title': 'Tugas diberikan',
      'time': widget.task.createdAt ?? DateTime.now(),
      'status': 'active',
    });

    // Start patrol event
    if (widget.task.startTime != null) {
      events.add({
        'title': 'Patroli dimulai',
        'time': widget.task.startTime!,
        'status': 'ongoing',
      });
    }

    if (widget.task.cancelledAt != null) {
      events.add({
        'title': 'Patroli dibatalkan',
        'time': widget.task.cancelledAt!,
        'status': 'cancelled',
      });
    }

    // End patrol event
    if (widget.task.endTime != null) {
      events.add({
        'title': 'Patroli selesai',
        'time': widget.task.endTime!,
        'status': 'finished',
      });
    }

    // Sort events by time
    events.sort(
        (a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime));

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final isLastItem = index == events.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _getTimelineColor(event['status'] as String),
                  ),
                ),
                if (!isLastItem)
                  Container(
                    width: 2,
                    height: 50,
                    color: neutral300,
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event['title'] as String,
                    style: semiBoldTextStyle(size: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${dateFormatter.format(event['time'] as DateTime)} ${timeFormatter.format(event['time'] as DateTime)}',
                    style: regularTextStyle(size: 12, color: neutral600),
                  ),
                  if (!isLastItem) const SizedBox(height: 36),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Tugas Dijadwalkan';
      case 'ongoing':
        return 'Sedang Berpatroli';
      case 'active':
        return 'Tugas sudah dijadwalkan';
      case 'finished':
      case 'finished':
        return 'Patroli Selesai';
      case 'cancelled':
        return 'Patroli Dibatalkan';
      default:
        return 'Status Tidak Diketahui';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ongoing':
        return warningY500;
      case 'active':
        return kbpBlue700;
      case 'finished':
      case 'finished':
        return successG500;
      case 'cancelled':
        return dangerR500;
      default:
        return neutral500;
    }
  }

  Color _getStatusBgColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return warningY50;
      case 'ongoing':
      case 'active':
        return kbpBlue50;
      case 'finished':
      case 'finished':
        return successG50;
      case 'cancelled':
        return dangerR50;
      default:
        return neutral200;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Icons.assignment;
      case 'ongoing':
      case 'active':
        return Icons.directions_run;
      case 'finished':
      case 'finished':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  Color _getTimelineColor(String status) {
    switch (status.toLowerCase()) {
      case 'ongoing':
        return warningY500;
      case 'active':
        return kbpBlue700;
      case 'finished':
        return successG500;
      case 'cancelled':
        return dangerR300;
      default:
        return neutral500;
    }
  }

  String _getProgressDescription(String status, int progress) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Patroli belum dimulai. Petugas akan segera memulai tugasnya.';
      case 'active':
        return 'Petugas belum memulai patroli. Masih menunggu untuk berangkat.';
      case 'ongoing':
        return 'Petugas sedang berpatroli. Telah mengunjungi $progress% dari titik patroli.';
      case 'finished':
      case 'finished':
        return 'Patroli telah selesai.';
      case 'cancelled':
        return 'Patroli dibatalkan. Petugas tidak menyelesaikan kunjungan.';
      default:
        return 'Status patroli tidak diketahui.';
    }
  }

  // Tambahkan method ini di dalam class _PatrolHistoryScreenState
  void _showFullScreenImage(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(
              'Foto Laporan',
              style: semiBoldTextStyle(color: Colors.white),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () async {
                  try {
                    // Menggunakan package share_plus untuk berbagi gambar
                    // await Share.share('Laporan patroli: $imageUrl');

                    // Alternatif: copy URL ke clipboard
                    await Clipboard.setData(ClipboardData(text: imageUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('URL foto disalin ke clipboard')),
                    );
                  } catch (e) {
                    print('Error sharing image: $e');
                  }
                },
                tooltip: 'Bagikan',
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(80),
              child: Hero(
                tag: 'final_report_photo',
                child: Image.network(
                  imageUrl,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                        color: Colors.white,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.broken_image,
                          size: 64,
                          color: Colors.white70,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Gagal memuat gambar',
                          style: mediumTextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Coba Lagi'),
                          onPressed: () {
                            Navigator.of(context).pop();
                            _showFullScreenImage(imageUrl);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kbpBlue700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          // Tambahkan tombol untuk membuka di browser
          floatingActionButton: FloatingActionButton(
            backgroundColor: kbpBlue900,
            child: const Icon(Icons.open_in_browser),
            onPressed: () async {
              if (await canLaunch(imageUrl)) {
                await launch(imageUrl);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Tidak dapat membuka gambar di browser')),
                );
              }
            },
          ),
        ),
      ),
    );
  }

  // Tambahkan metode ini di dalam _PatrolHistoryScreenState
  Map<String, dynamic> _calculateVisitedPoints({double? customRadius}) {
    try {
      final Set<int> visitedCheckpoints = <int>{};
      final List<Map<String, double>> routePositions = [];

      // PERBAIKAN: Gunakan radius dari cluster, lalu custom, lalu task, lalu default
      final double radiusInMeters = customRadius ??
          _clusterValidationRadius ??
          widget.task.validationRadius ??
          50.0;

      print(
          'DEBUG: Using validation radius: ${radiusInMeters}m (source: ${customRadius != null ? 'custom' : _clusterValidationRadius != null ? 'cluster' : 'task/default'})');

      if (widget.task.routePath != null && widget.task.assignedRoute != null) {
        // Ekstrak posisi dari route path
        final routePathMap = Map<String, dynamic>.from(widget.task.routePath!);
        routePathMap.forEach((key, value) {
          try {
            if (value is Map && value.containsKey('coordinates')) {
              final coordinates = value['coordinates'] as List;
              if (coordinates.length >= 2) {
                routePositions.add({
                  'lat': coordinates[0] as double,
                  'lng': coordinates[1] as double
                });
              }
            }
          } catch (e) {
            print('Error parsing route path entry $key: $e');
          }
        });

        // Periksa jarak terdekat untuk setiap checkpoint
        for (int i = 0; i < widget.task.assignedRoute!.length; i++) {
          try {
            final checkpoint = widget.task.assignedRoute![i];
            final checkpointLat = checkpoint[0] as double;
            final checkpointLng = checkpoint[1] as double;

            double minDistance = double.infinity;
            for (final position in routePositions) {
              final distance = Geolocator.distanceBetween(position['lat']!,
                  position['lng']!, checkpointLat, checkpointLng);

              minDistance = Math.min(minDistance, distance);
              if (distance <= radiusInMeters) {
                visitedCheckpoints.add(i);
                break;
              }
            }

            // Debug info untuk checkpoint
            if (minDistance != double.infinity) {
              print(
                  'DEBUG: Checkpoint $i - min distance: ${minDistance.toStringAsFixed(1)}m, visited: ${visitedCheckpoints.contains(i)} (radius: ${radiusInMeters}m)');
            }
          } catch (e) {
            print('Error checking distance for checkpoint $i: $e');
          }
        }
      }

      print(
          'DEBUG: Final result - Visited: ${visitedCheckpoints.length}/${widget.task.assignedRoute?.length ?? 0} checkpoints with ${radiusInMeters}m radius');

      return {
        'visitedCheckpoints': visitedCheckpoints,
        'routePositions': routePositions,
        'visitedCount': visitedCheckpoints.length,
        'totalCount': widget.task.assignedRoute?.length ?? 0,
        'radiusUsed': radiusInMeters, // Radius yang benar-benar digunakan
      };
    } catch (e) {
      print('Error calculating visited points: $e');
      return {
        'visitedCheckpoints': <int>{},
        'routePositions': <Map<String, double>>[],
        'visitedCount': 0,
        'totalCount': widget.task.assignedRoute?.length ?? 0,
        'radiusUsed': customRadius ?? _clusterValidationRadius ?? 50.0,
      };
    }
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
